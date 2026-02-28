 if not "%1" == "am_admin" (PowerShell start -verb runas '%0' am_admin & exit)
PowerShell.exe -ExecutionPolicy Bypass -File C:\Users\shubymao\Scripts\toggle_touch.ps1" 