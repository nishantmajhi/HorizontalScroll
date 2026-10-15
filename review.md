# HorizontalScroll — review and remediation record

First reviewed 2026-09-04 against git HEAD `b247a8b` ("first commit").
Remediated 2026-09-17 on branch `cleanup/2026-09-17`. Not pushed.

This file started as a to-do list. It is now the record: what was fixed, what
the first review got wrong, what was deliberately left alone, and what still
needs a human.

---

## Corrections to the first review

**"There is no way to quit the script" was overstated.** The script never calls
`#NoTrayIcon`, so AutoHotkey showed its standard tray icon, and that menu has
always carried an Exit item. The first review contradicts itself on this — its
own tray-icon bullet says the tray is "the only built-in way to exit" — and the
Critical Issues heading above it says there is no way at all. What was actually
true is narrower and still worth fixing: quitting was undiscoverable, because
the Exit item sits below six entries about editing and reloading scripts that
mean nothing to someone who downloaded a scrolling utility, and the README told
users to end the process in Task Manager instead of pointing at it.

Everything else in the first review held up. The registry write really was
unconditional, the README really did claim the opposite, there really was no
`LICENSE`, and the documented tree really was wrong in two places.

---

## Bugs the first review missed

These came out of writing the tests, and all but the last are in the same eight
lines the review had already flagged for a different reason.

**The startup entry was written unquoted.** `RegWrite A_ScriptFullPath, ...`
puts a bare path into the Run key. Windows parses a Run value as a command
line, so `C:\Program Files\HorizontalScroll\HorizontalScroll.exe` is read as
the program `C:\Program` with the argument `Files\HorizontalScroll\...`, and
startup silently does nothing. The repository lives at a path with no spaces,
which is why this was never noticed; the default home for a downloaded `.exe`
is `C:\Users\<name>\Downloads`, and plenty of Windows account names have a
space in them. `StartupCommand()` now quotes both halves, and the test suite
runs its black-box checks from a directory with a space in its name on purpose.

**The startup entry named the `.ahk` with no interpreter.** Run uncompiled, the
value written was the path to the script itself, which only starts if the `.ahk`
file association is registered and points at v2. Compiled, `A_ScriptFullPath` is
the `.exe` and this was fine; uncompiled, it was a coin toss. The entry now
reads `"...\AutoHotkey64.exe" "...\HorizontalScroll.ahk"` when the script is not
compiled.

**`#SingleInstance Force` is backwards from what the README described.** The
README said duplicate launches "exit immediately"; `Force` means the *newcomer*
kills the running instance and takes over. That was invisible while the two
copies behaved identically — and it became a real problem the moment `--install`
was added as a switch on the same executable, because asking to register startup
would have terminated the copy that was scrolling. Single-instance is now
enforced with a named mutex *after* the command line has been read, so
`--install` and `--status` leave a running instance alone, and a second plain
launch exits as documented.

**`build.ps1` hardcoded a base file that may not exist.** It looks for Ahk2Exe
in both `Program Files` and `Program Files (x86)`, then unconditionally passes
`/base "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"`. On a 32-bit-only
install the first probe succeeds and the build then fails inside Ahk2Exe,
instead of producing the clear message the script was written to give. `/base`
is now passed only when that file is present.

**The CI workflow promised a checksum it does not contain.** The comment above
the download step invites you to "verify the SHA-256 below", and there is no
SHA-256 below. The URL serves whatever the current v2 release is, so pinning a
hash there would be wrong rather than merely missing; the comment now says what
the step actually checks and what you would change to get a reproducible build.

---

## What was fixed

The structural change underneath all of it: every decision the program makes now
lives in `lib/core.ahk`, which touches no registry, no input, no files and no
hotkeys. `HorizontalScroll.ahk` is the plumbing that calls into it. That split
is what made the test suite possible — the original was thirty-five lines with
no seam anywhere in it.

- **P1 — the registry write is gone from the startup path.** A plain run now
  changes nothing on disk. `--install` writes the Run value, `--uninstall`
  removes it, `--status` reports it. An unrecognised switch exits 2 with the
  usage text rather than falling through to a plain run, because a user who
  typed `--instal` must not walk away believing startup was registered.
- **P1 — quitting is discoverable.** `A_TrayMenu` gets an **Exit
  HorizontalScroll** item at the top, above a separator, and the icon has a
  tooltip naming the program. No global exit hotkey was added; see below.
- **P1 — `LICENSE` added**, MIT, matching what the README claimed.
- **P2 — README rewritten** from first principles. The tray-icon claim is gone
  (there is a tray icon, and quitting from it is now documented), the tree is
  accurate, `tests/test.txt` is named correctly, and the section on Option C no
  longer claims that running the `.ahk` skips startup registration — nothing
  registers startup unless asked.
- **P3 — settings moved to a runtime file.** `HorizontalScroll.ini` beside the
  program, with `Multiplier`, `Reverse` and `ExcludeProcesses`. Absent file means
  the old defaults exactly. `Multiplier` is clamped to 1–20: zero suppressed the
  wheel event and then sent nothing, so `Shift`+wheel stopped scrolling at all
  and looked like a crash, and an unbounded value hangs the machine inside
  `Loop`. Bad values warn and keep the default rather than refusing to start.
  `HorizontalScroll.ini.example` documents the format and is the tracked copy;
  the real file is gitignored.
- **The exclusion list the first review asked for** exists as
  `ExcludeProcesses`, empty by default so shipped behaviour is unchanged. It
  matches against the process under the *cursor*, not the active window, because
  that is where Windows delivers a wheel event and "scroll inactive windows on
  hover" is on by default. The `HotIf` filter is only installed when the list is
  non-empty, so the common case pays nothing for it.
- **P3 — the stale `HorizontalScroll.exe` is deleted** from the working tree. It
  was untracked and gitignored, and it was built from the old source.
- `test/test.txt` moved to `tests/test.txt`, next to the suite.
- `.gitignore` also ignores `HorizontalScroll.ini`.
- A **Run HorizontalScroll tests** task added to `.vscode/tasks.json`, and a test
  step added to the CI workflow before the compile step, with `fetch-depth: 0`
  so the regression half has the history it needs.

---

## Tests

```
"C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tests\run.ahk
```

100 checks, all passing. No framework and no dependency beyond AutoHotkey
itself, per the archive convention.

The suite has two halves. The unit half calls `lib/core.ahk` directly. The
behaviour half copies `HorizontalScroll.ahk` into a temporary directory — one
with a space in its name — rewrites the single registry-key literal to a scratch
key under `HKCU\Software\HorizontalScroll-SelfTest`, runs it as a real process
with real arguments, and reads back what it did. **It never writes to the real
Run key**, and it removes the scratch key and the temporary directory when it
finishes. Because the redirection is a one-line `StrReplace` that asserts it
matched exactly once, the entry point must keep that literal on one line; there
is a comment in the source saying so.

Those seven behaviour checks are then run again against the original source,
fetched with `git show b247a8b:HorizontalScroll.ahk`, and the suite asserts that
**every one of them fails there**. That is the confirmation the archive
convention asks for, kept in the repository rather than claimed in a file like
this one. If git is unavailable the half is skipped with a note rather than
silently passing.

The seven: a plain run writes no startup entry; `--install` writes a quoted
command naming the interpreter and the script; `--uninstall` removes it and
exits; `--help` prints usage, exits 0 and writes nothing; `--status` reports
honestly before and after; an unrecognised switch exits non-zero and changes
nothing; a second launch exits and leaves the running copy alone.

Two traps worth knowing if you write AutoHotkey tests here, both of which cost
time:

- **`ProcessWaitClose` returns the PID when the timeout expires**, and 0 when
  the process actually closed. It reads like a success/failure flag and is the
  opposite of one. Getting it backwards makes fast processes look like hangs and
  hangs look like clean exits.
- **`FileOpen(path, "w", "UTF-8")` writes a byte-order mark**, and `cmd.exe`
  treats a BOM at the top of a `.cmd` file as part of the first command. Batch
  files written from AutoHotkey need `"CP0"`.

---

## Deliberately not done

**No global exit hotkey.** The first review suggested `^!q::ExitApp` or a tray
menu item, as alternatives. A global hotkey takes that chord away from every
application on the machine for as long as this runs, which is a poor trade for a
utility whose entire job is one gesture. The tray item does the same work and
costs nothing.

**`#NoTrayIcon` was not added.** The review offered it as one way to make the
README's "no tray icon" claim true. Removing the icon would remove the only way
to quit without Task Manager, which is the problem directly above it. The README
was corrected instead.

**The app compatibility table was toned down, not deleted.** Chrome, Edge,
Firefox and VS Code do handle `Shift`+wheel natively, so listing them as wins
overstates what this adds. The README now says so and points at
`ExcludeProcesses`. Whether to ship a non-empty default exclusion list is a
judgement about taste, not a bug, and it is the author's to make — the mechanism
is there and tested.

**No `SECRETS-TODO.md`.** There are no credentials anywhere in this project, and
nothing in its history.

---

## Still needs a machine

**Nothing here has been through Ahk2Exe.** There is no AutoHotkey installation
on this machine; the suite runs against a portable AutoHotkey v2 unpacked to
`D:\dev-tools\autohotkey\`, which has no compiler in it. The source runs
correctly under that interpreter — `--help`, `--status` and config loading were
all driven by hand in addition to the suite — but `build.ps1` and the CI compile
step have not been executed. Compiling is the one path where `A_IsCompiled` is
true, which selects the other branch of `StartupCommand()`; that branch is unit
tested, but the value it produces has not been written to a real Run key by a
real `.exe`.

**The wheel handlers have not been exercised against a real window.** Nothing
here can move a mouse over a scrollable window and watch it scroll. The
translation from `Shift`+wheel to `WheelLeft`/`WheelRight` is unchanged from the
original except for reading the multiplier from config instead of a constant, so
this is a check that nothing regressed rather than a fix to confirm.

A ten-minute manual pass, if you have a Windows desktop:

1. `.\build.ps1`, then run `HorizontalScroll.exe`. Confirm a tray icon appears
   with the tooltip, and that right-clicking it shows **Exit HorizontalScroll**
   at the top.
2. Open `tests\test.txt` in Notepad, narrow the window, and try `Shift`+wheel in
   both directions. Repeat in VS Code, which takes a different input path.
3. `HorizontalScroll.exe --install`, then look at
   `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` in regedit. The value
   must be the quoted path to the `.exe`. Reboot, or log out and back in, and
   confirm it starts.
4. Copy the `.exe` to a folder whose name contains a space and run `--install`
   from there. This is the case the original got wrong.
5. `HorizontalScroll.exe --uninstall` and confirm the value is gone.
6. Put an `ExcludeProcesses=Code.exe` line in `HorizontalScroll.ini`, restart it,
   and confirm VS Code goes back to its own `Shift`+wheel behaviour while Notepad
   still uses this one. That is the only part of the config path a machine can
   check.

## Licence, 2026-10-02

The author chose one licence for all of their projects: free for personal,
non-commercial use, modifiable for the user's own use, and not to be
distributed, original or modified. No standard licence says that, so `LICENSE`
is a short custom text, the same in every project apart from the year and what
it excludes. The README's licence section says the same. Anything above that
calls the licence an open question, or calls the project MIT, is superseded.

## CI, 2026-10-02

`.github/workflows/ci.yml` installs AutoHotkey 2.0.28 (checked against its
published SHA-256) and runs `tests/run.ahk` from bash on `windows-latest`, on
every push. `build.yml` still builds releases on tags. Nothing has been
pushed, so it has not run on GitHub yet. Every job was run before committing,
from a fresh clone of this branch, the way a runner would run it: Windows jobs
here, in PowerShell 7 or the shell the step names, with only the tools the job
sets up on `PATH`. 100.

**Fixed on the way:** `build.yml`'s test step, added in the 2026-09-17 pass,
ran `& $ahk tests\run.ahk` in PowerShell and failed the job if `$LASTEXITCODE`
was not 0. PowerShell does not reliably wait for a GUI program and, in every
trial here, left `$LASTEXITCODE` unset, and `$null -ne 0` is true, so the step
failed on every run whatever the suite did. It now runs from bash, which waits
and passes the exit code on (checked with a script ending `ExitApp 7`).

**For the author:** the compile step below it runs `Ahk2Exe` the same way, and
the workflow installs AutoHotkey with the v2 installer, which as far as I know
does not include Ahk2Exe; its check for `Compiler\Ahk2Exe.exe` would then stop
the job. Neither could be checked without installing to C:. Run the workflow
by hand (`workflow_dispatch`) before tagging a release.
