// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public enum PortableWindowsImportReader {
    public struct Imports {
        public let architecture: String
        public let libraries: Set<String>
    }

    private enum FormatError: Error {
        case invalidHeader, invalidImportTable, oversizedImage
    }

    public static func read(_ file: URL) throws -> Imports {
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 256 * 1024 * 1024 else { throw FormatError.oversizedImage }
        let image = try Image(Data(contentsOf: file, options: .alwaysMapped))
        let regular = try image.imports(directory: 1, delayed: false)
        let delayed = try image.imports(directory: 13, delayed: true)
        return Imports(architecture: image.architecture, libraries: regular.union(delayed))
    }

    private struct Section {
        let virtualAddress: Int
        let rawOffset: Int
        let rawSize: Int
    }

    private struct Image {
        let data: Data
        let architecture: String
        let imageBase: UInt64
        let directoryStart: Int
        let directoryCount: Int
        let sections: [Section]

        init(_ data: Data) throws {
            self.data = data
            guard data.u16(0) == 0x5a4d, let header = data.u32(0x3c),
                  data.u32(header) == 0x4550, let magic = data.u16(header + 24),
                  let machine = data.u16(header + 4), let sectionCount = data.u16(header + 6),
                  let optionalSize = data.u16(header + 20), (1...96).contains(sectionCount) else {
                throw FormatError.invalidHeader
            }
            let optional = header + 24
            let directoryOffset: Int
            switch (machine, magic) {
            case (0x14c, 0x10b):
                architecture = "x86"
                directoryOffset = 96
                imageBase = UInt64(data.u32(optional + 28) ?? 0)
            case (0x8664, 0x20b):
                architecture = "x64"
                directoryOffset = 112
                let low = UInt64(data.u32(optional + 24) ?? 0)
                let high = UInt64(data.u32(optional + 28) ?? 0)
                imageBase = low | (high << 32)
            default:
                throw FormatError.invalidHeader
            }
            guard optionalSize >= directoryOffset, let count = data.u32(optional + directoryOffset - 4) else {
                throw FormatError.invalidHeader
            }
            directoryStart = optional + directoryOffset
            directoryCount = min(count, (optionalSize - directoryOffset) / 8)
            sections = try Self.readSections(data, at: optional + optionalSize, count: sectionCount)
        }

        private static func readSections(_ data: Data, at start: Int, count: Int) throws -> [Section] {
            guard start + count * 40 <= data.count else { throw FormatError.invalidHeader }
            return try (0..<count).map { index in
                let header = start + index * 40
                guard let address = data.u32(header + 12), let rawSize = data.u32(header + 16),
                      let rawOffset = data.u32(header + 20) else { throw FormatError.invalidHeader }
                return Section(virtualAddress: address, rawOffset: rawOffset, rawSize: rawSize)
            }
        }

        func imports(directory index: Int, delayed: Bool) throws -> Set<String> {
            guard index < directoryCount, let address = data.u32(directoryStart + index * 8),
                  let size = data.u32(directoryStart + index * 8 + 4), address != 0 else { return [] }
            let step = delayed ? 32 : 20
            guard size >= step, let start = offset(address) else { throw FormatError.invalidImportTable }
            var result = Set<String>()
            for index in 0..<min(size / step, 4096) {
                let row = start + index * step
                guard let rawName = data.u32(row + (delayed ? 4 : 12)) else {
                    throw FormatError.invalidImportTable
                }
                if rawName == 0 { return result }
                let name = try nameAddress(rawName, row: row, delayed: delayed)
                guard let location = offset(name), let library = data.importName(at: location) else {
                    throw FormatError.invalidImportTable
                }
                result.insert(library)
            }
            throw FormatError.invalidImportTable
        }

        private func nameAddress(_ rawName: Int, row: Int, delayed: Bool) throws -> Int {
            guard delayed, let attributes = data.u32(row), attributes & 1 == 0 else { return rawName }
            guard UInt64(rawName) >= imageBase else { throw FormatError.invalidImportTable }
            return Int(UInt64(rawName) - imageBase)
        }

        private func offset(_ address: Int) -> Int? {
            for section in sections where address >= section.virtualAddress {
                let difference = address - section.virtualAddress
                if difference < section.rawSize, section.rawOffset + difference < data.count {
                    return section.rawOffset + difference
                }
            }
            return nil
        }
    }
}

private extension Data {
    func u16(_ offset: Int) -> Int? {
        guard offset >= 0, offset + 2 <= count else { return nil }
        return Int(self[offset]) | (Int(self[offset + 1]) << 8)
    }

    func u32(_ offset: Int) -> Int? {
        guard let low = u16(offset), let high = u16(offset + 2) else { return nil }
        return low | (high << 16)
    }

    func importName(at offset: Int) -> String? {
        let bytes = self[offset..<Swift.min(offset + 260, count)]
        guard let end = bytes.firstIndex(of: 0), end > offset else { return nil }
        let name = bytes[..<end]
        guard name.allSatisfy({ (32...126).contains($0) && ![47, 58, 92].contains($0) }) else { return nil }
        return String(bytes: name, encoding: .ascii)?.lowercased()
    }
}
