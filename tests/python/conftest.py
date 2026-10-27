"""pytest configuration for installed-artifact CLI tests.

The ``slopguard_bin`` session fixture builds a wheel from the project root,
installs it in a throw-away virtual environment, and returns the absolute
path to the ``slopguard`` binary.  This validates that the PyPI distribution
is self-contained: data files bundled, entry-point wired, Bash runtime
discoverable from the installed location.

Environment shortcut
---------------------
Set ``SLOPGUARD_TEST_BIN`` to the absolute path of an already-installed
``slopguard`` binary to skip the build step entirely.  CI can pre-install
the wheel once and export the path:

    pip install dist/aisdlc_guard-*.whl
    SLOPGUARD_TEST_BIN="$(which slopguard)" pytest tests/python/
"""
from __future__ import annotations

import os
import subprocess
import sys
import venv
from pathlib import Path

import pytest

# Absolute path of the repository root (slop-guard-src/).
PROJECT_ROOT = Path(__file__).parent.parent.parent


@pytest.fixture(scope="session")
def slopguard_bin(tmp_path_factory: pytest.TempPathFactory) -> Path:
    """Return the path of an installed ``slopguard`` binary.

    Builds the wheel and installs it in a fresh virtual environment.
    Honours the ``SLOPGUARD_TEST_BIN`` env-var override for pre-built CI
    scenarios.
    """
    if override := os.environ.get("SLOPGUARD_TEST_BIN"):
        path = Path(override)
        assert path.exists(), f"SLOPGUARD_TEST_BIN={override!r} does not exist"
        return path

    work = tmp_path_factory.mktemp("slopguard-install")
    dist_dir = work / "dist"
    dist_dir.mkdir()

    # Ensure the build frontend is available in the current interpreter.
    subprocess.run(
        [sys.executable, "-m", "pip", "install", "--quiet", "build"],
        check=True,
        capture_output=True,
    )

    # Build the wheel from the repository root.
    result = subprocess.run(
        [sys.executable, "-m", "build", "--wheel", "--outdir", str(dist_dir)],
        cwd=PROJECT_ROOT,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        pytest.fail(
            f"wheel build failed (exit {result.returncode}):\n"
            f"--- stdout ---\n{result.stdout}\n"
            f"--- stderr ---\n{result.stderr}",
            pytrace=False,
        )

    wheels = sorted(dist_dir.glob("aisdlc_guard-*.whl"))
    if not wheels:
        pytest.fail(f"No aisdlc_guard-*.whl found in {dist_dir}", pytrace=False)
    wheel = wheels[-1]

    # Create a clean virtual environment and install the wheel into it.
    venv_dir = work / "venv"
    venv.create(str(venv_dir), with_pip=True, clear=True)

    pip = venv_dir / "bin" / "pip"
    result = subprocess.run(
        [str(pip), "install", "--quiet", str(wheel)],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        pytest.fail(
            f"wheel install failed (exit {result.returncode}):\n"
            f"--- stdout ---\n{result.stdout}\n"
            f"--- stderr ---\n{result.stderr}",
            pytrace=False,
        )

    cli = venv_dir / "bin" / "slopguard"
    if not cli.exists():
        pytest.fail(
            f"slopguard binary not present at {cli} after wheel install",
            pytrace=False,
        )
    return cli
