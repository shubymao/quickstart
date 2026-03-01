param(
    [string]$WslDistro = "Ubuntu",
    [string]$RepoCloneDir = "",
    [ValidateSet("SettingsOnly", "BaseOnly", "Dev")]
    [string]$InstallProfile,
    [switch]$NoExitPrompt,
    [switch]$SkipUserInstall,
    [string]$OriginalUserPath = $HOME
)

$RepoUrl = "https://github.com/shubymao/quickstart"
$ScriptUrl = "$RepoUrl/raw/main/scripts/win-init.ps1"
$tempScript = Join-Path $env:TEMP "win-init-$(Get-Random).ps1"

Write-Host "[quickstart] Downloading win-init.ps1..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $ScriptUrl -OutFile $tempScript -UseBasicParsing

Write-Host "[quickstart] Running win-init.ps1..." -ForegroundColor Cyan
& $tempScript -WslDistro $WslDistro -RepoCloneDir $RepoCloneDir -InstallProfile $InstallProfile -NoExitPrompt:$NoExitPrompt -SkipUserInstall:$SkipUserInstall -OriginalUserPath $OriginalUserPath

Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
