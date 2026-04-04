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


; --- 5. HYPER KEY SHORTCUTS (^!+# = Ctrl+Shift+Alt+Win) ---

; Window Snapping (HJKL - Vim Style) - Pass to Raycast
^!+#h:: Send("!h")
^!+#l:: Send("!l")
^!+#j:: Send("!j")
^!+#k:: Send("!k")
^!+#;:: Send("!;")
^!+#m:: Send("!m")

; Focus mode
^!+#o:: Send("!o")

; Cycle Windows of same Type
^!+#n:: {
    hWnd := WinActive("A")
    if !hWnd
        return
    winClass := WinGetClass("ahk_id " hWnd)
    winList := WinGetList("ahk_class " winClass)
    if (winList.Length > 1)
        WinActivate("ahk_id " winList[winList.Length])
}

; App Launching / Focusing - Both Hyper and Alt perform same action
^!+#Space:: Send("!{Space}")

^!+#q:: Send("!{F4}")
!q:: Send("!{F4}")

^!+#w::{
    ahkPath := A_AppData . "\Microsoft\Windows\Start Menu\Programs\Startup\main.ahk"
    codePath := GetVSCodePath()
    Run(codePath . ' "' . ahkPath . '"')
}
!w::{
    ahkPath := A_AppData . "\Microsoft\Windows\Start Menu\Programs\Startup\main.ahk"
    codePath := GetVSCodePath()
    Run(codePath . ' "' . ahkPath . '"')
}

^!+#e:: Run("explorer.exe")
!e:: Run("explorer.exe")

^!+#r:: Reload()
!r:: Reload()

^!+#a:: runFocusOrStart("C:\Program Files\Mozilla Firefox\firefox.exe", "firefox.exe")
!a:: runFocusOrStart("C:\Program Files\Mozilla Firefox\firefox.exe", "firefox.exe")

^!+#s::{
    codePath := GetVSCodePath()
    runFocusOrStart(codePath, "Code.exe")
}
!s::{
    codePath := GetVSCodePath()
    runFocusOrStart(codePath, "Code.exe")
}

^!+#d:: Send("#{d}")
!d:: Send("#{d}")

^!+#f:: runFocusOrStart("C:\Program Files\WezTerm\wezterm-gui.exe", "wezterm-gui.exe")
!f:: runFocusOrStart("C:\Program Files\WezTerm\wezterm-gui.exe", "wezterm-gui.exe")

^!+#g:: Run("C:\Users\Home\AppData\Local\Programs\todoist\Todoist.exe")
!g:: Run("C:\Users\Home\AppData\Local\Programs\todoist\Todoist.exe")

^!+#c:: Send("!{Space}cbp{Space}")
!c:: Send("!{Space}cbp{Space}")

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


; --- 6. HELPER FUNCTIONS ---

runFocusOrStart(path, exe) {
    if ProcessExist(exe)
        WinActivate("ahk_exe " . exe)
    else
        Run(path)
}
