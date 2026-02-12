# Requires -Version 5.1

$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# -------- Configuration --------
$AppName = "geminicli2api"
$RepoUrl = "https://github.com/gzzhongqi/geminicli2api"
$BaseDir = Get-Location
$RepoDir = Join-Path $BaseDir $AppName

$StateDir = Join-Path $BaseDir ".${AppName}-installer"
$StateFile = Join-Path $StateDir "state.env"
$LogFile = Join-Path $StateDir "install.log"

# -------- Utils --------
function Get-Timestamp {
    return Get-Date -Format "yyyy-MM-dd HH:mm:ss"
}

function Write-Log {
    param (
        [string]$Message,
        [string]$Color = "Cyan",
        [string]$Level = "INFO"
    )
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

    Add-Content -Path $LogFile -Value "[$Level] $FormattedMsg" -Encoding UTF8
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

# -------- Setup Logging --------
if (-not (Test-Path $StateDir)) {
    New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
}
if (-not (Test-Path $LogFile)) {
    New-Item -ItemType File -Path $LogFile -Force | Out-Null
}

# -------- State Management --------
$Script:DoneStep = 0
$Script:ProjectIdSaved = ""

function Load-State {
    if (Test-Path $StateFile) {
        Get-Content $StateFile | ForEach-Object {
            if ($_ -match '^([^=]+)=(.*)$') {
                $Key = $matches[1]
                $Value = $matches[2]
                if ($Key -eq "DONE_STEP") { $Script:DoneStep = [int]$Value }
                if ($Key -eq "PROJECT_ID_SAVED") { $Script:ProjectIdSaved = $Value -replace '"','' }
            }
        }
    }
}

function Save-State {
    $Content = @"
DONE_STEP=$Script:DoneStep
PROJECT_ID_SAVED="$Script:ProjectIdSaved"
"@
    Set-Content -Path $StateFile -Value $Content -Encoding UTF8
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

$Step30_FixRequirements = {
    $ReqFile = Join-Path $RepoDir "requirements.txt"
    if (-not (Test-Path $ReqFile)) { Die "requirements.txt not found in $RepoDir" }

    Log "Checking requirements.txt for pydantic..."
    $Content = Get-Content $ReqFile
    $NewContent = @()
    foreach ($Line in $Content) {
        if ($Line -match '^pydantic([<>=!~].*)?$') {
        } else {
            $NewContent += $Line
        }
    }
    $NewContent += "pydantic<2.0"
    
    $NewContent | Set-Content -Path $ReqFile -Encoding UTF8
    Ok "requirements.txt updated: pydantic<2.0 guaranteed."
}

$Step40_SetupEnv = {
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
    if ($EnvContent -match 'GOOGLE_CLOUD_PROJECT=') {
        $EnvContent = $EnvContent -replace '(?m)^[ 	]*#?[ 	]*GOOGLE_CLOUD_PROJECT=.*', "GOOGLE_CLOUD_PROJECT=$Script:ProjectIdSaved"
        Log "GOOGLE_CLOUD_PROJECT updated in .env"
    } else {
        $EnvContent += "`r`nGOOGLE_CLOUD_PROJECT=$Script:ProjectIdSaved"
        Log "GOOGLE_CLOUD_PROJECT added to the end of .env"
    }
    Set-Content -Path $EnvFile -Value $EnvContent -Encoding UTF8
}

$Step50_InstallDeps = {
    Set-Location $RepoDir
    
    Log "Creating virtual environment via uv (python 3.12)..."
    uv venv -p 3.12 --clear .venv

    Log "Installing dependencies via uv..."
    uv pip install -r requirements.txt
    uv cache clean
    
    Ok "Dependencies installed."
}

$Step55_CreateBatFile = {
    $BatFile = Join-Path $RepoDir "StartCLI.bat"
    $BatContent = "uv run run.py`r`npause"
    Set-Content -Path $BatFile -Value $BatContent -Encoding Ascii
    Ok "StartCLI.bat created in $RepoDir"
}

$Step60_RunApp = {
    Set-Location $RepoDir

    Log "Starting geminicli2api..."
    Log "IMPORTANT: Keep this window open. You can stop it with Ctrl+C."
    Log "On first run, copy the auth link to your browser and login with your Google Account."
    
    uv run run.py
}

# -------- Main --------
function Main {
    Load-State

    $FirstRun = -not (Test-Path $StateFile)
    
    if ($FirstRun -and (Test-Path $RepoDir)) {
        Warn "Folder $RepoDir detected."
        if (Ask-YesNo "Perform a FULL REINSTALL (delete folder and start fresh)?") {
            Log "Deleting $RepoDir"
            Remove-Item -Path $RepoDir -Recurse -Force
            $Script:DoneStep = 0
            $Script:ProjectIdSaved = ""
            Save-State
            Ok "State reset. Starting clean installation."
        } else {
            Log "Continuing with the existing folder."
        }
    }

    if ([string]::IsNullOrWhiteSpace($Script:ProjectIdSaved)) {
        $PidArg = $args[0]
        if (-not [string]::IsNullOrWhiteSpace($PidArg)) {
            $Script:ProjectIdSaved = $PidArg
        } else {
            $InputId = Read-Host "Enter GOOGLE_CLOUD_PROJECT (Project ID)"
            $InputId = $InputId.Trim()
            if ([string]::IsNullOrWhiteSpace($InputId)) { Die "GOOGLE_CLOUD_PROJECT cannot be empty." }
            $Script:ProjectIdSaved = $InputId
        }
        Save-State
        Ok "PROJECT_ID saved: $Script:ProjectIdSaved"
    } else {
        Ok "Using saved PROJECT_ID: $Script:ProjectIdSaved"
        $PidArg = $args[0]
        if (-not [string]::IsNullOrWhiteSpace($PidArg) -and $PidArg -ne $Script:ProjectIdSaved) {
            Warn "New PROJECT_ID provided in arguments. Updating: $PidArg"
            $Script:ProjectIdSaved = $PidArg
            Save-State
        }
    }

    Run-Step 10 "Check and install components (uv, git)" $Step10_InstallPrereqs
    Run-Step 20 "Clone/Update repository" $Step20_CloneRepo
    Run-Step 30 "Modify requirements.txt" $Step30_FixRequirements
    Run-Step 40 "Configure .env" $Step40_SetupEnv
    Run-Step 50 "Install dependencies (uv venv + pip install)" $Step50_InstallDeps
    Run-Step 55 "Create StartCLI.bat shortcut" $Step55_CreateBatFile
    
    Log "=== Final: Launching Application ==="    
    & $Step60_RunApp
}

Main @args