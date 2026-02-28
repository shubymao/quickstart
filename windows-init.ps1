param(
    [string]$WslDistro = "Ubuntu",
    [string]$RepoCloneDir = (Join-Path ([Environment]::GetFolderPath("Desktop")) "quickstart"),
    [ValidateSet("SettingsOnly", "BaseOnly", "DevOnly", "Dev")]
    [string]$InstallProfile,
    [switch]$NoExitPrompt,
    # New parameter to track the original user's profile path
    [string]$OriginalUserPath = $HOME
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoUrl = "https://github.com/shubymao/quickstart"
$RepoBranch = "main"

# --- UI & Logging ---
function Write-Step { param([string]$Message) Write-Host "[quickstart] $Message" -ForegroundColor Cyan }
function Write-Failure { param([string]$Message) Write-Host "[quickstart] $Message" -ForegroundColor Red }

# --- Admin & Environment ---
function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-Admin {
    if (Test-IsAdmin) { return }
    Write-Step "Capturing user context and requesting elevation..."
    
    # Store current user path to pass to the admin session
    $currentHome = $HOME
    
    $arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath)
    if ($PSBoundParameters.ContainsKey("WslDistro")) { $arguments += @("-WslDistro", $WslDistro) }
    if ($PSBoundParameters.ContainsKey("RepoCloneDir")) { $arguments += @("-RepoCloneDir", $RepoCloneDir) }
    if ($PSBoundParameters.ContainsKey("InstallProfile")) { $arguments += @("-InstallProfile", $InstallProfile) }
    if ($NoExitPrompt) { $arguments += "-NoExitPrompt" }
    
    # Pass the original user path as an argument
    $arguments += @("-OriginalUserPath", $currentHome)

    try {
        Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -Verb RunAs | Out-Null
    } catch {
        throw "Administrator privileges required. Approve the UAC prompt."
    }
    exit 0
}

function Refresh-ProcessPath {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

# --- Settings & Personalization ---
function Apply-AllSettings {
    param([string]$RepoRoot)
    Write-Step "Applying System Personalization..."

    # When running as Admin, HKCU is the Admin's registry. 
    # To fix this, we'll use the current user's actual path to map settings.
    $personalizeKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    Set-ItemProperty -Path $personalizeKey -Name "AppsUseLightTheme" -Value 0 -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $personalizeKey -Name "SystemUsesLightTheme" -Value 0 -ErrorAction SilentlyContinue

    # Touch Keyboard Scaling
    $tabTipKey = "HKCU:\Software\Microsoft\TabletTip\1.7"
    if (-not (Test-Path $tabTipKey)) { New-Item -Path $tabTipKey -Force | Out-Null }
    Set-ItemProperty -Path $tabTipKey -Name "UserKeyboardScalingFactor" -Value 180

    # Wallpapers - Place in Original User's Pictures folder
    $sourceDir = Join-Path $RepoRoot "wallpapers"
    if (Test-Path $sourceDir) {
        $targetDir = Join-Path $OriginalUserPath "Pictures\quickstart-wallpapers"
        if (-not (Test-Path $targetDir)) { New-Item -Path $targetDir -ItemType Directory -Force | Out-Null }
        
        $copiedFiles = Get-ChildItem -Path $sourceDir -File | ForEach-Object {
            $dest = Join-Path $targetDir $_.Name
            Copy-Item -Path $_.FullName -Destination $dest -Force
            $dest
        }
        
        # Set wallpaper for current session
        $code = @'
        using System.Runtime.InteropServices;
        public class Wallpaper {
            [DllImport("user32.dll", CharSet = CharSet.Auto)]
            public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
        }
'@
        if (-not ([System.Management.Automation.PSTypeName]'Wallpaper').Type) { Add-Type -TypeDefinition $code }
        if ($copiedFiles.Count -gt 0) { [Wallpaper]::SystemParametersInfo(20, 0, $copiedFiles[0], 3) }
    }
}

# --- Installation Core ---
function Install-WingetPackage {
    param([string]$Id)
    $existing = winget list --exact --id $Id --accept-source-agreements 2>$null
    if ($LASTEXITCODE -eq 0 -and $existing -match [regex]::Escape($Id)) {
        Write-Step "Already installed: $Id"
        return
    }

    Write-Step "Installing: $Id..."
    $args = "install --exact --id $Id --silent --accept-package-agreements --accept-source-agreements --scope machine"
    $process = Start-Process winget -ArgumentList $args -Wait -PassThru -NoNewWindow
    
    if ($process.ExitCode -ne 0) {
        $fallbackArgs = "install --exact --id $Id --silent --accept-package-agreements --accept-source-agreements"
        Start-Process winget -ArgumentList $fallbackArgs -Wait -NoNewWindow
    }
}

function Register-DevConfigs {
    param([string]$RepoRoot)
    Write-Step "Configuring Dev Environment for user: $OriginalUserPath"

    $TargetHome = $OriginalUserPath
    $TargetAppData = Join-Path $TargetHome "AppData\Roaming"
    $TargetLocalData = Join-Path $TargetHome "AppData\Local"

    # 1. WezTerm
    $wezSource = Join-Path $RepoRoot "dotfiles\wezterm\.wezterm.lua"
    if (Test-Path $wezSource) { Copy-Item -Path $wezSource -Destination (Join-Path $TargetHome ".wezterm.lua") -Force }

    # 2. Alacritty
    $alacrittySource = Join-Path $RepoRoot "dotfiles\alacritty\alacritty.toml"
    $alacrittyDestDir = Join-Path $TargetAppData "alacritty"
    if (Test-Path $alacrittySource) {
        if (-not (Test-Path $alacrittyDestDir)) { New-Item -Path $alacrittyDestDir -ItemType Directory -Force | Out-Null }
        Copy-Item -Path $alacrittySource -Destination (Join-Path $alacrittyDestDir "alacritty.toml") -Force
    }

    # 3. Flow Launcher
    $flowSource = Join-Path $RepoRoot "dotfiles\flowlauncher\Settings.json"
    $flowDestDir = Join-Path $TargetAppData "FlowLauncher\Settings"
    if (Test-Path $flowSource) {
        if (-not (Test-Path $flowDestDir)) { New-Item -Path $flowDestDir -ItemType Directory -Force | Out-Null }
        Copy-Item -Path $flowSource -Destination (Join-Path $flowDestDir "Settings.json") -Force
    }

    # 4. AHK Startup
    $ahkScript = Join-Path $RepoRoot "dotfiles\main.ahk"
    if (Test-Path $ahkScript) {
        $ahkExe = "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
        if (Test-Path $ahkExe) {
            $startupFolder = Join-Path $TargetAppData "Microsoft\Windows\Start Menu\Programs\Startup"
            $wshShell = New-Object -ComObject WScript.Shell
            $shortcut = $wshShell.CreateShortcut((Join-Path $startupFolder "main.ahk.lnk"))
            $shortcut.TargetPath = $ahkExe
            $shortcut.Arguments = "`"$ahkScript`""
            $shortcut.Save()
        }
    }
}

# --- Execution Controller ---
function Invoke-WindowsInit {
    Ensure-Admin
    Install-WingetPackage -Id "Git.Git"
    Refresh-ProcessPath
    
    if (-not (Test-Path $RepoCloneDir)) {
        Write-Step "Cloning repository to $RepoCloneDir..."
        git clone --depth 1 $RepoUrl $RepoCloneDir
    }
    $repoRoot = (Resolve-Path $RepoCloneDir).Path

    $BaseApps = @("Mozilla.Firefox", "Google.Chrome", "Brave.Brave", "7zip.7zip", "VideoLAN.VLC")
    $DevApps = @("wez.wezterm", "Alacritty.Alacritty", "Microsoft.VisualStudioCode", "AutoHotkey.AutoHotkey", "Flow-Launcher.Flow-Launcher")

    if (-not $InstallProfile) {
        Write-Host "`nSelect Profile (User: $OriginalUserPath):`n1) SettingsOnly`n2) BaseOnly`n3) Dev" -ForegroundColor Yellow
        $choice = Read-Host "Choice"
        $InstallProfile = switch($choice) { "1"{"SettingsOnly"}; "2"{"BaseOnly"}; "3"{"Dev"}; Default{"SettingsOnly"} }
    }

    switch ($InstallProfile) {
        "SettingsOnly" { Apply-AllSettings -RepoRoot $repoRoot }
        "BaseOnly" {
            Apply-AllSettings -RepoRoot $repoRoot
            foreach ($app in $BaseApps) { Install-WingetPackage -Id $app }
        }
        "Dev" {
            Apply-AllSettings -RepoRoot $repoRoot
            foreach ($app in ($BaseApps + $DevApps)) { Install-WingetPackage -Id $app }
            Register-DevConfigs -RepoRoot $repoRoot
            wsl --install --no-distribution 2>$null
        }
    }

    Write-Step "Bootstrap finished. Refreshing explorer..."
    Get-Process explorer | Stop-Process -Force
}

try {
    Invoke-WindowsInit
} catch {
    Write-Failure "Error: $($_.Exception.Message)"
} finally {
    if (-not $NoExitPrompt) { Read-Host "`nPress Enter to exit" }
}