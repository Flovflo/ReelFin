"""Behavioral regressions for the credential-safe QA execution boundary."""

from __future__ import annotations

import os
import re
import shutil
import stat
import subprocess
import tempfile
import textwrap
import unittest
import urllib.parse
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"
WRAPPER = SCRIPTS / "run_python_with_uv.sh"
MANAGED_ROOT = Path("/Users/flo/.local/share/reelfin-codex/uv/python")
EXPECTED_UV = "/Users/flo/.local/share/reelfin-codex/uv/bin/uv"
EXPECTED_CACHE = "/Users/flo/.cache/reelfin-codex/uv"


def run_python(*arguments: str, **kwargs: object) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(WRAPPER), *arguments],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
        **kwargs,
    )


def mixed_percent_encode(value: str) -> str:
    encoded: list[str] = []
    upper = True
    for byte in value.encode("utf-8"):
        if chr(byte).isalnum():
            encoded.append(chr(byte))
        else:
            digits = f"{byte:02X}" if upper else f"{byte:02x}"
            encoded.append(f"%{digits}")
            upper = not upper
    return "".join(encoded)


class SecureQARunnerTests(unittest.TestCase):
    def run_playback_harness(
        self,
        *,
        producer_status: int = 0,
        redactor_status: int = 0,
        tee_status: int = 0,
        emit_canary: bool = False,
        runtime_redactor_status: int = 0,
    ) -> tuple[subprocess.CompletedProcess[str], Path, Path, str, tempfile.TemporaryDirectory[str]]:
        temporary = tempfile.TemporaryDirectory()
        temp = Path(temporary.name).resolve()
        mini_root = temp / "repo"
        scripts = mini_root / "scripts"
        bin_dir = temp / "bin"
        artifacts = temp / "artifacts"
        scripts.mkdir(parents=True)
        bin_dir.mkdir()
        canary = "Qa /Pass+Canary?%2F"
        for name in (
            "run_playback_qa_loop.sh",
            "run_python_with_uv.sh",
            "redact_xctest_activity.py",
            "assert_no_secret_artifacts.py",
        ):
            shutil.copy2(SCRIPTS / name, scripts / name)
        if redactor_status:
            (scripts / "redact_xctest_activity.py").write_text(
                f"raise SystemExit({redactor_status})\n", encoding="utf-8"
            )
        elif runtime_redactor_status:
            (scripts / "redact_xctest_activity.py").write_text(
                "import sys\n"
                "content = sys.stdin.read()\n"
                "sys.stdout.write(content)\n"
                f"raise SystemExit({runtime_redactor_status} if 'RUNTIME_ONLY_MARKER' in content else 0)\n",
                encoding="utf-8",
            )
        xcode_record = temp / "xcodebuild.args"
        emitted = f"printf '%s\\n' {canary!r}; printf '%s\\n' {canary!r} >&2\n" if emit_canary else ""
        (bin_dir / "xcodebuild").write_text(
            "#!/usr/bin/env bash\n"
            f"printf '%s\\n' \"$@\" > {str(xcode_record)!r}\n"
            f"{emitted}"
            f"exit {producer_status}\n",
            encoding="utf-8",
        )
        runtime_output = (
            "printf '%s\\n' RUNTIME_ONLY_MARKER"
            if runtime_redactor_status
            else f"printf '%s\\n' RUNTIME_ONLY_MARKER; printf '%s\\n' {canary!r}; printf '%s\\n' {canary!r} >&2"
        )
        (bin_dir / "xcrun").write_text(
            "#!/usr/bin/env bash\n"
            f"if [[ $* == *'log stream'* ]]; then {runtime_output}; fi\n"
            "exit 0\n",
            encoding="utf-8",
        )
        (bin_dir / "open").write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
        if tee_status:
            (bin_dir / "tee").write_text(
                "#!/usr/bin/env bash\n/bin/cat >/dev/null\n"
                f"exit {tee_status}\n",
                encoding="utf-8",
            )
        else:
            (bin_dir / "tee").write_text("#!/usr/bin/env bash\nexec /usr/bin/tee \"$@\"\n", encoding="utf-8")
        for path in bin_dir.iterdir():
            path.chmod(0o700)
        completed = subprocess.run(
            [str(scripts / "run_playback_qa_loop.sh"), "1", "FAKE-SIMULATOR-ID"],
            cwd=mini_root,
            env={
                "PATH": f"{bin_dir}:{os.environ['PATH']}",
                "HOME": str(temp / "home"),
                "TMPDIR": str(temp),
                "REELFIN_QA_ARTIFACT_ROOT": str(artifacts),
                "REELFIN_TEST_SERVER_URL": "https://qa.invalid",
                "REELFIN_TEST_USERNAME": "qa-user",
                "REELFIN_TEST_PASSWORD": canary,
            },
            text=True,
            capture_output=True,
            check=False,
        )
        return completed, artifacts, xcode_record, canary, temporary

    def run_e2e_runtime_harness(
        self, *, runtime_redactor_status: int
    ) -> tuple[subprocess.CompletedProcess[str], tempfile.TemporaryDirectory[str]]:
        temporary = tempfile.TemporaryDirectory()
        temp = Path(temporary.name).resolve()
        mini_root = temp / "repo"
        scripts = mini_root / "scripts"
        bin_dir = temp / "bin"
        scripts.mkdir(parents=True)
        bin_dir.mkdir()
        shutil.copy2(SCRIPTS / "run_reelfin_player_e2e.sh", scripts / "run_reelfin_player_e2e.sh")
        shutil.copy2(SCRIPTS / "assert_no_secret_artifacts.py", scripts / "assert_no_secret_artifacts.py")
        (scripts / "redact_xctest_activity.py").write_text(
            "import sys\n"
            "content = sys.stdin.read()\n"
            "sys.stdout.write(content)\n"
            f"raise SystemExit({runtime_redactor_status} if 'RUNTIME_ONLY_MARKER' in content else 0)\n",
            encoding="utf-8",
        )
        real_python = next(MANAGED_ROOT.glob("cpython-3.13*/bin/python3.13"))
        (scripts / "run_python_with_uv.sh").write_text(
            "#!/usr/bin/env bash\n"
            "set -euo pipefail\n"
            "case ${1:-} in\n"
            f"  -c|scripts/redact_xctest_activity.py|scripts/assert_no_secret_artifacts.py) exec {str(real_python)!r} \"$@\" ;;\n"
            "  *) exit 0 ;;\n"
            "esac\n",
            encoding="utf-8",
        )
        (bin_dir / "xcrun").write_text(
            "#!/usr/bin/env bash\n"
            "if [[ $* == *'list devices -j'* ]]; then printf '%s\\n' '{\"devices\":{\"runtime\":[{\"name\":\"iPhone 17\",\"udid\":\"FAKE-SIM\",\"isAvailable\":true,\"state\":\"Booted\"}]}}'; exit 0; fi\n"
            "if [[ $* == *'log stream'* ]]; then printf '%s\\n' RUNTIME_ONLY_MARKER; fi\n"
            "exit 0\n",
            encoding="utf-8",
        )
        for command in ("xcodebuild", "xcodegen"):
            (bin_dir / command).write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
        (bin_dir / "tee").write_text("#!/usr/bin/env bash\nexec /usr/bin/tee \"$@\"\n", encoding="utf-8")
        for path in [*bin_dir.iterdir(), scripts / "run_python_with_uv.sh", scripts / "run_reelfin_player_e2e.sh"]:
            path.chmod(0o700)
        completed = subprocess.run(
            [str(scripts / "run_reelfin_player_e2e.sh"), "--skip-tvos", "--loops", "1", "--sample-size", "1"],
            cwd=mini_root,
            env={
                "PATH": f"{bin_dir}:{os.environ['PATH']}",
                "HOME": str(temp / "home"),
                "TMPDIR": str(temp),
                "REELFIN_QA_ARTIFACT_ROOT": str(temp / "artifacts"),
                "REELFIN_TEST_SERVER_URL": "https://qa.invalid",
                "REELFIN_TEST_USERNAME": "qa-user",
                "REELFIN_TEST_PASSWORD": "qa-password",
                "TEST_DIRECTPLAY_MP4_ITEM_ID": "item-direct",
                "TEST_MKV_ITEM_ID": "item-mkv",
                "TEST_HDR_ITEM_ID": "item-hdr",
                "TEST_DOLBY_VISION_ITEM_ID": "item-dv",
            },
            text=True,
            capture_output=True,
            check=False,
        )
        return completed, temporary

    def run_wrapper_contract(self, source: str, required_flag: str) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as temporary:
            temp = Path(temporary).resolve()
            fake_uv = temp / "uv"
            fake_python = temp / "python-root" / "cpython-3.13-test" / "bin" / "python3.13"
            fake_python.parent.mkdir(parents=True)
            fake_python.write_text("#!/usr/bin/env bash\nexit 70\n", encoding="utf-8")
            fake_python.chmod(0o700)
            fake_uv.write_text(
                "#!/usr/bin/env bash\n"
                "set -euo pipefail\n"
                "operation=run\n"
                "[[ ${1:-} == python && ${2:-} == find ]] && operation=find\n"
                "required=${FAKE_REQUIRED_FLAG}\n"
                "if [[ ${operation} == find && ${required} == --no-env-file ]]; then required=; fi\n"
                "found=0\n"
                "for argument in \"$@\"; do [[ ${argument} == \"${required}\" ]] && found=1; done\n"
                "[[ -z ${required} || ${found} -eq 1 ]] || exit 91\n"
                "if [[ ${operation} == find ]]; then printf '%s\\n' \"${FAKE_PYTHON}\"; exit 0; fi\n"
                "while [[ $# -gt 0 && $1 != python ]]; do shift; done\n"
                "[[ $# -gt 0 ]] || exit 92\n"
                "shift\n"
                "if [[ ${1:-} == -c && ${2:-} == *version_info* ]]; then printf '3.13|%s\\n' \"${FAKE_PYTHON}\"; exit 0; fi\n"
                "exec \"${REAL_PYTHON}\" \"$@\"\n",
                encoding="utf-8",
            )
            fake_uv.chmod(0o700)
            wrapper = temp / "wrapper.sh"
            rewritten = source.replace(EXPECTED_UV, str(fake_uv))
            rewritten = rewritten.replace(str(MANAGED_ROOT), str(temp / "python-root"))
            rewritten = rewritten.replace(EXPECTED_CACHE, str(temp / "uv-cache"))
            wrapper.write_text(rewritten, encoding="utf-8")
            wrapper.chmod(0o700)
            real_python = next(MANAGED_ROOT.glob("cpython-3.13*/bin/python3.13"))
            return subprocess.run(
                [str(wrapper), "-c", "print('wrapper-contract-ok')"],
                env={
                    "PATH": os.environ["PATH"],
                    "FAKE_REQUIRED_FLAG": required_flag,
                    "FAKE_PYTHON": str(fake_python),
                    "REAL_PYTHON": str(real_python),
                },
                text=True,
                capture_output=True,
                check=False,
            )

    def test_wrapper_uses_fixed_managed_interpreter_and_ignores_project_config_and_env_files(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            temp = Path(temporary)
            (temp / "pyproject.toml").write_text("this is not valid toml = [", encoding="utf-8")
            (temp / "uv.toml").write_text("this is not valid toml = [", encoding="utf-8")
            (temp / ".env").write_text("REELFIN_UV_ENV_SENTINEL=leaked\n", encoding="utf-8")
            probe = temp / "probe.py"
            probe.write_text(
                "import os, pathlib, sys\n"
                "print(sys.version_info[:2])\n"
                "print(pathlib.Path(sys.executable).resolve())\n"
                "print(os.environ.get('UV_PYTHON_INSTALL_DIR'))\n"
                "print(os.environ.get('UV_CACHE_DIR'))\n"
                "print(os.environ.get('PYTHONDONTWRITEBYTECODE'))\n"
                "print(os.environ.get('REELFIN_UV_ENV_SENTINEL', 'absent'))\n",
                encoding="utf-8",
            )
            completed = subprocess.run(
                [str(WRAPPER), str(probe)],
                cwd=temp,
                env={
                    **os.environ,
                    "UV_PYTHON_INSTALL_DIR": str(temp / "host-python"),
                    "UV_CACHE_DIR": str(temp / "host-cache"),
                    "UV_ENV_FILE": str(temp / ".env"),
                    "UV_MANAGED_PYTHON": "false",
                    "UV_PYTHON_DOWNLOADS": "automatic",
                },
                text=True,
                capture_output=True,
                check=False,
            )
        self.assertEqual(0, completed.returncode, completed.stderr)
        lines = completed.stdout.splitlines()
        self.assertEqual("(3, 13)", lines[0])
        self.assertTrue(Path(lines[1]).is_relative_to(MANAGED_ROOT), lines[1])
        self.assertEqual(str(MANAGED_ROOT), lines[2])
        self.assertEqual(EXPECTED_CACHE, lines[3])
        self.assertEqual("1", lines[4])
        self.assertEqual("absent", lines[5])

    def test_wrapper_invokes_every_required_uv_guard_for_find_and_run(self) -> None:
        source = WRAPPER.read_text(encoding="utf-8")
        required = (
            "--offline",
            "--no-project",
            "--no-config",
            "--no-env-file",
            "--no-python-downloads",
            "--managed-python",
        )
        for flag in required:
            with self.subTest(flag=flag):
                baseline = self.run_wrapper_contract(source, flag)
                self.assertEqual(0, baseline.returncode, baseline.stderr)
                mutated = self.run_wrapper_contract(source.replace(flag, "", 1), flag)
                self.assertNotEqual(0, mutated.returncode, f"{flag} mutation escaped")

    def test_redactor_covers_exact_upper_lower_and_mixed_percent_forms_from_environment(self) -> None:
        canary = "Qa /Pass+Canary?%2F"
        upper = "Qa%20%2FPass%2BCanary%3F%252F"
        lower = upper.lower()
        mixed = mixed_percent_encode(canary)
        completed = run_python(
            "scripts/redact_xctest_activity.py",
            input=f"exact={canary}\nupper={upper}\nlower={lower}\nmixed={mixed}\n",
            env={**os.environ, "REELFIN_SECRET_SCAN_VALUE": canary},
        )
        self.assertEqual(0, completed.returncode, completed.stderr)
        combined = completed.stdout + completed.stderr
        for forbidden in (canary, upper, lower, mixed, str(len(canary))):
            self.assertNotIn(forbidden, combined)
        self.assertGreaterEqual(completed.stdout.count("<redacted>"), 4)

    def test_unicode_secret_raw_and_percent_forms_are_redacted_and_scanned_without_argv(self) -> None:
        canary = "päss-✓"
        upper = urllib.parse.quote(canary, safe="")
        lower = re.sub(r"%[0-9A-F]{2}", lambda match: match.group(0).lower(), upper)
        encoded_index = [0]
        def alternate_percent_case(match: re.Match[str]) -> str:
            digits = match.group(0).upper() if encoded_index[0] % 2 == 0 else match.group(0).lower()
            encoded_index[0] += 1
            return digits
        mixed = re.sub(r"%[0-9A-F]{2}", alternate_percent_case, upper)
        forms = (canary, upper, lower, mixed)
        redacted = run_python(
            "scripts/redact_xctest_activity.py",
            input="\n".join(forms) + "\n",
            env={**os.environ, "REELFIN_SECRET_SCAN_VALUE": canary},
        )
        self.assertEqual(0, redacted.returncode, redacted.stderr)
        for form in forms:
            self.assertNotIn(form, redacted.stdout + redacted.stderr)
        self.assertEqual(4, redacted.stdout.count("<redacted>"))
        for form in forms:
            with self.subTest(form=form), tempfile.TemporaryDirectory() as temporary:
                (Path(temporary) / "retained.log").write_text(form, encoding="utf-8")
                scanned = run_python(
                    "scripts/assert_no_secret_artifacts.py",
                    temporary,
                    "--secrets-stdin",
                    input=f"{canary}\n",
                    env={"PATH": os.environ["PATH"]},
                )
                self.assertNotEqual(0, scanned.returncode)
                self.assertNotIn(canary, scanned.stdout + scanned.stderr)
                self.assertNotIn(form, scanned.stdout + scanned.stderr)

    def test_scanner_reads_canaries_from_stdin_and_never_echoes_matches(self) -> None:
        canary = "Qa /Pass+Canary?%2F"
        forms = (canary, "Qa%20%2FPass%2BCanary%3F%252F", "qa%20%2fpass%2bcanary%3f%252f", mixed_percent_encode(canary))
        for index, form in enumerate(forms):
            with self.subTest(index=index), tempfile.TemporaryDirectory() as temporary:
                artifact = Path(temporary) / "retained.log"
                artifact.write_text(f"prefix {form} suffix", encoding="utf-8")
                completed = run_python(
                    "scripts/assert_no_secret_artifacts.py",
                    temporary,
                    "--secrets-stdin",
                    input=f"{canary}\n",
                    env={"PATH": os.environ["PATH"]},
                )
            self.assertNotEqual(0, completed.returncode)
            self.assertNotIn(canary, completed.stdout + completed.stderr)
            self.assertNotIn(form, completed.stdout + completed.stderr)

    def test_scanner_rejects_xcresult_and_binary_state_in_retained_artifacts(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "credentialed.xcresult").mkdir()
            completed = run_python("scripts/assert_no_secret_artifacts.py", temporary)
            self.assertNotEqual(0, completed.returncode)
            self.assertNotIn("credentialed.xcresult", completed.stdout + completed.stderr)

    def test_e2e_rejects_credential_env_files_without_printing_the_value(self) -> None:
        canary = "Qa /Pass+Canary?%2F"
        with tempfile.TemporaryDirectory() as temporary:
            env_file = Path(temporary) / "qa.env"
            env_file.write_text(f"REELFIN_TEST_PASSWORD={canary}\n", encoding="utf-8")
            completed = subprocess.run(
                [str(SCRIPTS / "run_reelfin_player_e2e.sh"), "--env-file", str(env_file), "--skip-ui", "--skip-tvos"],
                cwd=ROOT,
                env={"PATH": os.environ["PATH"], "TMPDIR": temporary},
                text=True,
                capture_output=True,
                check=False,
            )
            leftovers = list(Path(temporary).glob("reelfin-*-qa.*"))
        self.assertNotEqual(0, completed.returncode)
        self.assertIn("Credential keys are rejected", completed.stdout + completed.stderr)
        self.assertNotIn(canary, completed.stdout + completed.stderr)
        self.assertEqual([], leftovers)

    def test_e2e_accepts_password_stdin_without_argv_or_output_disclosure(self) -> None:
        canary = "Qa /Pass+Canary?%2F"
        with tempfile.TemporaryDirectory() as temporary:
            completed = subprocess.run(
                [str(SCRIPTS / "run_reelfin_player_e2e.sh"), "--password-stdin", "--skip-ui", "--skip-tvos"],
                cwd=ROOT,
                env={"PATH": os.environ["PATH"], "TMPDIR": temporary},
                input=f"{canary}\n",
                text=True,
                capture_output=True,
                check=False,
            )
            leftovers = list(Path(temporary).glob("reelfin-*-qa.*"))
        self.assertNotEqual(0, completed.returncode)
        self.assertNotIn(canary, completed.stdout + completed.stderr)
        self.assertNotIn("password-stdin=MISSING", completed.stdout + completed.stderr)
        self.assertEqual([], leftovers)

    def test_playback_runner_redacts_both_streams_uses_transient_derived_data_and_cleans_it(self) -> None:
        completed, artifacts, xcode_record, canary, temporary = self.run_playback_harness(emit_canary=True)
        try:
            self.assertEqual(0, completed.returncode, completed.stderr)
            retained = "".join(path.read_text(encoding="utf-8") for path in artifacts.rglob("*") if path.is_file())
            self.assertNotIn(canary, retained)
            self.assertIn("<redacted>", retained)
            arguments = xcode_record.read_text(encoding="utf-8").splitlines()
            derived = Path(arguments[arguments.index("-derivedDataPath") + 1])
            self.assertFalse(derived.exists())
            self.assertFalse(any(artifacts.rglob("*.xcresult")))
            self.assertFalse(any(path.name.startswith("reelfin-playback-qa.") for path in Path(temporary.name).iterdir()))
            for path in artifacts.rglob("*"):
                mode = stat.S_IMODE(path.stat().st_mode)
                self.assertEqual(0o700 if path.is_dir() else 0o600, mode, path)
        finally:
            temporary.cleanup()

    def test_playback_runner_propagates_every_pipeline_component_status(self) -> None:
        for component, kwargs, expected in (
            ("producer", {"producer_status": 23}, 23),
            ("redactor", {"redactor_status": 24}, 24),
            ("tee", {"tee_status": 25}, 25),
        ):
            with self.subTest(component=component):
                completed, _, _, _, temporary = self.run_playback_harness(**kwargs)
                try:
                    self.assertEqual(expected, completed.returncode, completed.stderr)
                finally:
                    temporary.cleanup()

    def test_playback_runner_fails_when_only_background_runtime_redaction_fails(self) -> None:
        completed, _, _, _, temporary = self.run_playback_harness(runtime_redactor_status=24)
        try:
            self.assertEqual(24, completed.returncode, completed.stderr)
        finally:
            temporary.cleanup()

    def test_e2e_runner_fails_when_only_background_runtime_redaction_fails(self) -> None:
        completed, temporary = self.run_e2e_runtime_harness(runtime_redactor_status=24)
        try:
            self.assertEqual(24, completed.returncode, completed.stderr)
        finally:
            temporary.cleanup()

    def test_runners_have_one_immutable_trap_private_transient_state_and_no_global_secrets(self) -> None:
        forbidden_exports = re.compile(
            r"^\s*export\s+(?:SIMCTL_CHILD_)?(?:REELFIN_TEST_(?:SERVER_URL|USERNAME|PASSWORD)|"
            r"JELLYFIN_(?:BASE_URL|USERNAME|PASSWORD|SERVER|USER|PASS)|TEST_[A-Z0-9_]*ITEM_ID)",
            re.MULTILINE,
        )
        for name in ("run_playback_qa_loop.sh", "run_reelfin_player_e2e.sh"):
            source = (SCRIPTS / name).read_text(encoding="utf-8")
            with self.subTest(runner=name):
                traps = [line for line in source.splitlines() if re.match(r"^trap\s", line)]
                self.assertEqual(1, len(traps), traps)
                self.assertNotIn("trap -", source)
                self.assertIn("mktemp -d", source)
                self.assertIn("chmod 700", source)
                self.assertIsNone(forbidden_exports.search(source))
                self.assertNotRegex(source, r"(?:^|/)DerivedData(?:/|\"|'|$)")
                self.assertNotIn(".xcresult", source)

    def test_every_persisted_runner_stream_is_redacted_scanned_and_checks_all_pipeline_statuses(self) -> None:
        for name in ("run_playback_qa_loop.sh", "run_reelfin_player_e2e.sh"):
            source = (SCRIPTS / name).read_text(encoding="utf-8")
            with self.subTest(runner=name):
                self.assertNotRegex(source, r"2>&1\s*(?:>|\|\s*tee)")
                self.assertIn("assert_no_secret_artifacts.py", source)
                self.assertRegex(source, r"PIPESTATUS\[0\].*PIPESTATUS\[1\].*PIPESTATUS\[2\]")
                self.assertNotRegex(source, r"2>&1\s*\|\s*tee")

    def test_no_system_python_or_executable_python_entry_points_remain(self) -> None:
        offenders: list[str] = []
        python_files = [*SCRIPTS.glob("*.py"), *Path(__file__).parent.glob("test_*.py")]
        for path in python_files:
            first_line = path.read_text(encoding="utf-8").splitlines()[0:1]
            if path.stat().st_mode & stat.S_IXUSR or (first_line and "python" in first_line[0]):
                offenders.append(str(path.relative_to(ROOT)))
        for path in SCRIPTS.glob("*.sh"):
            if path.name == WRAPPER.name:
                continue
            if re.search(r"(^|[;&|\s])python3?(\s|$)", path.read_text(encoding="utf-8")):
                offenders.append(str(path.relative_to(ROOT)))
        self.assertEqual([], offenders)

    def test_defaults_target_ios_and_tvos_26_5(self) -> None:
        e2e = (SCRIPTS / "run_reelfin_player_e2e.sh").read_text(encoding="utf-8")
        self.assertIn("name=iPhone 17,OS=26.5", e2e)
        self.assertIn("name=Apple TV 4K (3rd generation),OS=26.5", e2e)


if __name__ == "__main__":
    unittest.main()
