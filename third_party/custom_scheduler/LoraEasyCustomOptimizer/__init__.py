"""LoRA Easy custom optimizer package.

This package is used from sd-scripts with full import paths such as
``LoraEasyCustomOptimizer.fftdescent.FFTDescent``.  Keep package import light so
loading one optimizer or scheduler does not eagerly import every optional
optimizer dependency.
"""

OPTIMIZERS = {}
OPTIMIZER_LIST = []

__all__ = ["OPTIMIZERS", "OPTIMIZER_LIST"]
