# build.ps1 - Compile HorizontalScroll.ahk -> HorizontalScroll.exe
# Run directly:  .\build.ps1
# Or via VS Code: Ctrl+Shift+B
#
# Ahk2Exe follows the #Include in HorizontalScroll.ahk, so lib\core.ahk is
# compiled into the same binary. There is nothing else to pass it.

$ErrorActionPreference = "Stop"

$candidates = @(
    "C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe",
    "C:\Program Files (x86)\AutoHotkey\Compiler\Ahk2Exe.exe"
)

$ahk2exe = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $ahk2exe) {
    Write-Error "Ahk2Exe not found. Install AutoHotkey v2 from https://www.autohotkey.com/"
    exit 1
}

Write-Host "Using: $ahk2exe"

$src = Join-Path $PSScriptRoot "HorizontalScroll.ahk"
$out = Join-Path $PSScriptRoot "HorizontalScroll.exe"

if (-not (Test-Path $src)) {
    Write-Error "Source not found: $src"
    exit 1
}

# The base file decides which AutoHotkey runtime is embedded. Naming one that
# is not installed makes Ahk2Exe fail, so only pass /base when the 64-bit
# runtime is actually there; otherwise let Ahk2Exe pick its own default, which
# is what a 32-bit-only install needs.
$base = "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
$arguments = @("/in", $src, "/out", $out, "/cp", "65001")

if (Test-Path $base) {
    Write-Host "Base: $base"
    $arguments += @("/base", $base)
} else {
    Write-Host "Base: Ahk2Exe default (AutoHotkey64.exe not found at $base)"
}

& $ahk2exe @arguments

if (Test-Path $out) {
    Write-Host "Build succeeded -> HorizontalScroll.exe" -ForegroundColor Green
} else {
    Write-Error "Build failed - HorizontalScroll.exe was not created"
    exit 1
}
