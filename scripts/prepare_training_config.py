from __future__ import annotations

import argparse
import importlib.util
import math
import shutil
import sys
from pathlib import Path
from typing import Any

import toml


CUSTOM_RESTART_SCHEDULERS = {
    "LoraEasyCustomOptimizer.CosineAnnealingWarmRestarts.CosineAnnealingWarmRestarts",
    "LoraEasyCustomOptimizer.RexAnnealingWarmRestarts.RexAnnealingWarmRestarts",
}

CUSTOM_FFTDESCENT_OPTIMIZERS = {
    "LoraEasyCustomOptimizer.fftdescent.FFTDescent",
}


def flatten_sd_scripts_config(config: dict[str, Any]) -> dict[str, Any]:
    flat: dict[str, Any] = {}
    for key, value in config.items():
        if isinstance(value, dict):
            for nested_key, nested_value in value.items():
                flat[nested_key] = nested_value
        else:
            flat[key] = value
    return flat


def has_scheduler_arg(args: Any, key: str) -> bool:
    if args is None:
        return False
    if isinstance(args, dict):
        return key in args
    if isinstance(args, list):
        for item in args:
            if not isinstance(item, str) or "=" not in item:
                continue
            item_key = item.split("=", 1)[0].strip()
            if item_key == key:
                return True
        return False
    raise TypeError(f"lr_scheduler_args must be a list or dict, got {type(args).__name__}")


def has_optimizer_arg(args: Any, key: str) -> bool:
    if args is None:
        return False
    if isinstance(args, dict):
        return key in args
    if isinstance(args, list):
        for item in args:
            if not isinstance(item, str) or "=" not in item:
                continue
            item_key = item.split("=", 1)[0].strip()
            if item_key == key:
                return True
        return False
    raise TypeError(f"optimizer_args must be a list or dict, got {type(args).__name__}")


def append_scheduler_arg(config: dict[str, Any], key: str, value: int) -> None:
    container: dict[str, Any] = config
    scheduler_args_key = "lr_scheduler_args"
    if scheduler_args_key not in container:
        for section_value in config.values():
            if isinstance(section_value, dict) and scheduler_args_key in section_value:
                container = section_value
                break

    current = container.get(scheduler_args_key)
    if current is None:
        container[scheduler_args_key] = [f"{key}={value}"]
        return

    if isinstance(current, list):
        current.append(f"{key}={value}")
        return

    if isinstance(current, dict):
        current[key] = value
        return

    raise TypeError(f"lr_scheduler_args must be a list or dict, got {type(current).__name__}")


def append_optimizer_arg(config: dict[str, Any], key: str, value: str) -> None:
    container: dict[str, Any] = config
    optimizer_args_key = "optimizer_args"
    if optimizer_args_key not in container:
        for section_value in config.values():
            if isinstance(section_value, dict) and optimizer_args_key in section_value:
                container = section_value
                break

    current = container.get(optimizer_args_key)
    if current is None:
        container[optimizer_args_key] = [f"{key}={value}"]
        return

    if isinstance(current, list):
        current.append(f"{key}={value}")
        return

    if isinstance(current, dict):
        current[key] = value
        return

    raise TypeError(f"optimizer_args must be a list or dict, got {type(current).__name__}")


def remove_config_key(config: dict[str, Any], key: str) -> None:
    if key in config:
        del config[key]
    for section_value in config.values():
        if isinstance(section_value, dict) and key in section_value:
            del section_value[key]


def import_train_module(sd_scripts_dir: Path, train_script: str):
    script_path = sd_scripts_dir / train_script
    if not script_path.is_file():
        raise FileNotFoundError(f"training script was not found: {script_path}")

    sys.path.insert(0, str(sd_scripts_dir))
    module_name = f"_bootstrapper_{script_path.stem}"
    spec = importlib.util.spec_from_file_location(module_name, script_path)
    if spec is None or spec.loader is None:
        raise ImportError(f"could not import training script: {script_path}")

    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read_sd_scripts_args(sd_scripts_dir: Path, train_script: str, config_file: Path):
    module = import_train_module(sd_scripts_dir, train_script)
    if not hasattr(module, "setup_parser"):
        raise AttributeError(f"{train_script} does not expose setup_parser()")

    parser = module.setup_parser()
    parsed_args = parser.parse_args(["--config_file", str(config_file)])

    from library import args as args_util

    original_argv = sys.argv[:]
    try:
        sys.argv = [original_argv[0], "--config_file", str(config_file)]
        return args_util.read_config_from_file(parsed_args, parser)
    finally:
        sys.argv = original_argv


def calculate_total_training_steps(sd_scripts_dir: Path, train_script: str, config_file: Path, num_processes: int) -> int:
    args = read_sd_scripts_args(sd_scripts_dir, train_script, config_file)

    if getattr(args, "max_train_epochs", None) is None:
        return int(args.max_train_steps)

    if getattr(args, "dataset_class", None) is not None:
        raise ValueError("automatic custom scheduler step calculation is not supported with dataset_class")

    from library import accelerator_setup
    from library import config_util

    accelerator_setup.prepare_dataset_args(args, True)

    if args.dataset_config is not None:
        user_config = config_util.load_user_config(args.dataset_config)
    elif args.in_json is None:
        user_config = {
            "datasets": [
                {
                    "subsets": config_util.generate_dreambooth_subsets_config_by_subdirs(
                        args.train_data_dir,
                        args.reg_data_dir,
                    )
                }
            ]
        }
    else:
        user_config = {
            "datasets": [
                {
                    "subsets": [
                        {
                            "image_dir": args.train_data_dir,
                            "metadata_file": args.in_json,
                        }
                    ]
                }
            ]
        }

    sanitizer = config_util.ConfigSanitizer(True, True, args.masked_loss, True)
    blueprint = config_util.BlueprintGenerator(sanitizer).generate(user_config, args)
    train_dataset_group, _ = config_util.generate_dataset_group_by_blueprint(blueprint.dataset_group)

    if len(train_dataset_group) == 0:
        raise ValueError("no training data found while calculating custom scheduler steps")

    grad_accumulation_steps = int(getattr(args, "gradient_accumulation_steps", 1) or 1)
    return int(args.max_train_epochs) * math.ceil(len(train_dataset_group) / num_processes / grad_accumulation_steps)


def is_triton_importable() -> bool:
    return importlib.util.find_spec("triton") is not None


def prepare_config(args: argparse.Namespace) -> tuple[Path, bool, int | None, int | None, bool]:
    config_file = Path(args.config_file).resolve()
    output_config = Path(args.output_config).resolve()
    config = toml.load(config_file)
    flat_config = flatten_sd_scripts_config(config)

    optimizer_type = flat_config.get("optimizer_type")
    optimizer_args = flat_config.get("optimizer_args")
    scheduler_type = flat_config.get("lr_scheduler_type")
    scheduler_args = flat_config.get("lr_scheduler_args")
    scheduler_cycles = int(flat_config.get("lr_scheduler_num_cycles", 1) or 1)
    warmup_ratio = flat_config.get("warmup_ratio")

    should_fill_first_cycle = (
        scheduler_type in CUSTOM_RESTART_SCHEDULERS
        and not has_scheduler_arg(scheduler_args, "first_cycle_max_steps")
    )
    should_fill_warmup = (
        scheduler_type in CUSTOM_RESTART_SCHEDULERS
        and warmup_ratio is not None
        and not has_scheduler_arg(scheduler_args, "warmup_steps")
    )
    should_remove_warmup_ratio = scheduler_type in CUSTOM_RESTART_SCHEDULERS and warmup_ratio is not None
    should_disable_fftdescent_compile = (
        optimizer_type in CUSTOM_FFTDESCENT_OPTIMIZERS
        and not is_triton_importable()
        and not has_optimizer_arg(optimizer_args, "spectral_clip_compile")
        and not has_optimizer_arg(optimizer_args, "compile_step")
    )

    if scheduler_cycles < 1 and (should_fill_first_cycle or should_fill_warmup):
        raise ValueError("lr_scheduler_num_cycles must be greater than zero")

    total_steps: int | None = None
    filled_first_cycle: int | None = None
    filled_warmup: int | None = None
    if should_fill_first_cycle or should_fill_warmup:
        total_steps = calculate_total_training_steps(
            Path(args.sd_scripts_dir).resolve(),
            args.train_script,
            config_file,
            int(args.num_processes),
        )

    if should_fill_first_cycle:
        assert total_steps is not None
        filled_first_cycle = total_steps // scheduler_cycles
        append_scheduler_arg(config, "first_cycle_max_steps", filled_first_cycle)

    if should_fill_warmup:
        assert total_steps is not None
        filled_warmup = round(total_steps * float(warmup_ratio)) // scheduler_cycles
        append_scheduler_arg(config, "warmup_steps", filled_warmup)

    if should_remove_warmup_ratio:
        remove_config_key(config, "warmup_ratio")

    if should_disable_fftdescent_compile:
        append_optimizer_arg(config, "spectral_clip_compile", "False")

    output_config.parent.mkdir(parents=True, exist_ok=True)
    changed = (
        should_fill_first_cycle
        or should_fill_warmup
        or should_remove_warmup_ratio
        or should_disable_fftdescent_compile
    )
    if changed:
        with output_config.open("w", encoding="utf-8") as file:
            toml.dump(config, file)
    else:
        shutil.copyfile(config_file, output_config)

    return output_config, changed, filled_first_cycle, filled_warmup, should_disable_fftdescent_compile


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--sd-scripts-dir", required=True)
    parser.add_argument("--train-script", required=True)
    parser.add_argument("--config-file", required=True)
    parser.add_argument("--output-config", required=True)
    parser.add_argument("--num-processes", type=int, default=1)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    output_config, changed, filled_first_cycle, filled_warmup, disabled_fftdescent_compile = prepare_config(args)
    if filled_first_cycle is not None:
        print(f"filled first_cycle_max_steps={filled_first_cycle}")
    if filled_warmup is not None:
        print(f"filled warmup_steps={filled_warmup}")
    if disabled_fftdescent_compile:
        print("filled spectral_clip_compile=False for FFTDescent because triton is unavailable")
    if not changed:
        print("no training config changes needed")
    print(output_config)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
