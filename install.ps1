# TikTok Streak installer for Windows.
# Run in PowerShell:
#   irm https://raw.githubusercontent.com/enNeF/tiktok-streak/main/install.ps1 | iex
# Running it again later updates the code and keeps your login, friends and settings.

function Install-TikTokStreak {
    $Repo = "enNeF/tiktok-streak"
    $Dir = Join-Path $env:USERPROFILE "tiktok-streak"
    $Py = $null

    function Say($text, $color = "Cyan") { Write-Host ""; Write-Host $text -ForegroundColor $color }
    function Fail($text) { Write-Host ""; Write-Host "ERROR: $text" -ForegroundColor Red; Write-Host "Fix this and run the install command again." }

    function Find-Python {
        if (Get-Command py -ErrorAction SilentlyContinue) {
            $p = & py -3 -c "import sys; print(sys.executable)" 2>$null
            if ($LASTEXITCODE -eq 0 -and $p) { return $p.Trim() }
        }
        $c = Get-Command python -ErrorAction SilentlyContinue | Where-Object { $_.Source -notlike "*WindowsApps*" } | Select-Object -First 1
        if ($c) { return $c.Source }
        foreach ($v in "313", "312", "311", "314") {
            $guess = Join-Path $env:LOCALAPPDATA "Programs\Python\Python$v\python.exe"
            if (Test-Path $guess) { return $guess }
        }
        return $null
    }

    Write-Host "=== TikTok Streak installer ===" -ForegroundColor Magenta
    Write-Host "Installs to: $Dir"

    # 1. Python
    Say "[1/7] Checking Python..."
    $Py = Find-Python
    if (-not $Py) {
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            Fail "Python is not installed. Get it from https://www.python.org/downloads/ (tick 'Add python.exe to PATH')."
            return
        }
        Write-Host "Python not found - installing Python 3.13 (this can take a few minutes)..."
        winget install -e --id Python.Python.3.13 --scope user --silent --accept-package-agreements --accept-source-agreements
        $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
        $Py = Find-Python
        if (-not $Py) { Fail "Python install didn't work. Install it from https://www.python.org/downloads/ and try again."; return }
    }
    & $Py -c "import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)"
    if ($LASTEXITCODE -ne 0) { Fail "Your Python is too old. Install Python 3.9 or newer from https://www.python.org/downloads/"; return }
    Write-Host "Using $Py"

    # 2. Code
    Say "[2/7] Downloading TikTok Streak..."
    New-Item -ItemType Directory -Force $Dir | Out-Null
    $src = $null
    if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot "streak.py"))) {
        $src = $PSScriptRoot   # running from a downloaded copy
    } else {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $zip = Join-Path $env:TEMP "tiktok-streak.zip"
        $tmp = Join-Path $env:TEMP "tiktok-streak-src"
        try {
            Invoke-WebRequest "https://github.com/$Repo/archive/refs/heads/main.zip" -OutFile $zip -UseBasicParsing
        } catch { Fail "Couldn't download from GitHub. Check your internet connection."; return }
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
        Expand-Archive $zip $tmp -Force
        $src = (Get-ChildItem $tmp -Directory | Select-Object -First 1).FullName
    }
    foreach ($f in "streak.py", "login.py", "setup_task.ps1", "install.ps1", "config.example.json", "README.md") {
        $from = Join-Path $src $f
        if ((Test-Path $from) -and ((Resolve-Path $from).Path -ne (Join-Path $Dir $f))) { Copy-Item $from $Dir -Force }
    }

    # 3. Python packages + browser
    Say "[3/7] Installing Playwright and its browser (about 300 MB, first time only)..."
    $VPy = Join-Path $Dir ".venv\Scripts\python.exe"
    if (-not (Test-Path $VPy)) {
        & $Py -m venv (Join-Path $Dir ".venv")
        if (-not (Test-Path $VPy)) { Fail "Couldn't create the Python environment."; return }
    }
    & $VPy -m pip install --disable-pip-version-check -q "playwright==1.64.1"
    if ($LASTEXITCODE -ne 0) { Fail "Installing Playwright failed."; return }
    $env:PLAYWRIGHT_BROWSERS_PATH = "0"   # keep the browser inside the .venv folder
    & $VPy -m playwright install chromium
    if ($LASTEXITCODE -ne 0) { Fail "Downloading the browser failed."; return }

    # 4. Config
    $Cfg = Join-Path $Dir "config.json"
    $newConfig = -not (Test-Path $Cfg)
    if ($newConfig) {
        $topic = "streak-" + (-join ((48..57) + (97..122) | Get-Random -Count 12 | ForEach-Object { [char]$_ }))
        $text = (Get-Content (Join-Path $Dir "config.example.json") -Raw -Encoding UTF8) -replace '"ntfy_topic": ""', "`"ntfy_topic`": `"$topic`""
        [IO.File]::WriteAllText($Cfg, $text, (New-Object Text.UTF8Encoding $false))
    }
    $topic = ((Get-Content $Cfg -Raw -Encoding UTF8) | ConvertFrom-Json).ntfy_topic

    Push-Location $Dir
    try {
        # 5. Login
        Say "[4/7] Log into TikTok"
        $doLogin = $true
        if (Test-Path (Join-Path $Dir "profile")) {
            $doLogin = (Read-Host "You already logged in before. Log in again? (y/N)") -match "^[yY]"
        }
        if ($doLogin) {
            Write-Host "A browser window will open on TikTok's login page."
            Write-Host "Log in, wait until your feed loads, then CLOSE the browser window." -ForegroundColor Yellow
            Read-Host "Press Enter to open it" | Out-Null
            & $VPy login.py
        }

        # 6. Friends
        Say "[5/7] Add your friends"
        $doEdit = $true
        if (-not $newConfig) { $doEdit = (Read-Host "Edit your friend list now? (y/N)") -match "^[yY]" }
        if ($doEdit) {
            Write-Host "Notepad will open config.json. Replace 'Friend Name 1', 'Friend Name 2' with your friends'"
            Write-Host "names EXACTLY as they appear in your TikTok DM list. Keep the quotes and commas."
            Write-Host "Save (Ctrl+S) and close Notepad to continue." -ForegroundColor Yellow
            Start-Process notepad $Cfg -Wait
        }
        Write-Host "Checking that every friend can be found in your DMs..."
        & $VPy streak.py --check
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Some names weren't found (see FAILED above). Fix them in config.json later and run:" -ForegroundColor Yellow
            Write-Host "  cd `"$Dir`"; .\.venv\Scripts\python.exe streak.py --check"
        }

        # 7. Schedule
        Say "[6/7] Daily schedule"
        $time = Read-Host "What time should it run every day? 24-hour HH:MM (press Enter for 00:00 = midnight)"
        if ($time -notmatch "^([01]?\d|2[0-3]):[0-5]\d$") { $time = "00:00" }
        powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Dir "setup_task.ps1") -Time $time

        # 8. Phone alerts
        Say "[7/7] Phone alerts (optional)"
        Write-Host "To get an alert on your phone when something goes wrong:"
        Write-Host "  1. Install the free 'ntfy' app (App Store / Google Play)."
        Write-Host "  2. Tap +, and subscribe to this topic:  $topic" -ForegroundColor Yellow
        if ((Read-Host "Send a test alert now? (y/N)") -match "^[yY]") { & $VPy streak.py --test-notify }
    } finally {
        Pop-Location
    }

    Say "All done! Your streaks will be sent automatically every day at $time." "Green"
    Write-Host "Folder: $Dir   (see README.md there for help)"
    Write-Host "Keep your laptop on, or open it at least once a day - it catches up when you do."
}

Install-TikTokStreak
