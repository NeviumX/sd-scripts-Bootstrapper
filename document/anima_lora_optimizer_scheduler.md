# Anima LoRA Optimizer / Scheduler 設定ガイド

最終更新: 2026-06-15

## 解析対象

この一覧は、このリポジトリ内の `sd-scripts` checkout を確認して作成したものです。

- Anima LoRA 系学習 entrypoint: `sd-scripts/anima_train_network.py`
- 共通 Network 学習処理: `sd-scripts/train_network.py`
- Optimizer / Scheduler 定義: `sd-scripts/library/train_util.py`
- LoRA Easy custom optimizer: `third_party/custom_scheduler/LoraEasyCustomOptimizer`
- 参考 docs: `sd-scripts/docs/anima_train_network.md`, `sd-scripts/docs/train_README-ja.md`

`anima_train_network.py` は `train_network.setup_parser()` を土台にしており、
Optimizer と Scheduler の引数は `train_util.add_optimizer_arguments(parser)` で追加されます。
実際の生成処理は `train_util.get_optimizer()` と `train_util.get_scheduler_fix()` にあります。

このため、Anima LoRA / LoKR などの Anima Network 学習では、基本的に `train_network.py`
系と同じ Optimizer / Scheduler 指定が使えます。

## TOML で使う主なキー

`training_settings/anima/training_setting.toml` では、主に以下を設定します。

```toml
learning_rate = 0.000025
optimizer_type = "AdamW8bit"
optimizer_args = []

lr_scheduler = "constant"
lr_scheduler_type = ""
lr_scheduler_args = []
lr_scheduler_num_cycles = 1
lr_scheduler_power = 1.0
lr_warmup_steps = 0
lr_decay_steps = 0
# 必要な scheduler のときだけ数値で追加:
# lr_scheduler_timescale = 1000
# lr_scheduler_min_lr_ratio = 0.1
```

Anima LoKR 設定では、以下のように任意 optimizer class の仕組みも使えます。

```toml
network_module = "networks.lokr"
learning_rate = 0.000025
optimizer_type = "pytorch_optimizer.CAME"
optimizer_args = ["weight_decay=0.01"]
lr_scheduler = "cosine_with_restarts"
lr_scheduler_num_cycles = 1
lr_scheduler_power = 1.0
lr_warmup_steps = 0.05
```

## Optimizer: `optimizer_type` に指定できる値

`optimizer_type` は大文字小文字をほぼ区別せずに比較されます。未指定または空文字の場合は
`AdamW` が使われます。

| 値 | 実体 / 備考 |
| --- | --- |
| `AdamW` | `torch.optim.AdamW`。未指定時の default。 |
| `AdamW8bit` | `bitsandbytes.optim.AdamW8bit`。`--use_8bit_adam` と同等。 |
| `PagedAdamW` | `bitsandbytes.optim.PagedAdamW`。 |
| `PagedAdamW8bit` | `bitsandbytes.optim.PagedAdamW8bit`。 |
| `PagedAdamW32bit` | `bitsandbytes.optim.PagedAdamW32bit`。 |
| `Lion` | `lion_pytorch.Lion`。`--use_lion_optimizer` と同等。 |
| `Lion8bit` | `bitsandbytes.optim.Lion8bit`。 |
| `PagedLion8bit` | `bitsandbytes.optim.PagedLion8bit`。 |
| `SGDNesterov` | `torch.optim.SGD` with `nesterov=True`。`momentum` 未指定時は `0.9` が補われる。 |
| `SGDNesterov8bit` | `bitsandbytes.optim.SGD8bit` with `nesterov=True`。`momentum` 未指定時は `0.9` が補われる。 |
| `DAdaptation` | `dadaptation.experimental.DAdaptAdamPreprint`。 |
| `DAdaptAdamPreprint` | `DAdaptation` と同じ alias。 |
| `DAdaptAdaGrad` | `dadaptation.DAdaptAdaGrad`。 |
| `DAdaptAdam` | `dadaptation.DAdaptAdam`。 |
| `DAdaptAdan` | `dadaptation.DAdaptAdan`。 |
| `DAdaptAdanIP` | `dadaptation.experimental.DAdaptAdanIP`。 |
| `DAdaptLion` | `dadaptation.DAdaptLion`。 |
| `DAdaptSGD` | `dadaptation.DAdaptSGD`。 |
| `Prodigy` | `prodigyopt.Prodigy`。 |
| `Adafactor` / `AdaFactor` | `transformers.optimization.Adafactor`。`relative_step=True` が default として補われる。 |
| `RAdamScheduleFree` | `schedulefree.RAdamScheduleFree`。 |
| `AdamWScheduleFree` | `schedulefree.AdamWScheduleFree`。 |
| `SGDScheduleFree` | `schedulefree.SGDScheduleFree`。 |

## 任意 Optimizer class の指定

上記にない Optimizer も指定できます。

- `torch.optim` 内の class は class 名だけで指定できます。
  - 例: `RMSprop`, `Adam`, `Adamax`
- 他 module の class は full import path で指定できます。
  - 例: `pytorch_optimizer.CAME`
  - 例: `bitsandbytes.optim.AdEMAMix8bit`
  - 例: `bitsandbytes.optim.PagedAdEMAMix8bit`

この仕組みは `importlib` と `getattr` で class を解決しているだけなので、対象 package が
`.venv` に入っている必要があります。

## LoRA Easy custom optimizer / scheduler

このプロジェクトは、`third_party/custom_scheduler` に LoRA Easy 由来の
`LoraEasyCustomOptimizer` package を同梱します。`scripts/install_kohya_windows.py` が
project `.venv` に editable install するため、`sd-scripts` の
`optimizer_type` / `lr_scheduler_type` から full import path で指定できます。

custom optimizer / scheduler 用の runtime には、以下の package が含まれます。

- `LoraEasyCustomOptimizer==1.0.0`
- `adv-optm==2.2.3`
- `bitsandbytes==0.49.2`
- `lion-pytorch==0.2.4`
- `prodigy-plus-schedule-free==2.0.1`
- `pytorch-optimizer==3.10.0`
- `schedulefree==1.4.1`
- `torchao==0.13.0`
- `triton-windows>=3.3,<3.4` (Windows)
- `flash-attn==2.8.0.post2` (Windows prebuilt wheel, Python 3.11 / torch 2.7.1 / CUDA 12.8)

LoRA Easy UI の短縮名変換層は含まれません。そのため、
`optimizer_type = "FFTDescent"` のような短縮名ではなく、full import path を指定します。
full import path は大文字小文字も含めて正確に書く必要があります。

```toml
optimizer_type = "LoraEasyCustomOptimizer.fftdescent.FFTDescent"
optimizer_args = ["weight_decay=0.04", "spectral_clip_compile=True"]

lr_scheduler_type = "LoraEasyCustomOptimizer.RexAnnealingWarmRestarts.RexAnnealingWarmRestarts"
lr_scheduler_args = ["first_cycle_max_steps=702", "min_lr=0.0", "gamma=0.9", "d=0.9"]
lr_scheduler = "rex_annealing_warm_restarts_(RAWR)"
lr_warmup_steps = 0
```

`lr_scheduler_type` を使う custom scheduler では、`lr_scheduler` の文字列は主に記録用です。
実際に生成される scheduler は `lr_scheduler_type` の class です。

この bootstrapper は、学習起動前に `logs/generated_configs/` へ準備済み TOML を生成します。
`RexAnnealingWarmRestarts` / `CosineAnnealingWarmRestarts` で
`first_cycle_max_steps` が未指定の場合は、生成 TOML に以下の値を補完します。

```text
first_cycle_max_steps = 総学習ステップ数 // lr_scheduler_num_cycles
```

`max_train_steps` が TOML に明示されている場合はその値を使います。`max_train_epochs` で指定している場合は、
`sd-scripts` の dataset group を生成して、実際の dataset 長、`gradient_accumulation_steps`、
process 数から総学習ステップ数を計算します。TOML に `first_cycle_max_steps` が指定済みの場合は、
その値を優先します。

同じ準備処理で、LoRA Easy UI 形式の `warmup_ratio` も custom scheduler 用の
`warmup_steps` に変換します。`warmup_steps` が未指定の場合は、以下の値を
`lr_scheduler_args` に補完します。

```text
warmup_steps = round(総学習ステップ数 * warmup_ratio) // lr_scheduler_num_cycles
```

TOML に `warmup_steps` が指定済みの場合は、その値を優先します。生成 TOML からは
`warmup_ratio` を削除し、`sd-scripts` には `warmup_steps` として渡します。

### 利用できる custom scheduler

| `lr_scheduler_type` | 備考 |
| --- | --- |
| `LoraEasyCustomOptimizer.RexAnnealingWarmRestarts.RexAnnealingWarmRestarts` | Rex annealing warm restarts。`gamma`, `d`, `first_cycle_max_steps`, `min_lr` などを `lr_scheduler_args` で渡す。 |
| `LoraEasyCustomOptimizer.CosineAnnealingWarmRestarts.CosineAnnealingWarmRestarts` | Cosine annealing warm restarts。`gamma`, `first_cycle_max_steps`, `min_lr` などを `lr_scheduler_args` で渡す。 |

### 利用できる custom optimizer

以下は import 確認済みの `optimizer_type` 値です。先頭が `_` の内部 base class は除外しています。

```text
LoraEasyCustomOptimizer.abmog.ABMOG
LoraEasyCustomOptimizer.adabelief.AdaBelief
LoraEasyCustomOptimizer.adagc.AdaGC
LoraEasyCustomOptimizer.adai.Adai
LoraEasyCustomOptimizer.adam.AdamW4bitAO
LoraEasyCustomOptimizer.adam.AdamW8bitAO
LoraEasyCustomOptimizer.adam.AdamW8bitKahan
LoraEasyCustomOptimizer.adam.AdamWfp8AO
LoraEasyCustomOptimizer.adammini.AdamMini
LoraEasyCustomOptimizer.adamw_schedulefree_plus.AdamWScheduleFreePlus
LoraEasyCustomOptimizer.adan.Adan
LoraEasyCustomOptimizer.ademamix.AdEMAMix
LoraEasyCustomOptimizer.ademamix.SimplifiedAdEMAMix
LoraEasyCustomOptimizer.ademamix.SimplifiedAdEMAMixExM
LoraEasyCustomOptimizer.adopt.ADOPT
LoraEasyCustomOptimizer.adopt.ADOPTMARS
LoraEasyCustomOptimizer.adopt.FADOPTMARS
LoraEasyCustomOptimizer.alice.Alice
LoraEasyCustomOptimizer.amuse.AMUSE
LoraEasyCustomOptimizer.bcos.BCOS
LoraEasyCustomOptimizer.came.CAME
LoraEasyCustomOptimizer.cascade.CASCADE
LoraEasyCustomOptimizer.clybius_experiments.MomentusCaution
LoraEasyCustomOptimizer.clybius_experiments.REMASTER
LoraEasyCustomOptimizer.compass.Compass
LoraEasyCustomOptimizer.compass.Compass8BitBNB
LoraEasyCustomOptimizer.compass.CompassADOPT
LoraEasyCustomOptimizer.compass.CompassADOPTMARS
LoraEasyCustomOptimizer.compass.CompassAO
LoraEasyCustomOptimizer.compass.CompassPlus
LoraEasyCustomOptimizer.cstableadamw.CStableAdamW
LoraEasyCustomOptimizer.dehaze.Dehaze
LoraEasyCustomOptimizer.farmscrop.FARMSCrop
LoraEasyCustomOptimizer.farmscrop.FARMSCropV2
LoraEasyCustomOptimizer.fcompass.FCompass
LoraEasyCustomOptimizer.fcompass.FCompassADOPT
LoraEasyCustomOptimizer.fcompass.FCompassADOPTMARS
LoraEasyCustomOptimizer.fcompass.FCompassPlus
LoraEasyCustomOptimizer.fftdescent.FFTDescent
LoraEasyCustomOptimizer.fira.Fira
LoraEasyCustomOptimizer.fishmonger.FishMonger
LoraEasyCustomOptimizer.fishmonger.FishMonger8BitBNB
LoraEasyCustomOptimizer.fmarscrop.FMARSCrop
LoraEasyCustomOptimizer.fmarscrop.FMARSCropV2
LoraEasyCustomOptimizer.fmarscrop.FMARSCropV2ExMachina
LoraEasyCustomOptimizer.fmarscrop.FMARSCropV3
LoraEasyCustomOptimizer.fmarscrop.FMARSCropV3ExMachina
LoraEasyCustomOptimizer.galore.GaLore
LoraEasyCustomOptimizer.glyph.Glyph
LoraEasyCustomOptimizer.gooddog.GOODDOG
LoraEasyCustomOptimizer.grokfast.GrokFastAdamW
LoraEasyCustomOptimizer.lamb.Lamb
LoraEasyCustomOptimizer.laprop.LaProp
LoraEasyCustomOptimizer.lpfadamw.LPFAdamW
LoraEasyCustomOptimizer.moda.MODA
LoraEasyCustomOptimizer.mythical.Mythical
LoraEasyCustomOptimizer.nor_muon_schedulefree.NorMuonScheduleFree
LoraEasyCustomOptimizer.oagopt.OAGOpt
LoraEasyCustomOptimizer.ocgopt.OCGOpt
LoraEasyCustomOptimizer.ocgoptv2.OCGOptV2
LoraEasyCustomOptimizer.projective_adam.ProjectiveAdam
LoraEasyCustomOptimizer.racs.RACS
LoraEasyCustomOptimizer.radam_schedulefree.RAdamScheduleFree
LoraEasyCustomOptimizer.ranger21.Ranger21
LoraEasyCustomOptimizer.rmsprop.RMSProp
LoraEasyCustomOptimizer.rmsprop.RMSPropADOPT
LoraEasyCustomOptimizer.rmsprop.RMSPropADOPTMARS
LoraEasyCustomOptimizer.scgopt.SCGOpt
LoraEasyCustomOptimizer.schedulefree.ADOPTAOScheduleFree
LoraEasyCustomOptimizer.schedulefree.ADOPTEMAMixScheduleFree
LoraEasyCustomOptimizer.schedulefree.ADOPTMARSScheduleFree
LoraEasyCustomOptimizer.schedulefree.ADOPTNesterovScheduleFree
LoraEasyCustomOptimizer.schedulefree.ADOPTScheduleFree
LoraEasyCustomOptimizer.schedulefree.FADOPTEMAMixScheduleFree
LoraEasyCustomOptimizer.schedulefree.FADOPTMARSScheduleFree
LoraEasyCustomOptimizer.schedulefree.FADOPTNesterovScheduleFree
LoraEasyCustomOptimizer.schedulefree.FADOPTScheduleFree
LoraEasyCustomOptimizer.schedulefree.ScheduleFreeWrapper
LoraEasyCustomOptimizer.scion.SCION
LoraEasyCustomOptimizer.scorn.SCORN
LoraEasyCustomOptimizer.scornmachina.SCORNMachina
LoraEasyCustomOptimizer.sgd.SGDSaI
LoraEasyCustomOptimizer.shampoo.ScalableShampoo
LoraEasyCustomOptimizer.singstate.SingState
LoraEasyCustomOptimizer.snoo_asgd.SNOO_ASGD
LoraEasyCustomOptimizer.soap.SOAP
LoraEasyCustomOptimizer.soda.SODA
LoraEasyCustomOptimizer.soda_wrapper.SODAWrapper
LoraEasyCustomOptimizer.spam.StableSPAM
LoraEasyCustomOptimizer.talon.TALON
LoraEasyCustomOptimizer.vsgd.VSGD
LoraEasyCustomOptimizer.wiwiopt.WiwiOpt
```

## Optimizer 追加引数: `optimizer_args`

`optimizer_args` は `key=value` の list として渡します。値は Python literal として解釈されます。

```toml
optimizer_args = ["weight_decay=0.01", "betas=(0.9,0.999)"]
```

注意点:

- D-Adaptation / Prodigy 系は学習率を自動調整するため、`learning_rate` は通常 `1.0` 前後が推奨されます。
- D-Adaptation / Prodigy 系で複数 learning rate group を指定しても、実質的には最初の learning rate が効きます。
- `Adafactor` で `relative_step=True` の場合、`learning_rate` は `initial_lr` として扱われ、scheduler は内部的に `adafactor:<lr>` に変更されます。
- `Adafactor` で `relative_step=False` にする場合、`lr_scheduler = "constant_with_warmup"` と `max_grad_norm = 0.0` が推奨されています。
- `RAdamScheduleFree`, `AdamWScheduleFree`, `SGDScheduleFree` 使用時は dummy scheduler が返されるため、通常の `lr_scheduler` 指定は実質使われません。
- `fused_backward_pass` はコード上 `Adafactor` のみ許可されます。ただし Anima guide では主に VRAM 削減用の高度設定として扱われています。
- `FFTDescent` の `spectral_clip_compile=True` は `torch.compile` 経由で Triton を使います。このプロジェクトでは Windows 用に `triton-windows>=3.3,<3.4` を入れるため、PyTorch 2.7 / CUDA 12.8 / RTX 50 系では compiled spectral clipping を利用できます。Triton が使えない環境では、`optimizer_args` に `spectral_clip_compile=False` を指定すると spectral clipping 自体は維持したまま未コンパイル実行になります。

## Scheduler: `lr_scheduler` に指定できる値

`lr_scheduler` の default は `constant` です。

| 値 | 実体 / 備考 |
| --- | --- |
| `constant` | 学習率を一定に保つ。`lr_warmup_steps` は不要。 |
| `constant_with_warmup` | warmup 後に一定。`lr_warmup_steps` が必要。 |
| `linear` | warmup 後に線形 decay。`lr_warmup_steps` が必要。 |
| `cosine` | warmup 後に cosine decay。`lr_warmup_steps` が必要。 |
| `cosine_with_restarts` | cosine decay に hard restarts を加える。`lr_scheduler_num_cycles` を使う。 |
| `polynomial` | polynomial decay。`lr_scheduler_power` を使う。 |
| `inverse_sqrt` | inverse sqrt schedule。`lr_scheduler_timescale` を使える。 |
| `cosine_with_min_lr` | 最小学習率付き cosine。`lr_scheduler_min_lr_ratio` または `lr_scheduler_args` の `min_lr` / `min_lr_rate` が関係する。 |
| `warmup_stable_decay` | warmup、stable、decay の 3 段階 schedule。`lr_decay_steps` と `lr_scheduler_min_lr_ratio` を使う。 |
| `piecewise_constant` | Diffusers の piecewise constant scheduler。`lr_scheduler_args` で `step_rules` を渡す。 |
| `adafactor:<initial_lr>` | `Adafactor` 用 scheduler。通常は `optimizer_type = "Adafactor"` かつ `relative_step=True` で内部設定される。 |

## Scheduler enum にはあるが注意が必要な値

現在の installed `transformers` には以下の enum もあります。

- `reduce_lr_on_plateau`
- `cosine_warmup_with_min_lr`

ただし、この checkout の `train_util.get_scheduler_fix()` は scheduler ごとに渡す引数を独自に組み立てており、
これらは Anima Network 学習の通常設定としては扱いに注意が必要です。実運用では、上の表にある
`constant`, `constant_with_warmup`, `cosine`, `cosine_with_restarts`, `linear`, `polynomial`,
`inverse_sqrt`, `cosine_with_min_lr`, `warmup_stable_decay`, `piecewise_constant` を優先してください。

## Scheduler 追加引数: `lr_scheduler_args`

`lr_scheduler_args` も `key=value` の list として渡します。値は Python literal として解釈されます。

```toml
lr_scheduler_args = ["last_epoch=-1"]
```

`piecewise_constant` の例:

```toml
lr_scheduler = "piecewise_constant"
lr_scheduler_args = ["step_rules='1:1000,0.5:2000,0.1'"]
```

この例は「最初の 1000 step は 1 倍、次の 2000 step は 0.5 倍、その後は 0.1 倍」
という意味です。

`lr_scheduler_type` を使うと、`lr_scheduler` の定義済み値ではなく任意 scheduler class を指定できます。

- class 名だけの場合は `torch.optim.lr_scheduler` から解決されます。
  - 例: `CosineAnnealingLR`
- full import path の場合はその module から解決されます。
  - 例: `torch.optim.lr_scheduler.OneCycleLR`

`lr_scheduler_type` を使う場合、追加引数は `lr_scheduler_args` で指定します。

```toml
lr_scheduler_type = "CosineAnnealingLR"
lr_scheduler_args = ["T_max=100"]
```

LoRA Easy custom scheduler の例:

```toml
lr_scheduler_type = "LoraEasyCustomOptimizer.CosineAnnealingWarmRestarts.CosineAnnealingWarmRestarts"
lr_scheduler_args = ["first_cycle_max_steps=1000", "min_lr=1e-6", "gamma=0.9"]
lr_warmup_steps = 0
```

## Scheduler 補助パラメータ

| キー | 用途 |
| --- | --- |
| `lr_warmup_steps` | warmup step 数。`0.05` のような 1 未満の float は総 step に対する比率として扱われる。 |
| `lr_decay_steps` | decay step 数。`warmup_stable_decay` などで使う。1 未満の float は総 step に対する比率として扱われる。 |
| `lr_scheduler_num_cycles` | `cosine_with_restarts` の restart 回数。`cosine_with_min_lr` / `warmup_stable_decay` でも cycles 計算に使われる。 |
| `lr_scheduler_power` | `polynomial` の power。 |
| `lr_scheduler_timescale` | `inverse_sqrt` の timescale。未指定時は warmup steps が使われる。 |
| `lr_scheduler_min_lr_ratio` | `cosine_with_min_lr` と `warmup_stable_decay` の最小学習率比率。 |

## Anima LoRA でよく使いやすい組み合わせ

安定寄り:

```toml
optimizer_type = "AdamW8bit"
optimizer_args = ["weight_decay=0.01"]
lr_scheduler = "constant"
lr_warmup_steps = 0
```

cosine restart:

```toml
optimizer_type = "AdamW8bit"
optimizer_args = ["weight_decay=0.01"]
lr_scheduler = "cosine_with_restarts"
lr_scheduler_num_cycles = 1
lr_warmup_steps = 0.05
```

Adafactor 固定 learning rate:

```toml
optimizer_type = "Adafactor"
optimizer_args = ["relative_step=False", "scale_parameter=False", "warmup_init=False"]
lr_scheduler = "constant_with_warmup"
max_grad_norm = 0.0
```

任意 optimizer class:

```toml
optimizer_type = "pytorch_optimizer.CAME"
optimizer_args = ["weight_decay=0.01"]
lr_scheduler = "cosine_with_restarts"
lr_warmup_steps = 0.05
```

LoRA Easy FFTDescent + Rex scheduler:

```toml
optimizer_type = "LoraEasyCustomOptimizer.fftdescent.FFTDescent"
optimizer_args = ["weight_decay=0.04", "spectral_clip_compile=True"]
lr_scheduler_type = "LoraEasyCustomOptimizer.RexAnnealingWarmRestarts.RexAnnealingWarmRestarts"
lr_scheduler_args = ["first_cycle_max_steps=702", "min_lr=0.0", "gamma=0.9", "d=0.9"]
lr_scheduler = "rex_annealing_warm_restarts_(RAWR)"
lr_warmup_steps = 0
```
