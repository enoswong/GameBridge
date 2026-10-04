# Runtime provenance comparison — 2026-10-04

This is a binary provenance investigation, not redistribution clearance or a runtime compatibility test. No installed user prefix was accessed or changed.

## Verified inputs

- Community runtime: [frankea/Whisky v3.1.1](https://github.com/frankea/Whisky/releases/tag/v3.1.1), Libraries.tar.gz; SHA-256 `01f3a1b43b98065fe20c529c1023b61dd79a6d2ad93bba6040865f646481ccf3`.
- Candidate upstream: [Gcenx Wine 11.0_1](https://github.com/Gcenx/macOS_Wine_builds/releases/tag/11.0_1), wine-stable-11.0_1-osx64.tar.xz; downloaded bytes match GitHub's published SHA-256 `b50dc50ec7f41d58b115a6b685d4d1315ba3c797bd3aa0f49213f2703cb82388`.
- Community assembly recipe: [pinned script](https://github.com/frankea/Whisky/blob/3abfbae945e3400caaa13cf2e78fe5a187a1405b/scripts/assemble-runtime.sh). It consumes a v3.0.0 binary base and applies DXMT marker and winemetal changes; it is not the Wine compilation recipe.

## Comparison

Compare regular-file SHA-256 and length, or archive link kind and target, after stripping each archive's Wine directory prefix. Directories are excluded; modes and extended attributes are not compared.

| Result | Entries |
| --- | ---: |
| Identical | 3,267 |
| Changed regular files | 1,567 |
| Only in upstream | 1 |
| Only in community runtime | 4 |

The upstream-only entry is x86_64-windows/winemenubuilder.exe. Community-only entries are bin/wine64 and the three winemetal DLL/unix-library files.

Differences extend beyond the documented DXMT additions. For example, x86_64 user32.dll is 1,859,598 bytes upstream and 1,838,606 bytes in the community archive; x86_64 ntdll.dll is 716,814 and 693,262 bytes respectively. The user32.dll PE timestamps also differ. Thus the currently downloadable 11.0_1 archive cannot establish byte identity for the tested runtime. This does not establish the cause of the difference or imply that the upstream build is defective.

The current [MacPorts overlay Wine recipe](https://github.com/Gcenx/macports-wine/blob/123c1a96a26296918797ec6636b20d6e8a75ba83/emulators/wine-stable/Portfile) supplies Wine source checksums, two patches and dependency names. Its relationship to the exact community binaries and complete dependency revisions remains unverified. It must not be described as their confirmed build recipe.

## Release consequence

Keep the accepted payload internalOnly. Resolve the original build inputs or prepare a new runtime from pinned, reviewable inputs, then repeat clean setup and actual game acceptance before publishing a complete binary. Do not silently substitute the candidate upstream archive for the user-accepted engine.

This investigation does not complete dependency notices/source delivery, production catalog trust, Developer ID signing, notarization or clean-device validation. The public source preview remains available; no full binary release is claimed.
