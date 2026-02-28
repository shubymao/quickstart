# === CONFIGURATION ===
$DEVCON = "C:\Program Files (x86)\Windows Kits\10\Tools\10.0.26100.0\x64\devcon.exe"
$DEVICE1 = "HID\VEN_ELAN&DEV_2514&Col01"
$DEVICE2 = "PCI\VEN_8086&DEV_A845&SUBSYS_8DA1103C&REV_10"

# === CHECK DEVICE STATUS ===
$DEVICE_STATE = ""

# Get the status of DEVICE1
$status1 = & "$DEVCON" status "$DEVICE1" 2>$null
if ($status1 -match "running") {
    $DEVICE_STATE = "enabled"
}

# Get the status of DEVICE2
$status2 = & "$DEVCON" status "$DEVICE2" 2>$null
if ($status2 -match "running") {
    $DEVICE_STATE = "enabled"
}

# === TOGGLE DEVICES ===
if ($DEVICE_STATE -eq "enabled") {
    Write-Host "Devices are currently ENABLED. Disabling..."
    & "$DEVCON" disable "$DEVICE1"
    & "$DEVCON" disable "$DEVICE2"
} else {
    Write-Host "Devices are currently DISABLED or not found. Enabling..."
    & "$DEVCON" enable "$DEVICE1"
    & "$DEVCON" enable "$DEVICE2"
}

# Pause to view results
# Read-Host -Prompt "Press Enter to continue"
