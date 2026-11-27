// SPDX-License-Identifier: GPL-3.0-or-later
// Run on the maintainer's Mac. Never commit or upload the private key.
import Foundation
import CryptoKit
import Darwin

@main
struct MobileCatalogSigner {
    static func keyID(_ key: Curve25519.Signing.PrivateKey) -> String {
        SHA256.hash(data: key.publicKey.rawRepresentation)
            .prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.count == 2 && args[0] == "init-key" {
            let key = Curve25519.Signing.PrivateKey()
            // Exclusively create a local 0600 key; never overwrite or follow a link.
            let descriptor = Darwin.open(args[1], O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard descriptor >= 0 else { throw CocoaError(.fileWriteFileExists) }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            try handle.write(contentsOf: key.rawRepresentation)
            try handle.synchronize()
            try handle.close()
            print("GAMEBRIDGE_SUPPORT_KEY_ID=" + keyID(key))
            print("GAMEBRIDGE_SUPPORT_PUBLIC_KEY=" + key.publicKey.rawRepresentation.base64EncodedString())
            return
        }
        if args.count == 2 && args[0] == "public-key" {
            let key = try Curve25519.Signing.PrivateKey(
                rawRepresentation: Data(contentsOf: URL(fileURLWithPath: args[1])))
            let trust = ["keyID": keyID(key), "publicKey": key.publicKey.rawRepresentation.base64EncodedString()]
            let data = try JSONSerialization.data(withJSONObject: trust, options: [.sortedKeys, .prettyPrinted])
            FileHandle.standardOutput.write(data)
            return
        }
        if args.count == 4 && args[0] == "verify" {
            guard let publicKey = Data(base64Encoded: args[2]), publicKey.count == 32 else {
                throw MobileSupportCatalog.Failure.invalidCatalog
            }
            let data = try Data(contentsOf: URL(fileURLWithPath: args[3]))
            let verified = try MobileSupportCatalog.verify(data, keyID: args[1], publicKey: publicKey,
                now: Int(Date().timeIntervalSince1970))
            print("Verified support catalog revision \(verified.payload.revision)")
            return
        }
        if args.count == 4 && args[0] == "renew-payload" {
            try renewPayload(keyPath: args[1], envelopePath: args[2], outputPath: args[3])
            return
        }
        if args.count == 4 && args[0] == "sign" {
            try sign(keyPath: args[1], payloadPath: args[2], outputPath: args[3])
            return
        }
        print("Usage: mobile-support-signer init-key PRIVATE_KEY | sign PRIVATE_KEY PAYLOAD_JSON ENVELOPE_JSON")
        print("       mobile-support-signer verify KEY_ID PUBLIC_KEY_BASE64 ENVELOPE_JSON")
        print("       mobile-support-signer public-key PRIVATE_KEY")
        print("       mobile-support-signer renew-payload PRIVATE_KEY PREVIOUS_ENVELOPE OUTPUT_PAYLOAD")
        exit(2)
    }

    private static func sign(keyPath: String, payloadPath: String, outputPath: String) throws {
        let keyURL = URL(fileURLWithPath: keyPath)
        let values = try keyURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink == false else {
            throw CocoaError(.fileReadNoPermission)
        }
        let attrs = try FileManager.default.attributesOfItem(atPath: keyURL.path)
        guard let mode = attrs[.posixPermissions] as? NSNumber, mode.intValue & 0o077 == 0 else {
            throw CocoaError(.fileReadNoPermission)
        }
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(contentsOf: keyURL))
        let payload = try Data(contentsOf: URL(fileURLWithPath: payloadPath))
        guard payload.count <= 40 * 1024 else { throw MobileSupportCatalog.Failure.invalidCatalog }
        let envelope = try JSONSerialization.data(withJSONObject: [
            "keyID": keyID(key), "payload": payload.base64EncodedString(),
            "signature": key.signature(for: payload).base64EncodedString()
        ], options: [.sortedKeys])
        let verified = try MobileSupportCatalog.verify(envelope, keyID: keyID(key),
            publicKey: key.publicKey.rawRepresentation, now: Int(Date().timeIntervalSince1970))
        try envelope.write(to: URL(fileURLWithPath: outputPath), options: .withoutOverwriting)
        print("Signed and verified catalog revision \(verified.payload.revision)")
    }

    /// Renewal accepts expired historical metadata only after authenticating it at its original issue time.
    /// This is a maintainer-only operation; the app still rejects expired catalogs.
    private static func renewPayload(keyPath: String, envelopePath: String, outputPath: String) throws {
        let key = try Curve25519.Signing.PrivateKey(
            rawRepresentation: Data(contentsOf: URL(fileURLWithPath: keyPath)))
        let data = try Data(contentsOf: URL(fileURLWithPath: envelopePath))
        guard data.count <= MobileSupportCatalog.maxEnvelopeBytes else {
            throw MobileSupportCatalog.Failure.invalidCatalog
        }
        let envelope = try JSONDecoder().decode(MobileSupportCatalog.Envelope.self, from: data)
        let previous = try JSONDecoder().decode(MobileSupportCatalog.Payload.self, from: envelope.payload)
        let now = Int(Date().timeIntervalSince1970)
        guard previous.issuedAt <= now, previous.revision < Int.max else {
            throw MobileSupportCatalog.Failure.invalidCatalog
        }
        _ = try MobileSupportCatalog.verify(data, keyID: keyID(key), publicKey: key.publicKey.rawRepresentation,
                                            now: previous.issuedAt)
        var payload = try JSONSerialization.jsonObject(with: envelope.payload) as? [String: Any] ?? [:]
        payload["revision"] = previous.revision + 1
        payload["issuedAt"] = now - 60
        payload["expiresAt"] = now + 30 * 86400
        let renewed = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        try renewed.write(to: URL(fileURLWithPath: outputPath), options: .withoutOverwriting)
        print("Prepared unsigned renewal revision \(previous.revision + 1); verify archives and sign separately.")
    }
}
