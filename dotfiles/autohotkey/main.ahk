; AutoHotkey v2 script
#Requires AutoHotkey v2.0
#SingleInstance Force

; --- 1. WSL WARM-UP ---
Run("wsl.exe --exec true", , "Hide")

; --- 2. GLOBAL SETTINGS ---
SetWorkingDir(A_InitialWorkingDir)

; --- 3. VIRTUAL DESKTOP ACCESSOR ---
; Updated to check both Documents and Repo location
dllPath := A_MyDocuments . "\AutoHotkey\Lib\VirtualDesktopAccessor.dll"

try {
    vda := DllCall("LoadLibrary", "Str", dllPath, "Ptr")
} catch {
    vda := 0
}

GoToDesktopNumber(num) {
    if vda
        DllCall("VirtualDesktopAccessor\GoToDesktopNumber", "Int", num - 1, "Int")
}

; --- 4. DYNAMIC VS CODE PATH FINDER ---
; This looks in User Local, User Roaming, and System Program Files
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
    return "Code.exe" ; Fallback to PATH
}

; --- 5. COPILOT / OFFICE KEY KILLER ---
; The Copilot key fires Shift+Ctrl+Alt+Win+F23 (or similar). 
; This block catches the "Office" protocol to prevent it from opening the app.
#<^<+<!vk07:: {
    return ; Do nothing, effectively freeing the key for your Hyper shortcuts
}

; --- 6. HYPER KEY SHORTCUTS (^!+# = Ctrl+Shift+Alt+Win) ---

; Desktop Navigation
^!+#1:: GoToDesktopNumber(1)
^!+#2:: GoToDesktopNumber(2)
^!+#3:: GoToDesktopNumber(3)
^!+#4:: GoToDesktopNumber(4)
^!+#5:: GoToDesktopNumber(5)
^!+#6:: GoToDesktopNumber(6)
^!+#7:: GoToDesktopNumber(7)
^!+#8:: GoToDesktopNumber(8)
^!+#9:: GoToDesktopNumber(9)
^!+#0:: GoToDesktopNumber(10)

; Window Snapping (HJKL - Vim Style)
^!+#h:: SnapWindow("Left")
^!+#l:: SnapWindow("Right")
^!+#j:: SnapWindow("Down")
^!+#k:: SnapWindow("Up")
^!+#;:: MoveWindowToNextMonitor()
^!+#m:: {
    if WinGetMinMax("A") = 1
        WinRestore("A")
    else
        WinMaximize("A")
}

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

; App Launching / Focusing


; Shortcuts

^!+#Space:: Send("!{Space}") ; flow launcher

^!+#q:: Send("!{F4}")    ; Alt + F4
; edit this Script in VS Code
^!+#w:: {
    ahkPath := A_AppData . "\Microsoft\Windows\Start Menu\Programs\Startup\main.ahk"
    codePath := GetVSCodePath()
    Run(codePath . ' "' . ahkPath . '"')
}
^!+#e:: Run("explorer.exe")
^!+#r:: Reload()         ; Reload Script




^!+#a:: runFocusOrStart("C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe", "brave.exe")
^!+#s:: {
    codePath := GetVSCodePath()
    runFocusOrStart(codePath, "Code.exe")
}
^!+#d:: Send("#{d}")     ; Win + D
^!+#f:: runFocusOrStart("C:\Program Files\WezTerm\wezterm-gui.exe", "wezterm-gui.exe")
^!+#g:: Run("C:\Users\Home\AppData\Local\Programs\todoist\Todoist.exe")

^!+#c:: Send("!{Space}cbp{Space}")

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

; --- 7. HELPER FUNCTIONS ---

runFocusOrStart(path, exe) {
    if ProcessExist(exe)
        WinActivate("ahk_exe " . exe)
    else
        Run(path)
}

SnapWindow(direction) {
    activeHwnd := WinActive("A")
    if !activeHwnd
        return
    hMonitor := DllCall("User32.dll\MonitorFromWindow", "Ptr", activeHwnd, "UInt", 2, "Ptr")
    NumPut("UInt", 40, buf := Buffer(40))
    if !DllCall("User32.dll\GetMonitorInfoW", "Ptr", hMonitor, "Ptr", buf)
        return
    left := NumGet(buf, 20, "Int"), top := NumGet(buf, 24, "Int")
    right := NumGet(buf, 28, "Int"), bottom := NumGet(buf, 32, "Int")
    width := right - left, height := bottom - top
    if WinGetMinMax("ahk_id " activeHwnd) != 0
        WinRestore("ahk_id " activeHwnd)
    switch direction {
        case "Left":  WinMove(left, top, width // 2, height, "ahk_id " activeHwnd)
        case "Right": WinMove(left + width // 2, top, width // 2, height, "ahk_id " activeHwnd)
        case "Up":    WinMove(left, top, width, height // 2, "ahk_id " activeHwnd)
        case "Down":  WinMove(left, top + height // 2, width, height // 2, "ahk_id " activeHwnd)
    }
}

MoveWindowToNextMonitor() {
    activeHwnd := WinActive("A")
    if !activeHwnd
        return
    wasMaximized := WinGetMinMax("ahk_id " activeHwnd)
    hMonitor := DllCall("User32.dll\MonitorFromWindow", "Ptr", activeHwnd, "UInt", 2, "Ptr")
    monitorCount := MonitorGetCount()
    currentMonitor := 1
    loop monitorCount {
        NumPut("UInt", 40, buf := Buffer(40))
        if DllCall("User32.dll\GetMonitorInfoW", "Ptr", hMonitor, "Ptr", buf) {
            MonitorGet(A_Index, &L, &T, &R, &B)
            if (L == NumGet(buf, 4, "Int") && T == NumGet(buf, 8, "Int")) {
                currentMonitor := A_Index
                break
            }
        }
    }
    nextMonitor := (currentMonitor == monitorCount) ? 1 : currentMonitor + 1
    MonitorGetWorkArea(nextMonitor, &nLeft, &nTop)
    if (wasMaximized == 1)
        WinRestore("ahk_id " activeHwnd)
    WinMove(nLeft, nTop, , , "ahk_id " activeHwnd)
    if (wasMaximized == 1)
        WinMaximize("ahk_id " activeHwnd)
}
