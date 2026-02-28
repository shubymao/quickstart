param(
    [string]$WslDistro = "Ubuntu",
    # Clones directly to the User's Documents folder
    [string]$RepoCloneDir = (Join-Path ([Environment]::GetFolderPath("MyDocuments")) "quickstart"),
    [ValidateSet("SettingsOnly", "BaseOnly", "DevOnly", "Dev")]
    [string]$InstallProfile,
    [switch]$NoExitPrompt,
    [string]$OriginalUserPath = $HOME
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoUrl = "https://github.com/shubymao/quickstart"

# --- UI & Logging ---
function Write-Step { param([string]$Message) Write-Host "[quickstart] $Message" -ForegroundColor Cyan }
function Write-Failure { param([string]$Message) Write-Host "[quickstart] $Message" -ForegroundColor Red }

# --- Admin Elevation ---
function Ensure-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { return }

    Write-Step "Requesting administrator privileges..."
    $arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath)
    if ($PSBoundParameters.ContainsKey("InstallProfile")) { $arguments += @("-InstallProfile", $InstallProfile) }
    $arguments += @("-OriginalUserPath", $HOME)
    $arguments += @("-RepoCloneDir", $RepoCloneDir)

    try {
        Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -Verb RunAs | Out-Null
    } catch {
        throw "Administrator privileges required."
    }
    exit 0
}

# --- User Context Bridge (Crucial for User Installs/Registry) ---
function Run-AsUser {
    param([string]$ScriptContent, [string]$TaskName = "QuickstartUserTask")
    $TriggerScript = Join-Path $env:TEMP "$TaskName.ps1"
    $ScriptContent | Out-File -FilePath $TriggerScript -Encoding utf8

    $UserAccount = (Get-CimInstance Win32_ComputerSystem).UserName
    $Action = New-ScheduledTaskAction -Execute 'Powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$TriggerScript`""
    $Principal = New-ScheduledTaskPrincipal -UserId $UserAccount -LogonType Interactive
    
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Principal $Principal -Force | Out-Null
    Start-ScheduledTask -TaskName $TaskName
    
    # Wait for completion (especially for Winget)
    while ((Get-ScheduledTask -TaskName $TaskName).State -eq "Running") { Start-Sleep -Seconds 2 }
    
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
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
        Write-Step "Installing for User ($OriginalUserPath): $Id..."
        $UserWingetScript = "winget install --exact --id $Id --silent --accept-package-agreements --accept-source-agreements --scope user"
        Run-AsUser -ScriptContent $UserWingetScript -TaskName "Install-$($Id -replace '\.', '_')"
    }
}

# --- Personalization ---
function Apply-AllSettings {
    param([string]$RepoRoot)
    Write-Step "Applying Theme & Keyboard Settings to User Context..."

    $UserRegScript = @"
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -Value 0 -Force
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "SystemUsesLightTheme" -Value 0 -Force
    if (-not (Test-Path "HKCU:\Software\Microsoft\TabletTip\1.7")) { New-Item -Path "HKCU:\Software\Microsoft\TabletTip\1.7" -Force }
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\TabletTip\1.7" -Name "UserKeyboardScalingFactor" -Value 180 -Force
"@
    Run-AsUser -ScriptContent $UserRegScript -TaskName "ApplyUserRegistry"

    # Wallpapers
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

# --- Configs & Dotfiles (No Links/Shortcuts) ---
function Register-DevConfigs {
    param([string]$RepoRoot)
    Write-Step "Copying Configuration Files to User folders..."
    $TargetAppData = Join-Path $OriginalUserPath "AppData\Roaming"

    # 1. WezTerm
    $wezSource = Join-Path $RepoRoot "dotfiles\wezterm\.wezterm.lua"
    if (Test-Path $wezSource) { 
        Copy-Item -Path $wezSource -Destination (Join-Path $OriginalUserPath ".wezterm.lua") -Force 
    }

    # 2. Flow Launcher (Direct Copy + Permission Fix)
    $flowSource = Join-Path $RepoRoot "dotfiles\flowlauncher\Settings.json"
    $flowDestDir = Join-Path $TargetAppData "FlowLauncher\Settings"
    if (Test-Path $flowSource) {
        if (-not (Test-Path $flowDestDir)) { New-Item -Path $flowDestDir -ItemType Directory -Force | Out-Null }
        Copy-Item -Path $flowSource -Destination (Join-Path $flowDestDir "Settings.json") -Force
        
        $Acl = Get-Acl $flowDestDir
        $Ar = New-Object System.Security.AccessControl.FileSystemAccessRule((Get-CimInstance Win32_ComputerSystem).UserName, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
        $Acl.SetAccessRule($Ar)
        Set-Acl $flowDestDir $Acl
    }

    # 3. AutoHotkey (Direct File copy to Startup, not a link)
    $ahkSource = Join-Path $RepoRoot "dotfiles\main.ahk"
    if (Test-Path $ahkSource) {
        $startupDir = Join-Path $TargetAppData "Microsoft\Windows\Start Menu\Programs\Startup"
        # We copy the actual .ahk file into the startup folder so it runs on boot
        Copy-Item -Path $ahkSource -Destination (Join-Path $startupDir "main.ahk") -Force
    }
}

# --- Execution ---
function Invoke-WindowsInit {
    Ensure-Admin
    winget source update
    Install-WingetPackage -Id "Git.Git" -SystemWide $true
    
    # Ensure Git is in Path for cloning
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")

    if (-not (Test-Path $RepoCloneDir)) {
        Write-Step "Cloning repository to Documents..."
        git clone --depth 1 $RepoUrl $RepoCloneDir
    }
    $repoRoot = (Resolve-Path $RepoCloneDir).Path

    $SystemApps = @("Mozilla.Firefox", "Google.Chrome", "Brave.Brave", "7zip.7zip", "VideoLAN.VLC", "Tailscale.Tailscale")
    $UserApps = @("Flow-Launcher.Flow-Launcher", "Joplin.Joplin", "Microsoft.VisualStudioCode", "wez.wezterm", "AutoHotkey.AutoHotkey")

    if (-not $InstallProfile) {
        Write-Host "`nSelect Profile (User: $OriginalUserPath):`n1) SettingsOnly`n2) BaseOnly`n3) Dev" -ForegroundColor Yellow
        $choice = Read-Host "Choice"
        $InstallProfile = switch($choice) { "1"{"SettingsOnly"}; "2"{"BaseOnly"}; "3"{"Dev"}; Default{"SettingsOnly"} }
    }

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
    }

    Write-Step "Finished. Restarting Explorer..."
    Stop-Process -Name explorer -Force
}

try { Invoke-WindowsInit } 
catch { Write-Failure "Error: $($_.Exception.Message)" } 
finally { if (-not $NoExitPrompt) { Read-Host "`nPress Enter to exit" } }param(
    [string]$WslDistro = "Ubuntu",
    # Clones directly to the User's Documents folder
    [string]$RepoCloneDir = (Join-Path ([Environment]::GetFolderPath("MyDocuments")) "quickstart"),
    [ValidateSet("SettingsOnly", "BaseOnly", "DevOnly", "Dev")]
    [string]$InstallProfile,
    [switch]$NoExitPrompt,
    [string]$OriginalUserPath = $HOME
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoUrl = "https://github.com/shubymao/quickstart"

# --- UI & Logging ---
function Write-Step { param([string]$Message) Write-Host "[quickstart] $Message" -ForegroundColor Cyan }
function Write-Failure { param([string]$Message) Write-Host "[quickstart] $Message" -ForegroundColor Red }

# --- Admin Elevation ---
function Ensure-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { return }

    Write-Step "Requesting administrator privileges..."
    $arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath)
    if ($PSBoundParameters.ContainsKey("InstallProfile")) { $arguments += @("-InstallProfile", $InstallProfile) }
    $arguments += @("-OriginalUserPath", $HOME)
    $arguments += @("-RepoCloneDir", $RepoCloneDir)

    try {
        Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -Verb RunAs | Out-Null
    } catch {
        throw "Administrator privileges required."
    }
    exit 0
}

# --- User Context Bridge (Crucial for User Installs/Registry) ---
function Run-AsUser {
    param([string]$ScriptContent, [string]$TaskName = "QuickstartUserTask")
    $TriggerScript = Join-Path $env:TEMP "$TaskName.ps1"
    $ScriptContent | Out-File -FilePath $TriggerScript -Encoding utf8

    $UserAccount = (Get-CimInstance Win32_ComputerSystem).UserName
    $Action = New-ScheduledTaskAction -Execute 'Powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$TriggerScript`""
    $Principal = New-ScheduledTaskPrincipal -UserId $UserAccount -LogonType Interactive
    
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Principal $Principal -Force | Out-Null
    Start-ScheduledTask -TaskName $TaskName
    
    # Wait for completion (especially for Winget)
    while ((Get-ScheduledTask -TaskName $TaskName).State -eq "Running") { Start-Sleep -Seconds 2 }
    
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
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
        Write-Step "Installing for User ($OriginalUserPath): $Id..."
        $UserWingetScript = "winget install --exact --id $Id --silent --accept-package-agreements --accept-source-agreements --scope user"
        Run-AsUser -ScriptContent $UserWingetScript -TaskName "Install-$($Id -replace '\.', '_')"
    }
}

# --- Personalization ---
function Apply-AllSettings {
    param([string]$RepoRoot)
    Write-Step "Applying Theme & Keyboard Settings to User Context..."

    $UserRegScript = @"
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -Value 0 -Force
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "SystemUsesLightTheme" -Value 0 -Force
    if (-not (Test-Path "HKCU:\Software\Microsoft\TabletTip\1.7")) { New-Item -Path "HKCU:\Software\Microsoft\TabletTip\1.7" -Force }
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\TabletTip\1.7" -Name "UserKeyboardScalingFactor" -Value 180 -Force
"@
    Run-AsUser -ScriptContent $UserRegScript -TaskName "ApplyUserRegistry"

    # Wallpapers
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

# --- Configs & Dotfiles (No Links/Shortcuts) ---
function Register-DevConfigs {
    param([string]$RepoRoot)
    Write-Step "Copying Configuration Files to User folders..."
    $TargetAppData = Join-Path $OriginalUserPath "AppData\Roaming"

    # 1. WezTerm
    $wezSource = Join-Path $RepoRoot "dotfiles\wezterm\.wezterm.lua"
    if (Test-Path $wezSource) { 
        Copy-Item -Path $wezSource -Destination (Join-Path $OriginalUserPath ".wezterm.lua") -Force 
    }

    # 2. Flow Launcher (Direct Copy + Permission Fix)
    $flowSource = Join-Path $RepoRoot "dotfiles\flowlauncher\Settings.json"
    $flowDestDir = Join-Path $TargetAppData "FlowLauncher\Settings"
    if (Test-Path $flowSource) {
        if (-not (Test-Path $flowDestDir)) { New-Item -Path $flowDestDir -ItemType Directory -Force | Out-Null }
        Copy-Item -Path $flowSource -Destination (Join-Path $flowDestDir "Settings.json") -Force
        
        $Acl = Get-Acl $flowDestDir
        $Ar = New-Object System.Security.AccessControl.FileSystemAccessRule((Get-CimInstance Win32_ComputerSystem).UserName, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
        $Acl.SetAccessRule($Ar)
        Set-Acl $flowDestDir $Acl
    }

    # 3. AutoHotkey (Direct File copy to Startup, not a link)
    $ahkSource = Join-Path $RepoRoot "dotfiles\main.ahk"
    if (Test-Path $ahkSource) {
        $startupDir = Join-Path $TargetAppData "Microsoft\Windows\Start Menu\Programs\Startup"
        # We copy the actual .ahk file into the startup folder so it runs on boot
        Copy-Item -Path $ahkSource -Destination (Join-Path $startupDir "main.ahk") -Force
    }
}

# --- Execution ---
function Invoke-WindowsInit {
    Ensure-Admin
    winget source update
    Install-WingetPackage -Id "Git.Git" -SystemWide $true
    
    # Ensure Git is in Path for cloning
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")

    if (-not (Test-Path $RepoCloneDir)) {
        Write-Step "Cloning repository to Documents..."
        git clone --depth 1 $RepoUrl $RepoCloneDir
    }
    $repoRoot = (Resolve-Path $RepoCloneDir).Path

    $SystemApps = @("Mozilla.Firefox", "Google.Chrome", "Brave.Brave", "7zip.7zip", "VideoLAN.VLC", "Tailscale.Tailscale")
    $UserApps = @("Flow-Launcher.Flow-Launcher", "Joplin.Joplin", "Microsoft.VisualStudioCode", "wez.wezterm", "AutoHotkey.AutoHotkey")

    if (-not $InstallProfile) {
        Write-Host "`nSelect Profile (User: $OriginalUserPath):`n1) SettingsOnly`n2) BaseOnly`n3) Dev" -ForegroundColor Yellow
        $choice = Read-Host "Choice"
        $InstallProfile = switch($choice) { "1"{"SettingsOnly"}; "2"{"BaseOnly"}; "3"{"Dev"}; Default{"SettingsOnly"} }
    }

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
    }

    Write-Step "Finished. Restarting Explorer..."
    Stop-Process -Name explorer -Force
}

try { Invoke-WindowsInit } 
catch { Write-Failure "Error: $($_.Exception.Message)" } 
finally { if (-not $NoExitPrompt) { Read-Host "`nPress Enter to exit" } }