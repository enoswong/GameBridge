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

## GitHub publishing workflow

The dedicated support-catalog branch now contains a publication validation workflow. It uses a fixed verifier source revision, checks the signed envelope against public trust.json, compares the previous published revision and trust identity, then fetches the three Valve packages and verifies their hashes and coherent inventory. This is an Actions check on push/PR, not a configured branch protection rule; clients independently enforce their embedded trust anchor. No signing key is present on the branch or in Actions secrets.

For initial provisioning, on the maintainer's Mac use a separate clean checkout of gamebridge-universal (preserve any existing Xcode edits in GameBridge-iOS):

    bash scripts/init-mobile-support-channel.sh

This generates the key locally if absent, refuses to overwrite an existing initial release, verifies the official archives and prepares only steam-seed.json and trust.json under ~/.gamebridge-support/release-1. Share or publish only those two files, never the key or its parent directory. The initial revision is 1 and expires in 30 days. The public key must still be embedded in the native app once. The existing installed research build cannot consume this catalog until updated.

For each subsequent release, use the reviewed payload with a higher revision and fresh dates:

    bash scripts/prepare-mobile-support-release.sh /path/to/reviewed-payload.json /path/to/new-public-output

Publish both public JSON files together to the support-catalog branch, preferably through a PR with the validation check passing. A 30-day renewal requires the maintainer's offline signature even when package pins remain unchanged. Do not rotate trust on this branch alone. The workflow detects invalid/deleted metadata, unchanged-revision content changes and trust replacement relative to the previous commit. This does not automate discovering newer official packages or certify their runtime compatibility.

The repository is public and its default branch is main (verified through repository metadata). Apps do not need a GitHub token to fetch the signed raw catalog. The current support-catalog branch contains no active trust.json or steam-seed.json.

To create an atomic review branch containing both public files from the maintainer's existing Git login:

    bash scripts/publish-mobile-support-review.sh --check "$HOME/.gamebridge-support/release-1"
    bash scripts/publish-mobile-support-review.sh --push-review "$HOME/.gamebridge-support/release-1"

The helper clones the current support-catalog into an isolated temporary directory, rejects a trust change or non-increasing revision, verifies the signed envelope and official archive contents, and pushes only two public JSON files on a new review branch. It does not read the private key, push directly to the live branch, force push or merge. Review and merge the catalog PR only after the publication workflow passes. Existing Git authentication and author identity are required. The helper's real authenticated push has not been exercised.

## Renewal and health monitoring

To renew the same reviewed package cohort, copy the latest published mobile/steam-seed.json locally, then run:

    bash scripts/renew-mobile-support-channel.sh /path/to/current/steam-seed.json "$HOME/.gamebridge-support/next-public-release"

The local signer authenticates the previous envelope against the existing maintainer key, even if the old envelope has expired, and prepares a higher revision with a new 30-day validity period. The ordinary release tool re-downloads and verifies all pinned packages before signing. Historical verification is confined to the local renewal tool; the iPhone still rejects expired catalogs. Review the current branch revision before publishing both public JSON files together. No production signing key leaves the Mac.

The proposed SupportCatalogMonitor workflow runs daily at 02:20 UTC (10:20 Hong Kong/Singapore time) after it is merged to the default branch, or through workflow_dispatch when available. It checks the published metadata signature against the branch's public trust file, expiry and official package bytes. It creates or updates one fixed-title GitHub issue for failures or expiry within seven days and closes it on verified recovery. This is an operational health check, not independent proof that the branch trust file matches a particular installed app's embedded key. No private key, binary upload or automatic catalog publishing is involved. The workflow is not active on the default branch yet and has not exercised real issue creation.

## iPhone update and repair controls

The research home now has separate **Check GitHub support updates** and **Prepare / repair Steam** buttons. The former forces a signed metadata refresh and displays the verified revision (network or valid cache); it never changes guest files. The latter runs the normal preparation path without launching Wine or requesting JIT. An intact supported client checks for updates before launch using a 24-hour successful-verification cache; a missing or interrupted installation forces a new check. An unavailable catalog cannot stop an otherwise intact client from attempting its normal launch. Repair still refuses mixed-version replacement.

Minimum PE presence checks now distinguish the known x86 desktop layout from the x64 layout. An x64 GUI DLL does not satisfy a missing x86 GUI DLL. The x86 seed checks Steam executable, GUI, client, SteamUI and filesystem architecture. These are limited known layouts, not proof that new Steam releases or transitive dependencies can load. Complete native and physical-device acceptance remain required.

## Existing physical research installation

A separate maintainer-side repair tool can inspect a local copy of the stopped device's isolated Steam Big Picture folder. Copy only that folder locally using Files/Finder file sharing (do not upload it; it may contain account data). Run:

    python3 scripts/prepare-iphone-steam-repair.py \
      --client-dir "/path/to/copied/Steam Big Picture" \
      --output "$HOME/Desktop/GameBridge-missing-only"

It downloads the three fixed official archive pins, validates size/hash, safe archive paths, cohort identity and architecture, compares all existing matching cohort files, and exports only absent files. It never changes the copied client or the phone. Import only the missing files to the original matching stopped installation, preserving relative paths; do not replace existing files or import if the device changed since the snapshot. A version conflict stops the process. A present DLL that still cannot load requires further dependency diagnostics; the tool cannot prove Steam login. The output contains Valve binaries for local use, not redistribution.

The original iPhone project from revision 6787eca may also be updated without rebuilding the pinned native engines. From a separate current development checkout:

    bash scripts/update-existing-iphone-project.sh --check "/absolute/path/to/original/madeira-workspace"

Close Xcode before applying. Only if the check passes:

    bash scripts/update-existing-iphone-project.sh --apply "/absolute/path/to/original/madeira-workspace"

The helper computes the exact old-to-new overlay delta against the pinned upstream commit, accepts only reviewed app Swift/plist/project-file additions or modifications, checks patch context, and backs up changed files before applying. It refuses conflicts; it does not reset, overwrite signing entitlements or rebuild native artifacts. Xcode still needs to compile/re-sign/install the updated app, retaining its original identity. Use the usual full isolated build for any future native engine change. The migrated original workspace is not a clean checkout accepted by the full preparation script. A CI fixture tests preservation of simulated Team and engine-cache changes; actual local Xcode changes may differ.

## One-time activation on the existing iPhone project

The frozen full native build at b373669 succeeded (run 45930035353, Xcode 27.1), and the original-to-new source-only migration and missing-only recovery tests passed in 45933844455. Renewal and regular validation passed in 45938627280. None of these establishes that an installed iPhone can load Steam.

After generating the initial signed release locally and updating the original Xcode workspace with the checked source-only migration, use:

    bash scripts/configure-iphone-support-trust.sh --check "/path/to/original/madeira-workspace" "$HOME/.gamebridge-support/release-1"
    bash scripts/configure-iphone-support-trust.sh --apply "/path/to/original/madeira-workspace" "$HOME/.gamebridge-support/release-1"

Close Xcode before applying. The tool verifies public-key identity and the signed envelope, embeds only two public values in the research Info.plist, and preserves the original file in a local backup. It refuses an absent overlay or different embedded key. It reads no private key and changes no signing entitlements, project settings or native runtime artifacts. Rebuild and sign the app once using the existing device setup. This local plist edit must be preserved in future source migrations. The support-catalog branch still needs both public JSON files published; merely embedding a key does not activate the remote channel.

A separate operations-only PR #3 proposes default-branch monitoring and issue triage without merging native source or distributing any binaries. It pins the previously validated verifier revision. No merge or live issue/scheduled-job execution is claimed.

## Reporting and triage

Before preparation, after preparation/failure and when a session ends, store a small known-module PE status report locally. The Wine log hook additionally collects bounded, deduplicated module-not-found/load-failed DLL basenames, even when live log display is suppressed. It does not capture raw paths, Steam passwords, account identifiers, tokens, pairing files or full logs. Not every graphical fatal dialog emits a parsable log; static presence cannot prove the runtime loader can load a file.

The diagnostics disclosure exposes the local report and a GitHub issue link with the module status and failure codes prefilled. The user explicitly reviews and submits the issue; no automatic network telemetry, service credentials or private report endpoint is configured. GitHub issues may be public. Maintainers triage missing versus load-failed, reproduce, identify an official supported package, verify it, sign a new coherent catalog revision and publish the envelope. Do not automatically approve unknown modules based on a report.

A proposed SupportIssueTriage workflow on the development branch assigns a fixed set of labels (iOS, component-report, missing-module, loader-failure, Steam client, needs-triage) to matching newly opened or reopened issues. Issue content is untrusted; no shell execution, automatic binary selection or publication. The GitHub issues event requires this workflow on the default branch before it operates. It has not been merged or tested on a live user issue. Repository Watch notifications remain the manual monitoring option.

Future optional automatic reporting must be consent-based, bounded, rate-limited, redacted, and use a separate authenticated ingestion service and retention policy; app errors must not depend on that service. Current reporting is local plus explicit user submission only.

## First physical result

iPhone 17 / iOS 27.3 displayed the Wine desktop and Valve's Steam fatal dialog for bin/vgui2_s.dll. CI verified the official x86 module (3,266,200 bytes) is inside the pinned bins_win32 archive. This establishes the module source, not whether the user's device lacks the file or fails to load an existing copy. New support implementation, next signed installation and Steam desktop startup still require validation. No public IPA is published.
