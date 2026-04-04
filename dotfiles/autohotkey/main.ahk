; AutoHotkey v2 script
#Requires AutoHotkey v2.0
#SingleInstance Force

; --- 1. WSL WARM-UP ---
Run("wsl.exe --exec true", , "Hide")

; --- 2. GLOBAL SETTINGS ---
SetWorkingDir(A_InitialWorkingDir)

; --- 3. DYNAMIC VS CODE PATH FINDER ---
GetVSCodePath() {
    paths := [
        A_AppData . "\Local\Programs\Microsoft VS Code\Code.exe",
        A_AppData . "\Roaming\Microsoft\Windows\Start Menu\Programs\Microsoft VS Code\Code.exe",
        "C:\Program Files\Microsoft VS Code\Code.exe",
        "C:\Program Files (x86)\Microsoft VS Code\Code.exe"
    ]
    for path in paths {
        if FileExist(path)
            return path
    }
    return "Code.exe"
}

; --- 4. COPILOT / OFFICE KEY KILLER ---
#<^<+<!vk07:: {
    return
}

; --- 5. ALT TO HYPER REMAPPING ---
*LAlt::
{
    Send "{Ctrl down}{Shift down}{Alt down}{LWin down}"
}

*LAlt up::
{
    Send "{Ctrl up}{Shift up}{Alt up}{LWin up}"
}

; --- 5b. ALT SPECIFIC MAPPINGS ---

; --- 6. HYPER KEY SHORTCUTS (^!+# = Ctrl+Shift+Alt+Win) ---

^!+#w::{
    ahkPath := A_AppData . "\Microsoft\Windows\Start Menu\Programs\Startup\main.ahk"
    codePath := GetVSCodePath()
    Run(codePath . ' "' . ahkPath . '"')
}

^!+#r:: Reload()

; Disable stupid windows copilot re routing 
+!^LWin::
#^!Shift::
#^+Alt::
#!+Ctrl::
{
	Send "{Blind}{vkE8}"
	Return
}

; laptop with touch screen only (toggle touch screen on or off)
^!+#`:: Run("C:\Users\" . A_UserName . "\Scripts\toggle_touch.cmd")
