# Requires -Version 5.1

$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# -------- Metadata --------
$Version = "1.2.1"
$VersionDesc = "New repo with 3.1 Pro; Clean old steps; Add self-update; Add reset."
$UpdateUrl = "https://raw.githubusercontent.com/MakksSh/GeminiCLI2API-Windows-Autoinstall/refs/heads/main/cli2api.ps1"
$ScriptPath = if ($PSCommandPath) { $PSCommandPath } elseif ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } else { "" }

# -------- Configuration --------
$AppName = "geminicli2api"
$RepoUrl = "https://github.com/MakksSh/geminicli2api"
$BaseDir = Get-Location
$RepoDir = Join-Path $BaseDir $AppName

$StateDir = Join-Path $BaseDir ".${AppName}-installer"
$StateFile = Join-Path $StateDir "state.env"
$LogFile = Join-Path $StateDir "install.log"

# -------- Utils --------
function Get-Timestamp {
    Get-Date -Format "yyyy-MM-dd HH:mm:ss"
}

function Ensure-StateStorage {
    if (-not (Test-Path $StateDir)) {
        New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
    }
    if (-not (Test-Path $LogFile)) {
        New-Item -ItemType File -Path $LogFile -Force | Out-Null
    }
}

function Write-Log {
    param (
        [string]$Message,
        [string]$Color = "Cyan",
        [string]$Level = "INFO"
    )

    Ensure-StateStorage

    $Timestamp = Get-Timestamp
    $FormattedMsg = "[$Timestamp] $Message"

    if ($Level -eq "ERROR") {
        Write-Host "[$Timestamp] ERROR: $Message" -ForegroundColor Red
    } elseif ($Level -eq "WARN") {
        Write-Host "[$Timestamp] WARN: $Message" -ForegroundColor Yellow
    } elseif ($Level -eq "OK") {
        Write-Host "[$Timestamp] OK: $Message" -ForegroundColor Green
    } else {
        Write-Host "[$Timestamp] $Message" -ForegroundColor $Color
    }

    Add-Content -Path $LogFile -Value "[$Level] $FormattedMsg" -Encoding utf8NoBOM
}

function Log($msg) { Write-Log -Message $msg -Color "Cyan" -Level "INFO" }
function Ok($msg) { Write-Log -Message $msg -Color "Green" -Level "OK" }
function Warn($msg) { Write-Log -Message $msg -Color "Yellow" -Level "WARN" }
function Err($msg) { Write-Log -Message $msg -Color "Red" -Level "ERROR" }
function Die($msg) { Err $msg; exit 1 }

function Ask-YesNo {
    param ([string]$Prompt)
    while ($true) {
        $Ans = Read-Host "$Prompt [y/n]"
        if ($Ans -match '^(y|yes)$') { return $true }
        if ($Ans -match '^(n|no)$') { return $false }
        Write-Host "Please enter y or n."
    }
}

function Test-NewerVersion {
    param (
        [string]$RemoteVersion,
        [string]$LocalVersion
    )

    try {
        return ([version]$RemoteVersion -gt [version]$LocalVersion)
    } catch {
        return ($RemoteVersion -ne $LocalVersion)
    }
}

function Invoke-TextDownload {
    param ([string]$Url)

    try {
        return (Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 10).Content
    } catch {
        return $null
    }
}

# -------- State Management --------
$Script:DoneStep = 0
$Script:ProjectIdSaved = ""
$Script:StateSchema = 2

function Load-State {
    $HasStateFile = Test-Path $StateFile
    $HasStateSchema = $false

    if ($HasStateFile) {
        foreach ($Line in Get-Content $StateFile) {
            if ($Line -match '^([^=]+)=(.*)$') {
                $Key = $matches[1]
                $Value = $matches[2]

                switch ($Key) {
                    "DONE_STEP" { $Script:DoneStep = [int]$Value }
                    "PROJECT_ID_SAVED" { $Script:ProjectIdSaved = $Value -replace '^"|"$','' }
                    "STATE_SCHEMA" {
                        $Script:StateSchema = [int]$Value
                        $HasStateSchema = $true
                    }
                }
            }
        }

        if (-not $HasStateSchema) {
            $Script:StateSchema = 2
        }

        Save-State
    } else {
        $Script:DoneStep = 0
        $Script:ProjectIdSaved = ""
        $Script:StateSchema = 2
    }
}

function Save-State {
    Ensure-StateStorage
    $Content = @"
DONE_STEP=$Script:DoneStep
PROJECT_ID_SAVED="$Script:ProjectIdSaved"
STATE_SCHEMA=$Script:StateSchema
"@
    Set-Content -Path $StateFile -Value $Content -Encoding utf8NoBOM
}

function Set-Done {
    param ([int]$Step)
    $Script:DoneStep = $Step
    Save-State
}

function Run-Step {
    param (
        [int]$Step,
        [string]$Title,
        [scriptblock]$Action
    )
    if ($Script:DoneStep -ge $Step) {
        Log "Step ${Step} skipped (already done): $Title"
        return
    }
    Log "=== Step ${Step}: $Title ==="
    try {
        & $Action
        Ok "Step ${Step} completed: $Title"
        Set-Done $Step
    } catch {
        Err "Error at Step ${Step} ($Title): $_"
        Err "Last successful step: $Script:DoneStep"
        Err "Restart the script to continue from this point."
        Err "If the error persists, contact the script's author: https://t.me/Maks_Sh"
        exit 1
    }
}

# -------- Self Update --------
function Check-SelfUpdate {
    param ([string[]]$ScriptArgs)

    if ($ScriptArgs -contains "--no-update") {
        return
    }

    if ([string]::IsNullOrWhiteSpace($ScriptPath)) {
        Warn "Unable to determine script path. Self-update skipped."
        return
    }

    Log "Checking for script updates..."
    $RemoteScript = Invoke-TextDownload -Url $UpdateUrl
    if ([string]::IsNullOrWhiteSpace($RemoteScript)) {
        Warn "Failed to get version info from the server."
        return
    }

    $RemoteVersionMatch = [regex]::Match($RemoteScript, '(?m)^\$Version\s*=\s*"([^"]+)"')
    if (-not $RemoteVersionMatch.Success) {
        Warn "Failed to parse remote script version."
        return
    }

    $RemoteVersion = $RemoteVersionMatch.Groups[1].Value
    if (-not (Test-NewerVersion -RemoteVersion $RemoteVersion -LocalVersion $Version)) {
        Log "Script is up to date (v$Version)."
        return
    }

    $RemoteDescMatch = [regex]::Match($RemoteScript, '(?m)^\$VersionDesc\s*=\s*"([^"]+)"')
    $RemoteDesc = if ($RemoteDescMatch.Success) { $RemoteDescMatch.Groups[1].Value } else { "" }

    Log "New script version available: $RemoteVersion (current: $Version)"
    if (-not [string]::IsNullOrWhiteSpace($RemoteDesc)) {
        Log "What's new: $RemoteDesc"
    }

    if (Ask-YesNo "Update the script now?") {
        Do-SelfUpdate -RemoteScript $RemoteScript -ScriptArgs $ScriptArgs
    }
}

function Do-SelfUpdate {
    param (
        [string]$RemoteScript,
        [string[]]$ScriptArgs
    )

    if ([string]::IsNullOrWhiteSpace($ScriptPath)) {
        Die "Cannot self-update because script path is unknown."
    }

    $TempFile = Join-Path $StateDir "cli2api.ps1.update.tmp"
    Log "Downloading update..."
    Set-Content -Path $TempFile -Value $RemoteScript -Encoding utf8NoBOM

    $DownloadedVersion = [regex]::Match($RemoteScript, '(?m)^\$Version\s*=\s*"([^"]+)"')
    if (-not $DownloadedVersion.Success) {
        Remove-Item $TempFile -Force -ErrorAction SilentlyContinue
        Die "Downloaded script is invalid."
    }

    Move-Item -Path $TempFile -Destination $ScriptPath -Force

    $RestartArgs = @($ScriptArgs | Where-Object { $_ -ne "--no-update" }) + "--no-update"
    Ok "Script updated to version $($DownloadedVersion.Groups[1].Value). Restarting..."
    Start-Process -FilePath "powershell.exe" -ArgumentList (@("-ExecutionPolicy", "ByPass", "-File", $ScriptPath) + $RestartArgs) | Out-Null
    exit 0
}

# -------- Refresh Env --------
function Refresh-Env {
    $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $MachinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $env:Path = "$UserPath;$MachinePath"

    $UvDefaultPath = Join-Path $env:USERPROFILE ".local\bin"
    if (Test-Path $UvDefaultPath) {
        if ($env:Path -notlike "*$UvDefaultPath*") {
            $env:Path = "$UvDefaultPath;$env:Path"
        }
    }
}

# -------- Steps --------
$Step10_InstallPrereqs = {
    Log "Checking prerequisites..."

    Refresh-Env
    if (-not (Get-Command "uv" -ErrorAction SilentlyContinue)) {
        Log "Installing uv..."
        powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
        Refresh-Env
        if (-not (Get-Command "uv" -ErrorAction SilentlyContinue)) {
            Die "Failed to find 'uv' after installation. Try restarting your terminal and the script."
        }
    } else {
        Ok "uv is already installed."
    }

    if (-not (Get-Command "git" -ErrorAction SilentlyContinue)) {
        Log "Git not found."
        if (Get-Command "winget" -ErrorAction SilentlyContinue) {
            Log "Installing Git via winget..."
            winget install --id Git.Git -e --source winget
        } else {
            Log "winget not found. Downloading Git installer directly..."
            $GitUrl = "https://github.com/git-for-windows/git/releases/download/v2.53.0.windows.1/Git-2.53.0-64-bit.exe"
            $GitPath = Join-Path $env:TEMP "GitInstaller.exe"

            Log "Downloading Git ($GitUrl)..."
            Log "Please wait... We need some time..."

            try {
                $Request = [System.Net.HttpWebRequest]::Create($GitUrl)
                $Response = $Request.GetResponse()
                $TotalSize = $Response.ContentLength
                $ResponseStream = $Response.GetResponseStream()
                $FileStream = New-Object System.IO.FileStream($GitPath, [System.IO.FileMode]::Create)

                $Buffer = New-Object byte[] 65536
                $TotalRead = 0
                while (($Read = $ResponseStream.Read($Buffer, 0, $Buffer.Length)) -gt 0) {
                    $FileStream.Write($Buffer, 0, $Read)
                    $TotalRead += $Read
                    if ($TotalSize -gt 0) {
                        $Percent = [Math]::Round(($TotalRead / $TotalSize) * 100)
                        Write-Host -NoNewline "`r[$(Get-Timestamp)] INFO: Downloading Git: $Percent% " -ForegroundColor Cyan
                    }
                }
                $FileStream.Close()
                $ResponseStream.Close()
                $Response.Close()
                Write-Host ""
            } catch {
                if ($FileStream) { $FileStream.Close() }
                Die "Download failed: $_"
            }

            Log "Running silent Git installation (this may take a minute)..."
            $Process = Start-Process -FilePath $GitPath -ArgumentList "/VERYSILENT", "/NORESTART" -Wait -PassThru
            if ($Process.ExitCode -ne 0) {
                Die "Error installing Git. ExitCode: $($Process.ExitCode)"
            }
            Remove-Item $GitPath -Force
        }

        Refresh-Env
        if (-not (Get-Command "git" -ErrorAction SilentlyContinue)) {
            Die "Git was installed but not found in PATH. Try restarting your terminal."
        }
    } else {
        Ok "Git is already installed."
    }
}

$Step20_CloneRepo = {
    if (Test-Path -Path "$RepoDir\.git") {
        Log "Repository already exists. Updating..."
        Push-Location $RepoDir
        try {
            git fetch --all
            git pull --ff-only
        } catch {
            Warn "git pull failed (possibly local changes). Continuing."
        } finally {
            Pop-Location
        }
    } else {
        if (Test-Path $RepoDir) {
            Warn "Found folder $RepoDir without .git. Removing."
            Remove-Item -Path $RepoDir -Recurse -Force
        }
        Log "Cloning repository..."
        git clone "$RepoUrl" "$RepoDir"
        if (-not (Test-Path $RepoDir)) { Die "Clone failed." }
    }
}

$Step30_InstallDeps = {
    Set-Location $RepoDir

    Log "Creating virtual environment via uv (python 3.12)..."
    uv venv -p 3.12 --clear .venv

    Log "Installing dependencies via uv..."
    uv pip install -r requirements.txt
    uv cache clean

    Ok "Dependencies installed."
}

$Step40_CreateBatFile = {
    $BatFile = Join-Path $RepoDir "StartCLI.bat"
    $BatContent = "uv run run.py`r`npause"
    Set-Content -Path $BatFile -Value $BatContent -Encoding Ascii
    Ok "StartCLI.bat created in $RepoDir"
}

$Step50_SetupEnv = {
    $EnvFile = Join-Path $RepoDir ".env"
    $EnvExample = Join-Path $RepoDir ".env.example"

    if (-not (Test-Path $EnvFile)) {
        if (Test-Path $EnvExample) {
            Copy-Item $EnvExample $EnvFile
            Log "Created .env from .env.example"
        } else {
            Die ".env.example not found."
        }
    }

    $EnvContent = Get-Content $EnvFile -Raw
    if ($EnvContent -match '(?m)^[ \t]*#?[ \t]*GOOGLE_CLOUD_PROJECT=') {
        $EnvContent = $EnvContent -replace '(?m)^[ \t]*#?[ \t]*GOOGLE_CLOUD_PROJECT=.*', "GOOGLE_CLOUD_PROJECT=$Script:ProjectIdSaved"
        Log "GOOGLE_CLOUD_PROJECT updated in .env"
    } else {
        $EnvContent += "`r`nGOOGLE_CLOUD_PROJECT=$Script:ProjectIdSaved"
        Log "GOOGLE_CLOUD_PROJECT added to the end of .env"
    }
    Set-Content -Path $EnvFile -Value $EnvContent -Encoding UTF8
}

$Step60_RunApp = {
    Set-Location $RepoDir

    Log "Starting geminicli2api..."
    Log "IMPORTANT: Keep this window open. You can stop it with Ctrl+C."
    Log "On first run, copy the auth link to your browser and login with your Google Account."
    Log "If script was helpful - please subscribe: https://t.me/btwiusesillytavern"

    uv run run.py
}

# -------- Main --------
function Main {
    param ([string[]]$ScriptArgs)

    Ensure-StateStorage

    $PidArg = ""
    $DoReset = $false
    foreach ($Arg in $ScriptArgs) {
        switch ($Arg) {
            "--reset" { $DoReset = $true }
            "--no-update" { }
            default { $PidArg = $Arg }
        }
    }

    if ($DoReset) {
        Warn "WARNING: FULL RESET selected (--reset)."
        if (Ask-YesNo "This will remove all application files and settings ($RepoDir and $StateDir). Continue?") {
            Log "Performing reset..."
            if (Test-Path $RepoDir) {
                Remove-Item -Path $RepoDir -Recurse -Force
            }
            if (Test-Path $StateDir) {
                Remove-Item -Path $StateDir -Recurse -Force
            }

            $Script:DoneStep = 0
            $Script:ProjectIdSaved = ""
            $Script:StateSchema = 2

            Ensure-StateStorage
            Ok "All data removed. Starting fresh installation."
        } else {
            Log "Reset cancelled."
        }
    }

    Load-State
    Check-SelfUpdate -ScriptArgs $ScriptArgs

    $FirstRun = -not (Test-Path $StateFile)

    if ($FirstRun -and (Test-Path $RepoDir)) {
        Warn "Folder $RepoDir detected."
        if (Ask-YesNo "Perform a FULL REINSTALL (delete folder and start fresh)?") {
            Log "Deleting $RepoDir"
            Remove-Item -Path $RepoDir -Recurse -Force
            $Script:DoneStep = 0
            $Script:ProjectIdSaved = ""
            $Script:StateSchema = 2
            Save-State
            Ok "State reset. Starting clean installation."
        } else {
            Log "Continuing with the existing folder."
        }
    }

    if ([string]::IsNullOrWhiteSpace($Script:ProjectIdSaved)) {
        if (-not [string]::IsNullOrWhiteSpace($PidArg)) {
            $Script:ProjectIdSaved = $PidArg.Trim()
        } else {
            $InputId = Read-Host "Enter GOOGLE_CLOUD_PROJECT (Project ID)"
            $Script:ProjectIdSaved = $InputId.Trim()
        }

        if ([string]::IsNullOrWhiteSpace($Script:ProjectIdSaved)) {
            Die "GOOGLE_CLOUD_PROJECT cannot be empty."
        }

        Save-State
        Ok "PROJECT_ID saved: $Script:ProjectIdSaved"
    } else {
        Ok "Using saved PROJECT_ID: $Script:ProjectIdSaved"
        if (-not [string]::IsNullOrWhiteSpace($PidArg)) {
            $PidArg = $PidArg.Trim()
        }

        if (-not [string]::IsNullOrWhiteSpace($PidArg) -and $PidArg -ne $Script:ProjectIdSaved) {
            Warn "New PROJECT_ID provided in arguments. Updating: $PidArg"
            $Script:ProjectIdSaved = $PidArg

            if ($Script:DoneStep -ge 40) {
                Log "Resetting progress to step 40 to update .env only."
                $Script:DoneStep = 40
            }

            $OAuthCreds = Join-Path $RepoDir "oauth_creds.json"
            if (Test-Path $OAuthCreds) {
                Log "Removing old oauth_creds.json for re-authorization."
                Remove-Item -Path $OAuthCreds -Force
            }

            Save-State
        }
    }

    Run-Step 10 "Check and install components (uv, git)" $Step10_InstallPrereqs
    Run-Step 20 "Clone/Update repository" $Step20_CloneRepo
    Run-Step 30 "Install dependencies (uv venv + pip install)" $Step30_InstallDeps
    Run-Step 40 "Create StartCLI.bat shortcut" $Step40_CreateBatFile
    Run-Step 50 "Configure .env" $Step50_SetupEnv

    Log "=== Final: Launching Application ==="
    & $Step60_RunApp
}

Main -ScriptArgs $args
