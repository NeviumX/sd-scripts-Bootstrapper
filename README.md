## sd-scripts-bootstrapper

sd-scripts one click installer for windows

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
