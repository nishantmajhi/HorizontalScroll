#Requires AutoHotkey v2.0
#SingleInstance Off
#Include ..\lib\core.ahk

; run.ahk — the HorizontalScroll test suite.
;
;   AutoHotkey64.exe tests\run.ahk
;
; Two halves. The first calls lib/core.ahk directly and checks the decisions it
; makes. The second is black-box: it copies the entry point into a sandbox with
; its registry key redirected, runs it as a real process with real arguments,
; and reads back what it did. That second half also runs against the original
; pre-cleanup source, fetched from git, and asserts that every one of its checks
; fails there — a regression test that passes against the unfixed code is
; testing nothing.
;
; The sandbox lives under a directory with a space in its name on purpose. The
; original wrote an unquoted path into the Run key, which is invisible until the
; program sits somewhere like "C:\Program Files" or "C:\Users\A B\Downloads".

ORIGINAL_COMMIT := "b247a8b"
SANDBOX_ROOT := A_Temp "\HorizontalScroll tests"
TEST_ROOT_KEY := "HKCU\Software\HorizontalScroll-SelfTest"
TEST_RUN_KEY := TEST_ROOT_KEY "\Run"
REAL_RUN_KEY := "Software\Microsoft\Windows\CurrentVersion\Run"
SANDBOX_RUN_KEY := "Software\HorizontalScroll-SelfTest\Run"

Passed := 0
Failed := 0
Skipped := 0

OnError(ReportUncaught)

Main()


; An uncaught error in a test run would otherwise raise a dialog that nothing
; here can dismiss, or vanish silently. Print it and fail loudly instead.
ReportUncaught(err, mode) {
    Say("")
    Say("UNCAUGHT " Type(err) ": " (err is Error ? err.Message : err))
    if (err is Error) {
        Say("  " err.File ":" err.Line)
        if (err.Extra != "")
            Say("  extra: " err.Extra)
    }
    ExitApp 3
}


Main() {
    global Passed, Failed, Skipped

    Say("HorizontalScroll test suite")
    Say("")

    TestParseArgs()
    TestStartupCommand()
    TestScrollTarget()
    TestIsExcluded()
    TestParseConfig()
    TestHelpText()
    TestBehaviour()

    Say("")
    Say(Passed " passed, " Failed " failed" (Skipped ? ", " Skipped " skipped" : ""))
    ExitApp Failed ? 1 : 0
}


; ── Harness ───────────────────────────────────────────────────────────────────

Say(text) {
    try FileAppend text "`n", "*"
}

Check(condition, description) {
    global Passed, Failed
    if (condition) {
        Passed++
        return true
    }
    Failed++
    Say("  FAIL  " description)
    return false
}

Same(actual, expected, description) {
    global Passed, Failed

    if (actual == expected) {
        Passed++
        return true
    }
    Failed++
    Say("  FAIL  " description)
    Say("          expected: " Show(expected))
    Say("          actual:   " Show(actual))
    return false
}

Throws(callback, description) {
    global Passed, Failed

    try {
        callback()
    } catch {
        Passed++
        return
    }
    Failed++
    Say("  FAIL  " description " (no error was thrown)")
}

Show(value) {
    if (value is Array) {
        parts := ""
        for item in value
            parts .= (parts = "" ? "" : ", ") Show(item)
        return "[" parts "]"
    }
    if (value == true)
        return "true"
    if (value == false && !(value is String))
        return "false"
    return "<" value ">"
}

Section(name) {
    Say(name)
}


; ── lib/core.ahk: command line ────────────────────────────────────────────────

TestParseArgs() {
    Section("ParseArgs")

    Same(ParseArgs([]).action, "run", "no arguments means a plain run")
    Check(ParseArgs([]).ok, "no arguments is not an error")

    for spelling in ["--install", "-i", "/install", "/i", "--INSTALL"]
        Same(ParseArgs([spelling]).action, "install", spelling " selects install")

    for spelling in ["--uninstall", "-u", "/uninstall", "--remove"]
        Same(ParseArgs([spelling]).action, "uninstall", spelling " selects uninstall")

    for spelling in ["--status", "-s"]
        Same(ParseArgs([spelling]).action, "status", spelling " selects status")

    for spelling in ["--help", "-h", "/?", "-?"]
        Same(ParseArgs([spelling]).action, "help", spelling " selects help")

    ; A misspelled switch must not fall through to a plain run: the user who
    ; typed --instal meant to install, and silently scrolling instead would
    ; leave them believing startup was registered when it was not.
    bad := ParseArgs(["--instal"])
    Check(!bad.ok, "an unrecognised switch is rejected")
    Check(InStr(bad.message, "--instal"), "the rejection names the switch that was not understood")

    bare := ParseArgs(["install"])
    Check(!bare.ok, "a bare word without a dash is rejected")

    empty := ParseArgs([""])
    Check(!empty.ok, "an empty argument is rejected")

    conflict := ParseArgs(["--install", "--uninstall"])
    Check(!conflict.ok, "asking to install and uninstall at once is rejected")
    Check(InStr(conflict.message, "Conflicting"), "the conflict is described as a conflict")

    repeat := ParseArgs(["--install", "-i"])
    Check(repeat.ok, "the same action twice is not a conflict")
    Same(repeat.action, "install", "the same action twice still installs")
}


; ── lib/core.ahk: startup command ─────────────────────────────────────────────

TestStartupCommand() {
    Section("StartupCommand")

    exe := "C:\Program Files\HorizontalScroll\HorizontalScroll.exe"
    Same(StartupCommand(exe, true), '"' exe '"',
        "a compiled path is quoted, so a space in it does not split the command")

    script := "C:\Users\A B\Documents\HorizontalScroll.ahk"
    interpreter := "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
    Same(StartupCommand(script, false, interpreter),
        '"' interpreter '" "' script '"',
        "an uncompiled script runs through the interpreter, both paths quoted")

    Check(SubStr(StartupCommand("C:\x.exe", true), 1, 1) == Chr(34),
        "the command always begins with a quote")

    Throws(() => StartupCommand("", true), "an empty target is refused")
    Throws(() => StartupCommand("   ", true), "a whitespace-only target is refused")
    Throws(() => StartupCommand("C:\x.ahk", false),
        "an uncompiled script with no interpreter is refused rather than written unrunnable")
}


; ── lib/core.ahk: scroll direction ────────────────────────────────────────────

TestScrollTarget() {
    Section("ScrollTarget")

    Same(ScrollTarget("up", false), "WheelLeft", "wheel up scrolls left")
    Same(ScrollTarget("down", false), "WheelRight", "wheel down scrolls right")
    Same(ScrollTarget("up", true), "WheelRight", "reversed, wheel up scrolls right")
    Same(ScrollTarget("down", true), "WheelLeft", "reversed, wheel down scrolls left")
    Same(ScrollTarget("UP", false), "WheelLeft", "direction is case-insensitive")
    Same(ScrollTarget(" down ", false), "WheelRight", "direction tolerates surrounding space")

    Throws(() => ScrollTarget("sideways", false), "an unknown direction is refused")
    Throws(() => ScrollTarget("", false), "an empty direction is refused")
}


; ── lib/core.ahk: exclusions ──────────────────────────────────────────────────

TestIsExcluded() {
    Section("IsExcluded")

    Check(!IsExcluded("chrome.exe", []), "an empty list excludes nothing, which is the default")
    Check(IsExcluded("chrome.exe", ["chrome.exe"]), "an exact name matches")
    Check(IsExcluded("chrome.exe", ["CHROME.EXE"]), "matching ignores case")
    Check(IsExcluded("chrome.exe", ["chrome"]), "a name written without .exe still matches")
    Check(IsExcluded("Code.exe", ["notepad.exe", "Code.exe"]), "any entry in the list matches")
    Check(!IsExcluded("chrome.exe", ["chrom"]), "a partial name does not match")
    Check(!IsExcluded("", ["chrome.exe"]), "an unknown process is never excluded")
    Check(!IsExcluded("chrome.exe", ["", "  "]), "blank entries match nothing")
}


; ── lib/core.ahk: configuration ───────────────────────────────────────────────

TestParseConfig() {
    Section("ParseConfig")

    ; No config file at all must behave exactly like the version that had the
    ; settings baked in as constants.
    defaults := ParseConfig("")
    Same(defaults.multiplier, 3, "the default multiplier is 3, as the constant was")
    Check(defaults.reverse == false, "direction is not reversed by default")
    Same(defaults.exclude.Length, 0, "nothing is excluded by default")
    Same(defaults.warnings.Length, 0, "an absent config produces no warnings")

    cfg := ParseConfig("[Scroll]`nMultiplier=7`nReverse=true`nExcludeProcesses=chrome.exe, Code.exe`n")
    Same(cfg.multiplier, 7, "Multiplier is read")
    Check(cfg.reverse == true, "Reverse is read")
    Same(cfg.exclude.Length, 2, "ExcludeProcesses splits on commas")
    Same(cfg.exclude[1], "chrome.exe", "the first excluded process is kept verbatim")
    Same(cfg.warnings.Length, 0, "a valid config produces no warnings")

    ; A multiplier of zero suppresses the wheel event and then sends nothing, so
    ; Shift+wheel would stop scrolling in either direction. Clamping keeps a
    ; mistyped config from looking like the program has crashed.
    low := ParseConfig("Multiplier=0")
    Same(low.multiplier, 1, "a multiplier below the minimum is clamped up to 1")
    Same(low.warnings.Length, 1, "clamping is reported")

    negative := ParseConfig("Multiplier=-5")
    Same(negative.multiplier, 1, "a negative multiplier is clamped to 1")

    high := ParseConfig("Multiplier=10000")
    Same(high.multiplier, 20, "an absurd multiplier is clamped down to 20")
    Same(high.warnings.Length, 1, "clamping down is reported")

    junk := ParseConfig("Multiplier=fast")
    Same(junk.multiplier, 3, "a non-numeric multiplier leaves the default in place")
    Same(junk.warnings.Length, 1, "a non-numeric multiplier is reported")

    for text in ["Reverse=true", "Reverse=yes", "Reverse=on", "Reverse=1", "Reverse=TRUE"]
        Check(ParseConfig(text).reverse == true, text " reads as true")

    for text in ["Reverse=false", "Reverse=no", "Reverse=off", "Reverse=0"]
        Check(ParseConfig(text).reverse == false, text " reads as false")

    maybe := ParseConfig("Reverse=maybe")
    Check(maybe.reverse == false, "an unparseable Reverse leaves the default")
    Same(maybe.warnings.Length, 1, "an unparseable Reverse is reported")

    Same(ParseConfig("MULTIPLIER=5").multiplier, 5, "keys are case-insensitive")
    Same(ParseConfig("   Multiplier   =   5   ").multiplier, 5, "space around key and value is ignored")
    Same(ParseConfig("Multiplier=5`r`nReverse=true").multiplier, 5, "CRLF line endings are handled")

    quiet := ParseConfig("; a comment`n# another`n`n[Scroll]`nMultiplier=4")
    Same(quiet.multiplier, 4, "comments and section headers are skipped")
    Same(quiet.warnings.Length, 0, "comments and section headers are not warned about")

    unknown := ParseConfig("Speed=9")
    Same(unknown.warnings.Length, 1, "an unknown setting is reported rather than ignored")
    Check(InStr(unknown.warnings[1], "speed"), "the warning names the unknown setting")

    malformed := ParseConfig("Multiplier")
    Same(malformed.warnings.Length, 1, "a line with no equals sign is reported")
    Same(malformed.multiplier, 3, "a malformed line does not disturb the defaults")

    sparse := ParseConfig("ExcludeProcesses=chrome.exe, , Code.exe,")
    Same(sparse.exclude.Length, 2, "blank entries in the exclude list are dropped")

    none := ParseConfig("ExcludeProcesses=")
    Same(none.exclude.Length, 0, "an empty exclude list is empty, not one blank entry")
}


; ── lib/core.ahk: help ────────────────────────────────────────────────────────

TestHelpText() {
    Section("HelpText")

    help := HelpText()
    for flag in ["--install", "--uninstall", "--status", "--help"]
        Check(InStr(help, flag), "the help text documents " flag)

    Check(InStr(help, "registry"), "the help text says what --install changes")
    Check(InStr(help, "HorizontalScroll.ini"), "the help text names the config file")
    Check(InStr(help, "tray"), "the help text says how to quit")
}


; ── Black box: the entry point as a real process ──────────────────────────────

TestBehaviour() {
    global Skipped, ORIGINAL_COMMIT

    Section("Behaviour (real process, redirected registry)")

    CleanSandbox()

    current := FileRead(RepoFile("HorizontalScroll.ahk"), "UTF-8")
    fixed := Sandbox("current", current, true)

    for result in RunChecks(fixed) {
        if (!Check(result.ok, result.description))
            Say("          " result.detail)
    }

    ; The same checks against the code as it was before this pass. Every one of
    ; them has to fail, or it was never testing the bug it claims to cover.
    Section("Behaviour against the original source (" ORIGINAL_COMMIT ")")

    originalSource := GitShow(ORIGINAL_COMMIT ":HorizontalScroll.ahk")
    if (originalSource = "") {
        Skipped++
        Say("  SKIP  could not read " ORIGINAL_COMMIT ":HorizontalScroll.ahk from git")
    } else {
        original := Sandbox("original", originalSource, false)
        checks := RunChecks(original)
        broken := 0
        for result in checks
            if (!result.ok)
                broken++
        Same(broken, checks.Length,
            "every behaviour check fails against the original source")
    }

    CleanStartupKey(true)
    CleanSandbox()
}

; The four things the entry point must get right, as observable facts about a
; process that has been run and has exited.
RunChecks(dir) {
    results := []

    ; 1. Running it must not install anything. The original wrote to the Run key
    ;    at load time, unconditionally, so there was no way to try the tool once
    ;    without it registering itself for every future login.
    CleanStartupKey()
    RunAndKill(dir, 3)
    entry := ReadStartupEntry()
    results.Push({ ok: entry == "",
        description: "a plain run writes no startup entry",
        detail: "startup entry after a plain run: " Show(entry) })

    ; 2. --install must write a command that will actually start the program.
    CleanStartupKey()
    installed := RunScript(dir, "--install", 15)
    entry := ReadStartupEntry()
    ok := !installed.timedOut
        && installed.code == 0
        && SubStr(entry, 1, 1) == Chr(34)
        && InStr(entry, "AutoHotkey")
        && InStr(entry, "HorizontalScroll.ahk")
    results.Push({ ok: ok,
        description: "--install writes a quoted command naming the interpreter and the script",
        detail: Outcome(installed) "  entry: " Show(entry) })

    ; 3. --uninstall must undo it. The original had no uninstall path at all;
    ;    the README told the user to open regedit.
    removed := RunScript(dir, "--uninstall", 15)
    results.Push({ ok: !removed.timedOut && removed.code == 0 && ReadStartupEntry() == "",
        description: "--uninstall removes the startup entry and exits cleanly",
        detail: Outcome(removed) "  entry: " Show(ReadStartupEntry()) })

    ; 4. --help must be answerable without side effects.
    CleanStartupKey()
    helped := RunScript(dir, "--help", 15)
    results.Push({ ok: !helped.timedOut
            && helped.code == 0
            && InStr(helped.output, "--install")
            && ReadStartupEntry() == "",
        description: "--help prints usage, exits 0, and writes nothing",
        detail: Outcome(helped) "  entry: " Show(ReadStartupEntry()) })

    ; 5. --status must answer honestly in both directions, so that a user who is
    ;    not sure whether they ever ran --install can find out without regedit.
    CleanStartupKey()
    before := RunScript(dir, "--status", 15)
    RunScript(dir, "--install", 15)
    after := RunScript(dir, "--status", 15)
    results.Push({ ok: !before.timedOut && !after.timedOut
            && InStr(before.output, "Not installed")
            && !InStr(after.output, "Not installed")
            && InStr(after.output, "HorizontalScroll.ahk"),
        description: "--status reports not-installed before --install and installed after",
        detail: "before: " Outcome(before) "  after: " Outcome(after) })

    ; 6. A misspelled switch must fail loudly rather than silently scrolling, or
    ;    a user who typed --instal walks away believing startup is registered.
    CleanStartupKey()
    typo := RunScript(dir, "--instal", 15)
    results.Push({ ok: !typo.timedOut && typo.code == 2 && ReadStartupEntry() == "",
        description: "an unrecognised switch exits non-zero and changes nothing",
        detail: Outcome(typo) "  entry: " Show(ReadStartupEntry()) })

    ; 7. Launching it twice must leave the copy that is already scrolling alone.
    ;    #SingleInstance Force did the opposite: the newcomer killed the running
    ;    instance and took over. That is invisible when both copies behave
    ;    identically, but it is why --install could not be a switch on the same
    ;    executable -- asking to register startup would have stopped the tool.
    first := StartDetached(dir)
    Sleep 1500
    second := RunScript(dir, "", 10)
    survived := ProcessExist(first) != 0
    try ProcessClose(first)
    Sleep 250
    results.Push({ ok: !second.timedOut && survived,
        description: "a second launch exits and leaves the running copy alone",
        detail: "second: " Outcome(second)
            . "  first still running: " (survived ? "yes" : "no") })

    CleanStartupKey()
    return results
}


; ── Sandbox plumbing ──────────────────────────────────────────────────────────

Outcome(result) {
    return result.timedOut
        ? "timed out"
        : "exit " result.code ", " StrLen(result.output) " bytes of output"
}

RepoFile(relative) {
    return A_LineFile "\..\.." "\" relative
}

; Copies a script into a temporary directory whose name contains a space, with
; the real Run key rewritten to a scratch key under HKCU\Software. Nothing in
; the suite ever writes to the real startup key.
Sandbox(name, source, withLib) {
    global SANDBOX_ROOT, REAL_RUN_KEY, SANDBOX_RUN_KEY

    dir := SANDBOX_ROOT "\" name
    DirCreate dir

    redirected := StrReplace(source, REAL_RUN_KEY, SANDBOX_RUN_KEY, true, &count)
    if (count != 1)
        throw Error("expected one startup key literal in " name ", found " count)

    WriteFile(dir "\HorizontalScroll.ahk", redirected)

    if (withLib) {
        DirCreate dir "\lib"
        FileCopy RepoFile("lib\core.ahk"), dir "\lib\core.ahk", true
    }
    return dir
}

CleanSandbox() {
    global SANDBOX_ROOT
    try DirDelete SANDBOX_ROOT, true
}

; cmd.exe treats a UTF-8 byte-order mark at the top of a .cmd file as part of
; the first command, so batch files are written without one.
WriteFile(path, text, encoding := "UTF-8") {
    handle := FileOpen(path, "w", encoding)
    handle.Write(text)
    handle.Close()
}

; Runs the sandboxed script and waits for it to exit, capturing stdout and the
; exit code through a one-shot batch file. A GUI-subsystem program has no stdout
; of its own to redirect from here, so cmd has to do it.
RunScript(dir, args, timeoutSeconds) {
    outFile := dir "\stdout.txt"
    codeFile := dir "\exitcode.txt"
    batFile := dir "\run.cmd"

    try FileDelete outFile
    try FileDelete codeFile

    WriteFile(batFile, "@echo off`r`n"
        . Chr(34) A_AhkPath Chr(34) " " Chr(34) dir "\HorizontalScroll.ahk" Chr(34)
          " " args " > " Chr(34) outFile Chr(34) " 2>&1`r`n"
        . "echo %ERRORLEVEL% > " Chr(34) codeFile Chr(34) "`r`n", "CP0")

    Run(A_ComSpec " /c " Chr(34) batFile Chr(34), dir, "Hide", &pid)

    ; ProcessWaitClose returns the PID when the process is *still running*, so a
    ; non-zero result means the timeout expired, not that it finished.
    if (ProcessWaitClose(pid, timeoutSeconds)) {
        KillTree(pid)
        return { timedOut: true, code: -1, output: ReadIfPresent(outFile) }
    }

    code := Trim(ReadIfPresent(codeFile), " `t`r`n")
    return { timedOut: false,
             code: IsInteger(code) ? Integer(code) : -1,
             output: ReadIfPresent(outFile) }
}

; For the case that is meant to keep running: start it, give it long enough to
; have done any damage it was going to do, then stop it.
; Starts the script the way a user would and returns its PID, without waiting.
StartDetached(dir) {
    Run(Chr(34) A_AhkPath Chr(34) " " Chr(34) dir "\HorizontalScroll.ahk" Chr(34),
        dir, "Hide", &pid)
    return pid
}

RunAndKill(dir, seconds) {
    Run(Chr(34) A_AhkPath Chr(34) " " Chr(34) dir "\HorizontalScroll.ahk" Chr(34),
        dir, "Hide", &pid)
    Sleep seconds * 1000
    try ProcessClose(pid)
    Sleep 250
}

KillTree(pid) {
    try RunWait(A_ComSpec " /c taskkill /T /F /PID " pid " >nul 2>&1", , "Hide")
}

ReadIfPresent(path) {
    if (!FileExist(path))
        return ""
    try
        return FileRead(path)
    return ""
}

GitShow(spec) {
    global SANDBOX_ROOT

    DirCreate SANDBOX_ROOT
    out := SANDBOX_ROOT "\git-show.txt"
    try FileDelete out

    try RunWait(A_ComSpec " /c git show " spec " > " Chr(34) out Chr(34) " 2>nul",
        RepoFile(""), "Hide")
    return ReadIfPresent(out)
}


; ── Scratch registry key ──────────────────────────────────────────────────────

ReadStartupEntry() {
    global TEST_RUN_KEY
    try
        return RegRead(TEST_RUN_KEY, "HorizontalScroll")
    return ""
}

CleanStartupKey(removeTree := false) {
    global TEST_RUN_KEY, TEST_ROOT_KEY
    try RegDelete(TEST_RUN_KEY, "HorizontalScroll")
    if (removeTree)
        try RegDeleteKey(TEST_ROOT_KEY)
}
