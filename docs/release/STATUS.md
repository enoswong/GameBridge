# Public release status

The application source is prepared for a public Whisky fork. Source publication and binary runtime distribution are separate deliverables.

The accepted local preview embeds a Wine 11.0 / DXMT 0.80 research payload marked internalOnly. Do not upload this payload or the local preview ZIP to a public Release until exact corresponding runtime/dependency sources, patches, build scripts and notices are assembled and reviewed. Do not bypass the existing Release packaging gate or relabel the manifest.

Outstanding binary release work:

- Exact source/provenance inventory for Wine, patched DXMT and all included dependent libraries; resolve inherited source metadata inconsistencies.
- Corresponding source archives, applicable notices and build/installation scripts, including the bundled cabextract binary.
- Production catalog signing and renewal/update process, independent of macOS app signing.
- Developer ID signing, notarization, distribution artifact verification and clean-device validation.
- Check official installer origin/signatures and maintain pinned manifests when publisher downloads change.

The source exporter intentionally omits research binaries, Wine/Steam prefixes, local evidence logs, business requirements documents, personal paths and the earlier unlicensed reference pointer patch. It includes the independently authored pointer implementation and native transparency bridge.

A future Release should state prerequisites (supported Apple Silicon macOS, Rosetta, local APFS storage), installer terms, supported/tested behavior and limitations. A prerelease label does not remove the internalOnly distribution gate.
