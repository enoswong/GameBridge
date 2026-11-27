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
        if args.count == 4 && args[0] == "sign" {
            let keyURL = URL(fileURLWithPath: args[1])
            let values = try keyURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink == false else {
                throw CocoaError(.fileReadNoPermission)
            }
            let attrs = try FileManager.default.attributesOfItem(atPath: keyURL.path)
            guard let mode = attrs[.posixPermissions] as? NSNumber, mode.intValue & 0o077 == 0 else {
                throw CocoaError(.fileReadNoPermission)
            }
            let key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(contentsOf: keyURL))
            let payload = try Data(contentsOf: URL(fileURLWithPath: args[2]))
            guard payload.count <= 40 * 1024 else { throw MobileSupportCatalog.Failure.invalidCatalog }
            let envelope = try JSONSerialization.data(withJSONObject: [
                "keyID": keyID(key), "payload": payload.base64EncodedString(),
                "signature": key.signature(for: payload).base64EncodedString()
            ], options: [.sortedKeys])
            let verified = try MobileSupportCatalog.verify(envelope, keyID: keyID(key),
                publicKey: key.publicKey.rawRepresentation, now: Int(Date().timeIntervalSince1970))
            try envelope.write(to: URL(fileURLWithPath: args[3]), options: .withoutOverwriting)
            print("Signed and verified catalog revision \(verified.payload.revision)")
            return
        }
        print("Usage: mobile-support-signer init-key PRIVATE_KEY | sign PRIVATE_KEY PAYLOAD_JSON ENVELOPE_JSON")
        exit(2)
    }
}
