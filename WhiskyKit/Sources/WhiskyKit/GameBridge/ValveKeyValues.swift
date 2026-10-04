// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public enum SteamMetadataError: Error, Equatable, LocalizedError {
    case malformed, tooLarge, tooDeep, missingField(String), duplicateKey(String), unavailable(String), notWindowsExecutable
    public var errorDescription: String? {
        switch self {
        case .malformed: return "Steam metadata is incomplete or malformed. Try again after Steam finishes updating."
        case .tooLarge, .tooDeep: return "Steam metadata exceeds the supported size or nesting limit."
        case .missingField(let key): return "Steam metadata is missing \(key)."
        case .duplicateKey(let key): return "Steam metadata contains conflicting entries for \(key)."
        case .unavailable(let path): return "Steam library is unavailable: \(path)."
        case .notWindowsExecutable: return "Select the official Windows Steam.exe inside this environment. A native Mac client cannot validate Windows compatibility."
        }
    }
}
public indirect enum ValveValue: Equatable, Sendable {
    case string(String)
    case object(ValveKeyValues)
}
public struct ValveKeyValues: Equatable, Sendable {
    public let values: [String: ValveValue]
    public func string(_ key: String) throws -> String {
        guard case .string(let value) = values[key.lowercased()] else { throw SteamMetadataError.missingField(key) }
        return value
    }
    public func object(_ key: String) throws -> ValveKeyValues {
        guard case .object(let value) = values[key.lowercased()] else { throw SteamMetadataError.missingField(key) }
        return value
    }
    public static func parse(_ text: String) throws -> ValveKeyValues {
        guard text.utf8.count <= 4 * 1024 * 1024 else { throw SteamMetadataError.tooLarge }
        var parser = KeyValuesParser(characters: Array(text))
        return try parser.object(depth: 0, nested: false)
    }
    public static func read(_ url: URL) throws -> ValveKeyValues {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 4 * 1024 * 1024 + 1) ?? Data()
        guard data.count <= 4 * 1024 * 1024 else { throw SteamMetadataError.tooLarge }
        guard let text = String(data: data, encoding: .utf8) else { throw SteamMetadataError.malformed }
        return try parse(text)
    }
}
private struct KeyValuesParser {
    let characters: [Character]
    var position = 0
    var tokens = 0
    enum Token { case text(String), open, close }
    mutating func object(depth: Int, nested: Bool) throws -> ValveKeyValues {
        guard depth <= 64 else { throw SteamMetadataError.tooDeep }
        var values: [String: ValveValue] = [:]
        while let token = try next() {
            if case .close = token {
                guard nested else { throw SteamMetadataError.malformed }
                return ValveKeyValues(values: values)
            }
            guard case .text(let rawKey) = token, !rawKey.isEmpty, let value = try next() else { throw SteamMetadataError.malformed }
            let key = rawKey.lowercased()
            guard values[key] == nil else { throw SteamMetadataError.duplicateKey(key) }
            switch value {
            case .text(let text): values[key] = .string(text)
            case .open: values[key] = .object(try object(depth: depth + 1, nested: true))
            case .close: throw SteamMetadataError.malformed
            }
        }
        guard !nested else { throw SteamMetadataError.malformed }
        return ValveKeyValues(values: values)
    }
    mutating func next() throws -> Token? {
        while position < characters.count {
            if characters[position].isWhitespace || characters[position] == "\u{feff}" { position += 1; continue }
            if characters[position] == "/", position + 1 < characters.count, characters[position + 1] == "/" {
                while position < characters.count && characters[position] != "\n" { position += 1 }
                continue
            }
            break
        }
        guard position < characters.count else { return nil }
        tokens += 1
        guard tokens <= 500_000 else { throw SteamMetadataError.tooLarge }
        let first = characters[position]
        position += 1
        if first == "{" { return .open }
        if first == "}" { return .close }
        if first == "\"" {
            var result = ""
            while position < characters.count {
                let value = characters[position]; position += 1
                if value == "\"" { return .text(result) }
                if value == "\\" {
                    guard position < characters.count else { throw SteamMetadataError.malformed }
                    let escaped = characters[position]; position += 1
                    switch escaped {
                    case "\\", "\"": result.append(escaped)
                    case "n": result.append("\n")
                    case "t": result.append("\t")
                    case "r": result.append("\r")
                    default: result.append("\\"); result.append(escaped)
                    }
                } else { result.append(value) }
            }
            throw SteamMetadataError.malformed
        }
        guard first != "#", first != "[" else { throw SteamMetadataError.malformed }
        var result = String(first)
        while position < characters.count, !characters[position].isWhitespace, !["{", "}"].contains(characters[position]) {
            result.append(characters[position]); position += 1
        }
        return .text(result)
    }
}
