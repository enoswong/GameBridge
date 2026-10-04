// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Narrow USTAR format: regular files/directories only, no links, devices, PAX or GNU extensions.
/// Runtime packaging must materialize internal links before creating the signed archive.
public enum SafeTarExtractor {
    public static func extract(archive: URL, into root: URL, maximumBytes: UInt64) throws {
        let input = try FileHandle(forReadingFrom: archive)
        defer { try? input.close() }
        var total: UInt64 = 0
        var count = 0
        var seen = Set<String>()
        while true {
            let header = try readExactly(input, count: 512)
            if header.allSatisfy({ $0 == 0 }) {
                guard try readExactly(input, count: 512).allSatisfy({ $0 == 0 }) else { throw RuntimeError.invalidArchive("end marker") }
                while let padding = try input.read(upToCount: 65536), !padding.isEmpty {
                    guard padding.allSatisfy({ $0 == 0 }) else { throw RuntimeError.invalidArchive("trailing data") }
                }
                return
            }
            count += 1
            guard count <= 100_000 else { throw RuntimeError.invalidArchive("entry limit") }
            let bytes = Array(header)
            let checksum = try octal(bytes, 148..<156)
            let actual = bytes.enumerated().reduce(UInt64(0)) { $0 + UInt64((148..<156).contains($1.offset) ? 32 : $1.element) }
            guard checksum == actual, try text(bytes, 257..<263) == "ustar" else { throw RuntimeError.invalidArchive("header checksum or format") }
            let prefix = try text(bytes, 345..<500)
            var path = try text(bytes, 0..<100)
            if !prefix.isEmpty { path = prefix + "/" + path }
            let type = bytes[156]
            if type == 53 && path.hasSuffix("/") { path.removeLast() }
            try ManagedPath.validateRelative(path)
            guard seen.insert(path.lowercased()).inserted else { throw RuntimeError.invalidArchive("duplicate path") }
            guard type == 0 || type == 48 || type == 53 else { throw RuntimeError.invalidArchive("unsupported entry type") }
            let size = try octal(bytes, 124..<136)
            guard size <= maximumBytes - total else { throw RuntimeError.invalidArchive("unpacked size limit") }
            total += size
            let target = try ManagedPath.child(path, under: root)
            if type == 53 {
                guard size == 0 else { throw RuntimeError.invalidArchive("directory contains data") }
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            } else {
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                guard !FileManager.default.fileExists(atPath: target.path),
                      FileManager.default.createFile(atPath: target.path, contents: nil, attributes: [.posixPermissions: 0o600])
                else { throw RuntimeError.invalidArchive("conflicting entry") }
                let output = try FileHandle(forWritingTo: target)
                do {
                    var remaining = size
                    while remaining > 0 {
                        let chunk = try readExactly(input, count: Int(min(remaining, 1024 * 1024)))
                        try output.write(contentsOf: chunk)
                        remaining -= UInt64(chunk.count)
                    }
                    let mode = try octal(bytes, 100..<108)
                    try FileManager.default.setAttributes([.posixPermissions: mode & 0o111 != 0 ? 0o500 : 0o400], ofItemAtPath: target.path)
                    try output.synchronize()
                    try output.close()
                } catch { try? output.close(); throw error }
            }
            let padding = Int((512 - size % 512) % 512)
            if padding > 0 { _ = try readExactly(input, count: padding) }
        }
    }
    private static func readExactly(_ handle: FileHandle, count: Int) throws -> Data {
        var result = Data()
        while result.count < count {
            guard let chunk = try handle.read(upToCount: count - result.count), !chunk.isEmpty else { throw RuntimeError.invalidArchive("truncated") }
            result.append(chunk)
        }
        return result
    }
    private static func text(_ bytes: [UInt8], _ range: Range<Int>) throws -> String {
        let raw = bytes[range].prefix { $0 != 0 }
        guard let text = String(bytes: raw, encoding: .utf8) else { throw RuntimeError.invalidArchive("invalid text") }
        return text
    }
    private static func octal(_ bytes: [UInt8], _ range: Range<Int>) throws -> UInt64 {
        let value = try text(bytes, range).trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, value.utf8.allSatisfy({ (48...55).contains($0) }), let number = UInt64(value, radix: 8) else { throw RuntimeError.invalidArchive("invalid numeric field") }
        return number
    }
}
