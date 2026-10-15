#Requires AutoHotkey v2.0

; core.ahk — every decision HorizontalScroll makes, with none of the plumbing.
;
; Nothing in this file touches the registry, registers a hotkey, sends input or
; reads a file. It takes strings and returns values, which is what makes it
; testable: tests/run.ahk includes this file directly and calls into it. The
; entry point, HorizontalScroll.ahk, supplies the real registry and real input.

; Multiplier bounds. One is "no amplification"; twenty already overshoots a page
; in most apps, and an unbounded value read from a config file would let a stray
; digit in an INI hang the machine inside Loop.
MULTIPLIER_MIN := 1
MULTIPLIER_MAX := 20
MULTIPLIER_DEFAULT := 3


; ── Command line ──────────────────────────────────────────────────────────────

; ParseArgs(args) -> {action, ok, message}
;
; action is one of run|install|uninstall|status|help. Anything unrecognised is
; an error rather than a silent ignore: the whole point of --install is that the
; user asked for it, so a typo must not fall through to a plain run.
ParseArgs(args) {
    out := { action: "", ok: true, message: "" }

    for arg in args {
        name := NormaliseSwitch(arg)
        if (name = "") {
            out.ok := false
            out.message := "Unrecognised argument: " arg
            return out
        }

        action := ""
        switch name {
            case "install":             action := "install"
            case "uninstall", "remove": action := "uninstall"
            case "status":              action := "status"
            case "help":                action := "help"
            default:
                out.ok := false
                out.message := "Unrecognised option: " arg
                return out
        }

        if (out.action != "" && out.action != action) {
            out.ok := false
            out.message := "Conflicting options: --" out.action " and --" action
            return out
        }
        out.action := action
    }

    if (out.action = "")
        out.action := "run"
    return out
}

; Strips a leading --, - or / and expands single-letter forms. Returns "" for a
; bare word, which the caller reports as an error.
NormaliseSwitch(arg) {
    if (SubStr(arg, 1, 2) = "--")
        return ExpandShort(StrLower(SubStr(arg, 3)))
    if (StrLen(arg) > 1 && (SubStr(arg, 1, 1) = "-" || SubStr(arg, 1, 1) = "/"))
        return ExpandShort(StrLower(SubStr(arg, 2)))
    return ""
}

ExpandShort(name) {
    switch name, true {
        case "i": return "install"
        case "u": return "uninstall"
        case "s": return "status"
        case "h", "?": return "help"
    }
    return name
}


; ── Startup entry ─────────────────────────────────────────────────────────────

; StartupCommand(target, isCompiled, interpreter) -> command line for the Run key
;
; Both forms are quoted. An unquoted path in the Run key breaks the moment the
; program lives somewhere with a space in the name — "C:\Program Files\x.exe"
; is read as the program "C:\Program" with the argument "Files\x.exe" — and the
; usual home for a downloaded .exe is a user folder that may well contain one.
;
; An uncompiled script cannot be its own Run entry either. The value has to name
; the AutoHotkey interpreter and pass the script to it, or startup depends on a
; .ahk file association that may not be registered.
StartupCommand(target, isCompiled, interpreter := "") {
    if (Trim(target) = "")
        throw ValueError("StartupCommand: target path is required")

    if (isCompiled)
        return Quote(target)

    if (Trim(interpreter) = "")
        throw ValueError("StartupCommand: an uncompiled script needs an interpreter path")

    return Quote(interpreter) " " Quote(target)
}

Quote(path) {
    return Chr(34) path Chr(34)
}


; ── Scroll direction ──────────────────────────────────────────────────────────

; ScrollTarget(direction, reverse) -> "WheelLeft" | "WheelRight"
ScrollTarget(direction, reverse) {
    dir := StrLower(Trim(direction))
    if (dir != "up" && dir != "down")
        throw ValueError("ScrollTarget: direction must be 'up' or 'down', got: " direction)

    goLeft := (dir = "up")
    if (reverse)
        goLeft := !goLeft
    return goLeft ? "WheelLeft" : "WheelRight"
}


; ── Exclusions ────────────────────────────────────────────────────────────────

; IsExcluded(process, list) -> true if this process should keep its own
; Shift+wheel handling.
;
; Chrome, Edge, Firefox and VS Code scroll horizontally on Shift+wheel without
; any help. For those, this tool is not adding a capability, it is replacing
; their scrolling with its own at a different speed. The list is empty by
; default, so shipped behaviour is unchanged; a user who dislikes the override
; can name the apps to leave alone.
;
; Entries match with or without the .exe suffix, and case is ignored, because
; "chrome" and "Chrome.exe" are both what a person would reasonably write.
IsExcluded(process, list) {
    name := Trim(process)
    if (name = "")
        return false

    for entry in list {
        want := Trim(entry)
        if (want = "")
            continue
        if (want = name || want ".exe" = name)
            return true
    }
    return false
}


; ── Configuration ─────────────────────────────────────────────────────────────

; ParseConfig(text) -> {multiplier, reverse, exclude, warnings}
;
; A deliberately forgiving INI reader: section headers are ignored (there is
; only one namespace), and unknown keys or bad values produce a warning and
; leave the default in place rather than stopping the program. A scrolling
; utility that refuses to start because of a typo in an optional file is worse
; than one that scrolls at the default speed and says why.
ParseConfig(text) {
    global MULTIPLIER_MIN, MULTIPLIER_MAX, MULTIPLIER_DEFAULT

    cfg := { multiplier: MULTIPLIER_DEFAULT, reverse: false, exclude: [], warnings: [] }
    lineNo := 0

    for line in StrSplit(text, "`n", "`r") {
        lineNo++
        trimmed := Trim(line)
        first := SubStr(trimmed, 1, 1)

        if (trimmed = "" || first = ";" || first = "#" || first = "[")
            continue

        eq := InStr(trimmed, "=")
        if (!eq) {
            cfg.warnings.Push("line " lineNo ": expected key=value, got: " trimmed)
            continue
        }

        key := StrLower(Trim(SubStr(trimmed, 1, eq - 1)))
        value := Trim(SubStr(trimmed, eq + 1))

        switch key, true {
            case "multiplier":
                if (!IsInteger(value)) {
                    cfg.warnings.Push("line " lineNo ": Multiplier must be a whole number, got: " value)
                    continue
                }
                n := Integer(value)
                if (n < MULTIPLIER_MIN) {
                    cfg.warnings.Push("line " lineNo ": Multiplier " n " is below " MULTIPLIER_MIN ", using " MULTIPLIER_MIN)
                    n := MULTIPLIER_MIN
                } else if (n > MULTIPLIER_MAX) {
                    cfg.warnings.Push("line " lineNo ": Multiplier " n " is above " MULTIPLIER_MAX ", using " MULTIPLIER_MAX)
                    n := MULTIPLIER_MAX
                }
                cfg.multiplier := n

            case "reverse":
                b := ParseBool(value)
                if (b = "") {
                    cfg.warnings.Push("line " lineNo ": Reverse must be true or false, got: " value)
                    continue
                }
                cfg.reverse := b

            case "excludeprocesses":
                cfg.exclude := ParseList(value)

            default:
                cfg.warnings.Push("line " lineNo ": unknown setting: " key)
        }
    }

    return cfg
}

; Returns true, false, or "" when the text is not a recognisable boolean.
ParseBool(value) {
    switch StrLower(Trim(value)), true {
        case "true", "1", "yes", "on":   return true
        case "false", "0", "no", "off":  return false
    }
    return ""
}

; Splits a comma-separated list, trimming each entry and dropping empties, so
; that "chrome.exe, , Code.exe," yields two names rather than four.
ParseList(value) {
    out := []
    for part in StrSplit(value, ",") {
        item := Trim(part)
        if (item != "")
            out.Push(item)
    }
    return out
}


; ── Help ──────────────────────────────────────────────────────────────────────

HelpText() {
    global MULTIPLIER_MIN, MULTIPLIER_MAX, MULTIPLIER_DEFAULT

    return ""
        . "HorizontalScroll — hold Shift and scroll the wheel to scroll sideways.`n"
        . "`n"
        . "Usage:`n"
        . "  HorizontalScroll.exe               Run. Changes nothing on disk.`n"
        . "  HorizontalScroll.exe --install     Start automatically at login.`n"
        . "  HorizontalScroll.exe --uninstall   Stop starting automatically at login.`n"
        . "  HorizontalScroll.exe --status      Report whether it is installed.`n"
        . "  HorizontalScroll.exe --help        Show this text.`n"
        . "`n"
        . "Running with no arguments only scrolls. Nothing is written to the`n"
        . "registry unless you ask for it with --install.`n"
        . "`n"
        . "Settings come from HorizontalScroll.ini next to the program, if present:`n"
        . "`n"
        . "  [Scroll]`n"
        . "  Multiplier=" MULTIPLIER_DEFAULT "`n"
        . "  Reverse=false`n"
        . "  ExcludeProcesses=`n"
        . "`n"
        . "  Multiplier         wheel clicks per tick, " MULTIPLIER_MIN " to " MULTIPLIER_MAX "`n"
        . "  Reverse            true swaps left and right`n"
        . "  ExcludeProcesses   comma-separated programs to leave alone, for apps`n"
        . "                     that already handle Shift+wheel themselves`n"
        . "`n"
        . "To quit: right-click the tray icon and choose Exit HorizontalScroll.`n"
}
