"""OpenMind Sandbox: virtual and real objects driven by OpenMind BCI commands.

The sandbox does no EEG processing and no decoding. It receives the generic
commands of the OpenMind protocol (``left``, ``right``, ``forward``, ``rest``,
``action``) and turns them into object actions, with the safety rules of the
protocol applied on the object side.
"""

from importlib.metadata import PackageNotFoundError, version

try:
    __version__ = version("openmind-sandbox")
except PackageNotFoundError:  # pragma: no cover - only when running from a raw checkout
    __version__ = "0.0.0"

__all__ = ["__version__"]
