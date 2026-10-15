#Requires AutoHotkey v2.0

; HorizontalScroll — Shift + wheel scrolls sideways, system-wide.
;
; This file is the plumbing: the registry, the hotkeys, the tray menu and the
; wheel events. Every decision it makes — what the command line asked for, what
; the config file says, which wheel key to send, whether this window is excluded
; — lives in lib/core.ahk, which has no side effects and is what tests/run.ahk
; exercises.

; Single-instance is enforced by hand in EnsureSingleInstance() rather than by
; the directive. #SingleInstance Force applies at load time, before the command
; line is read, so `HorizontalScroll.exe --install` would kill the instance
; already scrolling and then exit, leaving nothing running.
#SingleInstance Off

#Include lib\core.ahk

; The startup entry. The test harness rewrites this literal to point at a
; scratch key, so it must stay on one line and stay spelled this way.
STARTUP_KEY := "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"
STARTUP_VALUE := "HorizontalScroll"

Main()


Main() {
    parsed := ParseArgs(A_Args)

    if (!parsed.ok) {
        Report(parsed.message "`n`n" HelpText(), true)
        ExitApp 2
    }

    switch parsed.action {
        case "help":
            Report(HelpText())
            ExitApp 0
        case "install":
            ExitApp Install()
        case "uninstall":
            ExitApp Uninstall()
        case "status":
            ExitApp Status()
    }

    EnsureSingleInstance()
    Persistent
    StartScrolling(LoadConfig())
    SetUpTray()
}


; ── Startup registration ──────────────────────────────────────────────────────

Install() {
    global STARTUP_KEY, STARTUP_VALUE

    try {
        command := StartupCommand(A_ScriptFullPath, A_IsCompiled, A_AhkPath)
        RegWrite command, "REG_SZ", STARTUP_KEY, STARTUP_VALUE
    } catch as err {
        Report("Could not write the startup entry: " err.Message, true)
        return 1
    }

    Report("Installed. HorizontalScroll will start at login:`n  " command)
    return 0
}

Uninstall() {
    global STARTUP_KEY, STARTUP_VALUE

    try {
        RegDelete STARTUP_KEY, STARTUP_VALUE
    } catch OSError {
        ; Nothing registered. Asking to uninstall something that is not
        ; installed is a no-op, not a failure.
        Report("No startup entry found. Nothing to remove.")
        return 0
    } catch as err {
        Report("Could not remove the startup entry: " err.Message, true)
        return 1
    }

    Report("Removed. HorizontalScroll will no longer start at login.")
    return 0
}

Status() {
    global STARTUP_KEY, STARTUP_VALUE

    try
        command := RegRead(STARTUP_KEY, STARTUP_VALUE)
    catch
        command := ""

    Report(command = ""
        ? "Not installed. Run --install to start at login."
        : "Installed, starting at login as:`n  " command)

    cfg := LoadConfig()
    Report("Multiplier=" cfg.multiplier
        . "  Reverse=" (cfg.reverse ? "true" : "false")
        . "  ExcludeProcesses=" (cfg.exclude.Length ? Join(cfg.exclude, ",") : "(none)"))
    return 0
}


; ── Configuration ─────────────────────────────────────────────────────────────

ConfigPath() {
    return A_ScriptDir "\HorizontalScroll.ini"
}

; Reads the optional INI beside the program. Absent or unreadable means
; defaults, which is exactly what the pre-config versions of this script did.
LoadConfig() {
    path := ConfigPath()
    if (!FileExist(path))
        return ParseConfig("")

    try
        text := FileRead(path, "UTF-8")
    catch as err {
        Report("Could not read " path ": " err.Message "`nUsing defaults.")
        return ParseConfig("")
    }

    cfg := ParseConfig(text)
    for warning in cfg.warnings
        Report(path ": " warning)
    return cfg
}

; The config as loaded at startup, held in a static so the wheel handlers can
; reach it without a global.
Config(replacement := unset) {
    static current := ""
    if (IsSet(replacement))
        current := replacement
    return current
}


; ── Scrolling ─────────────────────────────────────────────────────────────────

StartScrolling(cfg) {
    Config(cfg)

    ; Only install a context filter when there is something to exclude. With an
    ; empty list every wheel tick would pay for a window query that can never
    ; change the answer.
    if (cfg.exclude.Length)
        HotIf (*) => !ScrollTargetIsExcluded()

    Hotkey "+WheelUp", ScrollLeftwards, "On"
    Hotkey "+WheelDown", ScrollRightwards, "On"
    HotIf
}

ScrollLeftwards(*) {
    SendScroll("up")
}

ScrollRightwards(*) {
    SendScroll("down")
}

; AHK sends WheelLeft/WheelRight as real input events, which Windows delivers to
; the window under the cursor exactly like a touchpad horizontal swipe. That is
; why this works in Win32, Electron and browser apps alike without any per-app
; knowledge.
SendScroll(direction) {
    cfg := Config()
    key := ScrollTarget(direction, cfg.reverse)
    Loop cfg.multiplier
        Send "{" key "}"
}

ScrollTargetIsExcluded() {
    return IsExcluded(ProcessUnderCursor(), Config().exclude)
}

; The window under the cursor, not the active one: Windows delivers wheel events
; by cursor position, and "scroll inactive windows when I hover over them" is on
; by default, so the active window is frequently the wrong thing to ask about.
ProcessUnderCursor() {
    try {
        MouseGetPos , , &hwnd
        return WinGetProcessName("ahk_id " hwnd)
    }
    return ""
}


; ── Tray ──────────────────────────────────────────────────────────────────────

; AutoHotkey's default tray menu already carries an Exit item, but it sits below
; six entries about scripts and debugging that mean nothing to someone who
; downloaded a scrolling utility. A labelled item at the top makes quitting
; findable without having to end the process in Task Manager.
SetUpTray() {
    A_IconTip := "HorizontalScroll — Shift + wheel scrolls sideways"
    tray := A_TrayMenu
    tray.Insert("1&", "Exit HorizontalScroll", (*) => ExitApp(0))
    tray.Insert("2&")
}


; ── Plumbing ──────────────────────────────────────────────────────────────────

; A named mutex, rather than #SingleInstance, so that the choice happens after
; the command line has been read. See the note at the top of the file.
EnsureSingleInstance() {
    DllCall("CreateMutexW", "ptr", 0, "int", 1, "wstr", "Local\HorizontalScroll", "ptr")
    if (A_LastError = 183)  ; ERROR_ALREADY_EXISTS
        ExitApp 0
}

; Writes to stdout, which is where output belongs when the program was started
; from a console. Launched from Explorer there is no stdout at all, so anything
; the user must see — and only that — falls back to a message box.
Report(text, mustBeSeen := false) {
    try {
        FileAppend text "`n", "*"
        return
    }
    if (mustBeSeen)
        MsgBox text, "HorizontalScroll", "Iconi"
}

Join(list, separator) {
    out := ""
    for item in list
        out .= (out = "" ? "" : separator) item
    return out
}
