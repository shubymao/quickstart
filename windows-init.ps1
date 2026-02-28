param(
    [string]$WslDistro = "Ubuntu",
    [string]$RepoCloneDir = (Join-Path ([Environment]::GetFolderPath("Desktop")) "quickstart"),
    [ValidateSet("SettingsOnly", "BaseOnly", "DevOnly", "Dev")]
    [string]$InstallProfile,
    [switch]$NoExitPrompt,
    # Captures the non-admin user's home directory path before elevation
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
    Write-Step "Requesting administrator privileges..."
    
    $currentHome = $HOME 
    $arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath)
    if ($PSBoundParameters.ContainsKey("WslDistro")) { $arguments += @("-WslDistro", $WslDistro) }
    if ($PSBoundParameters.ContainsKey("RepoCloneDir")) { $arguments += @("-RepoCloneDir", $RepoCloneDir) }
    if ($PSBoundParameters.ContainsKey("InstallProfile")) { $arguments += @("-InstallProfile", $InstallProfile) }
    if ($NoExitPrompt) { $arguments += "-NoExitPrompt" }
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

# --- Taskbar Bridge (Impersonates User) ---
function Configure-TaskbarLinks {
    param([string]$Profile)
    Write-Step "Configuring Taskbar Pins for the logged-in user..."

    # Full App List
    $Apps = @(
        "C:\Windows\explorer.exe",
        "C:\Program Files\Google\Chrome\Application\chrome.exe",
        "C:\Program Files\Mozilla Firefox\firefox.exe",
        "C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe",
        "C:\Windows\System32\SnippingTool.exe",
        "C:\Windows\System32\calc.exe"
    )

    if ($Profile -eq "Dev") {
        $Apps += "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
        $Apps += "C:\Program Files\WezTerm\wezterm.exe"
        $Apps += "C:\Program Files\Alacritty\alacritty.exe"
        $Apps += Join-Path $OriginalUserPath "AppData\Local\Programs\Microsoft VS Code\Code.exe"
        $Apps += Join-Path $OriginalUserPath "AppData\Local\Programs\Joplin\Joplin.exe"
    }

    $TriggerScript = Join-Path $env:TEMP "pin_taskbar.ps1"
    $ScriptBlock = @"
    function Set-Pin {
        param(\$Path)
        if (-not (Test-Path \$Path)) { return }
        \$shell = New-Object -ComObject Shell.Application
        \$folder = \$shell.NameSpace((Split-Path \$Path))
        \$item = \$folder.ParseName((Split-Path \$Path -Leaf))
        \$verbs = \$item.Verbs()
        \$verb = \$verbs | Where-Object { \$_.Id -eq 'taskbarpin' -or \$_.Name -replace '&','' -match '(Pin to taskbar)' }
        if (\$verb) { \$verb.DoIt() }
    }
    \$AppsToPin = @($( ($Apps | ForEach-Object { "'$_'" }) -join "," ))
    foreach (\$App in \$AppsToPin) { Set-Pin -Path \$App }
"@
    $ScriptBlock | Out-File -FilePath $TriggerScript -Encoding utf8

    $TaskName = "QuickstartTaskbarPin"
    $UserAccount = (Get-CimInstance Win32_ComputerSystem).UserName
    $Action = New-ScheduledTaskAction -Execute 'Powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$TriggerScript`""
    $Principal = New-ScheduledTaskPrincipal -UserId $UserAccount -LogonType Interactive
    
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Principal $Principal -Force | Out-Null
    Start-ScheduledTask -TaskName $TaskName
    Start-Sleep -Seconds 3
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

# --- Personalization (Targets User Registry via SID) ---
function Apply-AllSettings {
    param([string]$RepoRoot)
    Write-Step "Applying Theme & Settings to $OriginalUserPath..."

    # Get User SID to modify their specific registry hive while Admin
    $UserSID = (New-Object System.Security.Principal.NTAccount((Get-CimInstance Win32_ComputerSystem).UserName)).Translate([System.Security.Principal.SecurityIdentifier]).Value
    $BaseRegPath = "Registry::HKEY_USERS\$UserSID"

    # 1. Dark Theme
    $personalizeKey = "$BaseRegPath\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    if (Test-Path $personalizeKey) {
        Set-ItemProperty -Path $personalizeKey -Name "AppsUseLightTheme" -Value 0 -Force
        Set-ItemProperty -Path $personalizeKey -Name "SystemUsesLightTheme" -Value 0 -Force
    }

    # 2. Touch Keyboard
    $tabTipKey = "$BaseRegPath\Software\Microsoft\TabletTip\1.7"
    if (-not (Test-Path $tabTipKey)) { New-Item -Path $tabTipKey -Force | Out-Null }
    Set-ItemProperty -Path $tabTipKey -Name "UserKeyboardScalingFactor" -Value 180 -Force

    # 3. Wallpapers
    $sourceDir = Join-Path $RepoRoot "wallpapers"
    if (Test-Path $sourceDir) {
        $targetDir = Join-Path $OriginalUserPath "Pictures\quickstart-wallpapers"
        if (-not (Test-Path $targetDir)) { New-Item -Path $targetDir -ItemType Directory -Force | Out-Null }
        
        $copiedFiles = Get-ChildItem -Path $sourceDir -File | ForEach-Object {
            $dest = Join-Path $targetDir $_.Name
            Copy-Item -Path $_.FullName -Destination $dest -Force
            $dest
        }

        # Set Wallpaper for current session
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

function Install-JetBrainsMonoNerdFont {
    Write-Step "Installing Fonts..."
    try {
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest" -Headers @{ "User-Agent" = "quickstart" }
        $asset = $release.assets | Where-Object { $_.name -eq "JetBrainsMono.zip" } | Select-Object -First 1
        $tempRoot = Join-Path $env:TEMP "quickstart-jb-font"
        New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
        $zipPath = Join-Path $tempRoot "JetBrainsMono.zip"
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath
        Expand-Archive -Path $zipPath -DestinationPath $tempRoot -Force
        Get-ChildItem -Path $tempRoot -Include "*.ttf", "*.otf" -Recurse | ForEach-Object {
            $dest = Join-Path $env:WINDIR "Fonts\$($_.Name)"
            if (-not (Test-Path $dest)) {
                Copy-Item -Path $_.FullName -Destination $dest -Force
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" -Name "$($_.BaseName) (TrueType)" -Value $_.Name
            }
        }
    } catch { Write-Failure "Font install failed." }
}

function Register-DevConfigs {
    param([string]$RepoRoot)
    Write-Step "Syncing Dotfiles..."
    $TargetAppData = Join-Path $OriginalUserPath "AppData\Roaming"

    # WezTerm
    $wezSource = Join-Path $RepoRoot "dotfiles\wezterm\.wezterm.lua"
    if (Test-Path $wezSource) { Copy-Item -Path $wezSource -Destination (Join-Path $OriginalUserPath ".wezterm.lua") -Force }

    # Alacritty
    $alacrittySource = Join-Path $RepoRoot "dotfiles\alacritty\alacritty.toml"
    $alacrittyDestDir = Join-Path $TargetAppData "alacritty"
    if (Test-Path $alacrittySource) {
        if (-not (Test-Path $alacrittyDestDir)) { New-Item -Path $alacrittyDestDir -ItemType Directory -Force | Out-Null }
        Copy-Item -Path $alacrittySource -Destination (Join-Path $alacrittyDestDir "alacritty.toml") -Force
    }

    # Flow Launcher
    $flowSource = Join-Path $RepoRoot "dotfiles\flowlauncher\Settings.json"
    $flowDestDir = Join-Path $TargetAppData "FlowLauncher\Settings"
    if (Test-Path $flowSource) {
        if (-not (Test-Path $flowDestDir)) { New-Item -Path $flowDestDir -ItemType Directory -Force | Out-Null }
        Copy-Item -Path $flowSource -Destination (Join-Path $flowDestDir "Settings.json") -Force
    }

    # AHK Startup (Shortcut placed in User's Startup folder)
    $ahkScript = Join-Path $RepoRoot "dotfiles\main.ahk"
    if (Test-Path $ahkScript) {
        $ahkExe = "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
        if (Test-Path $ahkExe) {
            $startup = Join-Path $TargetAppData "Microsoft\Windows\Start Menu\Programs\Startup"
            $wsh = New-Object -ComObject WScript.Shell
            $lnk = $wsh.CreateShortcut((Join-Path $startup "main.ahk.lnk"))
            $lnk.TargetPath = $ahkExe
            $lnk.Arguments = "`"$ahkScript`""
            $lnk.Save()
        }
    }
}

# --- Execution Controller ---
function Invoke-WindowsInit {
    Ensure-Admin
    Write-Step "Refreshing Winget sources..."
    winget source update
    
    Install-WingetPackage -Id "Git.Git"
    Refresh-ProcessPath
    
    if (-not (Test-Path $RepoCloneDir)) {
        Write-Step "Cloning repository..."
        git clone --depth 1 $RepoUrl $RepoCloneDir
    }
    $repoRoot = (Resolve-Path $RepoCloneDir).Path

    $BaseApps = @("Mozilla.Firefox", "Google.Chrome", "Brave.Brave", "7zip.7zip", "VideoLAN.VLC", "GIMP.GIMP.3", "PDFgear.PDFgear", "Tailscale.Tailscale", "Nextcloud.NextcloudDesktop", "Jellyfin.JellyfinMediaPlayer", "TheDocumentFoundation.LibreOffice", "SyncTrayzor.SyncTrayzor", "LAB02Research.HASSAgent")
    $DevApps = @("wez.wezterm", "Alacritty.Alacritty", "Microsoft.VisualStudioCode", "Joplin.Joplin", "Proton.ProtonVPN", "Oracle.VirtualBox", "AutoHotkey.AutoHotkey", "Flow-Launcher.Flow-Launcher")

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

    Write-Step "Bootstrap finished. Refreshing Explorer UI..."
    Stop-Process -Name explorer -Force
}

try { Invoke-WindowsInit } 
catch { Write-Failure "Error: $($_.Exception.Message)" } 
finally { if (-not $NoExitPrompt) { Read-Host "`nPress Enter to exit" } }