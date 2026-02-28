param(
    [string]$WslDistro = "Ubuntu",
    [string]$RepoCloneDir = "", 
    [ValidateSet("SettingsOnly", "BaseOnly", "Dev")]
    [string]$InstallProfile,
    [switch]$NoExitPrompt,
    [string]$OriginalUserPath = $HOME
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoUrl = "https://github.com/shubymao/quickstart"

# --- UI & Logging ---
function Write-Step { param([string]$Message) Write-Host "`n[quickstart] $Message" -ForegroundColor Cyan }
function Write-Failure { param([string]$Message) Write-Host "[quickstart] $Message" -ForegroundColor Red }

# --- Admin Elevation (The Handshake) ---
function Ensure-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { return }

    Write-Step "Requesting administrator privileges..."
    $currentHome = $HOME 
    $targetDocs = Join-Path $currentHome "Documents\quickstart"

    $arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath)
    if ($PSBoundParameters.ContainsKey("InstallProfile")) { $arguments += @("-InstallProfile", $InstallProfile) }
    $arguments += @("-OriginalUserPath", $currentHome)
    $arguments += @("-RepoCloneDir", $targetDocs)

    try {
        Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -Verb RunAs | Out-Null
    } catch {
        throw "Administrator privileges required."
    }
    exit 0
}

# --- User Context Bridge (Crucial for Non-Admin Apps like Flow Launcher) ---
function Run-AsUser {
    param([string]$ScriptContent, [string]$TaskName = "QuickstartUserTask")
    
    $SanitizedTaskName = $TaskName -replace '[.\-]', '_'
    $TriggerScript = Join-Path $env:TEMP "$SanitizedTaskName.ps1"
    $ScriptContent | Out-File -FilePath $TriggerScript -Encoding utf8

    $UserAccount = (Get-CimInstance Win32_ComputerSystem).UserName
    $Action = New-ScheduledTaskAction -Execute 'Powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$TriggerScript`""
    $Principal = New-ScheduledTaskPrincipal -UserId $UserAccount -LogonType Interactive
    
    Register-ScheduledTask -TaskName $SanitizedTaskName -Action $Action -Principal $Principal -Force | Out-Null
    Start-ScheduledTask -TaskName $SanitizedTaskName
    
    while ((Get-ScheduledTask -TaskName $SanitizedTaskName).State -eq "Running") { Start-Sleep -Seconds 2 }
    
    Unregister-ScheduledTask -TaskName $SanitizedTaskName -Confirm:$false
    if (Test-Path $TriggerScript) { Remove-Item $TriggerScript -Force }
}

# --- Installation Core ---
function Install-WingetPackage {
    param([string]$Id, [bool]$SystemWide = $true)
    
    $existing = winget list --exact --id $Id --accept-source-agreements 2>$null
    if ($LASTEXITCODE -eq 0 -and $existing -match [regex]::Escape($Id)) {
        Write-Step "Already installed: $Id"
        return
    }

    if ($SystemWide) {
        Write-Step "Installing System-Wide: $Id..."
        winget install --exact --id $Id --silent --accept-package-agreements --accept-source-agreements --scope machine
    } else {
        Write-Step "Installing for User (Non-Admin): $Id..."
        $UserWingetScript = "winget install --exact --id $Id --silent --accept-package-agreements --accept-source-agreements --scope user"
        Run-AsUser -ScriptContent $UserWingetScript -TaskName "Install_$Id"
    }
}

# --- Personalization & Taskbar ---
function Apply-AllSettings {
    param([string]$RepoRoot)
    Write-Step "Applying Theme & Keyboard Settings..."
    $UserRegScript = @"
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -Value 0 -Force
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "SystemUsesLightTheme" -Value 0 -Force
    if (-not (Test-Path "HKCU:\Software\Microsoft\TabletTip\1.7")) { New-Item -Path "HKCU:\Software\Microsoft\TabletTip\1.7" -Force }
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\TabletTip\1.7" -Name "UserKeyboardScalingFactor" -Value 180 -Force
"@
    Run-AsUser -ScriptContent $UserRegScript -TaskName "ApplyUserRegistry"

    $sourceDir = Join-Path $RepoRoot "wallpapers"
    if (Test-Path $sourceDir) {
        $targetDir = Join-Path $OriginalUserPath "Pictures\quickstart-wallpapers"
        if (-not (Test-Path $targetDir)) { New-Item -Path $targetDir -ItemType Directory -Force | Out-Null }
        Get-ChildItem -Path $sourceDir -File | ForEach-Object { Copy-Item -Path $_.FullName -Destination (Join-Path $targetDir $_.Name) -Force }
    }
}

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
        $Apps += Join-Path $OriginalUserPath "AppData\Local\Programs\Microsoft VS Code\Code.exe"
        $Apps += Join-Path $OriginalUserPath "AppData\Local\Programs\Joplin\Joplin.exe"
        $Apps += "C:\Program Files\WezTerm\wezterm.exe"
        $Apps += "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
    }

    $PinScript = @"
    function Set-Pin {
        param(`$Path)
        if (-not (Test-Path `$Path)) { return }
        `$shell = New-Object -ComObject Shell.Application
        `$folder = `$shell.NameSpace((Split-Path `$Path))
        `$item = `$folder.ParseName((Split-Path `$Path -Leaf))
        `$verb = `$item.Verbs() | Where-Object { `$_.Id -eq 'taskbarpin' -or `$_.Name -replace '&','' -match '(Pin to taskbar)' }
        if (`$verb) { `$verb.DoIt() }
    }
    @($( ($Apps | ForEach-Object { "'$_'" }) -join "," )) | ForEach-Object { Set-Pin -Path `$_ }
"@
    Run-AsUser -ScriptContent $PinScript -TaskName "PinTaskbarIcons"
}

# --- Configs & Dotfiles ---
function Register-DevConfigs {
    param([string]$RepoRoot)
    Write-Step "Syncing Dotfiles..."
    $TargetAppData = Join-Path $OriginalUserPath "AppData\Roaming"

    # WezTerm
    $wezSource = Join-Path $RepoRoot "dotfiles\wezterm\.wezterm.lua"
    if (Test-Path $wezSource) { Copy-Item -Path $wezSource -Destination (Join-Path $OriginalUserPath ".wezterm.lua") -Force }

    # Flow Launcher
    $flowSource = Join-Path $RepoRoot "dotfiles\flowlauncher\Settings.json"
    $flowDestDir = Join-Path $TargetAppData "FlowLauncher\Settings"
    if (Test-Path $flowSource) {
        if (-not (Test-Path $flowDestDir)) { New-Item -Path $flowDestDir -ItemType Directory -Force | Out-Null }
        Copy-Item -Path $flowSource -Destination (Join-Path $flowDestDir "Settings.json") -Force
        
        $UserAccount = (Get-CimInstance Win32_ComputerSystem).UserName
        $Acl = Get-Acl $flowDestDir
        $Ar = New-Object System.Security.AccessControl.FileSystemAccessRule($UserAccount, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
        $Acl.SetAccessRule($Ar)
        Set-Acl $flowDestDir $Acl
    }

    # AutoHotkey
    $ahkSource = Join-Path $RepoRoot "dotfiles\main.ahk"
    if (Test-Path $ahkSource) {
        $startupDir = Join-Path $TargetAppData "Microsoft\Windows\Start Menu\Programs\Startup"
        Copy-Item -Path $ahkSource -Destination (Join-Path $startupDir "main.ahk") -Force
    }
}

# --- Execution ---
function Invoke-WindowsInit {
    Ensure-Admin
    
    # 1. Base Git & Path Prep
    Install-WingetPackage -Id "Git.Git" -SystemWide $true
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
    
    if ([string]::IsNullOrEmpty($RepoCloneDir)) { $RepoCloneDir = Join-Path $OriginalUserPath "Documents\quickstart" }
    if (-not (Test-Path $RepoCloneDir)) { git clone --depth 1 $RepoUrl $RepoCloneDir }
    $repoRoot = (Resolve-Path $RepoCloneDir).Path

    # 2. App Lists
    $SystemApps = @(
        "Mozilla.Firefox", "Google.Chrome", "Brave.Brave", "7zip.7zip", 
        "VideoLAN.VLC", "GIMP.GIMP.3", "PDFgear.PDFgear", "Tailscale.Tailscale", 
        "Nextcloud.NextcloudDesktop", "Jellyfin.JellyfinMediaPlayer", 
        "TheDocumentFoundation.LibreOffice", "SyncTrayzor.SyncTrayzor", 
        "LAB02Research.HASSAgent", "Proton.ProtonVPN", "Oracle.VirtualBox"
    )
    
    $UserApps = @(
        "Flow-Launcher.Flow-Launcher", 
        "Joplin.Joplin", 
        "Microsoft.VisualStudioCode", 
        "wez.wezterm", 
        "Alacritty.Alacritty",
        "AutoHotkey.AutoHotkey"
    )

    if (-not $InstallProfile) {
        Write-Host "`nSelect Profile:`n1) SettingsOnly`n2) BaseOnly`n3) Dev (Full)" -ForegroundColor Yellow
        $choice = Read-Host "Choice"
        $InstallProfile = switch($choice) { "1"{"SettingsOnly"}; "2"{"BaseOnly"}; "3"{"Dev"}; Default{"SettingsOnly"} }
    }

    # 3. Process Profile
    switch ($InstallProfile) {
        "Dev" {
            Apply-AllSettings -RepoRoot $repoRoot
            foreach ($app in $SystemApps) { Install-WingetPackage -Id $app -SystemWide $true }
            foreach ($app in $UserApps) { Install-WingetPackage -Id $app -SystemWide $false }
            Configure-TaskbarLinks -Profile "Dev"
            Register-DevConfigs -RepoRoot $repoRoot
            wsl --install --no-distribution 2>$null
        }
        "BaseOnly" {
            Apply-AllSettings -RepoRoot $repoRoot
            foreach ($app in $SystemApps) { Install-WingetPackage -Id $app -SystemWide $true }
            Configure-TaskbarLinks -Profile "BaseOnly"
        }
        "SettingsOnly" {
            Apply-AllSettings -RepoRoot $repoRoot
        }
    }

    Write-Step "Finished. Restarting Explorer..."
    Stop-Process -Name explorer -Force
}

try { Invoke-WindowsInit } catch { Write-Failure "Error: $($_.Exception.Message)" } finally { if (-not $NoExitPrompt) { Read-Host "`nPress Enter to exit" } }