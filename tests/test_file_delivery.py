"""Unit tests for reliable report copying; no network share is required."""

import tempfile
import unittest
from pathlib import Path

from file_delivery import copy_report_with_logging


class CopyReportWithLoggingTests(unittest.TestCase):
    """Verify successful copies and useful failure behavior."""

    def test_copy_is_verified_and_logged(self) -> None:
        """A local test file reaches the destination with a success log."""

        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source = root / "05112026_report.csv.zip"
            destination = root / "destination"
            logs = root / "logs"
            source.write_bytes(b"test zip content")
            destination.mkdir()

            result = copy_report_with_logging(
                source,
                destination,
                logs,
                attempts=1,
                retry_seconds=0,
            )

            self.assertEqual(result, destination / source.name)
            self.assertEqual(result.read_bytes(), source.read_bytes())
            self.assertFalse((destination / f"{source.name}.copying").exists())
            self.assertIn(
                "SUCCESS",
                next(logs.glob("copy_*.log")).read_text(encoding="utf-8"),
            )

    def test_unavailable_destination_preserves_local_file_and_logs_error(
        self,
    ) -> None:
        """A copy failure keeps the local file and writes an error log."""

        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source = root / "05112026_report.csv.zip"
            missing_destination = root / "missing"
            logs = root / "logs"
            source.write_bytes(b"local report remains available")

            with self.assertRaisesRegex(
                RuntimeError, "downloaded locally"
            ):
                copy_report_with_logging(
                    source,
                    missing_destination,
                    logs,
                    attempts=1,
                    retry_seconds=0,
                )

            self.assertTrue(source.is_file())
            self.assertIn(
                "FAILED",
                next(logs.glob("copy_*.log")).read_text(encoding="utf-8"),
            )


if __name__ == "__main__":
    unittest.main()

