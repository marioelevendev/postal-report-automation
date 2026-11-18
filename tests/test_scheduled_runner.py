"""Regression tests for the Windows scheduled-run PowerShell wrapper."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(os.name == "nt", "The scheduled runner is Windows-only.")
class ScheduledRunnerTests(unittest.TestCase):
    """Verify complete errors, one retry, and dated error reports."""

    def _prepare_project(self, temporary_directory: str, program: str) -> Path:
        """Create a small deployment-shaped project for the wrapper test."""
        test_project = Path(temporary_directory)
        for script_name in (
            "run_scheduled.ps1",
            "append_network_log.ps1",
            "write_error_report.ps1",
        ):
            shutil.copy2(PROJECT_ROOT / script_name, test_project)

        # A copied venv launcher plus pyvenv.cfg still points to the same
        # installed base Python, while keeping the fixture self-contained.
        scripts_directory = test_project / ".venv" / "Scripts"
        scripts_directory.mkdir(parents=True)
        shutil.copy2(Path(sys.executable), scripts_directory / "python.exe")
        shutil.copy2(Path(sys.prefix) / "pyvenv.cfg", test_project / ".venv")
        (test_project / "main.py").write_text(program, encoding="utf-8")
        (test_project / "error_reports").mkdir()
        return test_project

    def _run_wrapper(self, test_project: Path) -> subprocess.CompletedProcess[str]:
        """Run the production wrapper through Windows PowerShell 5.1."""
        powershell = shutil.which("powershell.exe")
        if powershell is None:
            self.skipTest("Windows PowerShell is not installed.")

        environment = os.environ.copy()
        environment["POSTAL_APPEND_NETWORK_LOG"] = "false"
        environment["POSTAL_RETRY_DELAY_SECONDS"] = "0"
        environment["POSTAL_ERROR_LOG_DIR"] = str(test_project / "error_reports")
        return subprocess.run(
            [
                powershell,
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(test_project / "run_scheduled.ps1"),
            ],
            cwd=test_project,
            env=environment,
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )

    def test_persistent_failure_runs_exactly_twice_and_preserves_error(self) -> None:
        """Two failed attempts retain the traceback and final exit code."""
        program = """
from pathlib import Path
import sys

counter_file = Path(__file__).with_name("attempt_count.txt")
attempt = int(counter_file.read_text() or "0") + 1 if counter_file.exists() else 1
counter_file.write_text(str(attempt))
print(f"stdout from attempt {attempt}", flush=True)
sys.stderr.write("Traceback (most recent call last):\\n")
sys.stderr.write('  File "simulated.py", line 7, in <module>\\n')
sys.stderr.write("RuntimeError: simulated scheduled failure\\n")
sys.stderr.flush()
raise SystemExit(17)
""".lstrip()

        with tempfile.TemporaryDirectory(dir=PROJECT_ROOT / "tests") as temporary_directory:
            test_project = self._prepare_project(temporary_directory, program)
            completed = self._run_wrapper(test_project)

            self.assertEqual(
                completed.returncode,
                17,
                msg=f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}",
            )
            self.assertEqual((test_project / "attempt_count.txt").read_text(), "2")

            log_files = list((test_project / "logs").glob("*.log"))
            self.assertEqual(len(log_files), 1)
            raw_log = log_files[0].read_bytes()
            self.assertNotIn(b"\x00", raw_log)
            log_text = raw_log.decode("utf-8-sig")
            self.assertEqual(log_text.count("Traceback (most recent call last):"), 2)
            self.assertIn("Attempt 1 of 2 failed with exit code 17", log_text)
            self.assertIn("Attempt 2 of 2 failed with exit code 17", log_text)
            self.assertIn("Automation exit code: 17", log_text)

            error_files = list((test_project / "error_reports").glob("*"))
            self.assertEqual(len(error_files), 1)
            self.assertRegex(
                error_files[0].name,
                r"^\d{8}-error_postal-report-automation-1001234$",
            )
            error_text = error_files[0].read_text(encoding="utf-8")
            self.assertEqual(error_text.count("Outcome: Failed"), 2)
            self.assertIn("RuntimeError: simulated scheduled failure", error_text)

    def test_successful_retry_records_recovery_and_returns_success(self) -> None:
        """A transient first failure is recovered by one complete retry."""
        program = """
from pathlib import Path
import sys

counter_file = Path(__file__).with_name("attempt_count.txt")
attempt = int(counter_file.read_text() or "0") + 1 if counter_file.exists() else 1
counter_file.write_text(str(attempt))
if attempt == 1:
    sys.stderr.write("RuntimeError: transient simulated failure\\n")
    sys.stderr.flush()
    raise SystemExit(23)
print("automatic retry recovered successfully", flush=True)
""".lstrip()

        with tempfile.TemporaryDirectory(dir=PROJECT_ROOT / "tests") as temporary_directory:
            test_project = self._prepare_project(temporary_directory, program)
            completed = self._run_wrapper(test_project)

            self.assertEqual(
                completed.returncode,
                0,
                msg=f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}",
            )
            self.assertEqual((test_project / "attempt_count.txt").read_text(), "2")

            log_file = next((test_project / "logs").glob("*.log"))
            log_text = log_file.read_text(encoding="utf-8-sig")
            self.assertIn("Attempt 1 of 2 failed with exit code 23", log_text)
            self.assertIn("Retrying the complete automation once", log_text)
            self.assertIn("Attempt 2 of 2 completed successfully", log_text)
            self.assertIn("Automation exit code: 0", log_text)

            error_file = next((test_project / "error_reports").glob("*"))
            error_text = error_file.read_text(encoding="utf-8")
            self.assertIn("Outcome: Failed", error_text)
            self.assertIn("Exit code: 23", error_text)
            self.assertIn("Outcome: Recovered", error_text)
            self.assertIn("The automatic retry completed successfully", error_text)


if __name__ == "__main__":
    unittest.main()
