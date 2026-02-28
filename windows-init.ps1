param(
    [string]$WslDistro = "Ubuntu",
    [string]$RepoCloneDir = (Join-Path ([Environment]::GetFolderPath("Desktop")) "quickstart"),
    [ValidateSet("SettingsOnly", "BaseOnly", "DevOnly", "Dev")]
    [string]$InstallProfile,
    [switch]$NoExitPrompt,
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
    # Flow Launcher and Joplin often prefer User scope to avoid permission errors
    $scope = if ($Id -match "Flow-Launcher" -or $Id -match "Joplin") { "user" } else { "machine" }
    
    $args = "install --exact --id $Id --silent --accept-package-agreements --accept-source-agreements --scope $scope"
    $process = Start-Process winget -ArgumentList $args -Wait -PassThru -NoNewWindow
    if ($process.ExitCode -ne 0) {
        $fallbackArgs = "install --exact --id $Id --silent --accept-package-agreements --accept-source-agreements"
        Start-Process winget -ArgumentList $fallbackArgs -Wait -NoNewWindow
    }
}

# --- User Context Bridge ---
function Run-AsUser {
    param([string]$ScriptContent, [string]$TaskName = "QuickstartUserTask")
    $TriggerScript = Join-Path $env:TEMP "$TaskName.ps1"
    $ScriptContent | Out-File -FilePath $TriggerScript -Encoding utf8

    $UserAccount = (Get-CimInstance Win32_ComputerSystem).UserName
    $Action = New-ScheduledTaskAction -Execute 'Powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$TriggerScript`""
    $Principal = New-ScheduledTaskPrincipal -UserId $UserAccount -LogonType Interactive
    
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Principal $Principal -Force | Out-Null
    Start-ScheduledTask -TaskName $TaskName
    Start-Sleep -Seconds 5
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    if (Test-Path $TriggerScript) { Remove-Item $TriggerScript -Force }
}

# --- Personalization ---
function Apply-AllSettings {
    param([string]$RepoRoot)
    Write-Step "Applying Theme & Keyboard Settings..."

    $UserRegScript = @"
    # Dark Mode
    `$pers = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    if (-not (Test-Path `$pers)) { New-Item -Path `$pers -Force }
    Set-ItemProperty -Path `$pers -Name "AppsUseLightTheme" -Value 0 -Force
    Set-ItemProperty -Path `$pers -Name "SystemUsesLightTheme" -Value 0 -Force

    # Touch Keyboard Scaling
    `$ttip = "HKCU:\Software\Microsoft\TabletTip\1.7"
    if (-not (Test-Path `$ttip)) { New-Item -Path `$ttip -Force }
    Set-ItemProperty -Path `$ttip -Name "UserKeyboardScalingFactor" -Value 180 -Force
"@
    Run-AsUser -ScriptContent $UserRegScript -TaskName "ApplyUserRegistry"

    $sourceDir = Join-Path $RepoRoot "wallpapers"
    if (Test-Path $sourceDir) {
        $targetDir = Join-Path $OriginalUserPath "Pictures\quickstart-wallpapers"
        if (-not (Test-Path $targetDir)) { New-Item -Path $targetDir -ItemType Directory -Force | Out-Null }
        Get-ChildItem -Path $sourceDir -File | ForEach-Object { Copy-Item -Path $_.FullName -Destination (Join-Path $targetDir $_.Name) -Force }
    }
}

# --- Taskbar ---
function Configure-TaskbarLinks {
    param([string]$Profile)
    Write-Step "Configuring Taskbar Pins..."

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
        $Apps += Join-Path $OriginalUserPath "AppData\Local\Programs\Microsoft VS Code\Code.exe"
        $Apps += Join-Path $OriginalUserPath "AppData\Local\Programs\Joplin\Joplin.exe"
    }

    $PinScript = @"
    function Set-Pin {
        param(`$Path)
        if (-not (Test-Path `$Path)) { return }
        `$shell = New-Object -ComObject Shell.Application
        `$folder = `$shell.NameSpace((Split-Path `$Path))
        `$item = `$folder.ParseName((Split-Path `$Path -Leaf))
        `$verbs = `$item.Verbs()
        `$verb = `$verbs | Where-Object { `$_.Id -eq 'taskbarpin' -or `$_.Name -replace '&','' -match '(Pin to taskbar)' }
        if (`$verb) { `$verb.DoIt() }
    }
    `$AppsToPin = @($( ($Apps | ForEach-Object { "'$_'" }) -join "," ))
    foreach (`$App in `$AppsToPin) { Set-Pin -Path `$App }
"@
    Run-AsUser -ScriptContent $PinScript -TaskName "PinTaskbarIcons"
}

# --- Dev Configs ---
function Register-DevConfigs {
    param([string]$RepoRoot)
    Write-Step "Syncing Dotfiles (Fixing Flow Launcher Permissions)..."
    $TargetAppData = Join-Path $OriginalUserPath "AppData\Roaming"

    # WezTerm
    $wezSource = Join-Path $RepoRoot "dotfiles\wezterm\.wezterm.lua"
    if (Test-Path $wezSource) { Copy-Item -Path $wezSource -Destination (Join-Path $OriginalUserPath ".wezterm.lua") -Force }

    # Flow Launcher - WE CREATE THE FOLDER AS ADMIN BUT ENSURE IT'S ACCESSIBLE
    $flowSource = Join-Path $RepoRoot "dotfiles\flowlauncher\Settings.json"
    $flowDestDir = Join-Path $TargetAppData "FlowLauncher\Settings"
    if (Test-Path $flowSource) {
        if (-not (Test-Path $flowDestDir)) { 
            New-Item -Path $flowDestDir -ItemType Directory -Force | Out-Null 
        }
        Copy-Item -Path $flowSource -Destination (Join-Path $flowDestDir "Settings.json") -Force
        
        # FIX PERMISSIONS: Ensure the User has full control over the folder we just created as Admin
        $Acl = Get-Acl $flowDestDir
        $Ar = New-Object System.Security.AccessControl.FileSystemAccessRule((Get-CimInstance Win32_ComputerSystem).UserName, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
        $Acl.SetAccessRule($Ar)
        Set-Acl $flowDestDir $Acl
    }

    # AHK Startup
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

# --- Font Install ---
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

# --- Controller ---
function Invoke-WindowsInit {
    Ensure-Admin
    winget source update
    Install-WingetPackage -Id "Git.Git"
    Refresh-ProcessPath
    
    if (-not (Test-Path $RepoCloneDir)) { git clone --depth 1 $RepoUrl $RepoCloneDir }
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

    Write-Step "Finished. Restarting Explorer..."
    Stop-Process -Name explorer -Force
}

try { Invoke-WindowsInit } catch { Write-Failure "Error: $($_.Exception.Message)" } finally { if (-not $NoExitPrompt) { Read-Host "`nPress Enter to exit" } }