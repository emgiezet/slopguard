"""slopguard — PyPI console-script entry point.

Locates bin/slopguard bundled under slopguard/_plugin/ (wheel install) or at
the project root (editable install), sets CLAUDE_PLUGIN_ROOT unconditionally,
and exec-replaces the process.  No SLOPGUARD_PLUGIN_DIR override required.
Plugin hosts (Claude Code, Codex, Grok) invoke bin/slopguard directly via their
hooks manifest and never call this entry point.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path
from typing import NoReturn


def main() -> None:
    try:
        from importlib.resources import files as _res_files  # Python 3.9+
        pkg_path = Path(str(_res_files("slopguard")))
    except Exception as exc:
        _die(f"cannot locate package data: {exc}")

    plugin_root = pkg_path / "_plugin"

    if not plugin_root.is_dir():
        # Editable install: src/slopguard/ → src/ → project root.
        candidate = pkg_path.parent.parent
        if (candidate / "bin" / "slopguard").is_file():
            plugin_root = candidate
        else:
            _die(
                "plugin root not found.\n"
                f"  Wheel path: {plugin_root}\n"
                f"  Source root: {candidate}\n"
                "  Reinstall: pip install --no-binary :all: slopguard\n"
                "  Development: use bin/slopguard directly"
            )

    bash_cli = plugin_root / "bin" / "slopguard"
    if not bash_cli.is_file():
        _die(f"bundled CLI not found: {bash_cli}")

    env = os.environ.copy()
    # Unconditionally overwrite: a stale host-injected value must not win.
    env["CLAUDE_PLUGIN_ROOT"] = str(plugin_root)
    os.execvpe("bash", ["bash", str(bash_cli)] + sys.argv[1:], env)


def _die(msg: str) -> NoReturn:
    print(f"slopguard: {msg}", file=sys.stderr)
    sys.exit(1)
