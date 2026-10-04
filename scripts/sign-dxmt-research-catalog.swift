// SPDX-License-Identifier: GPL-3.0-or-later
// Developer-only follow-up catalog. Requires independently prepared DXMT hashes.
// Ephemeral signing key, no private key persisted; not a production trust root.
import Foundation
import CryptoKit
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let envelope = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("catalog.json"))) as! [String: Any]
var catalog = try JSONSerialization.jsonObject(with: Data(base64Encoded: envelope["payload"] as! String)!) as! [String: Any]
var engines = catalog["engines"] as! [[String: Any]]
var dxmt = engines[0]
dxmt["id"] = "internal-wine11-dxmt080-1"
dxmt["version"] = "11.0-dxmt0.80-research.1"
dxmt["backends"] = ["dxmt"]
dxmt["dxmtFileSHA256s"] = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("dxmt-hashes.json")))
engines.append(dxmt)
catalog["engines"] = engines
catalog["revision"] = 2
catalog["issuedAt"] = Date().timeIntervalSince1970 - 60
catalog["expiresAt"] = Date().timeIntervalSince1970 + 86400
let payload = try JSONSerialization.data(withJSONObject: catalog, options: [.sortedKeys])
let key = Curve25519.Signing.PrivateKey()
let signed: [String: Any] = ["keyID": "local-dxmt-research", "payload": payload.base64EncodedString(), "signature": try key.signature(for: payload).base64EncodedString()]
try JSONSerialization.data(withJSONObject: signed).write(to: directory.appendingPathComponent("dxmt-catalog.json"), options: .withoutOverwriting)
try JSONSerialization.data(withJSONObject: ["local-dxmt-research": key.publicKey.rawRepresentation.base64EncodedString()]).write(to: directory.appendingPathComponent("dxmt-public-keys.json"), options: .withoutOverwriting)
