"""slopguard — anti-pattern detection and gate for agent-written code."""

try:
    from importlib.metadata import PackageNotFoundError as _PNF
    from importlib.metadata import version as _version

    __version__: str = _version("slopguard")
except _PNF:  # not installed (development checkout without editable install)
    __version__ = "0.0.dev0"

__all__ = ["__version__"]
