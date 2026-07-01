## sd-scripts-bootstrapper

[sd-scripts](https://github.com/kohya-ss/sd-scripts) one click installer for windows

### Requirements

- Windows
- [Git for Windows](https://git-scm.com/download/win)

Python, uv, sd-scripts, and the custom optimizer checkout are prepared by the
setup script.

### Custom Optimizer source

Custom optimizer / scheduler support is installed from a local checkout under
`third_party/custom_scheduler`. The checkout is created automatically on setup
or training launch, and `third_party/` is treated as local generated state.

- Package: `LoraEasyCustomOptimizer`
- Source: LoRA Easy Training Scripts Backend `custom_scheduler`
- Source repository: https://github.com/67372a/LoRA_Easy_Training_scripts_Backend
- Source branch: `refresh`
- Upstream reference: https://github.com/derrian-distro/LoRA_Easy_Training_scripts_Backend

### Setup
``` ./setup-uv.bat ```

### Configure training settings
``` ./training_settings/***/training_setting.toml ```

### Start training
``` ./start_training_***.bat ```

Double-click a launcher to use its default `training_setting.toml`, or drag and
drop another `.toml` file onto the matching `start_training_***.bat` launcher to
train with that config. Drag-and-drop launches keep the window open after the
run finishes, including failures, so the result can be read. In TOML files,
write Windows paths with forward slashes like `D:/datasets/...` or
single-quoted strings like `'D:\datasets\...'`.
