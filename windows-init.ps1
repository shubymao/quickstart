param(
    [string]$WslDistro = "Ubuntu",
    [string]$RepoCloneDir = (Join-Path ([Environment]::GetFolderPath("Desktop")) "quickstart"),
    [ValidateSet("SettingsOnly", "BaseOnly", "DevOnly")]
    [string]$InstallProfile,
    [switch]$NoExitPrompt
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
    Write-Step "Requesting administrator privileges..."
    $arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath)
    if ($PSBoundParameters.ContainsKey("WslDistro")) { $arguments += @("-WslDistro", $WslDistro) }
    if ($PSBoundParameters.ContainsKey("RepoCloneDir")) { $arguments += @("-RepoCloneDir", $RepoCloneDir) }
    if ($PSBoundParameters.ContainsKey("InstallProfile")) { $arguments += @("-InstallProfile", $InstallProfile) }
    if ($NoExitPrompt) { $arguments += "-NoExitPrompt" }

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

# --- Installation Core ---
function Install-WingetPackage {
    param([string]$Id)
    $existing = winget list --exact --id $Id --accept-source-agreements 2>$null
    if ($LASTEXITCODE -eq 0 -and $existing -match [regex]::Escape($Id)) {
        Write-Step "Already installed: $Id"
        return
    }
    Write-Step "Installing: $Id"
    winget install --exact --id $Id --silent --accept-package-agreements --accept-source-agreements
}

# --- Settings & Personalization (SettingsOnly Mode) ---
function Apply-AllSettings {
    param([string]$RepoRoot)
    Write-Step "Applying System Personalization..."

    # 1. Dark Theme
    $personalizeKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    New-Item -Path $personalizeKey -Force | Out-Null
    Set-ItemProperty -Path $personalizeKey -Name "AppsUseLightTheme" -Value 0
    Set-ItemProperty -Path $personalizeKey -Name "SystemUsesLightTheme" -Value 0

    # 2. Wallpapers & Slideshow
    $sourceDir = Join-Path $RepoRoot "wallpapers"
    if (Test-Path $sourceDir) {
        $picturesDir = [Environment]::GetFolderPath("MyPictures")
        $targetDir = Join-Path $picturesDir "quickstart-wallpapers"
        
        if (-not (Test-Path $targetDir)) {
            New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
        }
        
        $copiedFiles = Get-ChildItem -Path $sourceDir -File | ForEach-Object {
            $dest = Join-Path $targetDir $_.Name
            Copy-Item -Path $_.FullName -Destination $dest -Force
            $dest
        }

        # Set Registry for Slideshow
        $wpReg = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers"
        Set-ItemProperty -Path $wpReg -Name "BackgroundType" -Value 2 # 2 = Slideshow
        Set-ItemProperty -Path "HKCU:\Control Panel\Personalization\Desktop Slideshow" -Name "Interval" -Value 600000
        Set-ItemProperty -Path "HKCU:\Control Panel\Personalization\Desktop Slideshow" -Name "Shuffle" -Value 1
        
        # This is the "Magic" string Windows needs for the directory path in some versions
        Set-ItemProperty -Path $wpReg -Name "ImagesRootPath" -Value $targetDir

        # FORCE REFRESH: Use C# to call SystemParametersInfo
        $code = @'
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
    public const int SPI_SETDESKWALLPAPER = 20;
    public const int SPIF_UPDATEINIFILE = 0x01;
    public const int SPIF_SENDWININICHANGE = 0x02;
}
'@
        Add-Type -TypeDefinition $code
        
        # Set the first image as static wallpaper immediately to force an update
        if ($copiedFiles.Count -gt 0) {
            [Wallpaper]::SystemParametersInfo([Wallpaper]::SPI_SETDESKWALLPAPER, 0, $copiedFiles[0], 3)
        }

        # 2b. Lock Screen (Applied via HKLM, needs Admin which you already have)
        $policyKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization"
        if (-not (Test-Path $policyKey)) { New-Item -Path $policyKey -Force | Out-Null }
        Set-ItemProperty -Path $policyKey -Name "LockScreenImage" -Value $copiedFiles[0]
    }

    # 3. Touch Keyboard Scaling
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\TabletTip\1.7" -Name "UserKeyboardScalingFactor" -Value 200
    Write-Step "UI and Theme settings complete."
}

# --- Optimized Single Font Extension ---
function Install-JetBrainsMonoNerdFont {
    Write-Step "Fetching JetBrains Mono Nerd Font (High Speed)..."
    $fontName = "JetBrainsMono"
    $releaseApi = "https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest"
    
    try {
        $release = Invoke-RestMethod -Uri $releaseApi -Headers @{ "User-Agent" = "quickstart" }
        $asset = $release.assets | Where-Object { $_.name -eq "$fontName.zip" } | Select-Object -First 1
        
        if (-not $asset) { throw "Font asset not found." }

        $tempRoot = Join-Path $env:TEMP "quickstart-jb-font"
        if (Test-Path $tempRoot) { Remove-Item $tempRoot -Recurse -Force }
        New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
        
        $zipPath = Join-Path $tempRoot "$fontName.zip"
        Write-Step "Downloading JetBrains Mono..."
        Start-BitsTransfer -Source $asset.browser_download_url -Destination $zipPath -Priority Foreground
        
        Expand-Archive -Path $zipPath -DestinationPath $tempRoot -Force
        
        $fontRegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
        Get-ChildItem -Path $tempRoot -Include "*.ttf", "*.otf" -Recurse | ForEach-Object {
            $dest = Join-Path $env:WINDIR "Fonts\$($_.Name)"
            if (-not (Test-Path $dest)) {
                Copy-Item -Path $_.FullName -Destination $dest -Force
                Set-ItemProperty -Path $fontRegPath -Name "$($_.BaseName) (TrueType)" -Value $_.Name
            }
        }
        Remove-Item $tempRoot -Recurse -Force
        Write-Step "JetBrains Mono installed and registered."
    } catch {
        Write-Failure "Font install failed: $($_.Exception.Message)"
    }
}

function Register-DevConfigs {
    param([string]$RepoRoot)
    Write-Step "Configuring Dev Environment..."
    
    $wezSource = Join-Path $RepoRoot "dotfiles\wezterm\.wezterm.lua"
    if (Test-Path $wezSource) { Copy-Item -Path $wezSource -Destination (Join-Path $HOME ".wezterm.lua") -Force }

    $ahkScript = Join-Path $RepoRoot "dotfiles\main.ahk"
    if (Test-Path $ahkScript) {
        $ahkExe = "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
        if (Test-Path $ahkExe) {
            $wshShell = New-Object -ComObject WScript.Shell
            $shortcut = $wshShell.CreateShortcut((Join-Path ([Environment]::GetFolderPath("Startup")) "main.ahk.lnk"))
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
        Write-Step "Cloning repository to Desktop..."
        git clone --depth 1 $RepoUrl $RepoCloneDir
    }
    $repoRoot = (Resolve-Path $RepoCloneDir).Path

    $BaseApps = @("Mozilla.Firefox", "Google.Chrome", "Brave.Brave", "7zip.7zip", "VideoLAN.VLC", "GIMP.GIMP", "PDFgear.PDFgear", "tailscale.tailscale")
    $DevApps = @("Wez.WezTerm", "Alacritty.Alacritty", "Microsoft.VisualStudioCode", "Oracle.VirtualBox", "AutoHotkey.AutoHotkey")

    if (-not $InstallProfile) {
        Write-Host "`nSelect Profile:`n1) SettingsOnly`n2) BaseOnly (Settings + Base Apps)`n3) DevOnly (Settings + Base + Dev Apps)" -ForegroundColor Yellow
        $choice = Read-Host "Choice"
        $InstallProfile = switch($choice) { "1"{"SettingsOnly"}; "2"{"BaseOnly"}; "3"{"DevOnly"}; Default{"SettingsOnly"} }
    }

    switch ($InstallProfile) {
        "SettingsOnly" {
            Apply-AllSettings -RepoRoot $repoRoot
        }
        "BaseOnly" {
            Apply-AllSettings -RepoRoot $repoRoot
            foreach ($app in $BaseApps) { Install-WingetPackage -Id $app }
        }
        "DevOnly" {
            Apply-AllSettings -RepoRoot $repoRoot
            foreach ($app in ($BaseApps + $DevApps)) { Install-WingetPackage -Id $app }
            Install-JetBrainsMonoNerdFont
            Register-DevConfigs -RepoRoot $repoRoot
            wsl --install --no-distribution 2>$null
        }
    }

    Write-Step "Bootstrap finished successfully."
}

try {
    Invoke-WindowsInit
} catch {
    Write-Failure "Error: $($_.Exception.Message)"
} finally {
    if (-not $NoExitPrompt) { Read-Host "`nPress Enter to exit" }
}