param(
    [string]$WslDistro = "Ubuntu",
    [string]$RepoCloneDir = (Join-Path $HOME "quickstart"),
    [switch]$NoExitPrompt
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoUrl = "https://github.com/shubymao/quickstart"
$RepoBranch = "main"

function Write-Step {
    param([string]$Message)
    Write-Host "[quickstart] $Message" -ForegroundColor Cyan
}

function Write-Failure {
    param([string]$Message)
    Write-Host "[quickstart] $Message" -ForegroundColor Red
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-Admin {
    if (Test-IsAdmin) {
        return
    }

    if (-not $PSCommandPath) {
        throw "Administrator privileges are required. Please rerun this script from an elevated PowerShell session."
    }

    Write-Step "Requesting administrator privileges..."
    $hostExe = (Get-Process -Id $PID).Path
    $arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath)
    if ($PSBoundParameters.ContainsKey("WslDistro")) {
        $arguments += @("-WslDistro", $WslDistro)
    }
    if ($PSBoundParameters.ContainsKey("RepoCloneDir")) {
        $arguments += @("-RepoCloneDir", $RepoCloneDir)
    }
    if ($NoExitPrompt) {
        $arguments += "-NoExitPrompt"
    }

    try {
        Start-Process -FilePath $hostExe -ArgumentList $arguments -Verb RunAs | Out-Null
    } catch {
        throw "Administrator privileges are required. Rerun this script and approve the UAC prompt."
    }

    exit 0
}

function Require-Command {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found."
    }
}

function Install-WingetPackage {
    param([string]$Id)

    $existing = winget list --exact --id $Id --accept-source-agreements 2>$null
    if ($LASTEXITCODE -eq 0 -and $existing -match [regex]::Escape($Id)) {
        Write-Step "Package already installed: $Id"
        return
    }

    Write-Step "Installing package: $Id"
    winget install --exact --id $Id --silent --accept-package-agreements --accept-source-agreements
}

function Refresh-ProcessPath {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $segments = @()
    if ($machinePath) { $segments += $machinePath }
    if ($userPath) { $segments += $userPath }
    $env:Path = ($segments -join ";")
}

function Ensure-GitInstalled {
    Install-WingetPackage -Id "Git.Git"
    Refresh-ProcessPath
    Require-Command -Name "git"
}

function Clone-Repo {
    param(
        [string]$RepoUrl,
        [string]$Branch,
        [string]$Destination
    )

    if (Test-Path $Destination) {
        if (Test-Path (Join-Path $Destination ".git")) {
            Write-Step "Repo already cloned: $Destination"
            return
        }
        throw "Destination exists but is not a git repo: $Destination"
    }

    Write-Step "Cloning repo to $Destination (shallow, faster)"
    git clone --depth 1 --filter=blob:none --single-branch --branch $Branch $RepoUrl $Destination
}

function Get-InstallProfile {
    Write-Host ""
    Write-Host "Choose install profile:"
    Write-Host "1) Base only (recommended for non-dev machines)"
    Write-Host "2) Dev (installs Base + Dev tools)"
    $choice = Read-Host "Enter choice [1/2]"

    if ($choice -eq "2") {
        return "Dev"
    }

    return "BaseOnly"
}

function Get-InstallMode {
    Write-Host ""
    Write-Host "Choose install mode:"
    Write-Host "1) Serial (recommended, most reliable)"
    Write-Host "2) Parallel (faster, may fail on some installers)"
    $choice = Read-Host "Enter choice [1/2]"

    if ($choice -eq "2") {
        return "Parallel"
    }

    return "Serial"
}

function Ensure-WslInstalled {
    param([string]$Distro)

    Write-Step "Ensuring WSL optional components are installed"
    wsl --install --no-distribution 2>$null | Out-Null

    Write-Step "Setting WSL default version to 2"
    wsl --set-default-version 2 2>$null | Out-Null

    $installedDistros = wsl -l -q 2>$null
    if ($installedDistros -match "^\s*$([regex]::Escape($Distro))\s*$") {
        Write-Step "WSL distro already installed: $Distro"
        return
    }

    Write-Step "Installing WSL distro: $Distro"
    wsl --install --distribution $Distro
}

function Install-WezTermConfig {
    param([string]$RepoRoot)

    $source = Join-Path $RepoRoot "dotfiles\wezterm\.wezterm.lua"
    if (-not (Test-Path $source)) {
        throw "WezTerm config not found: $source"
    }

    $target = Join-Path $HOME ".wezterm.lua"
    Copy-Item -Path $source -Destination $target -Force
    Write-Step "Installed WezTerm config to $target"
}

function Get-RepoAssetsRoot {
    param([string]$RepoRoot)

    if (-not (Test-Path $RepoRoot)) {
        throw "Repo root not found: $RepoRoot"
    }

    return (Resolve-Path $RepoRoot).Path
}

function Install-NerdFonts {
    param([string]$RepoRoot)

    $fontPacks = @("Meslo", "FiraCode", "SourceCodePro")
    $releaseApi = "https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest"

    Write-Step "Installing Nerd Fonts from latest release: $($fontPacks -join ', ')"

    try {
        $release = Invoke-RestMethod -Uri $releaseApi -Headers @{ "User-Agent" = "quickstart-windows-init" }
    } catch {
        throw "Failed to query Nerd Fonts latest release: $($_.Exception.Message)"
    }

    $tempRoot = Join-Path $env:TEMP "quickstart-nerd-fonts"
    New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null

    $shell = New-Object -ComObject Shell.Application
    $fontsNamespace = $shell.Namespace(0x14)
    if (-not $fontsNamespace) {
        throw "Unable to access Windows Fonts shell namespace."
    }

    foreach ($fontPack in $fontPacks) {
        $assetName = "$fontPack.zip"
        $asset = $release.assets | Where-Object { $_.name -ieq $assetName } | Select-Object -First 1
        if (-not $asset) {
            Write-Step "Skipping font pack '$fontPack': asset '$assetName' not found in release $($release.tag_name)"
            continue
        }

        $zipPath = Join-Path $tempRoot $asset.name
        $extractDir = Join-Path $tempRoot "$fontPack-$($release.tag_name)"
        if (Test-Path $extractDir) {
            Remove-Item -Path $extractDir -Recurse -Force
        }

        Write-Step "Downloading font pack: $assetName"
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath
        Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

        $fontFiles = Get-ChildItem -Path $extractDir -Recurse -File | Where-Object {
            $_.Extension -in @(".ttf", ".otf")
        }
        if (-not $fontFiles) {
            Write-Step "No font files found in $assetName"
            continue
        }

        foreach ($fontFile in $fontFiles) {
            $installedPath = Join-Path $env:WINDIR "Fonts\$($fontFile.Name)"
            if (Test-Path $installedPath) {
                continue
            }

            Write-Step "Installing font file: $($fontFile.Name)"
            $fontsNamespace.CopyHere($fontFile.FullName, 16)
        }
    }

    Write-Step "Nerd Font installation completed."
}

function Resolve-AutoHotkeyExe {
    $candidates = @(
        "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe",
        "C:\Program Files\AutoHotkey\v2\AutoHotkey.exe",
        (Join-Path $env:LOCALAPPDATA "Programs\AutoHotkey\v2\AutoHotkey64.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\AutoHotkey\v2\AutoHotkey.exe")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    $fromPath = Get-Command AutoHotkey64.exe -ErrorAction SilentlyContinue
    if ($fromPath) { return $fromPath.Source }

    $fromPath = Get-Command AutoHotkey.exe -ErrorAction SilentlyContinue
    if ($fromPath) { return $fromPath.Source }

    throw "AutoHotkey executable was not found after installation."
}

function Register-StartupAhk {
    param(
        [string]$RepoRoot
    )

    $ahkScript = Join-Path $RepoRoot "dotfiles\main.ahk"
    if (-not (Test-Path $ahkScript)) {
        throw "AutoHotkey script not found: $ahkScript"
    }

    $startupDir = [Environment]::GetFolderPath("Startup")
    $shortcutPath = Join-Path $startupDir "main.ahk.lnk"
    $ahkExe = Resolve-AutoHotkeyExe

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $ahkExe
    $shortcut.Arguments = '"' + $ahkScript + '"'
    $shortcut.WorkingDirectory = Split-Path -Parent $ahkScript
    $shortcut.IconLocation = "$ahkExe,0"
    $shortcut.Save()

    Write-Step "Registered startup shortcut: $shortcutPath"
}

function Install-Wallpapers {
    param([string]$RepoRoot)

    $sourceDir = Join-Path $RepoRoot "wallpapers"
    if (-not (Test-Path $sourceDir)) {
        throw "Wallpaper source directory not found: $sourceDir"
    }

    $picturesDir = [Environment]::GetFolderPath("MyPictures")
    $targetDir = Join-Path $picturesDir "quickstart-wallpapers"
    New-Item -Path $targetDir -ItemType Directory -Force | Out-Null

    $copied = Get-ChildItem -Path $sourceDir -File | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination (Join-Path $targetDir $_.Name) -Force
        Join-Path $targetDir $_.Name
    }

    if (-not $copied -or $copied.Count -eq 0) {
        throw "No wallpaper files found in $sourceDir"
    }

    Write-Step "Copied wallpapers to $targetDir"
    return @{
        Directory = $targetDir
        FirstImage = $copied[0]
    }
}

function Set-DesktopSlideshow {
    param([string]$WallpaperDirectory)

    $slideshowKey = "HKCU:\Control Panel\Personalization\Desktop Slideshow"
    $wallpaperKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers"

    New-Item -Path $slideshowKey -Force | Out-Null
    New-Item -Path $wallpaperKey -Force | Out-Null

    Set-ItemProperty -Path $slideshowKey -Name "Interval" -Type DWord -Value 600000
    Set-ItemProperty -Path $slideshowKey -Name "Shuffle" -Type DWord -Value 1
    Set-ItemProperty -Path $wallpaperKey -Name "BackgroundType" -Type DWord -Value 2
    Set-ItemProperty -Path $wallpaperKey -Name "SlideshowEnabled" -Type DWord -Value 1
    Set-ItemProperty -Path $wallpaperKey -Name "ImagesRootPath" -Type String -Value $WallpaperDirectory

    Start-Process -FilePath "RUNDLL32.EXE" -ArgumentList "USER32.DLL,UpdatePerUserSystemParameters 1, True" -WindowStyle Hidden
    Write-Step "Configured desktop wallpaper slideshow"
}

function Set-LockScreenImage {
    param([string]$ImagePath)

    $policyKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization"
    New-Item -Path $policyKey -Force | Out-Null
    Set-ItemProperty -Path $policyKey -Name "LockScreenImage" -Type String -Value $ImagePath
    Write-Step "Configured lock screen image policy to $ImagePath"
}

function Set-WindowsDarkTheme {
    $personalizeKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    New-Item -Path $personalizeKey -Force | Out-Null
    Set-ItemProperty -Path $personalizeKey -Name "AppsUseLightTheme" -Type DWord -Value 0
    Set-ItemProperty -Path $personalizeKey -Name "SystemUsesLightTheme" -Type DWord -Value 0

    $explorerAdvanced = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    New-Item -Path $explorerAdvanced -Force | Out-Null
    Set-ItemProperty -Path $explorerAdvanced -Name "UseOLEDTaskbarTransparency" -Type DWord -Value 1

    Write-Step "Configured Windows dark theme (apps + system)"
}

function Enable-TouchKeyboardLargest {
    $tabletTipKey = "HKCU:\Software\Microsoft\TabletTip\1.7"
    New-Item -Path $tabletTipKey -Force | Out-Null
    Set-ItemProperty -Path $tabletTipKey -Name "UserKeyboardScalingFactor" -Type DWord -Value 200
    Write-Step "Set touch keyboard size to largest"

    try {
        Set-Service -Name "TabletInputService" -StartupType Automatic -ErrorAction Stop
        if ((Get-Service -Name "TabletInputService").Status -ne "Running") {
            Start-Service -Name "TabletInputService"
        } else {
            Restart-Service -Name "TabletInputService" -Force
        }
        Write-Step "Touch Keyboard service is running"
    } catch {
        Write-Step "Touch Keyboard service update skipped: $($_.Exception.Message)"
    }
}

function Resolve-AppPath {
    param(
        [string[]]$Candidates,
        [switch]$AllowCommandName
    )

    foreach ($candidate in $Candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    if ($AllowCommandName) {
        foreach ($candidate in $Candidates) {
            $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
            if ($cmd -and $cmd.Source) {
                return $cmd.Source
            }
        }
    }

    return $null
}

function New-WindowsShortcut {
    param(
        [string]$ShortcutPath,
        [string]$TargetPath,
        [string]$Arguments = "",
        [string]$WorkingDirectory = "",
        [string]$IconLocation = ""
    )

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $TargetPath
    $shortcut.Arguments = $Arguments
    if ($WorkingDirectory) { $shortcut.WorkingDirectory = $WorkingDirectory }
    if ($IconLocation) { $shortcut.IconLocation = $IconLocation }
    $shortcut.Save()
}

function Try-PinToTaskbar {
    param(
        [string]$AppPath,
        [string]$ShortcutPath
    )

    try {
        $shell = New-Object -ComObject Shell.Application
        $folder = $shell.Namespace((Split-Path -Parent $AppPath))
        if ($folder) {
            $item = $folder.ParseName((Split-Path -Leaf $AppPath))
            if ($item) {
                $pinVerb = $item.Verbs() | Where-Object {
                    $_.Name.Replace('&', '') -match 'Pin to taskbar'
                } | Select-Object -First 1
                if ($pinVerb) {
                    $pinVerb.DoIt()
                    return $true
                }
            }
        }
    } catch {
    }

    try {
        $taskbarPinnedDir = Join-Path $env:APPDATA "Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
        New-Item -Path $taskbarPinnedDir -ItemType Directory -Force | Out-Null
        Copy-Item -Path $ShortcutPath -Destination (Join-Path $taskbarPinnedDir (Split-Path $ShortcutPath -Leaf)) -Force
        return $true
    } catch {
        return $false
    }
}

function Configure-AppShortcuts {
    Write-Step "Creating desktop shortcuts and pinning requested apps to taskbar"

    $desktopDir = [Environment]::GetFolderPath("Desktop")
    $pinnedFailed = @()

    $apps = @(
        @{
            Name = "File Explorer"
            Path = Resolve-AppPath -Candidates @("C:\Windows\explorer.exe", "explorer.exe") -AllowCommandName
        },
        @{
            Name = "PowerShell"
            Path = Resolve-AppPath -Candidates @("C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe", "powershell.exe") -AllowCommandName
        },
        @{
            Name = "WezTerm"
            Path = Resolve-AppPath -Candidates @(
                "C:\Program Files\WezTerm\wezterm-gui.exe",
                (Join-Path $env:LOCALAPPDATA "Programs\WezTerm\wezterm-gui.exe"),
                "wezterm-gui.exe"
            ) -AllowCommandName
        },
        @{
            Name = "Alacritty"
            Path = Resolve-AppPath -Candidates @(
                "C:\Program Files\Alacritty\alacritty.exe",
                (Join-Path $env:LOCALAPPDATA "Programs\Alacritty\alacritty.exe"),
                "alacritty.exe"
            ) -AllowCommandName
        },
        @{
            Name = "Snipping Tool"
            Path = Resolve-AppPath -Candidates @("C:\Windows\System32\SnippingTool.exe", "SnippingTool.exe") -AllowCommandName
        },
        @{
            Name = "Calculator"
            Path = Resolve-AppPath -Candidates @("C:\Windows\System32\calc.exe", "calc.exe") -AllowCommandName
        },
        @{
            Name = "Browser"
            Path = Resolve-AppPath -Candidates @(
                "C:\Program Files\Google\Chrome\Application\chrome.exe",
                "C:\Program Files\Mozilla Firefox\firefox.exe",
                "C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe",
                "chrome.exe",
                "firefox.exe",
                "brave.exe"
            ) -AllowCommandName
        },
        @{
            Name = "Google Chrome"
            Path = Resolve-AppPath -Candidates @(
                "C:\Program Files\Google\Chrome\Application\chrome.exe",
                "chrome.exe"
            ) -AllowCommandName
        }
    )

    foreach ($app in $apps) {
        if (-not $app.Path) {
            Write-Step "Skipping shortcut for $($app.Name): app not found"
            continue
        }

        $shortcutPath = Join-Path $desktopDir "$($app.Name).lnk"
        New-WindowsShortcut -ShortcutPath $shortcutPath -TargetPath $app.Path -WorkingDirectory (Split-Path -Parent $app.Path) -IconLocation "$($app.Path),0"

        if (-not (Try-PinToTaskbar -AppPath $app.Path -ShortcutPath $shortcutPath)) {
            $pinnedFailed += $app.Name
        }
    }

    if ($pinnedFailed.Count -gt 0) {
        Write-Step "Taskbar pinning may be blocked by Windows policy/version for: $($pinnedFailed -join ', ')"
    }
}

function Wait-ForExitPrompt {
    if ($NoExitPrompt) {
        return
    }

    if ($Host.Name -eq "ConsoleHost") {
        Write-Host ""
        [void](Read-Host "Press Enter to close this window")
    }
}

function Invoke-WindowsInit {
    Ensure-Admin
    Require-Command -Name "winget"
    Ensure-GitInstalled
    Clone-Repo -RepoUrl $RepoUrl -Branch $RepoBranch -Destination $RepoCloneDir

    Write-Step "Preparing assets from cloned repo"
    $repoRoot = Get-RepoAssetsRoot -RepoRoot $RepoCloneDir
    $InstallProfile = Get-InstallProfile
    $isDevProfile = $InstallProfile -eq "Dev"
    $InstallMode = Get-InstallMode

    $appGroups = @{
        Base = @(
            "Mozilla.Firefox",
            "Google.Chrome",
            "Brave.Brave",
            "7zip.7zip",
            "VideoLAN.VLC",
            "GIMP.GIMP",
            "PDFgear.PDFgear",
            "tailscale.tailscale",
            "Nextcloud.NextcloudDesktop",
            "Jellyfin.JellyfinMediaPlayer",
            "TheDocumentFoundation.LibreOffice"
        )
        Dev = @(
            "Wez.WezTerm",
            "Alacritty.Alacritty",
            "Microsoft.VisualStudioCode",
            "Joplin.Joplin",
            "Proton.ProtonVPN",
            "Oracle.VirtualBox",
            "AutoHotkey.AutoHotkey"
        )
    }

    $installIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($id in $appGroups.Base) { [void]$installIds.Add($id) }
    if ($isDevProfile) {
        foreach ($id in $appGroups.Dev) { [void]$installIds.Add($id) }
    }

    Write-Step "Installing app packages for profile: $InstallProfile"
    if ($InstallMode -eq "Parallel") {
        if ($PSVersionTable.PSVersion.Major -lt 7) {
            Write-Step "Parallel install requires PowerShell 7+. Falling back to serial mode."
            foreach ($id in $installIds) {
                Install-WingetPackage -Id $id
            }
        } else {
            Write-Step "Running winget installs in parallel (throttle=3)"
            $installFunc = ${function:Install-WingetPackage}
            @($installIds) | ForEach-Object -Parallel {
                & $using:installFunc -Id $_
            } -ThrottleLimit 3
        }
    } else {
        foreach ($id in $installIds) {
            Install-WingetPackage -Id $id
        }
    }

    Install-NerdFonts -RepoRoot $repoRoot

    if ($isDevProfile) {
        Require-Command -Name "wsl"
        Ensure-WslInstalled -Distro $WslDistro
        Install-WezTermConfig -RepoRoot $repoRoot
        Register-StartupAhk -RepoRoot $repoRoot
    }

    $wallpaperResult = Install-Wallpapers -RepoRoot $repoRoot
    Set-DesktopSlideshow -WallpaperDirectory $wallpaperResult.Directory
    try {
        Set-LockScreenImage -ImagePath $wallpaperResult.FirstImage
    } catch {
        Write-Step "Lock screen policy was not set: $($_.Exception.Message)"
    }
    Set-WindowsDarkTheme
    Enable-TouchKeyboardLargest
    Configure-AppShortcuts

    Write-Step "Windows bootstrap completed."
    if ($isDevProfile) {
        Write-Step "If WSL features were newly enabled, reboot Windows and run this script once more."
    }
}

try {
    Invoke-WindowsInit
} catch {
    Write-Failure "Bootstrap failed."
    Write-Failure "Message: $($_.Exception.Message)"
    if ($_.InvocationInfo -and $_.InvocationInfo.PositionMessage) {
        Write-Failure $_.InvocationInfo.PositionMessage
    }
    if ($_.ScriptStackTrace) {
        Write-Failure "Stack: $($_.ScriptStackTrace)"
    }
    exit 1
} finally {
    Wait-ForExitPrompt
}
