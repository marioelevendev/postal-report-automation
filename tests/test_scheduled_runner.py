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
    """Verify that failures retain their complete Python traceback."""

    def test_multiline_stderr_is_logged_and_exit_code_is_preserved(self) -> None:
        powershell = shutil.which("powershell.exe")
        if powershell is None:
            self.skipTest("Windows PowerShell is not installed.")

        # Keep the fixture inside the project tree. This also works in locked
        # down automation environments where the account cannot execute from
        # the user's general AppData temporary directory.
        with tempfile.TemporaryDirectory(dir=PROJECT_ROOT / "tests") as temporary_directory:
            test_project = Path(temporary_directory)
            shutil.copy2(PROJECT_ROOT / "run_scheduled.ps1", test_project)
            shutil.copy2(PROJECT_ROOT / "append_network_log.ps1", test_project)

            # A copied venv launcher plus pyvenv.cfg still points to the same
            # installed base Python, while keeping the fixture self-contained.
            scripts_directory = test_project / ".venv" / "Scripts"
            scripts_directory.mkdir(parents=True)
            shutil.copy2(Path(sys.executable), scripts_directory / "python.exe")
            shutil.copy2(Path(sys.prefix) / "pyvenv.cfg", test_project / ".venv")

            failing_program = """
import sys

print("stdout before simulated failure", flush=True)
sys.stderr.write("Traceback (most recent call last):\\n")
sys.stderr.write('  File "simulated.py", line 7, in <module>\\n')
sys.stderr.write("RuntimeError: simulated scheduled failure\\n")
sys.stderr.flush()
raise SystemExit(17)
""".lstrip()
            (test_project / "main.py").write_text(failing_program, encoding="utf-8")

            environment = os.environ.copy()
            environment["POSTAL_APPEND_NETWORK_LOG"] = "false"
            completed = subprocess.run(
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

            self.assertEqual(
                completed.returncode,
                17,
                msg=(
                    "The scheduled wrapper did not preserve Python's exit code.\n"
                    f"stdout:\n{completed.stdout}\n"
                    f"stderr:\n{completed.stderr}"
                ),
            )
            log_files = list((test_project / "logs").glob("*.log"))
            self.assertEqual(len(log_files), 1)

            raw_log = log_files[0].read_bytes()
            self.assertNotIn(b"\x00", raw_log)
            log_text = raw_log.decode("utf-8-sig")
            self.assertIn("stdout before simulated failure", log_text)
            self.assertIn("Traceback (most recent call last):", log_text)
            self.assertIn('File "simulated.py", line 7', log_text)
            self.assertIn("RuntimeError: simulated scheduled failure", log_text)
            self.assertIn("Automation exit code: 17", log_text)


if __name__ == "__main__":
    unittest.main()
