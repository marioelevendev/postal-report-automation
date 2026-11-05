"""Reliably copy a downloaded report to the Talend trigger directory."""

from __future__ import annotations

import os
import shutil
import time
from datetime import datetime
from pathlib import Path


COPY_ATTEMPTS = 3
COPY_RETRY_SECONDS = 5


def _write_copy_log(log_file: Path, level: str, message: str) -> None:
    """Append one timestamped line to the dedicated copy log."""

    timestamp = datetime.now().astimezone().isoformat(timespec="seconds")
    with log_file.open("a", encoding="utf-8") as handle:
        handle.write(f"{timestamp} {level} {message}\n")


def copy_report_with_logging(
    source_file: Path,
    destination_directory: Path,
    log_directory: Path,
    *,
    attempts: int = COPY_ATTEMPTS,
    retry_seconds: int = COPY_RETRY_SECONDS,
) -> Path:
    """Copy a report to the network directory and log every attempt.

    The file is first copied with a '.copying' suffix. Only after its size is
    verified is it atomically renamed to the final ZIP filename. This prevents
    Talend from processing a partially copied file.
    """

    if attempts < 1:
        raise ValueError("attempts must be at least 1")

    source_file = source_file.resolve(strict=True)
    log_directory.mkdir(parents=True, exist_ok=True)
    log_file = log_directory / f"copy_{datetime.now():%Y-%m-%d}.log"

    final_path = destination_directory / source_file.name
    temporary_path = destination_directory / f"{source_file.name}.copying"

    for attempt_number in range(1, attempts + 1):
        try:
            if not destination_directory.is_dir():
                raise FileNotFoundError(
                    f"Destination directory is unavailable: "
                    f"{destination_directory}"
                )

            # Remove a partial file left by a previously interrupted attempt.
            if temporary_path.exists():
                temporary_path.unlink()

            shutil.copy2(source_file, temporary_path)

            if temporary_path.stat().st_size != source_file.stat().st_size:
                raise OSError(
                    "Copied file size does not match the local report size."
                )

            # os.replace safely replaces an older same-named report and keeps
            # the final ZIP name invisible to Talend until copying is complete.
            os.replace(temporary_path, final_path)

            message = (
                f"SUCCESS attempt={attempt_number}/{attempts} "
                f"source={source_file} destination={final_path} "
                f"bytes={final_path.stat().st_size}"
            )
            _write_copy_log(log_file, "INFO", message)
            print(f"Report copied successfully: {final_path}")
            print(f"Copy log: {log_file}")
            return final_path
        except Exception as error:  # noqa: BLE001 - log and retry I/O failures
            message = (
                f"FAILED attempt={attempt_number}/{attempts} "
                f"source={source_file} destination={final_path} "
                f"error={type(error).__name__}: {error}"
            )
            _write_copy_log(log_file, "ERROR", message)

            # A failed transfer must never leave a trigger-like temporary file.
            try:
                if temporary_path.exists():
                    temporary_path.unlink()
            except OSError as cleanup_error:
                _write_copy_log(
                    log_file,
                    "ERROR",
                    f"TEMP_CLEANUP_FAILED path={temporary_path} "
                    f"error={type(cleanup_error).__name__}: {cleanup_error}",
                )

            if attempt_number < attempts:
                print(
                    f"Copy attempt {attempt_number}/{attempts} failed: {error}. "
                    f"Retrying in {retry_seconds} seconds..."
                )
                time.sleep(retry_seconds)
                continue

            raise RuntimeError(
                f"The report was downloaded locally at {source_file}, but "
                f"copying it to {destination_directory} failed after "
                f"{attempts} attempts. See {log_file}."
            ) from error

    # The loop either returns or raises. This guard keeps static analyzers happy.
    raise AssertionError("Unreachable copy state.")

