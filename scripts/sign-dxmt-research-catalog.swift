// SPDX-License-Identifier: GPL-3.0-or-later
// Developer-only follow-up catalog. Requires independently prepared DXMT hashes.
// Ephemeral signing key, no private key persisted; not a production trust root.
import Foundation
import CryptoKit
guard let inputPath = CommandLine.arguments.dropFirst().first else {
    throw CocoaError(.fileReadInvalidFileName)
}
let directory = URL(fileURLWithPath: inputPath)
let envelopeData = try Data(contentsOf: directory.appendingPathComponent("catalog.json"))
guard let envelope = try JSONSerialization.jsonObject(with: envelopeData) as? [String: Any],
      let encodedPayload = envelope["payload"] as? String,
      let catalogData = Data(base64Encoded: encodedPayload),
      var catalog = try JSONSerialization.jsonObject(with: catalogData) as? [String: Any],
      var engines = catalog["engines"] as? [[String: Any]],
      var dxmt = engines.first else {
    throw CocoaError(.fileReadCorruptFile)
}
dxmt["id"] = "internal-wine11-dxmt080-1"
dxmt["version"] = "11.0-dxmt0.80-research.1"
dxmt["backends"] = ["dxmt"]
dxmt["dxmtFileSHA256s"] = try JSONSerialization.jsonObject(with: Data(
    contentsOf: directory.appendingPathComponent("dxmt-hashes.json")))
engines.append(dxmt)
catalog["engines"] = engines
catalog["revision"] = 2
catalog["issuedAt"] = Date().timeIntervalSince1970 - 60
catalog["expiresAt"] = Date().timeIntervalSince1970 + 86400
let payload = try JSONSerialization.data(withJSONObject: catalog, options: [.sortedKeys])
let key = Curve25519.Signing.PrivateKey()
let signed: [String: Any] = ["keyID": "local-dxmt-research", "payload": payload.base64EncodedString(),
    "signature": try key.signature(for: payload).base64EncodedString()]
try JSONSerialization.data(withJSONObject: signed).write(
    to: directory.appendingPathComponent("dxmt-catalog.json"), options: .withoutOverwriting)
let trustKeys = ["local-dxmt-research": key.publicKey.rawRepresentation.base64EncodedString()]
try JSONSerialization.data(withJSONObject: trustKeys).write(
    to: directory.appendingPathComponent("dxmt-public-keys.json"), options: .withoutOverwriting
)
