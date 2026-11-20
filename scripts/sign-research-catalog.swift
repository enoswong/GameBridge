// SPDX-License-Identifier: GPL-3.0-or-later
// Developer-only internal probe catalog; private key exists only in this process.
import Foundation
import CryptoKit
guard let inputPath = CommandLine.arguments.dropFirst().first else {
    throw CocoaError(.fileReadInvalidFileName)
}
let directory = URL(fileURLWithPath: inputPath)
let metadataData = try Data(contentsOf: directory.appendingPathComponent("normalization.json"))
guard let metadata = try JSONSerialization.jsonObject(with: metadataData) as? [String: Any],
      let archiveHash = metadata["archiveSHA256"],
      let archiveBytes = metadata["archiveBytes"],
      let unpackedBytes = metadata["unpackedBytes"],
      let sourceHash = metadata["sourceSHA256"] else {
    throw CocoaError(.fileReadCorruptFile)
}
let manifest: [String: Any] = [
    "schemaVersion": 1, "id": "internal-wine11-probe-1", "version": "11.0-research.1",
    "cpuMode": "rosettaX86_64", "minimumMacOS": "15.0.0", "backends": ["wineD3D"],
    "synchronizationModes": ["none"], "winePath": "Libraries/Wine/bin/wine",
    "wineserverPath": "Libraries/Wine/bin/wineserver",
    "archiveSHA256": archiveHash, "archiveBytes": archiveBytes,
    "unpackedBytes": unpackedBytes,
    "sources": [["name": "community assembly (not a source rebuild)", "url": "https://github.com/frankea/Whisky",
                 "revision": "3abfbae945e3400caaa13cf2e78fe5a187a1405b",
                     "license": "GPL-3.0; component license audit pending"]],
    "patchSHA256s": [String](), "toolchain": "Upstream prebuilt; compiler and dependency source closure not verified",
    "dependencySHA256s": ["upstream-archive": sourceHash],
    "testReferences": [String](), "distribution": "internalOnly"
]
let now = Date().timeIntervalSince1970
let catalog: [String: Any] = ["schemaVersion": 1, "revision": 1, "issuedAt": now - 60,
                              "expiresAt": now + 86400, "engines": [manifest], "revokedEngineIDs": [String]()]
let payload = try JSONSerialization.data(withJSONObject: catalog, options: [.sortedKeys])
let key = Curve25519.Signing.PrivateKey()
let envelope: [String: Any] = ["keyID": "local-research-only", "payload": payload.base64EncodedString(),
                              "signature": try key.signature(for: payload).base64EncodedString()]
try JSONSerialization.data(withJSONObject: envelope, options: [
    .sortedKeys]).write(to: directory.appendingPathComponent("catalog.json"), options: .withoutOverwriting)
let trustKeys = ["local-research-only": key.publicKey.rawRepresentation.base64EncodedString()]
try JSONSerialization.data(withJSONObject: trustKeys, options: [.sortedKeys]).write(
    to: directory.appendingPathComponent("public-keys.json"), options: .withoutOverwriting
)
print("Created ephemeral internal-only catalog. No private key persisted.")
