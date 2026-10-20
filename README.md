# Postal report automation

This small Python project reproduces the report flow verified against the live
Postal Management site:

1. Open installed Google Chrome in a visible, isolated Incognito-style context.
2. Sign in with credentials stored in a local `.env` file.
3. Submit the authenticator code already populated in the two-factor field.
4. Open **Project Reports → Filters**.
5. Calculate and fill `FromDate` and `ToDate`.
6. Select only `Epa Warehouse Billing` and `ΕΠΑ BILLING-ELECTRICITY`.
7. Select all matching dispatches and download the ZIP report.
8. Open the user menu and confirm **Logout**.

## Date rule

The script implements the requested component-based rule:

- `FromDate`: previous-day number, previous month, previous year.
- `ToDate`: previous-day number, current month, current year.

For example, a run on **20 October 2026** uses:

- `FromDate = 19-09-2025`
- `ToDate = 19-10-2026`

If the chosen day does not exist in a month, it is safely clamped to that
month's final day.

## Setup on Windows

Open PowerShell in this folder and create a virtual environment:

```powershell
py -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
```

The script controls the locally installed Google Chrome (`channel="chrome"`).
If Playwright reports that its browser support files are missing, run:

```powershell
python -m playwright install
```

Create the private settings file:

```powershell
Copy-Item .env.example .env
```

Edit `.env` and set `POSTAL_USERNAME` and `POSTAL_PASSWORD`. The `.gitignore`
file excludes `.env`, so credentials are not committed to source control.

## Run

```powershell
python main.py
```

The code never reads or stores a 2FA secret. It only submits a value that is
already present in the website's authenticator-code field. If that field is
empty, the run stops with a clear error instead of attempting an invalid login.
Reports are saved in `downloads` unless `POSTAL_DOWNLOAD_DIR` is set in `.env`.

To check only the calculated dates without opening Chrome or needing secrets:

```powershell
python main.py --dry-run
```

## Daily execution at 07:00

The Codex app can run this project every day at 07:00. A recurring local job
named **Daily postal report** has been created for the `Python` project.

Three PowerShell helpers are also included for computers that should schedule
the job directly through Windows Task Scheduler:

- `setup.ps1` creates `.venv` and installs the Python dependencies.
- `install_daily_task.ps1` registers a Windows task for 07:00 every day.
- `run_now.ps1` runs the same project immediately on demand.

Run setup once and complete the generated `.env`:

```powershell
.\setup.ps1
notepad .env
```

Do not install a second Windows schedule while the Codex job is active, because
both schedules would download the report. If you intentionally disable the
Codex job and prefer Windows Task Scheduler, install the standalone task with:

```powershell
.\install_daily_task.ps1
```

The Windows task is named `Postal Report Automation - 07-00`. It uses the
Europe/Athens computer time zone and runs only while this Windows user is logged
on, which avoids storing the Windows account password in Task Scheduler.

To run the automation immediately:

```powershell
.\run_now.ps1
```

## Run the date tests

```powershell
python -m unittest discover -s tests -v
```

## Selector maintenance

The code prefers visible roles and labels because they are easier to understand
and usually more stable than generated CSS classes. Two selectors intentionally
use verified IDs/classes:

- `#myTable tr` limits project matching to the project grid.
- `a.nav-link[data-toggle='dropdown']:has(i.fa-user-circle)` identifies the
  icon-only user menu described in the original requirement.

If the website wording or HTML changes, the script raises an error instead of
silently selecting an unintended project.

