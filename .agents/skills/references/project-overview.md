# Project Overview

Last updated: 2026-06-15

## Summary

`sd-scripts-bootstrapper` is a Windows-first one-click launcher project for
setting up and running `kohya-ss/sd-scripts` training jobs from this repository.
It keeps the Python environment, uv cache, managed Python install, cloned
`sd-scripts` checkout, outputs, and user training configs under the project root
so the workflow is reproducible and easy to launch from `.bat` files.

The main supported training entrypoints are:

- Anima: `start_training_anima.bat` / `start_training_anima.ps1`
- FLUX: `start_training_flux.bat` / `start_training_flux.ps1`
- SDXL: `start_training_sdxl.bat` / `start_training_sdxl.ps1`

`setup-uv.bat` / `setup-uv.ps1` prepare the repository-local runtime before
training.

## Repository Layout

- `README.md`: short user-facing setup summary.
- `pyproject.toml`: uv project definition, pinned training dependencies, and
  PyTorch CUDA 12.8 index configuration.
- `.python-version`: required managed Python version for uv.
- `setup-uv.bat`: double-click wrapper for `setup-uv.ps1`.
- `setup-uv.ps1`: clones or updates `sd-scripts`, then installs/syncs the
  repository-local Python environment.
- `start_training_*.bat`: double-click wrappers for the matching PowerShell
  launchers; pause on direct double-click failures.
- `start_training_*.ps1`: model-specific launchers that set the default config
  path and call `Start-SdScriptsTraining`.
- `scripts/bootstrapper_common.ps1`: shared PowerShell implementation for
  native command invocation, uv setup, git update, venv validation, output
  safety checks, and training launch.
- `scripts/install_kohya_windows.py`: Python-side dependency installer run
  inside the project `.venv`.
- `scripts/prepare_training_config.py`: Python-side pre-launch config helper
  that writes prepared TOML files under `logs/generated_configs/`.
- `third_party/custom_scheduler/`: vendored LoRA Easy
  `LoraEasyCustomOptimizer` package, installed editable into `.venv`.
- `document/anima_lora_optimizer_scheduler.md`: Anima optimizer and scheduler
  setting guide, including custom optimizer full import paths.
- `training_settings/<model>/training_setting.template.toml`: tracked empty
  templates for model-specific config files.
- `training_settings/<model>/training_setting.toml`: user-local training config
  files. These are intentionally gitignored.
- `sd-scripts/`: local clone of `kohya-ss/sd-scripts`; created and updated by
  the bootstrapper.
- `.venv/`, `.uv-cache/`, `.uv-python/`, `outputs/`, `wandb/`, `logs/`: local
  generated state and ignored runtime artifacts.

## Runtime Model

The intended runtime is repository-local:

- uv installs/uses the Python version declared in `.python-version`.
- uv-managed Python files are stored in `.uv-python/`.
- uv package cache is stored in `.uv-cache/`.
- The virtual environment lives at `.venv/`.
- Training runs through the `.venv` Python executable, not through manual shell
  activation.
- `sd-scripts` is consumed as a local path dependency via
  `tool.uv.sources.library = { path = "sd-scripts" }` in `pyproject.toml`.

The dependency set in `pyproject.toml` pins the important ML stack, including
`torch==2.7.1+cu128`, `torchvision==0.22.1+cu128`, and
`xformers==0.0.31.post1`, using the explicit `pytorch-cu128` index.
On Windows, the installer explicitly installs the prebuilt `flash-attn`
`2.8.0.post2` wheel for Python 3.11 / torch 2.7.1 / CUDA 12.8 from
`sdbds/flash-attention-for-windows`.

The runtime also includes LoRA Easy custom optimizer support through
`third_party/custom_scheduler`. Supporting packages are pinned with the project
dependencies, including `adv-optm==2.2.3`, `bitsandbytes==0.49.2`,
`lion-pytorch==0.2.4`, `prodigy-plus-schedule-free==2.0.1`,
`pytorch-optimizer==3.10.0`, `schedulefree==1.4.1`, and `torchao==0.13.0`.
On Windows, `triton-windows>=3.3,<3.4` is included to match PyTorch 2.7 and
enable CUDA `torch.compile` paths such as FFTDescent compiled spectral
clipping.

## Setup Flow

The normal setup command is:

```powershell
.\setup-uv.bat
```

`setup-uv.ps1` does the following:

1. Loads `scripts/bootstrapper_common.ps1`.
2. Resolves the project root from the launcher location.
3. Ensures Git is available.
4. Ensures `sd-scripts/` exists:
   - clones `https://github.com/kohya-ss/sd-scripts.git` if missing,
   - fetches tags/pruned refs,
   - fast-forwards the current branch when possible,
   - updates submodules recursively.
5. Unless `-SkipSync` is passed, checks whether `.venv` already has the required
   runtime packages.
6. If the environment is missing or the user chooses reinstall, creates or
   repairs `.venv` and runs `scripts/install_kohya_windows.py`.

`setup-uv.ps1` accepts:

- `-SdScriptsUrl <url>`: override the `sd-scripts` clone source.
- `-SkipSync`: update/clone `sd-scripts` but skip Python environment sync.

## Python Installation Details

Most environment work is in `scripts/bootstrapper_common.ps1`:

- `Ensure-Uv` finds or installs `uv`, preferring `winget` and falling back to
  the official uv installer.
- `Use-ProjectUvCache` sets `UV_CACHE_DIR` and `UV_PYTHON_INSTALL_DIR` to
  project-local directories.
- `Ensure-ProjectPythonVenv` installs the required Python with uv and creates a
  seeded `.venv`.
- Invalid `.venv` directories are moved aside to `.venv.invalid-<timestamp>`
  after path safety checks.
- `Invoke-PythonInstallerScript` runs `scripts/install_kohya_windows.py` with
  the project root and `sd-scripts` directory.

`scripts/install_kohya_windows.py` reruns itself inside `.venv`, ensures pip is
present, installs `requirements_pytorch_windows.txt`, installs
`third_party/custom_scheduler` editable, runs `accelerate config default`, then
prints versions for key packages including `LoraEasyCustomOptimizer`.

## Training Flow

The normal training commands are:

```powershell
.\start_training_anima.bat
.\start_training_flux.bat
.\start_training_sdxl.bat
```

Each PowerShell launcher accepts:

- `-ConfigPath <path>`: override the default training TOML.
- `-SdScriptsUrl <url>`: override the `sd-scripts` clone/update source.
- `-SkipUpdate`: require an existing `sd-scripts/.git` checkout and skip fetch/
  merge/submodule update.
- `-NoSync`: skip dependency install/sync before training.
- `-ForceOverwrite`: bypass output overwrite confirmation.
- Remaining arguments are passed through to the training script.

Default configs:

- Anima: `training_settings\anima\training_setting.toml`
- FLUX: `training_settings\flux\training_setting.toml`
- SDXL: `training_settings\sdxl\training_setting.toml`

Default `sd-scripts` targets:

- Anima: `anima_train_network.py`
- FLUX: `flux_train_network.py`
- SDXL: `sdxl_train_network.py`

Training is launched as:

```text
<project .venv python> -m accelerate.commands.launch --num_cpu_threads_per_process 1 <train_script> --config_file <resolved_config_path>
```

The working directory is `sd-scripts/`.

Anima configs can use custom optimizer and scheduler classes by full import
path. For example, `optimizer_type` may be
`LoraEasyCustomOptimizer.fftdescent.FFTDescent`, and `lr_scheduler_type` may be
`LoraEasyCustomOptimizer.RexAnnealingWarmRestarts.RexAnnealingWarmRestarts`.
The project does not include LoRA Easy UI short-name conversion, so TOML files
must use the exact full import path. Before launch, the bootstrapper writes a
prepared config under `logs/generated_configs/`; for LoRA Easy warm-restart
schedulers it preserves an explicit `first_cycle_max_steps`, or fills
`first_cycle_max_steps = total_training_steps // lr_scheduler_num_cycles` when
the value is omitted. The same helper also converts LoRA Easy `warmup_ratio`
to custom-scheduler `warmup_steps` when `warmup_steps` is omitted, using
`warmup_steps = round(total_training_steps * warmup_ratio) //
lr_scheduler_num_cycles`. Explicit `warmup_steps=...` values in
`lr_scheduler_args` are preserved. For `FFTDescent`, if Triton is not importable
and `spectral_clip_compile` is not explicitly set, the prepared config adds
`spectral_clip_compile=False` so spectral clipping can run without
`torch.compile`. In the intended Windows runtime, `triton-windows` is installed
so explicit `spectral_clip_compile=True` can be used.

Training launchers update the `sd-scripts` checkout by default, but they do not
reinstall Python packages when the project `.venv` already has the expected
runtime package versions. If the environment is missing or a pinned runtime
package is mismatched, the launcher runs the installer before training.

## Output Safety

Before training starts, `Prepare-TrainingOutput` reads these TOML scalar keys
from the selected config:

- `output_dir`
- `output_name`
- `save_model_as`

It resolves `output_dir` relative to the `sd-scripts/` working directory unless
the value is absolute, creates the directory if needed, then checks for likely
existing output artifacts:

- `<output_name>.<extension>`
- `<output_name>-000000.<extension>`
- `<output_name>-step00000000.<extension>`
- matching `-state` directories

If artifacts exist, the launcher asks for confirmation through a Windows
MessageBox when available, falling back to console confirmation. Use
`-ForceOverwrite` for non-interactive runs.

## Training Settings Policy

`training_settings/**/*.toml` is ignored because filled training configs are
local user state. Template files are explicitly re-included with:

```gitignore
!training_settings/**/*.template.toml
```

When adding or changing templates:

- Keep `training_setting.template.toml` files valid TOML even when empty.
- Use `""` for scalar placeholders.
- Use `[]` for list-valued placeholders such as `network_args`,
  `optimizer_args`, `lr_scheduler_args`, or list-valued learning-rate fields.
- Keep templates model-specific; do not copy unrelated fields across Anima,
  FLUX, and SDXL just to make them look symmetrical.
- Prefer deriving fields from the matching `sd-scripts` parser/entrypoint.
- For custom optimizers or schedulers, prefer full import paths that can be
  resolved by `sd-scripts` through `importlib`. Do not rely on LoRA Easy UI
  short names in project TOML files.

## Gitignored Local State

The project intentionally ignores:

- `sd-scripts/`
- `.venv/`
- `.venv.invalid-*/`
- `.uv-cache/`
- `.uv-python/`
- `logs/`
- `outputs/`
- `wandb/`
- `training_settings/**/*.toml`
- `uv.lock`

Do not treat these as shared project artifacts unless the user explicitly asks
to change that policy.

## Maintenance Notes For Agents

- Preserve the repo-local runtime model. Do not switch to manual venv activation
  as the default launcher path.
- Keep clone/update of `sd-scripts` in the setup and launch flow unless the user
  asks for a manual-only workflow.
- Use `scripts/bootstrapper_common.ps1` for shared launcher behavior instead of
  duplicating setup or training logic in each model launcher.
- Be careful with native command output in PowerShell. `Invoke-NativeCommand`
  intentionally lets native stdout/stderr flow without converting normal
  progress output into PowerShell errors.
- Before changing launcher defaults, check whether matching training scripts
  actually exist in the current `sd-scripts` checkout.
- Avoid adding unsupported model launchers just to round out a list.
- Treat user-filled `training_settings/<model>/training_setting.toml` files as
  private local configs, even when they exist in the working tree.
- Keep custom optimizer integration in the project installer and requirements,
  not inside the generated `sd-scripts/` checkout.
- If editing output handling, keep the path safety checks around moving `.venv`
  aside and the overwrite confirmation behavior.

---

# プロジェクト概要

最終更新: 2026-06-15

## 概要

`sd-scripts-bootstrapper` は、Windows で `kohya-ss/sd-scripts` の学習ジョブ
をこのリポジトリからセットアップして実行するためのワンクリックランチャー
プロジェクトです。

Python 環境、uv キャッシュ、uv 管理の Python、clone された `sd-scripts`、
出力、ユーザー個別の学習設定をプロジェクトルート配下にまとめることで、
再現しやすく、`.bat` ファイルから起動しやすい構成にしています。

主な対応学習エントリポイントは以下です。

- Anima: `start_training_anima.bat` / `start_training_anima.ps1`
- FLUX: `start_training_flux.bat` / `start_training_flux.ps1`
- SDXL: `start_training_sdxl.bat` / `start_training_sdxl.ps1`

`setup-uv.bat` / `setup-uv.ps1` は、学習前にリポジトリローカルの実行環境を
準備します。

## リポジトリ構成

- `README.md`: ユーザー向けの短いセットアップ概要。
- `pyproject.toml`: uv プロジェクト定義、固定された学習依存関係、
  PyTorch CUDA 12.8 用 index 設定。
- `.python-version`: uv が使う管理 Python の要求バージョン。
- `setup-uv.bat`: `setup-uv.ps1` をダブルクリック実行するための wrapper。
- `setup-uv.ps1`: `sd-scripts` を clone/update し、リポジトリローカルの
  Python 環境を install/sync する。
- `start_training_*.bat`: 対応する PowerShell ランチャーの
  ダブルクリック用 wrapper。直接ダブルクリックされた場合は失敗時に pause する。
- `start_training_*.ps1`: モデル別ランチャー。デフォルト config path を設定し、
  `Start-SdScriptsTraining` を呼び出す。
- `scripts/bootstrapper_common.ps1`: native command 実行、uv setup、git update、
  venv 検証、出力安全確認、学習起動をまとめた共通 PowerShell 実装。
- `scripts/install_kohya_windows.py`: project `.venv` 内で実行される
  Python 側の依存関係 installer。
- `scripts/prepare_training_config.py`: 学習起動前に `logs/generated_configs/`
  へ準備済み TOML を書き出す Python helper。
- `third_party/custom_scheduler/`: vendored された LoRA Easy の
  `LoraEasyCustomOptimizer` package。`.venv` に editable install される。
- `document/anima_lora_optimizer_scheduler.md`: Anima optimizer / scheduler の
  設定ガイド。custom optimizer の full import path も含む。
- `training_settings/<model>/training_setting.template.toml`: track される
  モデル別の空テンプレート。
- `training_settings/<model>/training_setting.toml`: ユーザー個別の学習 config。
  意図的に gitignore される。
- `sd-scripts/`: `kohya-ss/sd-scripts` のローカル clone。
  bootstrapper により作成・更新される。
- `.venv/`, `.uv-cache/`, `.uv-python/`, `outputs/`, `wandb/`, `logs/`:
  ローカル生成状態および ignore される runtime artifact。

## 実行モデル

想定される runtime はリポジトリローカルです。

- uv は `.python-version` に書かれた Python version を install/use する。
- uv 管理の Python ファイルは `.uv-python/` に置かれる。
- uv package cache は `.uv-cache/` に置かれる。
- virtual environment は `.venv/` に作られる。
- 学習は shell で手動 activate するのではなく、`.venv` の Python 実行ファイル
  から直接起動する。
- `sd-scripts` は `pyproject.toml` の
  `tool.uv.sources.library = { path = "sd-scripts" }` により local path dependency
  として扱われる。

`pyproject.toml` の依存関係は主要な ML stack を固定しています。
特に `torch==2.7.1+cu128`, `torchvision==0.22.1+cu128`,
`xformers==0.0.31.post1` は明示的な `pytorch-cu128` index を使います。
Windows では installer が `sdbds/flash-attention-for-windows` から
Python 3.11 / torch 2.7.1 / CUDA 12.8 向けの prebuilt `flash-attn`
`2.8.0.post2` wheel を明示的に install します。

runtime には `third_party/custom_scheduler` 経由の LoRA Easy custom optimizer
support も含まれます。関連 package として `adv-optm==2.2.3`,
`bitsandbytes==0.49.2`, `lion-pytorch==0.2.4`,
`prodigy-plus-schedule-free==2.0.1`, `pytorch-optimizer==3.10.0`,
`schedulefree==1.4.1`, `torchao==0.13.0` が project dependencies に固定されています。
Windows では PyTorch 2.7 に合わせて `triton-windows>=3.3,<3.4` も含め、
FFTDescent の compiled spectral clipping など CUDA `torch.compile` 経路を使えるようにします。

## セットアップフロー

通常の setup command は以下です。

```powershell
.\setup-uv.bat
```

`setup-uv.ps1` は以下を行います。

1. `scripts/bootstrapper_common.ps1` を読み込む。
2. ランチャー位置から project root を解決する。
3. Git が利用可能か確認する。
4. `sd-scripts/` が存在することを保証する。
   - 存在しない場合は `https://github.com/kohya-ss/sd-scripts.git` を clone する。
   - tags と pruned refs を fetch する。
   - 可能な場合は現在 branch を fast-forward する。
   - submodule を recursive に更新する。
5. `-SkipSync` が渡されていなければ、`.venv` に必要な runtime packages があるか確認する。
6. 環境がない、またはユーザーが reinstall を選んだ場合、`.venv` を作成/修復し、
   `scripts/install_kohya_windows.py` を実行する。

`setup-uv.ps1` の引数:

- `-SdScriptsUrl <url>`: `sd-scripts` の clone source を上書きする。
- `-SkipSync`: `sd-scripts` の update/clone は行うが、Python environment sync は省略する。

## Python インストール詳細

環境構築の大半は `scripts/bootstrapper_common.ps1` にあります。

- `Ensure-Uv` は `uv` を探し、なければ install する。`winget` を優先し、
  失敗時は official uv installer に fallback する。
- `Use-ProjectUvCache` は `UV_CACHE_DIR` と `UV_PYTHON_INSTALL_DIR` を
  project-local directories に設定する。
- `Ensure-ProjectPythonVenv` は必要な Python を uv で install し、
  seeded `.venv` を作成する。
- 不正な `.venv` は path safety check 後に `.venv.invalid-<timestamp>` へ退避される。
- `Invoke-PythonInstallerScript` は project root と `sd-scripts` directory を渡して
  `scripts/install_kohya_windows.py` を実行する。

`scripts/install_kohya_windows.py` は自身を `.venv` 内で再実行し、pip を確認し、
`requirements_pytorch_windows.txt` を install し、`third_party/custom_scheduler` を
editable install し、`accelerate config default` を実行します。最後に
`LoraEasyCustomOptimizer` を含む主要 package version を出力します。

## 学習フロー

通常の学習 command は以下です。

```powershell
.\start_training_anima.bat
.\start_training_flux.bat
.\start_training_sdxl.bat
```

各 PowerShell ランチャーの引数:

- `-ConfigPath <path>`: デフォルトの training TOML を上書きする。
- `-SdScriptsUrl <url>`: `sd-scripts` の clone/update source を上書きする。
- `-SkipUpdate`: 既存の `sd-scripts/.git` checkout を要求し、fetch/merge/submodule update を省略する。
- `-NoSync`: 学習前の dependency install/sync を省略する。
- `-ForceOverwrite`: output overwrite confirmation を bypass する。
- 残りの引数は training script にそのまま渡される。

デフォルト config:

- Anima: `training_settings\anima\training_setting.toml`
- FLUX: `training_settings\flux\training_setting.toml`
- SDXL: `training_settings\sdxl\training_setting.toml`

デフォルトの `sd-scripts` target:

- Anima: `anima_train_network.py`
- FLUX: `flux_train_network.py`
- SDXL: `sdxl_train_network.py`

学習は以下の形で起動されます。

```text
<project .venv python> -m accelerate.commands.launch --num_cpu_threads_per_process 1 <train_script> --config_file <resolved_config_path>
```

working directory は `sd-scripts/` です。

Anima configs では、full import path で custom optimizer / scheduler class を
指定できます。たとえば `optimizer_type` に
`LoraEasyCustomOptimizer.fftdescent.FFTDescent`、`lr_scheduler_type` に
`LoraEasyCustomOptimizer.RexAnnealingWarmRestarts.RexAnnealingWarmRestarts` を
指定できます。この project には LoRA Easy UI の短縮名変換は含まれないため、
TOML では正確な full import path を使います。学習起動前に bootstrapper は
`logs/generated_configs/` に準備済み config を書き出します。LoRA Easy の
warm-restart scheduler では、TOML の `first_cycle_max_steps` 明示値を優先し、
未指定の場合は `first_cycle_max_steps = total_training_steps // lr_scheduler_num_cycles`
を補完します。同じ helper は LoRA Easy の `warmup_ratio` も custom scheduler の
`warmup_steps` へ変換します。`warmup_steps` が未指定の場合は
`warmup_steps = round(total_training_steps * warmup_ratio) // lr_scheduler_num_cycles`
を補完し、`lr_scheduler_args` に明示済みの `warmup_steps=...` がある場合はその値を
優先します。`FFTDescent` では、Triton を import できず、かつ
`spectral_clip_compile` が明示されていない場合、準備済み config に
`spectral_clip_compile=False` を追加し、spectral clipping を `torch.compile` なしで
実行できるようにします。想定される Windows runtime では `triton-windows` を install するため、
明示的に `spectral_clip_compile=True` を指定して compiled spectral clipping を使えます。

学習ランチャーはデフォルトで `sd-scripts` checkout を update しますが、project `.venv` に
想定される runtime package versions が揃っている場合は Python packages を再 install しません。
環境が存在しない、または pin された runtime package が不足・不一致の場合のみ、学習前に installer を実行します。

## 出力の安全確認

学習開始前に、`Prepare-TrainingOutput` は選択された config から以下の TOML scalar keys
を読みます。

- `output_dir`
- `output_name`
- `save_model_as`

`output_dir` は absolute path でない限り、`sd-scripts/` working directory からの相対 path
として解決されます。directory がなければ作成し、その後、既存 artifact の可能性がある
以下のファイル/ディレクトリを確認します。

- `<output_name>.<extension>`
- `<output_name>-000000.<extension>`
- `<output_name>-step00000000.<extension>`
- 対応する `-state` directory

artifact が存在する場合、Windows MessageBox が使える環境では popup で確認し、
使えない場合は console confirmation に fallback します。
非対話実行では `-ForceOverwrite` を使います。

## Training Settings の方針

`training_settings/**/*.toml` は、入力済み training configs が local user state であるため
ignore されています。template files は以下で明示的に再 include されています。

```gitignore
!training_settings/**/*.template.toml
```

template を追加・変更するときの方針:

- `training_setting.template.toml` は空の値でも valid TOML に保つ。
- scalar placeholder には `""` を使う。
- `network_args`, `optimizer_args`, `lr_scheduler_args`、list-valued learning-rate fields
  などの list-valued placeholder には `[]` を使う。
- template は model-specific に保つ。Anima、FLUX、SDXL 間で、見た目を揃えるためだけに
  無関係な field をコピーしない。
- 対応する `sd-scripts` parser/entrypoint から fields を導くことを優先する。
- custom optimizer / scheduler では、`sd-scripts` が `importlib` で解決できる
  full import path を優先する。project TOML では LoRA Easy UI の短縮名に依存しない。

## Gitignore されるローカル状態

この project は以下を意図的に ignore します。

- `sd-scripts/`
- `.venv/`
- `.venv.invalid-*/`
- `.uv-cache/`
- `.uv-python/`
- `logs/`
- `outputs/`
- `wandb/`
- `training_settings/**/*.toml`
- `uv.lock`

ユーザーが明示的に方針変更を求めない限り、これらを共有 project artifact として扱わないでください。

## エージェント向け保守メモ

- repo-local runtime model を維持する。デフォルト launcher path を手動 venv activation に
  切り替えない。
- ユーザーが manual-only workflow を求めない限り、`sd-scripts` の clone/update は setup と
  launch flow に残す。
- 共有 launcher behavior は `scripts/bootstrapper_common.ps1` に置き、model launcher ごとに
  setup/training logic を重複させない。
- PowerShell の native command output に注意する。`Invoke-NativeCommand` は通常の progress output
  を PowerShell error に変換しないよう、native stdout/stderr をそのまま流す。
- launcher default を変更する前に、対象 training script が現在の `sd-scripts` checkout に
  実在するか確認する。
- list を揃えるためだけに unsupported model launcher を追加しない。
- `training_settings/<model>/training_setting.toml` が working tree に存在していても、
  ユーザー個別の private config として扱う。
- custom optimizer integration は project installer と requirements 側に置き、
  生成される `sd-scripts/` checkout 側へ混ぜない。
- output handling を編集する場合は、`.venv` 退避時の path safety checks と overwrite confirmation
  behavior を維持する。
