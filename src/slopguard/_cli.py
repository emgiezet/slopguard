"""slopguard — PyPI console-script entry point.

Locates the Bash implementation bundled as package data under
``slopguard/_plugin/`` and exec-replaces the current process with it,
forwarding all arguments and environment intact.

Discovery order
---------------
1. ``<installed-package-dir>/_plugin/``
   Standard wheel install via pip.  ``importlib.resources.files("slopguard")``
   resolves to ``<site-packages>/slopguard/``; ``_plugin/`` is bundled there
   by hatchling's ``force-include`` at build time.

2. ``<package-dir>/../../``
   Editable install (``pip install -e .``).  ``src/slopguard/`` lives two
   levels below the project root; if the project root contains
   ``bin/slopguard`` we use it directly, which is the normal developer
   workflow.

``CLAUDE_PLUGIN_ROOT`` handling
--------------------------------
``bin/slopguard`` already derives ``PLUGIN_ROOT`` from its own ``$SCRIPT_DIR``
at startup, so setting ``CLAUDE_PLUGIN_ROOT`` here is belt-and-suspenders: it
prevents an outer plugin host from injecting a stale value while still letting
an intentionally set host value pass through.

No ``SLOPGUARD_PLUGIN_DIR`` env var is required — the installed entry point
discovers its bundled root without any caller assistance.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path


def main() -> None:
    """Locate bundled plugin root and exec the Bash CLI implementation."""
    # ── Locate the installed package directory ─────────────────────────────
    try:
        from importlib.resources import files as _res_files  # Python 3.9+

        pkg_path = Path(str(_res_files("slopguard")))
    except Exception as exc:
        _die(f"cannot locate package data: {exc}")
        return  # unreachable; _die exits

    # ── Resolve plugin root ────────────────────────────────────────────────
    plugin_root = pkg_path / "_plugin"

    if not plugin_root.is_dir():
        # Editable install: src/slopguard/ → src/ → project root
        candidate = pkg_path.parent.parent
        if (candidate / "bin" / "slopguard").is_file():
            plugin_root = candidate
        else:
            _die(
                "plugin root not found.\n"
                f"  Wheel path checked : {plugin_root}\n"
                f"  Source root checked: {candidate}\n"
                "  Wheel install missing data? Try: pip install --no-binary :all: slopguard\n"
                "  Development checkout? Use: bin/slopguard"
            )
            return

    bash_cli = plugin_root / "bin" / "slopguard"
    if not bash_cli.is_file():
        _die(f"bundled CLI not found at {bash_cli}")
        return

    # ── Build environment ──────────────────────────────────────────────────
    env = os.environ.copy()
    # Set CLAUDE_PLUGIN_ROOT so lib/*.sh sources find their siblings when
    # running from an installed wheel (SCRIPT_DIR-based auto-detection works
    # the same way, but explicit is safer across shells and sudo scenarios).
    env.setdefault("CLAUDE_PLUGIN_ROOT", str(plugin_root))

    # ── Exec-replace: no Python overhead remains after this line ───────────
    os.execvpe("bash", ["bash", str(bash_cli)] + sys.argv[1:], env)


def _die(msg: str) -> None:
    print(f"slopguard: {msg}", file=sys.stderr)
    sys.exit(1)
