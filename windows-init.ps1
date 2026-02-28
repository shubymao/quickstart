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

    Write-Step "Installing: $Id..."
    $args = "install --exact --id $Id --silent --accept-package-agreements --accept-source-agreements --scope machine"
    $process = Start-Process winget -ArgumentList $args -Wait -PassThru -NoNewWindow
    
    if ($process.ExitCode -ne 0) {
        Write-Warning "Machine scope failed for $Id. Retrying without scope restriction..."
        $fallbackArgs = "install --exact --id $Id --silent --accept-package-agreements --accept-source-agreements"
        $fallbackProcess = Start-Process winget -ArgumentList $fallbackArgs -Wait -PassThru -NoNewWindow
        
        if ($fallbackProcess.ExitCode -ne 0) {
            Write-Failure "Failed to install $Id after fallback."
        } else {
            Write-Host "    Successfully installed $Id via fallback." -ForegroundColor Green
        }
    } else {
        Write-Host "    Successfully installed $Id (Machine)." -ForegroundColor Green
    }
}

# --- Settings & Personalization ---
function Apply-AllSettings {
    param([string]$RepoRoot)
    Write-Step "Applying System Personalization & Touch Keyboard..."

    # 1. Dark Theme
    $personalizeKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    if (-not (Test-Path $personalizeKey)) { New-Item -Path $personalizeKey -Force | Out-Null }
    Set-ItemProperty -Path $personalizeKey -Name "AppsUseLightTheme" -Value 0
    Set-ItemProperty -Path $personalizeKey -Name "SystemUsesLightTheme" -Value 0

    # 2. Touch Keyboard Scaling (180) and Visibility
    $tabTipKey = "HKCU:\Software\Microsoft\TabletTip\1.7"
    if (-not (Test-Path $tabTipKey)) { New-Item -Path $tabTipKey -Force | Out-Null }
    Set-ItemProperty -Path $tabTipKey -Name "UserKeyboardScalingFactor" -Value 180
    
    # Enable Touch Keyboard icon in Taskbar (1 = Always show)
    $taskbarKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\TouchKeyboard"
    if (-not (Test-Path $taskbarKey)) { New-Item -Path $taskbarKey -Force | Out-Null }
    Set-ItemProperty -Path $taskbarKey -Name "TouchKeyboardContextMenuOption" -Value 2

    # 3. Wallpapers
    $sourceDir = Join-Path $RepoRoot "wallpapers"
    if (Test-Path $sourceDir) {
        $picturesDir = [Environment]::GetFolderPath("MyPictures")
        $targetDir = Join-Path $picturesDir "quickstart-wallpapers"
        if (-not (Test-Path $targetDir)) { New-Item -Path $targetDir -ItemType Directory -Force | Out-Null }
        
        $copiedFiles = Get-ChildItem -Path $sourceDir -File | ForEach-Object {
            $dest = Join-Path $targetDir $_.Name
            Copy-Item -Path $_.FullName -Destination $dest -Force
            $dest
        }

        $wpReg = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers"
        Set-ItemProperty -Path $wpReg -Name "BackgroundType" -Value 2 
        Set-ItemProperty -Path "HKCU:\Control Panel\Personalization\Desktop Slideshow" -Name "Interval" -Value 600000
        Set-ItemProperty -Path "HKCU:\Control Panel\Personalization\Desktop Slideshow" -Name "Shuffle" -Value 1
        Set-ItemProperty -Path $wpReg -Name "ImagesRootPath" -Value $targetDir

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

# --- Optimized Font Install ---
function Install-JetBrainsMonoNerdFont {
    Write-Step "Fetching JetBrains Mono Nerd Font..."
    $fontName = "JetBrainsMono"
    $releaseApi = "https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest"
    
    try {
        $release = Invoke-RestMethod -Uri $releaseApi -Headers @{ "User-Agent" = "quickstart" }
        $asset = $release.assets | Where-Object { $_.name -eq "$fontName.zip" } | Select-Object -First 1
        
        $tempRoot = Join-Path $env:TEMP "quickstart-jb-font"
        if (Test-Path $tempRoot) { Remove-Item $tempRoot -Recurse -Force }
        New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
        
        $zipPath = Join-Path $tempRoot "$fontName.zip"
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
    } catch {
        Write-Failure "Font install failed: $($_.Exception.Message)"
    }
}

function Install-VDALibrary {
    param([string]$RepoRoot)
    Write-Step "Installing VirtualDesktopAccessor.dll..."

    # Define paths
    $sourceDll = Join-Path $RepoRoot "lib\VirtualDesktopAccessor.dll"
    $destFolder = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "AutoHotkey\Lib"
    $destFile = Join-Path $destFolder "VirtualDesktopAccessor.dll"

    if (Test-Path $sourceDll) {
        # Create folder if it doesn't exist
        if (-not (Test-Path $destFolder)) {
            New-Item -Path $destFolder -ItemType Directory -Force | Out-Null
            Write-Step "Created directory: $destFolder"
        }

        # Copy the file
        Copy-Item -Path $sourceDll -Destination $destFile -Force
        Write-Host "    Successfully copied DLL to $destFile" -ForegroundColor Green
    } else {
        Write-Failure "Source DLL not found at $sourceDll"
    }
}

function Install-TouchScripts {
    param([string]$RepoRoot)
    Write-Step "Installing Touch Toggle scripts..."

    # Define paths
    $userProfile = [Environment]::GetFolderPath("UserProfile")
    $destFolder = Join-Path $userProfile "Scripts"
    $sourceDir = Join-Path $RepoRoot "scripts"

    # Create destination folder if it doesn't exist
    if (-not (Test-Path $destFolder)) {
        New-Item -Path $destFolder -ItemType Directory -Force | Out-Null
        Write-Step "Created directory: $destFolder"
    }

    $filesToCopy = @("toggle_touch.cmd", "toggle_touch.ps1")

    foreach ($file in $filesToCopy) {
        $src = Join-Path $sourceDir $file
        $dest = Join-Path $destFolder $file

        if (Test-Path $src) {
            Copy-Item -Path $src -Destination $dest -Force
            Write-Host "    Copied $file to $dest" -ForegroundColor Green
        } else {
            Write-Warning "Source file not found: $src"
        }
    }
}

function Set-TaskbarPin {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][ValidateSet("Pin", "Unpin")][string]$Action
    )
    
    if (-not (Test-Path $FilePath)) {
        Write-Warning "Cannot pin $FilePath - Path not found."
        return
    }

    $shell = New-Object -ComObject Shell.Application
    $folder = $shell.NameSpace((Split-Path $FilePath))
    $item = $folder.ParseName((Split-Path $FilePath -Leaf))
    $verbs = $item.Verbs()

    # Find the localized string for Pin/Unpin
    $verbName = if ($Action -eq "Pin") { "taskbarpin" } else { "taskbarunpin" }
    $verb = $verbs | Where-Object { $_.Id -eq $verbName -or $_.Name -replace '&','' -match "(Pin to taskbar|Unpin from taskbar)" }

    if ($verb) {
        $verb.DoIt()
    }
}

function Configure-TaskbarLinks {
    param([string]$Profile)
    Write-Step "Configuring Taskbar Pins..."

    # Common Paths
    $Explorer = "C:\Windows\explorer.exe"
    $Chrome = "C:\Program Files\Google\Chrome\Application\chrome.exe"
    $Firefox = "C:\Program Files\Mozilla Firefox\firefox.exe"
    $Brave = "C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe"
    $SnippingTool = "C:\Windows\System32\SnippingTool.exe"
    $Calculator = "C:\Windows\System32\calc.exe"
    
    # Dev Paths
    $PowerShell = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
    $WezTerm = "$env:ProgramFiles\WezTerm\wezterm.exe"
    $Alacritty = "$env:ProgramFiles\Alacritty\alacritty.exe"
    $VSCode = "$env:LocalAppdata\Programs\Microsoft VS Code\Code.exe"
    $Joplin = "$env:LocalAppdata\Programs\Joplin\Joplin.exe"

    $BasePins = @($Explorer, $Chrome, $Firefox, $Brave, $SnippingTool, $Calculator)
    $DevPins = @($PowerShell, $WezTerm, $Alacritty, $VSCode, $Joplin)

    # Pin Base apps
    foreach ($app in $BasePins) { Set-TaskbarPin -FilePath $app -Action "Pin" }

    # Pin Dev apps if applicable
    if ($Profile -eq "Dev") {
        foreach ($app in $DevPins) { Set-TaskbarPin -FilePath $app -Action "Pin" }
    }
}

function Register-DevConfigs {
    param([string]$RepoRoot)
    Write-Step "Configuring Dev Environment..."

    # 1. WezTerm
    $wezSource = Join-Path $RepoRoot "dotfiles\wezterm\.wezterm.lua"
    if (Test-Path $wezSource) { Copy-Item -Path $wezSource -Destination (Join-Path $HOME ".wezterm.lua") -Force }

    # 2. Alacritty
    $alacrittySource = Join-Path $RepoRoot "dotfiles\alacritty\alacritty.toml"
    if (Test-Path $alacrittySource) {
        $alacrittyDestDir = Join-Path $env:APPDATA "alacritty"
        if (-not (Test-Path $alacrittyDestDir)) { New-Item -Path $alacrittyDestDir -ItemType Directory -Force | Out-Null }
        Copy-Item -Path $alacrittySource -Destination (Join-Path $alacrittyDestDir "alacritty.toml") -Force
    }

    # 3. Flow Launcher Settings Sync
    $flowSource = Join-Path $RepoRoot "dotfiles\flowlauncher\Settings.json"
    if (Test-Path $flowSource) {
        $flowDestDir = Join-Path $env:APPDATA "FlowLauncher\Settings"
        if (-not (Test-Path $flowDestDir)) { New-Item -Path $flowDestDir -ItemType Directory -Force | Out-Null }
        Copy-Item -Path $flowSource -Destination (Join-Path $flowDestDir "Settings.json") -Force
    }

    # 4. AutoHotkey Startup Registration
    Install-VDALibrary -RepoRoot $repoRoot
    Install-TouchScripts -RepoRoot $repoRoot
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
        Write-Step "Cloning repository..."
        git clone --depth 1 $RepoUrl $RepoCloneDir
    }
    $repoRoot = (Resolve-Path $RepoCloneDir).Path

    $BaseApps = @(
        "Mozilla.Firefox", "Google.Chrome", "Brave.Brave", "7zip.7zip", "VideoLAN.VLC", 
        "GIMP.GIMP.3", "PDFgear.PDFgear", "Tailscale.Tailscale",
        "Nextcloud.NextcloudDesktop", "Jellyfin.JellyfinMediaPlayer", "TheDocumentFoundation.LibreOffice", 
        "SyncTrayzor.SyncTrayzor", "LAB02Research.HASSAgent"
    )

    $DevApps = @(
        "wez.wezterm", "Alacritty.Alacritty", "Microsoft.VisualStudioCode", 
        "Joplin.Joplin", "Proton.ProtonVPN", "Oracle.VirtualBox", 
        "AutoHotkey.AutoHotkey", "Flow-Launcher.Flow-Launcher"
    )

    if (-not $InstallProfile) {
        Write-Host "`nSelect Profile:`n1) SettingsOnly`n2) BaseOnly`n3) Dev" -ForegroundColor Yellow
        $choice = Read-Host "Choice"
        $InstallProfile = switch($choice) { "1"{"SettingsOnly"}; "2"{"BaseOnly"}; "3"{"Dev"}; Default{"SettingsOnly"} }
    }

    switch ($InstallProfile) {
        "SettingsOnly" { Apply-AllSettings -RepoRoot $repoRoot }
        "BaseOnly" {
            Apply-AllSettings -RepoRoot $repoRoot
            foreach ($app in $BaseApps) { Install-WingetPackage -Id $app }
            Configure-TaskbarLinks -Profile "BaseOnly"
        }
        "Dev" {
            Apply-AllSettings -RepoRoot $repoRoot
            foreach ($app in ($BaseApps + $DevApps)) { Install-WingetPackage -Id $app }
            Configure-TaskbarLinks -Profile "Dev"
            Install-JetBrainsMonoNerdFont
            Register-DevConfigs -RepoRoot $repoRoot
            wsl --install --no-distribution 2>$null
        }
    }

    Write-Step "Bootstrap finished. Refreshing shell..."
    Get-Process explorer | Stop-Process -Force # Restarts Explorer to apply Taskbar/UI changes
}

try {
    Invoke-WindowsInit
} catch {
    Write-Failure "Error: $($_.Exception.Message)"
} finally {
    if (-not $NoExitPrompt) { Read-Host "`nPress Enter to exit" }
}