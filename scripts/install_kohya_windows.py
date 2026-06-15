from __future__ import annotations

import argparse
import datetime as dt
import os
import subprocess
import sys
import venv
from importlib import metadata
from pathlib import Path


MIN_PYTHON = (3, 10, 9)
MAX_PYTHON = (3, 12, 0)

KEY_PACKAGES = (
    "torch",
    "torchvision",
    "flash-attn",
    "xformers",
    "accelerate",
    "diffusers",
    "bitsandbytes",
    "lion-pytorch",
    "pytorch-optimizer",
    "torchao",
    "triton-windows",
    "adv-optm",
    "safetensors",
    "prodigy-plus-schedule-free",
    "schedulefree",
    "LoraEasyCustomOptimizer",
    "voluptuous",
)

FLASH_ATTN_WHEELS = {
    ("win32", 11): (
        "https://github.com/sdbds/flash-attention-for-windows/releases/download/2.8.0.post2/"
        "flash_attn-2.8.0.post2+cu128torch2.7.1cxx11abiFALSEfullbackward-cp311-cp311-win_amd64.whl"
    ),
}


def log(message: str) -> None:
    print(f"[bootstrap] {message}", flush=True)


def fail(message: str) -> None:
    raise SystemExit(message)


def project_venv_python(project_root: Path) -> Path:
    if os.name == "nt":
        return project_root / ".venv" / "Scripts" / "python.exe"
    return project_root / ".venv" / "bin" / "python"


def path_eq(left: Path, right: Path) -> bool:
    try:
        return os.path.normcase(str(left.resolve())) == os.path.normcase(str(right.resolve()))
    except OSError:
        return os.path.normcase(str(left.absolute())) == os.path.normcase(str(right.absolute()))


def run(args: list[str | Path], *, cwd: Path | None = None) -> None:
    rendered = " ".join(str(arg) for arg in args)
    log(rendered)
    env = os.environ.copy()
    env.setdefault("PYTHONIOENCODING", "utf-8")
    env.setdefault("PIP_DISABLE_PIP_VERSION_CHECK", "1")
    env["PIP_PROGRESS_BAR"] = "on"
    env.pop("PIP_NO_PROGRESS_BAR", None)
    env.pop("UV_NO_PROGRESS", None)
    completed = subprocess.run(
        [str(arg) for arg in args],
        cwd=str(cwd) if cwd else None,
        env=env,
        check=False,
    )
    if completed.returncode != 0:
        fail(f"Command failed with exit code {completed.returncode}: {rendered}")


def ensure_supported_python() -> None:
    current = sys.version_info[:3]
    if not (MIN_PYTHON <= current < MAX_PYTHON):
        fail(
            "Python "
            f"{sys.version.split()[0]} is not supported. "
            "Use Python >= 3.10.9 and < 3.12."
        )


def move_invalid_venv(project_root: Path) -> None:
    venv_dir = project_root / ".venv"
    if not venv_dir.exists() or project_venv_python(project_root).exists():
        return

    root = project_root.resolve()
    source = venv_dir.resolve()
    if os.path.commonpath([str(root), str(source)]) != str(root):
        fail(f"Refusing to move invalid venv outside project root: {source}")

    timestamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_dir = project_root / f".venv.invalid-{timestamp}"
    log(f"Project .venv has no Python executable. Moving it to {backup_dir}")
    venv_dir.rename(backup_dir)


def create_venv_if_needed(project_root: Path) -> None:
    python_path = project_venv_python(project_root)
    if python_path.exists():
        return

    log(f"Creating virtual environment: {project_root / '.venv'}")
    venv.EnvBuilder(with_pip=True, clear=False).create(project_root / ".venv")
    if not python_path.exists():
        fail(f"Virtual environment was created, but Python was not found: {python_path}")


def rerun_inside_project_venv(project_root: Path, argv: list[str]) -> None:
    target_python = project_venv_python(project_root)
    if path_eq(Path(sys.executable), target_python):
        return

    move_invalid_venv(project_root)
    create_venv_if_needed(project_root)

    log(f"Re-running installer with {target_python}")
    completed = subprocess.run([str(target_python), *argv], check=False)
    raise SystemExit(completed.returncode)


def ensure_pip() -> None:
    completed = subprocess.run(
        [sys.executable, "-m", "pip", "--version"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if completed.returncode == 0:
        return

    log("pip is missing in .venv; bootstrapping it with ensurepip")
    run([sys.executable, "-m", "ensurepip", "--upgrade"])


def install_requirements(project_root: Path, requirements_file: Path) -> None:
    if not requirements_file.exists():
        fail(f"Requirements file not found: {requirements_file}")

    run(
        [
            sys.executable,
            "-m",
            "pip",
            "install",
            "--progress-bar",
            "on",
            "--upgrade",
            "-r",
            requirements_file,
        ],
        cwd=project_root,
    )


def install_flash_attn(project_root: Path) -> None:
    if sys.platform != "win32":
        log("Skipping flash-attn wheel install: only the Windows prebuilt wheel is configured.")
        return

    python_minor = sys.version_info.minor
    wheel_url = FLASH_ATTN_WHEELS.get((sys.platform, python_minor))
    if wheel_url is None:
        fail(f"No flash-attn Windows wheel is configured for Python 3.{python_minor}")

    run(
        [
            sys.executable,
            "-m",
            "pip",
            "install",
            "--progress-bar",
            "on",
            "--upgrade",
            "--no-deps",
            wheel_url,
        ],
        cwd=project_root,
    )


def install_editable_project(project_root: Path, package_dir: Path, label: str) -> None:
    if not package_dir.exists():
        fail(f"{label} directory does not exist: {package_dir}")
    if not is_installable_python_project(package_dir):
        fail(
            f"{label} does not look installable: "
            f"{package_dir} (expected pyproject.toml, setup.py, or setup.cfg)"
        )

    run(
        [
            sys.executable,
            "-m",
            "pip",
            "install",
            "--progress-bar",
            "on",
            "--upgrade",
            "-e",
            package_dir,
        ],
        cwd=project_root,
    )


def custom_optimizer_package_dir(project_root: Path) -> Path:
    cloned_package_dir = project_root / "third_party" / "custom_scheduler" / "custom_scheduler"
    legacy_package_dir = project_root / "third_party" / "custom_scheduler"

    if is_installable_python_project(cloned_package_dir):
        return cloned_package_dir
    return legacy_package_dir


def configure_accelerate(project_root: Path) -> None:
    if os.name == "nt":
        accelerate = project_root / ".venv" / "Scripts" / "accelerate.exe"
    else:
        accelerate = project_root / ".venv" / "bin" / "accelerate"

    if accelerate.exists():
        run([accelerate, "config", "default"], cwd=project_root)
        return

    run([sys.executable, "-m", "accelerate.commands.accelerate_cli", "config", "default"], cwd=project_root)


def print_version_report() -> None:
    log("Installed key package versions:")
    for package_name in KEY_PACKAGES:
        try:
            version = metadata.version(package_name)
        except metadata.PackageNotFoundError:
            version = "not installed"
        print(f"  {package_name}=={version}", flush=True)


def is_installable_python_project(path: Path) -> bool:
    return any((path / filename).exists() for filename in ("pyproject.toml", "setup.py", "setup.cfg"))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Install the Windows Anima/kohya dependency set into the project .venv."
    )
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--sd-scripts-dir", type=Path, required=True)
    parser.add_argument(
        "--requirements-file",
        type=Path,
        default=Path("requirements_pytorch_windows.txt"),
    )
    parser.add_argument("--skip-accelerate-config", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    project_root = args.project_root.resolve()
    sd_scripts_dir = args.sd_scripts_dir.resolve()
    requirements_file = args.requirements_file
    if not requirements_file.is_absolute():
        requirements_file = project_root / requirements_file

    if not project_root.exists():
        fail(f"Project root does not exist: {project_root}")
    if not sd_scripts_dir.exists():
        fail(f"sd-scripts directory does not exist: {sd_scripts_dir}")
    if not is_installable_python_project(sd_scripts_dir):
        fail(
            "sd-scripts does not look installable: "
            f"{sd_scripts_dir} (expected pyproject.toml, setup.py, or setup.cfg)"
        )

    ensure_supported_python()
    rerun_inside_project_venv(project_root, [str(Path(__file__).resolve()), *sys.argv[1:]])
    ensure_supported_python()
    ensure_pip()

    install_requirements(project_root, requirements_file)
    install_flash_attn(project_root)
    install_editable_project(
        project_root,
        custom_optimizer_package_dir(project_root),
        "LoRA Easy custom optimizer",
    )
    if not args.skip_accelerate_config:
        configure_accelerate(project_root)

    print_version_report()
    log("Python environment setup complete.")


if __name__ == "__main__":
    main()
