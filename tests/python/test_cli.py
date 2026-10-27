"""Installed-artifact CLI tests for slopguard.

Every test runs the installed ``slopguard`` binary (from the ``slopguard_bin``
session fixture in conftest.py) in a subprocess to validate behaviour
end-to-end from the distributed wheel.

Groups
------
* TestVersion    — ``slopguard version`` / ``--version``
* TestHelp       — ``slopguard help`` / unknown command
* TestDepsCheck  — offline fixture, network gate, error/warn modes
"""
from __future__ import annotations

import json
import os
import shutil
import stat
import subprocess
import textwrap
from pathlib import Path
from typing import Optional

import pytest


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
    def test_exit_zero(self, slopguard_bin: Path) -> None:
        assert run(slopguard_bin, ["version"]).returncode == 0

    def test_output_starts_with_slopguard(self, slopguard_bin: Path) -> None:
        out = run(slopguard_bin, ["version"]).stdout.strip()
        assert out.startswith("slopguard "), f"unexpected: {out!r}"

    def test_version_token_is_numeric(self, slopguard_bin: Path) -> None:
        out = run(slopguard_bin, ["version"]).stdout.strip()
        version = out[len("slopguard "):]
        assert version and version[0].isdigit(), (
            f"version token should start with a digit: {version!r}"
        )

    def test_double_dash_flag(self, slopguard_bin: Path) -> None:
        result = run(slopguard_bin, ["--version"])
        assert result.returncode == 0
        assert result.stdout.strip().startswith("slopguard ")

    def test_version_matches_pypi_metadata(self, slopguard_bin: Path) -> None:
        """The Bash version matches the Python package's installed metadata."""
        import importlib.metadata as _meta
        try:
            pypi_ver = _meta.version("slopguard")
        except _meta.PackageNotFoundError:
            pytest.skip("slopguard not installed as a package in the current interpreter")

        bash_ver = run(slopguard_bin, ["version"]).stdout.strip().split()[-1]
        assert bash_ver == pypi_ver, (
            f"bash version {bash_ver!r} != pypi version {pypi_ver!r}"
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

    def test_help_shows_plugin_root(self, slopguard_bin: Path) -> None:
        assert "Plugin root:" in run(slopguard_bin, ["help"]).stdout

    def test_unknown_command_exits_nonzero(self, slopguard_bin: Path) -> None:
        result = run(slopguard_bin, ["__no_such_command__"])
        assert result.returncode != 0

    def test_unknown_command_stderr_message(self, slopguard_bin: Path) -> None:
        result = run(slopguard_bin, ["__no_such_command__"])
        combined = result.stdout + result.stderr
        assert "unknown command" in combined.lower(), (
            f"expected 'unknown command' in output; got: {combined!r}"
        )


# ---------------------------------------------------------------------------
# deps-check fixtures (module-scoped, built once per test session)
# ---------------------------------------------------------------------------

@pytest.fixture(scope="module")
def deps_work(tmp_path_factory: pytest.TempPathFactory) -> Path:
    """Offline deps-check fixtures: registries, fetch stub, package manifests."""
    work = tmp_path_factory.mktemp("deps-fixtures")

    # Minimal npm-only registries stub — matches the format in rules/registries.json.
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

    # Offline fetch stub: never touches the real network.
    #   react     — pinned == latest → ok
    #   axios     — 0.21.1 vs 1.7.2 (major 0→1, old release) → major-behind
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

    # Full project: react (ok) + axios (major-behind).
    proj = work / "project"
    proj.mkdir()
    (proj / "package.json").write_text(
        json.dumps({"dependencies": {"react": "18.3.1", "axios": "0.21.1"}}),
        encoding="utf-8",
    )

    # Single major-behind project — for exit-code mode tests.
    proj_major = work / "proj-major"
    proj_major.mkdir()
    (proj_major / "package.json").write_text(
        json.dumps({"dependencies": {"axios": "0.21.1"}}),
        encoding="utf-8",
    )

    return work


# Shared env vars for offline runs — every test that wants the network enabled
# and uses the fixture fetch stub passes this dict as extra_env.
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
    """When ALLOW_NETWORK is unset the network gate fires; no fetch is called."""

    def test_exits_zero_without_network(
        self, slopguard_bin: Path, deps_work: Path
    ) -> None:
        result = run(
            slopguard_bin,
            ["deps-check", str(deps_work / "project")],
            extra_env={"SLOPGUARD_REGISTRIES_JSON": str(deps_work / "registries.json")},
        )
        assert result.returncode == 0, f"stderr: {result.stderr}"

    def test_emits_allow_network_notice(
        self, slopguard_bin: Path, deps_work: Path
    ) -> None:
        result = run(
            slopguard_bin,
            ["deps-check", str(deps_work / "project")],
            extra_env={"SLOPGUARD_REGISTRIES_JSON": str(deps_work / "registries.json")},
        )
        combined = result.stdout + result.stderr
        assert "ALLOW_NETWORK" in combined, (
            f"expected ALLOW_NETWORK mention in output; got: {combined!r}"
        )

    def test_does_not_call_fetch_without_network(
        self, slopguard_bin: Path, deps_work: Path, tmp_path: Path
    ) -> None:
        """A sentinel file is created if fetch runs; it must not exist."""
        sentinel = tmp_path / "fetch-called"
        stub = tmp_path / "sentinel-fetch.sh"
        stub.write_text(
            f"#!/usr/bin/env bash\ntouch {sentinel}\nexit 1\n",
            encoding="utf-8",
        )
        stub.chmod(stub.stat().st_mode | stat.S_IEXEC)

        run(
            slopguard_bin,
            ["deps-check", str(deps_work / "project")],
            extra_env={
                "SLOPGUARD_REGISTRIES_JSON": str(deps_work / "registries.json"),
                "SLOPGUARD_FETCH_CMD": str(stub),
                # ALLOW_NETWORK deliberately omitted
            },
        )
        assert not sentinel.exists(), "fetch was called despite network gate being inactive"


# ---------------------------------------------------------------------------
# slopguard deps-check — offline fixture results
# ---------------------------------------------------------------------------

class TestDepsCheckOfflineFixture:
    """Correctness of verdicts using the offline fetch stub."""

    def _json_rows(
        self, slopguard_bin: Path, deps_work: Path, project_dir: str = "project"
    ) -> list[dict]:
        result = run(
            slopguard_bin,
            ["deps-check", "--json", str(deps_work / project_dir)],
            extra_env=_offline_env(deps_work),
        )
        assert result.returncode == 0, f"stderr: {result.stderr}"
        return json.loads(result.stdout)

    def test_json_output_is_array(self, slopguard_bin: Path, deps_work: Path) -> None:
        rows = self._json_rows(slopguard_bin, deps_work)
        assert isinstance(rows, list) and rows

    def test_json_rows_have_required_fields(
        self, slopguard_bin: Path, deps_work: Path
    ) -> None:
        required = {"ecosystem", "package", "pinned", "latest", "verdict", "age_days"}
        for row in self._json_rows(slopguard_bin, deps_work):
            missing = required - row.keys()
            assert not missing, f"row missing fields {missing}: {row}"

    def test_react_verdict_ok(self, slopguard_bin: Path, deps_work: Path) -> None:
        rows = self._json_rows(slopguard_bin, deps_work)
        row = next((r for r in rows if r["package"] == "react"), None)
        assert row is not None, "react missing from output"
        assert row["verdict"] == "ok", f"react verdict: {row['verdict']}"

    def test_axios_verdict_major_behind(
        self, slopguard_bin: Path, deps_work: Path
    ) -> None:
        rows = self._json_rows(slopguard_bin, deps_work)
        row = next((r for r in rows if r["package"] == "axios"), None)
        assert row is not None, "axios missing from output"
        assert row["verdict"] == "major-behind", f"axios verdict: {row['verdict']}"

    def test_human_output_includes_summary(
        self, slopguard_bin: Path, deps_work: Path
    ) -> None:
        result = run(
            slopguard_bin,
            ["deps-check", str(deps_work / "project")],
            extra_env=_offline_env(deps_work),
        )
        assert "Summary:" in result.stdout, f"no Summary line; stdout={result.stdout!r}"


# ---------------------------------------------------------------------------
# slopguard deps-check — freshness enforcement modes
# ---------------------------------------------------------------------------

class TestDepsCheckModes:
    """Exit code varies by DEPENDENCY_FRESHNESS mode when major-behind deps exist."""

    def test_error_mode_exits_nonzero(
        self, slopguard_bin: Path, deps_work: Path
    ) -> None:
        env = {**_offline_env(deps_work), "CLAUDE_PLUGIN_OPTION_DEPENDENCY_FRESHNESS": "error"}
        result = run(
            slopguard_bin,
            ["deps-check", str(deps_work / "proj-major")],
            extra_env=env,
        )
        assert result.returncode != 0, (
            f"expected non-zero with major-behind in error mode; "
            f"stdout={result.stdout!r}"
        )

    def test_warn_mode_exits_zero(
        self, slopguard_bin: Path, deps_work: Path
    ) -> None:
        env = {**_offline_env(deps_work), "CLAUDE_PLUGIN_OPTION_DEPENDENCY_FRESHNESS": "warn"}
        result = run(
            slopguard_bin,
            ["deps-check", str(deps_work / "proj-major")],
            extra_env=env,
        )
        assert result.returncode == 0, f"stderr: {result.stderr}"

    def test_error_mode_json_exits_nonzero(
        self, slopguard_bin: Path, deps_work: Path
    ) -> None:
        """--json must carry the same exit status as the human-readable output."""
        env = {**_offline_env(deps_work), "CLAUDE_PLUGIN_OPTION_DEPENDENCY_FRESHNESS": "error"}
        result = run(
            slopguard_bin,
            ["deps-check", "--json", str(deps_work / "proj-major")],
            extra_env=env,
        )
        assert result.returncode != 0, "expected non-zero with --json in error mode"


# ---------------------------------------------------------------------------
# slopguard deps-check — missing jq
# ---------------------------------------------------------------------------

class TestDepsCheckMissingJq:
    """deps-check exits non-zero with a useful message when jq is absent."""

    def test_exits_nonzero_without_jq(
        self, slopguard_bin: Path, deps_work: Path, tmp_path: Path
    ) -> None:
        bash_path = shutil.which("bash")
        if not bash_path:
            pytest.skip("bash not found; cannot construct minimal PATH")

        # Minimal PATH: bash present, jq absent.
        minimal_bin = tmp_path / "minimal-bin"
        minimal_bin.mkdir()
        (minimal_bin / "bash").symlink_to(bash_path)

        # Point CLAUDE_PLUGIN_DATA to an empty dir so bootstrap_jq cannot use
        # a cached managed jq either.
        empty_data = tmp_path / "plugin-data"
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
            f"expected failure without jq; "
            f"stdout={result.stdout!r} stderr={result.stderr!r}"
        )

    def test_error_message_mentions_jq(
        self, slopguard_bin: Path, deps_work: Path, tmp_path: Path
    ) -> None:
        bash_path = shutil.which("bash")
        if not bash_path:
            pytest.skip("bash not found; cannot construct minimal PATH")

        minimal_bin = tmp_path / "minimal-bin2"
        minimal_bin.mkdir()
        (minimal_bin / "bash").symlink_to(bash_path)
        empty_data = tmp_path / "plugin-data2"
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
        combined = result.stdout + result.stderr
        assert "jq" in combined.lower(), (
            f"expected 'jq' mention in error; got: {combined!r}"
        )
