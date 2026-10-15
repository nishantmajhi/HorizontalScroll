# HorizontalScroll

Hold **Shift** and turn the mouse wheel to scroll sideways, in any Windows application.

A mouse with one wheel can only scroll one axis. Windows has no system-wide setting that maps the
second axis onto a modifier key, so most applications are left to decide for themselves — and most
never do. This is about forty lines of AutoHotkey that fills the gap: it intercepts `Shift`+wheel
globally and re-emits it as a horizontal wheel event.

Requires Windows 10 or 11.

---

## What it actually does

`WheelLeft` and `WheelRight` are real input events, the ones a touchpad driver sends for a two-finger
horizontal swipe. Windows delivers them to whichever window is under the mouse cursor. So rather than
knowing anything about individual applications, this script translates one event into another and
lets Windows route it:

```
Shift + WheelUp / WheelDown
 └── intercepted globally, original vertical scroll suppressed
      └── WheelLeft / WheelRight sent, Multiplier times
           └── Windows delivers to the window under the cursor
                └── the application scrolls horizontally
```

That is the whole mechanism, and it is also the limit of it: an application that ignores horizontal
wheel events will ignore these too.

**Note that some applications already do this.** Chrome, Edge, Firefox and VS Code map `Shift`+wheel
to horizontal scrolling themselves. There, this script is not adding a capability — it suppresses
what the application would have done and substitutes its own scrolling at `Multiplier` times the
speed. If you prefer the original behaviour in some applications, list them under
`ExcludeProcesses` (see [Settings](#settings)) and they will be left alone.

---

## Getting it

### Download the binary

Take `HorizontalScroll.exe` from [Releases](../../releases) and run it. It needs no installer and no
administrator rights.

Running it does not change anything on your machine. If you want it to start with Windows, that is a
separate, explicit step:

```
HorizontalScroll.exe --install
```

### Build it yourself

The `.exe` is compiled from `HorizontalScroll.ahk` and `lib/core.ahk` in this repository, and there
is no reason to take a binary from the internet on trust when building takes two minutes.

1. Install [AutoHotkey v2](https://www.autohotkey.com/).
2. Install [Ahk2Exe](https://github.com/AutoHotkey/Ahk2Exe/releases), which is the compiler and is
   **not** bundled with AutoHotkey v2. Create `C:\Program Files\AutoHotkey\Compiler\` and put
   `Ahk2Exe.exe` in it:

   ```powershell
   # in an elevated PowerShell
   New-Item -Path "C:\Program Files\AutoHotkey\Compiler" -ItemType Directory
   Move-Item "$env:USERPROFILE\Downloads\Ahk2Exe.exe" "C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe"
   ```

   Windows Defender sometimes flags the Ahk2Exe download, because it is a tool that produces
   executables. That is what it is for.

3. Run `.\build.ps1` from the repository root, or press **Ctrl+Shift+B** in VS Code. Either produces
   `HorizontalScroll.exe` beside the source.

`build.ps1` finds Ahk2Exe itself and follows the `#Include`, so `lib/core.ahk` is compiled into the
same binary.

### Verify a release instead

`.github/workflows/build.yml` compiles every tagged release on a GitHub-hosted Windows runner, with
a public log. To reproduce it: fork the repository, push a tag (`git tag v1.0.0 && git push origin
v1.0.0`), and watch the Actions tab. The workflow installs AutoHotkey from `autohotkey.com`, runs
the test suite, compiles, and attaches the result to a release. No secrets and no private build
machine are involved.

### Run the script without compiling

Double-click `HorizontalScroll.ahk` and AutoHotkey v2 will run it directly. Everything works
identically, including `--install`: the startup entry then names the AutoHotkey interpreter and
passes it the script, so it survives a reboot just as the compiled version does.

---

## Using it

| Gesture | Action |
| --- | --- |
| `Shift` + wheel up | scroll left |
| `Shift` + wheel down | scroll right |

Reversed if `Reverse=true` in the settings file.

There is a tray icon while it runs. To quit, right-click it and choose **Exit HorizontalScroll**.

Launching it a second time does nothing — the second copy sees the first and exits, leaving the
running one alone.

### Command line

```
HorizontalScroll.exe               run; changes nothing on disk
HorizontalScroll.exe --install     start automatically at login
HorizontalScroll.exe --uninstall   stop starting automatically at login
HorizontalScroll.exe --status      report what is registered and what settings are in effect
HorizontalScroll.exe --help        usage
```

`--install` writes one value, `HorizontalScroll`, under
`HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run`. That is a per-user key, which is
why no UAC prompt appears. `--uninstall` removes it and nothing else. Nothing is written unless you
ask for it.

---

## Settings

Optional. Copy `HorizontalScroll.ini.example` to `HorizontalScroll.ini`, next to the program, and
edit it. Without the file, the defaults below apply.

```ini
[Scroll]
Multiplier=3
Reverse=false
ExcludeProcesses=
```

| Setting | Default | Meaning |
| --- | --- | --- |
| `Multiplier` | `3` | Horizontal wheel clicks sent per tick of your real wheel. 1 to 20; anything outside that is clamped, and the reason is printed. |
| `Reverse` | `false` | Swap the directions, so wheel up scrolls right. |
| `ExcludeProcesses` | empty | Comma-separated programs to leave alone, for applications that handle `Shift`+wheel themselves. The `.exe` is optional, and case does not matter: `chrome, Code.exe` is valid. |

The file is read once at startup, so restart the program after changing it. A typo does not stop it
starting: the affected setting keeps its default and a line saying so is printed to the console.
`--status` shows what is actually in effect.

---

## Uninstalling

```
HorizontalScroll.exe --uninstall
```

Then quit it from the tray icon and delete the `.exe`. Nothing else is left behind — no installer
record, no files outside the folder you put it in, and no other registry keys.

---

## Testing

The suite is written in AutoHotkey and needs nothing but AutoHotkey:

```
"C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tests\run.ahk
```

It prints a pass/fail count and exits non-zero on failure. Ninety-seven checks in two halves:

- **Unit.** `lib/core.ahk` holds every decision the program makes — how the command line parses, what
  goes into the startup entry, which wheel key a direction maps to, how the settings file is read,
  which processes are excluded — with no registry, no input and no file access in it. Those are
  called directly.
- **Behaviour.** The entry point is copied into a temporary directory with its registry key rewritten
  to a scratch location under `HKCU\Software`, then run as a real process with real arguments, and
  what it did is read back. **The suite never touches the real startup key**, and it deletes the
  scratch key and the temporary directory when it finishes.

  Those same four checks are then run against the original pre-cleanup source, fetched from git, and
  the suite asserts that all four *fail* there. A regression test that passes against the code it was
  written for is not testing anything.

`tests/test.txt` is for testing by hand: it has lines long enough to produce a horizontal scrollbar.
Open it, narrow the window, and try the gesture. Worth doing in one classic Win32 application
(Notepad) and one Electron application (VS Code), since they take different paths to the same event.

---

## Repository layout

```
HorizontalScroll/
├── .github/workflows/build.yml   CI: installs AutoHotkey, tests, compiles, releases
├── .vscode/tasks.json            build and test tasks for VS Code
├── HorizontalScroll.ahk          entry point: registry, hotkeys, tray, wheel events
├── lib/core.ahk                  the decisions, with no side effects — what the tests drive
├── tests/run.ahk                 the test suite
├── tests/test.txt                long lines, for checking the gesture by hand
├── HorizontalScroll.ini.example  documented settings file; copy to HorizontalScroll.ini
├── build.ps1                     Ahk2Exe wrapper
├── LICENSE
└── README.md
```

`HorizontalScroll.exe` and `HorizontalScroll.ini` are deliberately not tracked: one is a build
output, the other is yours.

---

## License

Free for personal, non-commercial use. You may use, study and modify this
software for yourself, but you may not use it commercially, and you may not
share or publish it, in its original form or modified. See [LICENSE](LICENSE)
for the full terms.
