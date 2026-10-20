"""Dependency-free date calculations for the report filters."""

import calendar
from datetime import date, timedelta


def build_report_dates(reference_date: date) -> tuple[str, str]:
    """Return the FromDate and ToDate values requested by the workflow.

    The rule uses the previous day's *day number* in both values:

    * FromDate = previous-day number / previous month / previous year
    * ToDate   = previous-day number / current month / current year

    Some combinations do not exist, such as day 31 in February. In that rare
    case, the day is safely clamped to the final day of the target month.
    """

    previous_day_number = (reference_date - timedelta(days=1)).day

    # January wraps back to December when we calculate the previous month.
    previous_month = 12 if reference_date.month == 1 else reference_date.month - 1
    previous_year = reference_date.year - 1

    # Clamp the day number so we never try to construct an invalid date.
    from_last_day = calendar.monthrange(previous_year, previous_month)[1]
    to_last_day = calendar.monthrange(reference_date.year, reference_date.month)[1]
    from_day = min(previous_day_number, from_last_day)
    to_day = min(previous_day_number, to_last_day)

    from_date = date(previous_year, previous_month, from_day)
    to_date = date(reference_date.year, reference_date.month, to_day)

    return from_date.strftime("%d-%m-%Y"), to_date.strftime("%d-%m-%Y")

