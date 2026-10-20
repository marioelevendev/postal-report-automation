"""Unit tests for the date rule; these tests do not open a browser."""

import unittest
from datetime import date

from dates import build_report_dates


class BuildReportDatesTests(unittest.TestCase):
    """Check ordinary and end-of-month date combinations."""

    def test_requested_october_example(self) -> None:
        """20 October 2026 produces the values verified in the live run."""

        result = build_report_dates(date(2026, 10, 20))
        self.assertEqual(result, ("19-09-2025", "19-10-2026"))

    def test_invalid_day_is_clamped_to_end_of_month(self) -> None:
        """A day number that February lacks is safely moved to its last day."""

        result = build_report_dates(date(2026, 3, 1))
        self.assertEqual(result, ("28-02-2025", "28-03-2026"))


if __name__ == "__main__":
    unittest.main()

