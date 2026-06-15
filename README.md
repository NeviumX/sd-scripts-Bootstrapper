## sd-scripts-bootstrapper

sd-scripts one click installer for windows

### Custom Optimizer source

Custom optimizer / scheduler support is vendored under `third_party/custom_scheduler`.

- Package: `LoraEasyCustomOptimizer`
- Source: LoRA Easy Training Scripts Backend `custom_scheduler`
- Source repository used for this vendored copy: https://github.com/67372a/LoRA_Easy_Training_scripts_Backend
- Source commit inspected locally: `4c7ba3e2aa8520b11ba68f44d092cbb75db547bb`
- Upstream reference: https://github.com/derrian-distro/LoRA_Easy_Training_scripts_Backend

### Setup
``` ./setup-uv.bat ```

### Configure training settings
``` ./training_settings/***/training_setting.toml ```

### Start training
``` ./start_training_***.bat ```
