# GameBridge native performance: first device-validation milestone

Baseline: ec9932bc14465eafa5039641d84fd3e6eeba5681 (Universal validation 46019091069).
Keep the existing isolated Windows Steam client and its data unchanged. Native library is an explicit experimental route; no account or licence bypass, no new default backend until device evidence.

## Tasks and acceptance gates

1. Install the baseline in the original iPhone workspace using scripts/upgrade-iphone-steam-support.sh. Verify Chinese menu text (not store artwork). Confirm font installation and NLS loading; report any remaining fallback issue. Do not delete the application or prefix.
2. Import the x64 smoke probe in the native library as a standalone program. Record first Win32 dialog and second D3D11 device-creation result separately. A device-creation success does not prove hardware acceleration or frame presentation. If first dialog fails, investigate executable launch/Wine/FEX; if second fails, investigate D3D11/DXMT, not Steam.
3. Compare independent sessions for the same device/OS/build and fixed display resolution: direct launch, Steam CPU baseline, GPU-only experiment, V8-only experiment. Keep both experiments off by default. End the session between trials. Run one cold and two warm repeats; do not compare multi-session logs. Record first visible window, peak footprint, compression, guard-page failures, host-PC reports, and actual frames/interactive time where measurable.
4. Test an owned small Windows game: direct executable only if it supports standalone operation; otherwise use the legitimate Steam authorization path. Require game window, 10 minutes of interaction, working controls/audio and save/reopen. A process spawn is not a playable-game pass.
5. Before selecting a backend automatically, collect repeatable frame-time p50/p95, 1% low FPS, peak memory, thermal state and crashes at matched resolution/settings. Promote a profile only if it meets the stability gates and beats the baseline. Do not remove JIT guard-page protection simply to suppress an error.
6. Alternative engine spike: evaluate upstream Porthole and Box64/iOS separately, pin versions and review licences and security. Do not claim engine interchangeability until a working adapter has been demonstrated. No main merge or release in this milestone.

## Offline session evidence

`python3 scripts/audit-mobile-session.py /path/to/madeira-log.txt --game GameBridge-native-smoke-x64.exe`

Exports only numeric/boolean/status fields, not paths or account information. A spawn marker does not prove successful process initialization. Missing fields are not measured; false game observation means not seen (or no expected name supplied). Repeated absent-config markers flag potentially mixed sessions; this heuristic does not prove a log contains just one session. The GPU flag records a request, not confirmed Metal execution.

`python3 scripts/test-mobile-session-audit.py` — four regression tests.

## Smoke probe build

Source: tests/mobile/native-smoke-x64.c. With an x86_64 MinGW toolchain:

```sh
x86_64-w64-mingw32-gcc -O2 -ffreestanding -fno-stack-protector -nostdlib -Wl,-e,mainCRTStartup -mwindows tests/mobile/native-smoke-x64.c -lkernel32 -luser32 -o GameBridge-native-smoke-x64.exe
```

Alternatively use Clang targeting x86_64-pc-windows-msvc and lld-link with import libraries for kernel32 (ExitProcess, LoadLibraryW, GetProcAddress) and user32 (MessageBoxW), no CRT. The D3D11 import is dynamic so the first dialog can be shown even if D3D11 is missing.

Device validation and FPS measurement remain open. This milestone does not rewrite FEX, add a second engine, or enable experimental acceleration by default.
