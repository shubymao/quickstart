param(
    [string]$WslDistro = "Ubuntu",
    [string]$RepoCloneDir = "", 
    [AllowNull()]
    [string]$InstallProfile,
    [switch]$NoExitPrompt,
    [switch]$SkipUserInstall,
    [string]$OriginalUserPath = $HOME
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoUrl = "https://github.com/shubymao/quickstart"

# --- UI & Logging ---
function Write-Step { param([string]$Message) Write-Host "`n[quickstart] $Message" -ForegroundColor Cyan }
function Write-Failure { param([string]$Message) Write-Host "[quickstart] $Message" -ForegroundColor Red }

# --- 1. User-Level Installation Logic ---
function Install-UserApps {
    param([string]$Profile)
    
    # If the skip flag is present, we get out immediately
    if ($SkipUserInstall) { 
        Write-Step "Skipping User-Level Apps (already processed or requested skip)."
        return 
    }

    # Define User-Level apps (Always installed in User Scope)
    $BaseUserApps = @(
        "Nextcloud.NextcloudDesktop"
    )

    # Base apps installed via Chocolatey
    $ChocolateyBaseApps = @(
        "hass-agent",
        "synctrayzor"
    )

    $DevUserApps = @(
        "wez.wezterm",
        "Raycast.Raycast",
        "AutoHotkey.AutoHotkey",
        "Doist.Todoist"
    )

    $AppsToInstall = @()
    if ($Profile -eq "Dev" -or $Profile -eq "BaseOnly" -or $Profile -eq "Gaming") { $AppsToInstall += $BaseUserApps }
    if ($Profile -eq "Dev") { $AppsToInstall += $DevUserApps }

    if ($AppsToInstall.Count -gt 0) {
        Write-Step "Phase 1: Installing User-Level Applications..."
        foreach ($AppId in $AppsToInstall) {
            Write-Host "Installing $AppId (User Scope)..." -ForegroundColor Gray
            winget install --exact --id $AppId --silent --accept-package-agreements --accept-source-agreements
        }
    }

}

function Install-Chocolatey {
    param([string]$Profile)
    
    $chocoBaseApps = @("hass-agent", "synctrayzor")
    
    Write-Step "Checking Chocolatey..."
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    if ($env:ChocolateyInstall -and (Test-Path $env:ChocolateyInstall)) {
        Write-Step "Chocolatey already detected at $env:ChocolateyInstall, skipping install."
    } else {
        Write-Step "Installing Chocolatey..."
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        # Attempt to refresh Chocolatey environment
        try { & "$env:ChocolateyInstall\\bin\\refreshenv.ps1" } catch { if ($env:ChocolateyInstall) { $env:Path += ";$env:ChocolateyInstall\\bin" } }
    }
}

    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Step "Phase 1b: Installing apps via Chocolatey..."
        foreach ($app in $chocoBaseApps) {
            Write-Host "Installing $app via Chocolatey..." -ForegroundColor Gray
            choco install $app -y --no-progress 2>$null
        }
    } else {
        Write-Host "Chocolatey not available, skipping HASS.Agent and SyncTrayzor" -ForegroundColor Yellow
    }
}

# --- 2. Admin Elevation (The Handshake) ---
function Ensure-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { return }

    Write-Step "Phase 2: Requesting administrator privileges..."
    $currentHome = $HOME 
    $targetDocs = if ([string]::IsNullOrEmpty($RepoCloneDir)) { Join-Path $currentHome "Documents\quickstart" } else { $RepoCloneDir }

    $scriptUrl = "https://raw.githubusercontent.com/shubymao/quickstart/main/scripts/win-init.ps1?$([guid]::NewGuid().ToString())"
    $tempScript = Join-Path $env:TEMP "quickstart-win-init.ps1"
    Invoke-WebRequest -Uri $scriptUrl -OutFile $tempScript -UseBasicParsing

    $arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $tempScript)
    if ($null -ne $InstallProfile) { $arguments += @("-InstallProfile", $InstallProfile) }
    $arguments += @("-OriginalUserPath", $currentHome)
    $arguments += @("-RepoCloneDir", $targetDocs)
    $arguments += "-SkipUserInstall" 

    try {
        Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -Verb RunAs | Out-Null
    } catch {
        throw "Administrator privileges required for system-wide installs."
    }
    exit 0
}

# --- 3. System-Level Logic ---
function Install-WingetPackage {
    param([string]$Id)
    $existing = winget list --exact --id $Id --accept-source-agreements 2>$null
    if ($LASTEXITCODE -eq 0 -and $existing -match [regex]::Escape($Id)) {
        Write-Host "Already installed: $Id" -ForegroundColor Gray
        return
    }
    Write-Step "Installing System-Wide: $Id..."
    winget install --exact --id $Id --silent --accept-package-agreements --accept-source-agreements --scope machine
}

function Apply-AllSettings {
    param([string]$RepoRoot)
    Write-Step "Applying Registry & Personalization..."
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -Value 0 -Force
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "SystemUsesLightTheme" -Value 0 -Force
    
    if (-not (Test-Path "HKCU:\Software\Microsoft\TabletTip\1.7")) { New-Item -Path "HKCU:\Software\Microsoft\TabletTip\1.7" -Force }
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\TabletTip\1.7" -Name "UserKeyboardScalingFactor" -Value 180 -Force

    $targetDir = Join-Path $OriginalUserPath "Pictures\quickstart-wallpapers"
    if ((Test-Path $targetDir) -and (Get-ChildItem -Path $targetDir -File -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0) {
        Write-Step "Wallpapers already installed at $targetDir"
    } else {
        Remove-Item -Path $targetDir -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
        git clone --quiet https://github.com/shubymao/wallpaper.git $targetDir 2>$null
        Write-Step "Cloned wallpapers to $targetDir"
    }
}

function Register-DevConfigs {
    param([string]$RepoRoot)
    Write-Step "Syncing Dotfiles..."
    
    $wezSource = Join-Path $RepoRoot "dotfiles\wezterm\.wezterm.lua"
    if (Test-Path $wezSource) { Copy-Item -Path $wezSource -Destination (Join-Path $OriginalUserPath ".wezterm.lua") -Force }

    $raycastSource = Join-Path $RepoRoot "dotfiles\raycast\settings.json"
    $raycastDestDir = Join-Path $OriginalUserPath "AppData\Roaming\Raycast\Settings"
    if (Test-Path $raycastSource) {
        if (-not (Test-Path $raycastDestDir)) { New-Item -Path $raycastDestDir -ItemType Directory -Force | Out-Null }
        Copy-Item -Path $raycastSource -Destination (Join-Path $raycastDestDir "settings.json") -Force
    }

    $ahkSource = Join-Path $RepoRoot "dotfiles\autohotkey\main.ahk"
    if (Test-Path $ahkSource) {
        $startupDir = Join-Path $OriginalUserPath "AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"
        Copy-Item -Path $ahkSource -Destination (Join-Path $startupDir "main.ahk") -Force
    }
}

# --- 4. Main Execution Flow ---
function Invoke-WindowsInit {
    # Phase 1: Interactive Choice
    if (-not $InstallProfile) {
        Write-Host "`nSelect Profile:`n1) SettingsOnly`n2) BaseOnly`n3) Dev (Full Setup)`n4) Gaming`n5) DevConfigOnly" -ForegroundColor Yellow
        $choice = Read-Host "Choice"
        $script:InstallProfile = switch($choice) { "1"{"SettingsOnly"}; "2"{"BaseOnly"}; "3"{"Dev"}; "4"{"Gaming"}; "5"{"DevConfigOnly"}; Default{"SettingsOnly"} }
    }

    # Phase 2: User-Level Installs (Will skip if -SkipUserInstall is passed)
    Install-UserApps -Profile $InstallProfile

    # Phase 3: Elevate for System Tasks (Adds -SkipUserInstall to next process)
    Ensure-Admin

    # Phase 4: Git & Repo Setup
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Install-WingetPackage -Id "Git.Git"
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","User") + ";" + [System.Environment]::GetEnvironmentVariable("Path","Machine")
    }
    
    if ([string]::IsNullOrEmpty($RepoCloneDir)) { $RepoCloneDir = Join-Path $OriginalUserPath "Documents\quickstart" }
    if (-not (Test-Path $RepoCloneDir)) { 
        git clone --depth 1 $RepoUrl $RepoCloneDir 
    } else {
        Write-Step "Updating quickstart repo..."
        Set-Location $RepoCloneDir
        git pull
    }
    $repoRoot = (Resolve-Path $RepoCloneDir).Path

    # Phase 5: Package Lists
    $SystemApps = @(
        "Mozilla.Firefox",
        "Google.Chrome",
        "Brave.Brave",
        "7zip.7zip",
        "VideoLAN.VLC",
        "Tailscale.Tailscale",
        "Jellyfin.JellyfinMediaPlayer",
        "Adobe.Acrobat.Reader.64-bit",
        "TheDocumentFoundation.LibreOffice"
    )
    $DevApps = @(
        "Proton.ProtonVPN",
        "Joplin.Joplin",
        "GIMP.GIMP.3",
        "Microsoft.VisualStudioCode",
        "Alacritty.Alacritty",
        "Oracle.VirtualBox",
        "SoftFever.OrcaSlicer",
        "MusicBrainz.Picard",
        "Docker.DockerDesktop"
    )

    $GamingApps = @(
        "Valve.Steam",
        "EpicGames.EpicGamesLauncher",
        "Ryochan7.DS4Windows"
    )

    # Phase 6: Execute Profile Logic
    switch ($InstallProfile) {
        "Dev" {
            Apply-AllSettings -RepoRoot $repoRoot
            foreach ($app in $SystemApps) { Install-WingetPackage -Id $app }
            foreach ($app in $DevApps) { Install-WingetPackage -Id $app }
            Install-Chocolatey -Profile $InstallProfile
            Register-DevConfigs -RepoRoot $repoRoot
            wsl --install --no-distribution 2>$null
        }
        "Gaming" {
            Apply-AllSettings -RepoRoot $repoRoot
            foreach ($app in $SystemApps) { Install-WingetPackage -Id $app }
            foreach ($app in $GamingApps) { Install-WingetPackage -Id $app }
            Install-Chocolatey -Profile $InstallProfile
        }
        "BaseOnly" {
            Apply-AllSettings -RepoRoot $repoRoot
            foreach ($app in $SystemApps) { Install-WingetPackage -Id $app }
            Install-Chocolatey -Profile $InstallProfile
        }
        "SettingsOnly" {
            Apply-AllSettings -RepoRoot $repoRoot
        }
        "DevConfigOnly" {
            if ([string]::IsNullOrEmpty($RepoCloneDir)) { $RepoCloneDir = Join-Path $OriginalUserPath "Documents\quickstart" }
            if (Test-Path $RepoCloneDir) {
                Set-Location $RepoCloneDir
                git pull
                $repoRoot = (Resolve-Path $RepoCloneDir).Path
                Register-DevConfigs -RepoRoot $repoRoot
                Write-Step "Dev config files synced and updated."
            } else {
                Write-Host "Quickstart repo not found at $RepoCloneDir" -ForegroundColor Yellow
            }
        }
    }
}

try { Invoke-WindowsInit } catch { Write-Failure "Error: $($_.Exception.Message)" } finally { if (-not $NoExitPrompt) { Read-Host "`nPress Enter to exit" } }
