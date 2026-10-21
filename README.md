# Postal report automation

This Python project automates the Postal Management report workflow. It can run
on demand in a visible Chrome window or automatically in headless mode every day
at **07:00 Europe/Athens time**.

The project is also available on
[GitHub](https://github.com/marioelevendev/postal-report-automation).

## What the automation does

1. Opens the locally installed Google Chrome in an isolated Incognito-style
   browser context.
2. Signs in with credentials stored in a private local `.env` file.
3. Submits the authenticator code that is already populated in the two-factor
   authentication field.
4. Opens **Project Reports → Filters**.
5. Calculates and fills `FromDate` and `ToDate`.
6. Selects only these projects:
   - `Epa Warehouse Billing`
   - `ΕΠΑ BILLING-ELECTRICITY`
7. Clicks **Select Projects**, selects all matching dispatches, and downloads
   the report.
8. Opens the user menu and confirms **Logout**.

## Date rule

The script implements the requested component-based rule:

- `FromDate`: previous-day number, previous month, previous year.
- `ToDate`: previous-day number, current month, current year.

For example, a run on **20 October 2026** uses:

- `FromDate = 19-09-2025`
- `ToDate = 19-10-2026`

If the selected day does not exist in a month, the script safely uses that
month's final day. This prevents invalid dates such as 31 February.

## Requirements

Before starting, make sure the computer has:

- Windows 10 or Windows 11.
- Python 3.10 or newer.
- Google Chrome.
- PowerShell.
- Access to the Postal Management website.
- A valid Postal Management username and password.

Check that Python is available:

```powershell
py --version
```

Expected output is similar to:

```text
Python 3.12.7
```

The exact version may be different. Python 3.10 or newer is suitable. If
PowerShell says that `py` is not recognized, install Python from
[python.org](https://www.python.org/downloads/windows/) and enable the option to
add the Python launcher to Windows.

## Project files

| File or directory | Purpose |
| --- | --- |
| `main.py` | Runs the browser automation. |
| `dates.py` | Calculates the requested FromDate and ToDate values. |
| `.env.example` | Safe template showing the available private settings. |
| `.env` | Your private credentials and settings; it is not uploaded to GitHub. |
| `requirements.txt` | Lists the Python packages required by the project. |
| `setup.ps1` | Creates the virtual environment and installs dependencies. |
| `run_now.ps1` | Runs the automation immediately. |
| `install_daily_task.ps1` | Optionally creates a Windows Scheduled Task. |
| `tests` | Contains automated tests for the date calculations. |
| `downloads` | Default location for downloaded reports. |
| `logs` | Output from scheduled runs. |

## Open the project in PowerShell

Open PowerShell and move to the project directory:

```powershell
Set-Location "C:\Users\m.diles\Documents\ChatGPT\Python\postal_report_automation"
```

`Set-Location` changes PowerShell's current directory. Most commands in this
README assume that PowerShell is already in this project directory.

To confirm the current directory:

```powershell
Get-Location
```

## Setup option A: automatic setup

The simplest setup command is:

```powershell
.\setup.ps1
```

The setup script:

1. Creates `.venv` if it does not already exist.
2. Installs the packages from `requirements.txt`.
3. Creates `.env` from `.env.example` if necessary.
4. Creates the `downloads` and `logs` directories.

When it succeeds, it prints instructions for editing `.env` and running the
project. Re-running `setup.ps1` is safe; it reuses the existing virtual
environment.

## Setup option B: manual setup

The same setup can be performed one command at a time:

```powershell
py -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
```

### Command 1: create a virtual environment

```powershell
py -m venv .venv
```

| Part | Explanation |
| --- | --- |
| `py` | Windows Python Launcher. It selects an installed Python interpreter. |
| `-m` | Tells Python to run a module as a program. |
| `venv` | Python's built-in module for creating virtual environments. |
| `.venv` | The directory in which the virtual environment is created. |

A virtual environment gives this project its own Python interpreter and
packages. It prevents this project's dependencies from interfering with other
Python projects on the computer.

The command usually produces no output when it succeeds. A new `.venv`
directory should appear. Verify it with:

```powershell
Test-Path .\.venv\Scripts\python.exe
```

Expected output:

```text
True
```

### Command 2: activate the virtual environment

```powershell
.\.venv\Scripts\Activate.ps1
```

| Part | Explanation |
| --- | --- |
| `.\` | Tells PowerShell to run a file from the current directory. |
| `.venv\Scripts` | Directory containing the environment's Windows commands. |
| `Activate.ps1` | PowerShell script that selects this environment for the current terminal. |

After activation, the PowerShell prompt normally begins with `(.venv)`:

```text
(.venv) PS C:\Users\m.diles\Documents\ChatGPT\Python\postal_report_automation>
```

Activation affects only the current PowerShell window. A new PowerShell window
must activate the environment again before manual `python` commands are run.
The included helper scripts use the environment directly, so they do not depend
on manual activation.

To verify which Python interpreter is active:

```powershell
python -c "import sys; print(sys.executable)"
```

The displayed path should end with:

```text
postal_report_automation\.venv\Scripts\python.exe
```

If PowerShell reports that script execution is disabled, allow scripts only for
the current PowerShell process and then retry activation:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\.venv\Scripts\Activate.ps1
```

This temporary policy ends when that PowerShell window is closed.

### Command 3: install the required packages

```powershell
python -m pip install -r requirements.txt
```

| Part | Explanation |
| --- | --- |
| `python` | Uses the currently active Python interpreter. |
| `-m pip` | Runs that interpreter's package installer. |
| `install` | Asks pip to install packages. |
| `-r requirements.txt` | Reads the package names and versions from the requirements file. |

Using `python -m pip` is useful because it ensures that packages are installed
for the same Python interpreter that will run the project.

During installation, pip displays download and installation progress. A
successful result normally includes `Successfully installed ...`. If the
packages are already present, `Requirement already satisfied` is normal.

The script controls the locally installed Google Chrome by using Playwright's
`channel="chrome"` option. If Playwright reports that browser support files
are missing, run:

```powershell
python -m playwright install
```

## Configure private settings

Create the private settings file:

```powershell
Copy-Item .env.example .env
```

The command normally produces no output. It creates a local `.env` file from
the safe example file. Open it in a text editor:

```powershell
notepad .env
```

At minimum, replace the placeholder values:

```dotenv
POSTAL_USERNAME=your_real_username
POSTAL_PASSWORD=your_real_password
POSTAL_HEADLESS=true
```

Available settings:

| Setting | Meaning |
| --- | --- |
| `POSTAL_USERNAME` | Postal Management username. Required for a real run. |
| `POSTAL_PASSWORD` | Postal Management password. Required for a real run. |
| `POSTAL_HEADLESS` | `true` hides Chrome; `false` shows the browser. |
| `POSTAL_DOWNLOAD_DIR` | Optional custom directory for downloaded reports. |
| `POSTAL_REFERENCE_DATE` | Optional testing override in `YYYY-MM-DD` format. Normally leave empty. |

Security notes:

- Never upload or send the `.env` file to another person.
- Never place real credentials in Python code, screenshots, README files, or
  Git commits.
- `.env` is excluded by `.gitignore`.
- `.env.example` contains placeholders only and is safe to keep on GitHub.

## Run on demand

For a normal visible run:

```powershell
.\run_now.ps1
```

During the run, expect Chrome to open and move through the login, filters,
project selection, dispatch selection, download, and logout pages. A successful
run prints the full path of the downloaded report.

For an on-demand run without showing Chrome:

```powershell
.\run_now.ps1 -Headless
```

If the virtual environment is already active, the equivalent direct commands
are:

```powershell
python main.py
python main.py --headless
```

Do not close the PowerShell window or shut down the computer while an on-demand
run is active.

## Check the dates without opening Chrome

Use dry-run mode to verify the calculated dates:

```powershell
python main.py --dry-run
```

Dry-run mode does not open Chrome, contact the website, download a file, or
require credentials. It prints the FromDate and ToDate values that a real run
would use.

## Two-factor authentication

The automation does not generate, request, read, or store a 2FA secret. It only
clicks **Log In** when the authenticator-code field has already been populated
by the existing authentication process.

If the field is empty, the automation stops with a clear error. This is
intentional: it avoids repeatedly submitting an invalid or missing code.

## Daily execution at 07:00

A Codex recurring local job named **Daily postal report** is active and is
configured for **07:00 Europe/Athens time**.

Important:

- The computer and the local execution host must be available at run time.
- Keep the local project, `.venv`, and `.env` in place.
- Do not create a second schedule unless the Codex job is disabled. Two active
  schedules could download the same report twice.
- Scheduled runs use headless mode and write diagnostic output to `logs`.

### Optional Windows Task Scheduler alternative

If the Codex job is intentionally disabled, install the standalone Windows task:

```powershell
.\install_daily_task.ps1
```

A successful command prints a message confirming that the task was installed.
The task is named `Postal Report Automation - 07-00`. It:

- Uses the computer's local Europe/Athens time.
- Runs at 07:00 every day.
- Starts later when Windows reports that the scheduled start was missed.
- Runs only while the current Windows user is logged on, avoiding storage of
  the Windows account password in Task Scheduler.
- Runs the automation in headless mode.

Verify the task with:

```powershell
Get-ScheduledTask -TaskName "Postal Report Automation - 07-00"
```

Its state will normally be `Ready` while it is waiting for the next run.

## Using the project with PyCharm

PyCharm can be used as the editor while every setup and run action remains a
PowerShell command.

1. In PyCharm, choose **Open** and select:
   `C:\Users\m.diles\Documents\ChatGPT\Python\postal_report_automation`
2. Open **File → Settings → Project → Python Interpreter**.
3. Choose **Add Interpreter → Add Local Interpreter → Existing**.
4. Select:
   `.venv\Scripts\python.exe`

Use the existing `.venv`; PyCharm does not need to create a second virtual
environment.

An optional PyCharm Run configuration can use:

| Field | Value |
| --- | --- |
| Script path | The project's `main.py` |
| Working directory | The project directory |
| Python interpreter | `.venv\Scripts\python.exe` |
| Parameters | Empty for a visible run, `--headless`, or `--dry-run` |

The application loads `.env` itself, so the credentials do not need to be
copied into the PyCharm Run configuration.

## Run the automated tests

With the virtual environment active:

```powershell
python -m unittest discover -s tests -v
```

Expected final output:

```text
Ran 2 tests in ...

OK
```

The elapsed time may differ. `OK` means that the tested date calculations
passed.

## Troubleshooting

| Problem | What to check |
| --- | --- |
| `py` is not recognized | Install Python and the Windows Python Launcher, then reopen PowerShell. |
| `Activate.ps1` cannot be loaded | Use the temporary `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` command shown above. |
| `No module named playwright` | Activate `.venv` and run `python -m pip install -r requirements.txt`. |
| Playwright browser support is missing | Run `python -m playwright install`. |
| Google Chrome cannot be found | Install or update Google Chrome. |
| Username or password error | Check `POSTAL_USERNAME` and `POSTAL_PASSWORD` in the local `.env` file. |
| Authenticator field is empty | Confirm that the site's existing 2FA process populates the field before **Log In** is clicked. |
| A required project is not found | Confirm that both configured project labels still exist and that the account has access to them. |
| A timeout occurs | Check the internet connection, website availability, and whether the website layout or wording changed. |
| The scheduled run did not start | Confirm the computer was available, the schedule is active, and inspect files in `logs`. |
| No report appears | Inspect the PowerShell output or the latest log for an error and check the configured downloads directory. |

## GitHub and generated files

The source repository is
[marioelevendev/postal-report-automation](https://github.com/marioelevendev/postal-report-automation).

These local or generated items are intentionally not committed:

- `.env`
- `.venv`
- Downloaded reports
- Log files
- Python cache files

Before committing changes, check the repository:

```powershell
git status --short
git check-ignore .env .venv
```

`git status --short` shows modified and untracked files. The second command
should print `.env` and `.venv`, confirming that Git ignores them.

## Selector maintenance

The code prefers visible roles and labels because they are easier to understand
and usually more stable than generated CSS classes. Two selectors intentionally
use verified IDs or classes:

- `#myTable tr` limits project matching to the project grid.
- `a.nav-link[data-toggle='dropdown']:has(i.fa-user-circle)` identifies the
  icon-only user menu from the original requirement.

If the website wording or HTML changes, the script raises an error instead of
silently selecting an unintended project. Do not weaken these checks without
first confirming the live page structure and the exact rows that may be
selected.

