# Bundled Deskrawl pointer compatibility component

`deskrawl-pointer.c`, `deskrawl-version.c`, `deskrawl-version.def`,
`build-pointer.sh`, and `test-pointer.sh` are original GameBridge project code,
Copyright (C) 2026 GameBridge contributors, licensed under GPL-3.0-or-later.
The full license is the repository's `LICENSE`; distribute that license and
corresponding source with the GameBridge source release.

This implementation does not incorporate the unlicensed ptrshim research source
or its patch. The historical `ptrshim-source.json` and `ptrshim-deskrawl.patch`
remain provenance for an earlier local-only experiment, and are not inputs to the
bundled component. No license grant is claimed for that upstream experiment.

Implementation references are the public Windows API contracts:

- https://learn.microsoft.com/en-us/windows/win32/winmsg/getmsgproc
- https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-pointer_info
- MinGW-w64 `winver.h` interface declarations for version API signatures.

Build with `scripts/compatibility/build-pointer.sh`. The output is a Windows
x86-64 `version.dll`. It is linked with `-nostdlib`, uses its own DLL entrypoint,
and imports only KERNEL32 and USER32 from the supported Wine engine. It does not
link a C runtime, GCC runtime, or libwinpthread. Windows API declarations and
import libraries come from MinGW-w64; its license and contributor notices are
included beside this file as `MINGW-COPYING.txt` and `MINGW-AUTHORS.txt`.

## Activation, scope and rollback

Only an executable whose basename is exactly `Deskrawl.exe` (case insensitive)
activates the pointer compatibility code. Other processes receive ordinary
system version API forwarding. Install in this game's directory and use only
Wine's `AppDefaults\\Deskrawl.exe\\DllOverrides` override for `version`.

The supported target is 64-bit Deskrawl with the tested Wine 11 engine. The DLL
must be loaded at application startup. It replaces four pointer API entrypoints
in process memory with a 14-byte x86-64 jump, before application threads start;
it never changes Wine binaries on disk. Hook installation is lazy on each thread
that calls `EnableMouseInPointer(TRUE)`. The shim represents one synthetic mouse,
not physical touch or pen devices. Pointer information is valid during the
synchronous pointer callback. Device/display rectangles use identical pixel
coordinates for the synthetic device. Original mouse messages are retained.

The module is pinned for process lifetime because patched APIs reference its
code. To roll back, exit the game, remove only this installed DLL and the game's
version override, then restart. Calling `EnableMouseInPointer(FALSE)` suppresses
synthetic events immediately for the process. No game files or saves are edited.

## Validation

Set `WINE_BINARY` to the supported Wine executable and run
`scripts/compatibility/test-pointer.sh`. It creates and uses only
`build/compatibility/test-prefix`, regardless of the caller's `WINEPREFIX`.
The regression exercises real Windows message queues and APIs, checking:

- exactly two pointer events for queued mouse DOWN/UP despite repeated
  `PM_NOREMOVE` calls;
- synchronous queried flags and button change state;
- pointer type, target window, screen coordinates and valid device rectangles;
- system version forwarding;
- disabled input, an unrelated executable, and rollback after DLL removal.

Harness success does not substitute for a fresh interactive game acceptance
run with this independently implemented binary.
