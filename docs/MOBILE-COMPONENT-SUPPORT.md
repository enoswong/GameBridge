# GameBridge mobile component support

Status: research, not a production update channel yet.

## Independent release boundaries

The native iOS application, signed app extensions, Wine/FEX/DXMT native code and JIT/security policy remain in the signed app and require an app build when changed. The supported Steam desktop seed is provisioned into the isolated Windows prefix from Valve's own CDN. Steam's client self-update remains enabled. Do not publish modified Valve or Microsoft DLLs.

The support channel is a data-only signed catalog. It can change the three allowed Valve archive versions, exact sizes, SHA-256 hashes and coherent steamclient64 identity without changing native code. It cannot execute commands, select arbitrary download hosts or replace a user's updated client. It is intentionally not a general-purpose remote code loader. Other component families need a reviewed installer implementation before they can be added to the protocol.

At startup, the installer checks the executable and minimum client/GUI module presence. On first install or missing seed components, it stages and verifies all three official archives, rejects conflicting existing cohort files, adds only missing files and publishes steam.exe last. Interrupted repairs are marked pending. This is not a complete Steam installer or a guarantee of self-update/CEF success. A newer/incompatible partial install must be repaired by the official updater or reviewed separately; do not mix versions. The known UI module can be present but still fail because of imports or architecture.

## Configure once

On the maintainer's Mac, from the source root:

    mkdir -p "$HOME/.gamebridge-support"
    chmod 700 "$HOME/.gamebridge-support"
    swiftc -parse-as-library WhiskyKit/Sources/GameBridgeCore/MobileSupportCatalog.swift \
      scripts/mobile-support-signer.swift -o "$HOME/.gamebridge-support/signer"
    "$HOME/.gamebridge-support/signer" init-key "$HOME/.gamebridge-support/ed25519.key"

Keep the private key offline, never in GitHub or a chat, and back it up securely. Only the printed key ID and base64 public key may be added to the Xcode build settings GAMEBRIDGE_SUPPORT_KEY_ID and GAMEBRIDGE_SUPPORT_PUBLIC_KEY. The app's Info.plist expands these. An already installed build needs one native update to obtain the trust anchor and support client. A build with both settings absent uses the built-in official pins instead.

The fixed remote data URL is:

https://raw.githubusercontent.com/enoswong/GameBridge/refs/heads/support-catalog/mobile/steam-seed.json

Start from mobile/support/steam-seed.template.json. Set issuedAt/expiresAt to actual Unix seconds, use an increasing integer revision, and keep expiry within 31 days. Verify all official archive bytes and coherent file inventory before signing. Example:

    "$HOME/.gamebridge-support/signer" sign "$HOME/.gamebridge-support/ed25519.key" \
      /path/to/reviewed-payload.json /path/to/steam-seed.json

Publish only the signed envelope to the support-catalog branch at mobile/steam-seed.json. A template with zero dates is not a valid catalog. The verifier checks Ed25519, schema, scope, package names, expiry, monotonic revision and equal-revision payload identity. An accepted catalog is cached locally for offline use until it expires. Once a remote revision has been accepted, an expired or invalid cache blocks a new repair rather than silently reverting to older pins. A new unconfigured install may use the shipped verified pins.

## Reporting and triage

Before preparation, after preparation/failure and when a session ends, store a small known-module PE status report locally. The Wine log hook additionally collects bounded, deduplicated module-not-found/load-failed DLL basenames, even when live log display is suppressed. It does not capture raw paths, Steam passwords, account identifiers, tokens, pairing files or full logs. Not every graphical fatal dialog emits a parsable log; static presence cannot prove the runtime loader can load a file.

The diagnostics disclosure exposes the local report and a GitHub issue link with the module status and failure codes prefilled. The user explicitly reviews and submits the issue; no automatic network telemetry, service credentials or private report endpoint is configured. GitHub issues may be public. Maintainers triage missing versus load-failed, reproduce, identify an official supported package, verify it, sign a new coherent catalog revision and publish the envelope. Do not automatically approve unknown modules based on a report.

Future optional automatic reporting must be consent-based, bounded, rate-limited, redacted, and use a separate authenticated ingestion service and retention policy; app errors must not depend on that service. Current reporting is local plus explicit user submission only.

## First physical result

iPhone 17 / iOS 27.3 displayed the Wine desktop and Valve's Steam fatal dialog for bin/vgui2_s.dll. CI verified the official x86 module (3,266,200 bytes) is inside the pinned bins_win32 archive. This establishes the module source, not whether the user's device lacks the file or fails to load an existing copy. New support implementation, next signed installation and Steam desktop startup still require validation. No public IPA is published.
