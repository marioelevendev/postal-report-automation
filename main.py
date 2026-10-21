"""Download the Postal Management project report with Playwright.

The script intentionally keeps passwords out of the source code. The username
and password come from a local ``.env`` file, while the script only submits a
two-factor code that the website has already populated.
"""

from __future__ import annotations

import argparse
import os
import re
from dataclasses import dataclass
from datetime import date, datetime
from pathlib import Path

from dotenv import load_dotenv
from playwright.sync_api import (
    Browser,
    BrowserContext,
    Page,
    Playwright,
    TimeoutError as PlaywrightTimeoutError,
    sync_playwright,
)

from dates import build_report_dates


# This is the public entry page used by both the live walkthrough and the script.
BASE_URL = "https://vncrdpostal.informservices.gr"

# These are the only client/project labels that the user asked us to select.
PROJECT_LABELS = (
    "Epa Warehouse Billing",
    "ΕΠΑ BILLING-ELECTRICITY",
)

# A report can take a while to be generated, so downloads get a longer timeout.
REPORT_TIMEOUT_MS = 180_000


@dataclass(frozen=True)
class Settings:
    """Values needed for one automation run."""

    username: str
    password: str
    download_directory: Path
    reference_date: date
    headless: bool


def parse_arguments() -> argparse.Namespace:
    """Read the small set of command-line options supported by the project."""

    parser = argparse.ArgumentParser(
        description="Download the selected Postal Management project report."
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the calculated dates without opening Chrome.",
    )
    parser.add_argument(
        "--headless",
        action="store_true",
        help="Run Chrome without showing a browser window (recommended for scheduling).",
    )
    return parser.parse_args()


def load_settings(require_credentials: bool = True) -> Settings:
    """Load secrets and optional settings from the local environment.

    ``load_dotenv`` reads a local .env file when it exists.  The .env file is
    excluded from Git so credentials cannot be committed accidentally.
    """

    load_dotenv()

    username = os.getenv("POSTAL_USERNAME", "").strip()
    password = os.getenv("POSTAL_PASSWORD", "")

    # A dry run does not visit the website, so it does not need credentials.
    if require_credentials and (not username or not password):
        raise RuntimeError(
            "POSTAL_USERNAME and POSTAL_PASSWORD must be set in the .env file."
        )

    # Save generated reports inside the project unless another folder is set.
    default_download_directory = Path(__file__).parent / "downloads"
    download_directory = Path(
        os.getenv("POSTAL_DOWNLOAD_DIR", str(default_download_directory))
    ).expanduser()

    # This override is useful for testing.  Normal runs use the computer's date.
    reference_date_text = os.getenv("POSTAL_REFERENCE_DATE", "").strip()
    if reference_date_text:
        try:
            reference_date = datetime.strptime(
                reference_date_text, "%Y-%m-%d"
            ).date()
        except ValueError as error:
            raise RuntimeError(
                "POSTAL_REFERENCE_DATE must use the format YYYY-MM-DD."
            ) from error
    else:
        reference_date = date.today()

    # Scheduled runs normally use headless mode. Values such as true, 1, and yes
    # are accepted so the setting is convenient to write in a .env file.
    headless = os.getenv("POSTAL_HEADLESS", "false").strip().lower() in {
        "1",
        "true",
        "yes",
        "on",
    }

    return Settings(
        username=username,
        password=password,
        download_directory=download_directory.resolve(),
        reference_date=reference_date,
        headless=headless,
    )


def launch_chrome(
    playwright: Playwright, headless: bool
) -> tuple[Browser, BrowserContext, Page]:
    """Open installed Google Chrome in an isolated browser context."""

    # Playwright contexts are isolated like Incognito windows.  The explicit
    # flag also makes the requested intent clear when launching Google Chrome.
    chrome_arguments = ["--incognito"]
    if not headless:
        chrome_arguments.append("--start-maximized")

    browser = playwright.chromium.launch(
        channel="chrome",
        headless=headless,
        args=chrome_arguments,
    )

    # Downloads are allowed because the final action saves a ZIP report.
    if headless:
        context = browser.new_context(
            accept_downloads=True,
            viewport={"width": 1920, "height": 1080},
        )
    else:
        context = browser.new_context(accept_downloads=True, viewport=None)
    page = context.new_page()
    page.set_default_timeout(30_000)

    return browser, context, page


def log_in(page: Page, settings: Settings) -> None:
    """Sign in and submit the two-factor code already present in its field."""

    page.goto(BASE_URL, wait_until="domcontentloaded")

    # Placeholder selectors match the visible login form and are easy to read.
    page.get_by_placeholder("Email / Username").fill(settings.username)
    page.get_by_placeholder("Password").fill(settings.password)
    page.get_by_role("button", name=re.compile(r"Sign In", re.IGNORECASE)).click()

    # The account currently uses two-factor authentication. We wait briefly
    # for that screen, but also allow accounts that do not require 2FA.
    two_factor_field = page.locator("#Input_TwoFactorCode")
    try:
        two_factor_field.wait_for(state="visible", timeout=15_000)
    except PlaywrightTimeoutError:
        pass
    else:
        # The established process populates this field outside this script. We
        # deliberately do not overwrite it or store a 2FA secret in the project.
        if not two_factor_field.input_value().strip():
            raise RuntimeError(
                "The 2FA page appeared, but its authenticator-code field was empty."
            )

        page.get_by_role("button", name="Log in", exact=True).click()

    # Waiting for this navigation item verifies that authentication succeeded.
    page.get_by_role(
        "link", name=re.compile(r"Project Reports", re.IGNORECASE)
    ).wait_for(state="visible", timeout=30_000)


def open_project_filters(page: Page) -> None:
    """Open Project Reports and then its Filters page."""

    page.get_by_role(
        "link", name=re.compile(r"Project Reports", re.IGNORECASE)
    ).click()
    page.get_by_role("link", name=re.compile(r"Filters", re.IGNORECASE)).click()

    # This heading confirms that the expected project-selection page loaded.
    page.get_by_role("heading", name="Select Projects", exact=True).wait_for(
        state="visible"
    )


def set_dates(page: Page, from_date: str, to_date: str) -> None:
    """Replace the two pre-filled date values with the calculated values."""

    page.get_by_role("textbox", name="FromDate", exact=True).fill(from_date)
    page.get_by_role("textbox", name="ToDate", exact=True).fill(to_date)


def select_requested_projects(page: Page) -> None:
    """Select exactly the two rows identified by their client/project labels."""

    project_rows = page.locator("#myTable tr")

    for label in PROJECT_LABELS:
        # Restrict the search to one table row, then select its only checkbox.
        matching_row = project_rows.filter(has_text=label)
        match_count = matching_row.count()

        # Failing loudly is safer than downloading a report for the wrong row.
        if match_count != 1:
            raise RuntimeError(
                f"Expected one project row for {label!r}, found {match_count}."
            )

        checkbox = matching_row.get_by_role("checkbox")

        # The site renders a Bootstrap-style label on top of the real input.
        # A normal Playwright click therefore waits for the input to receive
        # pointer events and eventually times out. ``force=True`` keeps
        # Playwright's checkbox semantics and final checked-state validation,
        # while allowing this intentional custom-control overlay.
        checkbox.set_checked(True, force=True)

        # Keep an explicit guard here because selecting the wrong set of
        # projects would produce an incorrect report.
        if not checkbox.is_checked():
            raise RuntimeError(f"Could not select project row for {label!r}.")

    # Submit the two checked project rows and wait for dispatch selection.
    with page.expect_navigation(wait_until="domcontentloaded"):
        page.get_by_role(
            "button", name=re.compile(r"Select Projects", re.IGNORECASE)
        ).click()

    page.get_by_role("heading", name="Select Dispatches", exact=True).wait_for(
        state="visible"
    )


def select_all_dispatches(page: Page) -> None:
    """Use the site's Select ALL action to include every matching dispatch."""

    # On the verified site, Select ALL submits the dispatch list immediately
    # and navigates straight to the results page.
    with page.expect_navigation(wait_until="domcontentloaded"):
        page.get_by_role(
            "link", name=re.compile(r"Select ALL", re.IGNORECASE)
        ).click()

    page.get_by_role("heading", name="Dispatches", exact=True).wait_for(
        state="visible"
    )


def download_report(
    page: Page, download_directory: Path, report_date: date
) -> Path:
    """Download the ZIP with a DDMMYYYY prefix and return its local path."""

    download_directory.mkdir(parents=True, exist_ok=True)

    # Start listening before clicking so a fast download event is never missed.
    with page.expect_download(timeout=REPORT_TIMEOUT_MS) as download_info:
        page.get_by_role(
            "link", name=re.compile(r"Download Report", re.IGNORECASE)
        ).click()

    download = download_info.value

    # Keep the filename supplied by the website, but add the run date first so
    # reports are easy to sort and identify. Path.name also prevents a browser
    # supplied path from escaping the configured download directory.
    original_filename = Path(download.suggested_filename).name
    dated_filename = f"{report_date:%d%m%Y}_{original_filename}"
    output_path = download_directory / dated_filename
    download.save_as(output_path)

    if not output_path.is_file():
        raise RuntimeError(f"The report was not saved at {output_path}.")

    return output_path


def dismiss_notification_toasts(page: Page) -> None:
    """Remove completed toast messages that cover the user menu."""

    toast_containers = page.locator("#toastsContainerTopRight")
    if toast_containers.count() == 0:
        return

    # The report-complete toast remains above the user icon and intercepts all
    # pointer events. At this stage the report is already saved, so removing
    # only this notification container is safe and leaves the page controls
    # unchanged. Using evaluate_all also handles an accidental duplicate ID.
    toast_containers.evaluate_all(
        "containers => containers.forEach(container => container.remove())"
    )
    print("Dismissed the report notification before logout.")


def log_out(page: Page) -> None:
    """Open the user menu, confirm Logout in the modal, and verify sign-out."""

    dismiss_notification_toasts(page)

    # The icon-only user menu has no useful visible label, so this selector uses
    # the stable HTML classes shown in the verified page markup.
    user_menu = page.locator(
        "a.nav-link[data-toggle='dropdown']:has(i.fa-user-circle)"
    )
    user_menu.click()

    # Include the hidden link in the locator so we can recover if Bootstrap
    # receives the menu click but does not visually open its dropdown.
    logout_link = page.get_by_role(
        "link", name="Logout", exact=True, include_hidden=True
    )
    try:
        logout_link.wait_for(state="visible", timeout=5_000)
        logout_link.click()
    except PlaywrightTimeoutError:
        print(
            "The user dropdown did not open; activating its existing "
            "Logout link directly."
        )
        logout_link.evaluate("element => element.click()")

    # Scope the final button lookup to the confirmation modal to avoid matching
    # the menu link that is also named Logout.
    logout_modal = page.locator("#logoutModal")
    logout_modal.wait_for(state="visible")

    with page.expect_navigation(wait_until="domcontentloaded"):
        logout_modal.get_by_role("button", name="Logout", exact=True).click()

    page.get_by_role(
        "button", name=re.compile(r"Sign In", re.IGNORECASE)
    ).wait_for(state="visible")


def run_automation(settings: Settings) -> Path:
    """Run the complete browser workflow and return the downloaded file path."""

    from_date, to_date = build_report_dates(settings.reference_date)
    logged_in = False
    logged_out = False

    with sync_playwright() as playwright:
        browser, context, page = launch_chrome(playwright, settings.headless)

        try:
            print(f"Using FromDate: {from_date}")
            print(f"Using ToDate:   {to_date}")

            log_in(page, settings)
            logged_in = True

            open_project_filters(page)
            set_dates(page, from_date, to_date)
            select_requested_projects(page)
            select_all_dispatches(page)
            report_path = download_report(
                page, settings.download_directory, settings.reference_date
            )

            log_out(page)
            logged_out = True
            return report_path
        finally:
            # If a later step fails, make one best-effort attempt to end the web
            # session before closing the isolated browser context.
            if logged_in and not logged_out:
                try:
                    log_out(page)
                except Exception as logout_error:  # noqa: BLE001
                    print(f"Warning: automatic logout failed: {logout_error}")

            context.close()
            browser.close()


def main() -> None:
    """Command-line entry point."""

    arguments = parse_arguments()
    settings = load_settings(require_credentials=not arguments.dry_run)
    if arguments.headless:
        # A command-line option takes precedence over POSTAL_HEADLESS in .env.
        settings = Settings(
            username=settings.username,
            password=settings.password,
            download_directory=settings.download_directory,
            reference_date=settings.reference_date,
            headless=True,
        )
    from_date, to_date = build_report_dates(settings.reference_date)

    if arguments.dry_run:
        print(f"Reference date: {settings.reference_date:%d-%m-%Y}")
        print(f"FromDate:       {from_date}")
        print(f"ToDate:         {to_date}")
        return

    report_path = run_automation(settings)
    print(f"Report downloaded successfully: {report_path}")


if __name__ == "__main__":
    main()

