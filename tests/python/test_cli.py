"""Installed-artifact CLI tests for slopguard.

Every test runs the installed ``slopguard`` binary (from the ``slopguard_bin``
session fixture in conftest.py) in a subprocess to validate behaviour
end-to-end from the distributed wheel.

Groups
------
* TestVersion    — version format, version matches source, stale root ignored
* TestHelp       — help content, unknown command handling
* TestDepsCheck  — network gate, offline fixture verdicts, mode exit codes, missing jq
"""
from __future__ import annotations

import json
import os
import re
import shutil
import stat
import subprocess
import textwrap
from pathlib import Path
from typing import Optional

import pytest

PROJECT_ROOT = Path(__file__).parent.parent.parent


# ---------------------------------------------------------------------------
# subprocess helper
# ---------------------------------------------------------------------------

def run(
    cli: Path,
    args: list[str],
    *,
    extra_env: Optional[dict[str, str]] = None,
    stdin: Optional[str] = None,
    cwd: Optional[Path] = None,
) -> subprocess.CompletedProcess:
    """Run the slopguard binary and return the completed process."""
    env = dict(os.environ)
    if extra_env:
        env.update(extra_env)
    return subprocess.run(
        [str(cli)] + args,
        capture_output=True,
        text=True,
        env=env,
        input=stdin,
        cwd=str(cwd) if cwd else None,
    )


# ---------------------------------------------------------------------------
# slopguard version
# ---------------------------------------------------------------------------

class TestVersion:
    def test_version_format(self, slopguard_bin: Path) -> None:
        """Output is exactly 'slopguard X.Y.Z' (semver), exit 0."""
        result = run(slopguard_bin, ["version"])
        assert result.returncode == 0
        assert re.fullmatch(r"slopguard \d+\.\d+\.\d+\S*\n?", result.stdout), (
            f"unexpected version output: {result.stdout!r}"
        )

    def test_version_matches_package_version(self, slopguard_bin: Path) -> None:
        """CLI version matches pyproject.toml and the installed wheel metadata.

        Reads the ground-truth version from pyproject.toml (always reachable
        in the source tree — no skip path).  Also checks the colocated venv
        Python's wheel metadata when slopguard_bin lives in a virtual
        environment (the standard conftest install path).
        """
        # Ground truth: pyproject.toml version field.
        text = (PROJECT_ROOT / "pyproject.toml").read_text()
        m = re.search(r'^version\s*=\s*"([^"]+)"', text, re.MULTILINE)
        assert m, "version field not found in pyproject.toml"
        expected = m.group(1)

        bash_ver = run(slopguard_bin, ["version"]).stdout.strip().split()[-1]
        assert bash_ver == expected, (
            f"CLI reports {bash_ver!r}; pyproject.toml says {expected!r}"
        )

        # If the binary lives in a venv, its sibling Python has the wheel
        # metadata — verify that matches too.
        venv_python = slopguard_bin.parent / "python"
        if venv_python.exists():
            r = subprocess.run(
                [str(venv_python), "-c",
                 "import importlib.metadata; "
                 "print(importlib.metadata.version('slopguard'))"],
                capture_output=True, text=True,
            )
            assert r.returncode == 0, f"venv Python failed: {r.stderr}"
            wheel_ver = r.stdout.strip()
            assert wheel_ver == expected, (
                f"wheel metadata {wheel_ver!r} != pyproject.toml {expected!r}"
            )

    def test_double_dash_version(self, slopguard_bin: Path) -> None:
        """--version is accepted and returns the same output as 'version'."""
        r1 = run(slopguard_bin, ["version"])
        r2 = run(slopguard_bin, ["--version"])
        assert r2.returncode == 0
        assert r2.stdout.strip() == r1.stdout.strip()

    def test_stale_claude_plugin_root_is_ignored(self, slopguard_bin: Path) -> None:
        """An inherited CLAUDE_PLUGIN_ROOT pointing nowhere must not prevent startup.

        The entry point unconditionally overwrites CLAUDE_PLUGIN_ROOT with the
        discovered bundled root, so a stale host-injected value is discarded.
        """
        result = run(
            slopguard_bin,
            ["version"],
            extra_env={"CLAUDE_PLUGIN_ROOT": "/nonexistent/stale/host/root"},
        )
        assert result.returncode == 0, (
            f"version failed with stale CLAUDE_PLUGIN_ROOT; stderr={result.stderr!r}"
        )
        assert re.fullmatch(r"slopguard \d+\.\d+\.\d+\S*\n?", result.stdout), (
            f"unexpected output with stale root: {result.stdout!r}"
        )


# ---------------------------------------------------------------------------
# slopguard help / unknown command
# ---------------------------------------------------------------------------

class TestHelp:
    def test_help_exit_zero(self, slopguard_bin: Path) -> None:
        assert run(slopguard_bin, ["help"]).returncode == 0

    def test_no_args_exit_zero(self, slopguard_bin: Path) -> None:
        assert run(slopguard_bin, []).returncode == 0

    def test_help_mentions_core_commands(self, slopguard_bin: Path) -> None:
        out = run(slopguard_bin, ["help"]).stdout
        for cmd in ("version", "doctor", "deps-check", "adopt-config"):
            assert cmd in out, f"help output missing {cmd!r}"

    def test_help_plugin_root_is_real_directory(self, slopguard_bin: Path) -> None:
        """'Plugin root:' in help must point to an existing directory."""
        out = run(slopguard_bin, ["help"]).stdout
        m = re.search(r"Plugin root:\s*(\S+)", out)
        assert m, "Plugin root line not found in help output"
        root = Path(m.group(1))
        assert root.is_dir(), f"Plugin root {root} is not a directory"
        assert (root / "bin" / "slopguard").is_file(), (
            f"bin/slopguard not present under plugin root {root}"
        )

    def test_unknown_command_exits_nonzero_with_message(
        self, slopguard_bin: Path
    ) -> None:
        result = run(slopguard_bin, ["__no_such_command__"])
        assert result.returncode != 0
        assert "unknown command" in (result.stdout + result.stderr).lower(), (
            f"expected 'unknown command'; got stderr={result.stderr!r}"
        )


# ---------------------------------------------------------------------------
# deps-check fixtures (module-scoped)
# ---------------------------------------------------------------------------

@pytest.fixture(scope="module")
def deps_work(tmp_path_factory: pytest.TempPathFactory) -> Path:
    """Offline deps-check fixtures: registries, fetch stub, package manifests."""
    work = tmp_path_factory.mktemp("deps-fixtures")

    (work / "registries.json").write_text(
        json.dumps({
            "npm": {
                "manifests": ["package.json"],
                "url": "https://registry.npmjs.org/{package}",
                "latest_jq": '."dist-tags".latest',
                "published_jq": ".time[$v]",
            }
        }),
        encoding="utf-8",
    )

    # Offline fetch stub — never touches the real network.
    #   react 18.3.1 (pinned == latest)           → ok
    #   axios 0.21.1 (latest 1.7.2, major 0→1)   → major-behind
    fetch_sh = work / "fetch.sh"
    fetch_sh.write_text(
        textwrap.dedent("""\
            #!/usr/bin/env bash
            case "$1" in
                *npmjs.org/react)
                    printf '{"dist-tags":{"latest":"18.3.1"},"time":{"18.3.1":"2024-04-26T00:00:00.000Z"}}'
                    ;;
                *npmjs.org/axios)
                    printf '{"dist-tags":{"latest":"1.7.2"},"time":{"1.7.2":"2024-06-12T00:00:00.000Z"}}'
                    ;;
                *)
                    exit 1
                    ;;
            esac
        """),
        encoding="utf-8",
    )
    fetch_sh.chmod(fetch_sh.stat().st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)

    proj = work / "project"
    proj.mkdir()
    (proj / "package.json").write_text(
        json.dumps({"dependencies": {"react": "18.3.1", "axios": "0.21.1"}}),
        encoding="utf-8",
    )

    proj_major = work / "proj-major"
    proj_major.mkdir()
    (proj_major / "package.json").write_text(
        json.dumps({"dependencies": {"axios": "0.21.1"}}),
        encoding="utf-8",
    )

    return work


def _offline_env(work: Path) -> dict[str, str]:
    return {
        "CLAUDE_PLUGIN_OPTION_ALLOW_NETWORK": "true",
        "SLOPGUARD_REGISTRIES_JSON": str(work / "registries.json"),
        "SLOPGUARD_FETCH_CMD": str(work / "fetch.sh"),
        "CLAUDE_PLUGIN_OPTION_DEPENDENCY_COOLDOWN_DAYS": "3",
    }


# ---------------------------------------------------------------------------
# slopguard deps-check — network gate
# ---------------------------------------------------------------------------

class TestDepsCheckNetworkGate:
    def test_exits_zero_and_skips_fetch(
        self, slopguard_bin: Path, deps_work: Path, tmp_path: Path
    ) -> None:
        """Network gate: exits 0, emits ALLOW_NETWORK notice, never calls fetch."""
        sentinel = tmp_path / "fetch-called"
        stub = tmp_path / "sentinel-fetch.sh"
        stub.write_text(
            f"#!/usr/bin/env bash\ntouch {sentinel}\nexit 1\n",
            encoding="utf-8",
        )
        stub.chmod(stub.stat().st_mode | stat.S_IEXEC)

        result = run(
            slopguard_bin,
            ["deps-check", str(deps_work / "project")],
            extra_env={
                "SLOPGUARD_REGISTRIES_JSON": str(deps_work / "registries.json"),
                "SLOPGUARD_FETCH_CMD": str(stub),
                # ALLOW_NETWORK deliberately absent
            },
        )
        assert result.returncode == 0, f"stderr: {result.stderr}"
        assert "ALLOW_NETWORK" in (result.stdout + result.stderr), (
            "expected ALLOW_NETWORK skip notice"
        )
        assert not sentinel.exists(), "fetch script was called despite network gate"


# ---------------------------------------------------------------------------
# slopguard deps-check — offline fixture verdicts
# ---------------------------------------------------------------------------

class TestDepsCheckOfflineFixture:
    def _json_rows(self, slopguard_bin: Path, deps_work: Path) -> list[dict]:
        result = run(
            slopguard_bin,
            ["deps-check", "--json", str(deps_work / "project")],
            extra_env=_offline_env(deps_work),
        )
        assert result.returncode == 0, f"stderr: {result.stderr}"
        rows = json.loads(result.stdout)
        assert isinstance(rows, list) and rows, "expected non-empty JSON array"
        return rows

    def test_json_schema_and_verdicts(
        self, slopguard_bin: Path, deps_work: Path
    ) -> None:
        """Every row has required fields; react=ok, axios=major-behind."""
        rows = self._json_rows(slopguard_bin, deps_work)
        required = {"ecosystem", "package", "pinned", "latest", "verdict", "age_days"}
        for row in rows:
            missing = required - row.keys()
            assert not missing, f"row missing fields {missing}: {row}"

        by_pkg = {r["package"]: r["verdict"] for r in rows}
        assert by_pkg.get("react") == "ok", f"react verdict: {by_pkg.get('react')}"
        assert by_pkg.get("axios") == "major-behind", (
            f"axios verdict: {by_pkg.get('axios')}"
        )

    def test_human_output_summary_line(
        self, slopguard_bin: Path, deps_work: Path
    ) -> None:
        """Human-readable output ends with a 'Summary: N ok, …' line."""
        result = run(
            slopguard_bin,
            ["deps-check", str(deps_work / "project")],
            extra_env=_offline_env(deps_work),
        )
        assert re.search(r"Summary: \d+ ok", result.stdout), (
            f"Summary line missing or malformed; stdout={result.stdout!r}"
        )


# ---------------------------------------------------------------------------
# slopguard deps-check — freshness enforcement modes
# ---------------------------------------------------------------------------

class TestDepsCheckModes:
    def test_error_mode_major_behind_exits_nonzero(
        self, slopguard_bin: Path, deps_work: Path
    ) -> None:
        env = {**_offline_env(deps_work), "CLAUDE_PLUGIN_OPTION_DEPENDENCY_FRESHNESS": "error"}
        assert run(slopguard_bin, ["deps-check", str(deps_work / "proj-major")],
                   extra_env=env).returncode != 0

    def test_warn_mode_major_behind_exits_zero(
        self, slopguard_bin: Path, deps_work: Path
    ) -> None:
        env = {**_offline_env(deps_work), "CLAUDE_PLUGIN_OPTION_DEPENDENCY_FRESHNESS": "warn"}
        assert run(slopguard_bin, ["deps-check", str(deps_work / "proj-major")],
                   extra_env=env).returncode == 0

    def test_error_mode_json_same_exit_code(
        self, slopguard_bin: Path, deps_work: Path
    ) -> None:
        """--json must carry the same non-zero exit as human output in error mode."""
        env = {**_offline_env(deps_work), "CLAUDE_PLUGIN_OPTION_DEPENDENCY_FRESHNESS": "error"}
        assert run(slopguard_bin, ["deps-check", "--json", str(deps_work / "proj-major")],
                   extra_env=env).returncode != 0


# ---------------------------------------------------------------------------
# slopguard deps-check — missing jq
# ---------------------------------------------------------------------------

class TestDepsCheckMissingJq:
    def test_exits_nonzero_with_jq_in_error(
        self, slopguard_bin: Path, deps_work: Path, tmp_path: Path
    ) -> None:
        """deps-check fails and mentions 'jq' when the binary is absent from PATH."""
        bash_path = shutil.which("bash")
        if not bash_path:
            pytest.skip("bash not found; cannot construct minimal PATH")

        minimal_bin = tmp_path / "bin"
        minimal_bin.mkdir()
        (minimal_bin / "bash").symlink_to(bash_path)
        # Point CLAUDE_PLUGIN_DATA at an empty dir so bootstrap_jq finds no
        # cached managed jq and falls through to the download step (which will
        # fail because curl is also absent from minimal_bin).
        empty_data = tmp_path / "data"
        empty_data.mkdir()

        result = run(
            slopguard_bin,
            ["deps-check", str(deps_work / "project")],
            extra_env={
                "PATH": str(minimal_bin),
                "CLAUDE_PLUGIN_OPTION_ALLOW_NETWORK": "true",
                "SLOPGUARD_REGISTRIES_JSON": str(deps_work / "registries.json"),
                "SLOPGUARD_FETCH_CMD": str(deps_work / "fetch.sh"),
                "CLAUDE_PLUGIN_DATA": str(empty_data),
            },
        )
        assert result.returncode != 0, (
            f"expected failure without jq; stdout={result.stdout!r} stderr={result.stderr!r}"
        )
        assert "jq" in (result.stdout + result.stderr).lower(), (
            f"expected 'jq' in error output; got: {result.stderr!r}"
        )
