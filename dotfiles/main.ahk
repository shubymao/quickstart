; AutoHotkey v2 script
#Requires AutoHotkey v2.0
#SingleInstance Force

; --- 1. WSL WARM-UP ---
; This runs silently in the background when the script starts (at Windows login)
; to ensure your terminal opens instantly later.
Run("wsl.exe --exec true", , "Hide")

; --- 2. GLOBAL SETTINGS ---
SetWorkingDir(A_InitialWorkingDir)

; --- 3. VIRTUAL DESKTOP ACCESSOR ---
dllPath := "C:\Users\" . A_UserName . "\Documents\AutoHotkey\Lib\VirtualDesktopAccessor.dll"

try {
    vda := DllCall("LoadLibrary", "Str", dllPath, "Ptr")
    if !vda {
        throw Error("DLL not found at: " . dllPath)
    }
} catch as e {
    ToolTip("VirtualDesktopAccessor.dll failed to load.`n" . e.Message)
    SetTimer(() => ToolTip(), -5000)
    vda := 0
}

GoToDesktopNumber(num) {
    if !vda {
        return
    }
    DllCall("VirtualDesktopAccessor\GoToDesktopNumber", "Int", num - 1, "Int")
}

; --- 4. HYPER KEY SHORTCUTS (^!+# = Ctrl+Shift+Alt+Win) ---

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
    if WinGetMinMax("A") = 1 ; If already maximized
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
    
    if (winList.Length > 1) {
        ; Activate the bottom-most window of the stack to cycle
        WinActivate("ahk_id " winList[winList.Length])
    }
}

; App Launching / Focusing
^!+#e:: Run("explorer.exe")
^!+#f:: runFocusOrStart("C:\Program Files\WezTerm\wezterm-gui.exe", "wezterm-gui.exe")
^!+#a:: runFocusOrStart("C:\Program Files\Mozilla Firefox\firefox.exe", "firefox.exe")
^!+#s:: runFocusOrStart("C:\Users\" . A_UserName . "\AppData\Local\Programs\Microsoft VS Code\Code.exe", "Code.exe")

; Special Logic: Edit this Script in VS Code
^!+#w:: {
    ahkPath := "C:\Users\" . A_UserName . "\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\main.ahk"
    codePath := "C:\Users\" . A_UserName . "\AppData\Local\Programs\Microsoft VS Code\Code.exe"
    Run(codePath . ' "' . ahkPath . '"')
}


; Your exact path - Note the 'app-2.0.3' subfolder
; Map Hyper Key (Ctrl+Alt+Shift+Win) + Space
^!+#Space::
{
    localAppData := EnvGet("LocalAppData")
    targetPath := localAppData . "\FlowLauncher\app-2.0.3\Flow.Launcher.exe"
    
    if FileExist(targetPath) {
        Run('"' targetPath '" --toggle')
    } else {
        MsgBox("Path not found: " . targetPath)
    }
}
^!+#d::     Send("#{d}")     ; Win + D
^!+#q::     Send("!{F4}")    ; Alt + F4
^!+#r::     Reload()         ; Reload Script
^!+#`::     Run("C:\Users\" . A_UserName . "\Scripts\toggle_touch.cmd")


; --- 5. HELPER FUNCTIONS ---

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

    ; 1. Get the handle of the monitor the window is currently on
    ; MONITOR_DEFAULTTONEAREST = 2
    hMonitor := DllCall("User32.dll\MonitorFromWindow", "Ptr", activeHwnd, "UInt", 2, "Ptr")
    
    ; 2. Get monitor info via a buffer (shorthand for V2)
    NumPut("UInt", 40, buf := Buffer(40))
    if !DllCall("User32.dll\GetMonitorInfoW", "Ptr", hMonitor, "Ptr", buf)
        return

    ; Extract Work Area coordinates from the buffer
    left   := NumGet(buf, 20, "Int")
    top    := NumGet(buf, 24, "Int")
    right  := NumGet(buf, 28, "Int")
    bottom := NumGet(buf, 32, "Int")
    
    width  := right - left
    height := bottom - top

    ; 3. Handle Maximized state (Restore before moving)
    if WinGetMinMax("ahk_id " activeHwnd) != 0
        WinRestore("ahk_id " activeHwnd)

    ; 4. Perform the Snap based on the specific monitor's bounds
    switch direction {
        case "Left":  WinMove(left, top, width // 2, height, "ahk_id " activeHwnd)
        case "Right": WinMove(left + width // 2, top, width // 2, height, "ahk_id " activeHwnd)
        case "Up":    WinMove(left, top, width, height // 2, "ahk_id " activeHwnd)
        case "Down":  WinMove(left, top + height // 2, width, height // 2, "ahk_id " activeHwnd)
    }
}

; --- 5. HELPER FUNCTIONS (Add this) ---
MoveWindowToNextMonitor() {
    activeHwnd := WinActive("A")
    if !activeHwnd
        return

    ; 1. Store the state
    wasMaximized := WinGetMinMax("ahk_id " activeHwnd)

    ; 2. Get the Monitor Handle for the current window
    ; 2 = MONITOR_DEFAULTTONEAREST
    hMonitor := DllCall("User32.dll\MonitorFromWindow", "Ptr", activeHwnd, "UInt", 2, "Ptr")
    
    ; 3. Loop through monitors to find which index matches that handle
    monitorCount := MonitorGetCount()
    currentMonitor := 1
    loop monitorCount {
        ; Create a buffer for monitor info
        NumPut("UInt", 40, buf := Buffer(40))
        if DllCall("User32.dll\GetMonitorInfoW", "Ptr", hMonitor, "Ptr", buf) {
            ; Check if this monitor's coordinates match the current index
            MonitorGet(A_Index, &L, &T, &R, &B)
            ; Get monitor info from buffer to compare (simplified for this logic)
            if (L == NumGet(buf, 4, "Int") && T == NumGet(buf, 8, "Int")) {
                currentMonitor := A_Index
                break
            }
        }
    }

    ; 4. Calculate Next Monitor (The Swap)
    nextMonitor := (currentMonitor == monitorCount) ? 1 : currentMonitor + 1
    MonitorGetWorkArea(nextMonitor, &nLeft, &nTop)

    ; 5. The Logic: Restore -> Move -> Re-maximize
    if (wasMaximized == 1)
        WinRestore("ahk_id " activeHwnd)

    WinMove(nLeft, nTop, , , "ahk_id " activeHwnd)

    if (wasMaximized == 1)
        WinMaximize("ahk_id " activeHwnd)
}