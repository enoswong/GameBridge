// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public struct PortableLegacyGameAudit: Encodable, Sendable {
    public enum AuditError: Error, Sendable { case unavailableDirectory(String) }

    public struct Import: Encodable, Sendable, Hashable {
        public let name: String
        public let architecture: String
        public let component: String?
    }

    public let directory: URL
    public let executablesScanned: Int
    public let unreadableExecutables: [String]
    public let scanLimitReached: Bool
    public let runtimeImports: [Import]
    public let unresolvedImports: [Import]

    public var summary: String {
        var lines = [directory.path, "已檢查 \(executablesScanned) 個 Windows EXE／DLL。"]
        let components = Set(runtimeImports.compactMap(\.component)).sorted()
        if !components.isEmpty { lines.append("偵測到共用依賴：\(components.joined(separator: "、"))") }
        for item in unresolvedImports {
            lines.append("未在已檢查位置找到：\(item.name)（\(item.architecture)）")
        }
        for item in unreadableExecutables { lines.append("未能讀取匯入表：\(item)") }
        if scanLimitReached { lines.append("已達掃描檔案上限。可選擇個別遊戲子目錄重查。") }
        if executablesScanned == 0 { lines.append("此目錄暫無可讀嘅 x86／x64 Windows 執行檔。") }
        return lines.joined(separator: "\n")
    }

    public static func scan(directory: URL, prefix: URL? = nil) throws -> Self {
        let directory = directory.standardizedFileURL.resolvingSymlinksInPath()
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        guard directory.isFileURL, try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true,
              let files = FileManager.default.enumerator(
                  at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
              ) else { throw AuditError.unavailableDirectory(directory.path) }
        var scan = Scan(prefix: prefix)
        var visited = 0
        for case let file as URL in files {
            try Task.checkCancellation()
            let values = try? file.resourceValues(forKeys: Set(keys))
            if values?.isSymbolicLink == true {
                files.skipDescendants()
                continue
            }
            guard values?.isRegularFile == true, ["exe", "dll"].contains(file.pathExtension.lowercased()) else {
                continue
            }
            visited += 1
            if visited > 2048 { break }
            scan.inspect(file)
        }
        return Self(
            directory: directory, executablesScanned: scan.count, unreadableExecutables: scan.errors.sorted(),
            scanLimitReached: visited > 2048, runtimeImports: scan.runtime.sorted(by: Self.order),
            unresolvedImports: scan.unresolved.sorted(by: Self.order)
        )
    }

    private static func order(_ lhs: Import, _ rhs: Import) -> Bool {
        (lhs.name, lhs.architecture) < (rhs.name, rhs.architecture)
    }

    public static func component(for name: String) -> String? {
        RuntimeDependencyPolicy.component(for: name)
    }

    private struct Scan {
        let prefix: URL?
        var count = 0
        var errors: [String] = []
        var runtime = Set<Import>()
        var unresolved = Set<Import>()
        var directoryFiles: [URL: Set<String>] = [:]
        var architectureFiles: [String: Set<String>] = [:]

        mutating func inspect(_ file: URL) {
            do {
                let imports = try PortableWindowsImportReader.read(file)
                count += 1
                let local = names(in: file.deletingLastPathComponent())
                let system = systemNames(for: imports.architecture)
                for name in imports.libraries {
                    let item = Import(
                        name: name, architecture: imports.architecture, component: PortableLegacyGameAudit.component(for: name)
                    )
                    if item.component != nil { runtime.insert(item) }
                    if !name.hasPrefix("api-ms-win-"), !name.hasPrefix("ext-ms-win-"),
                       !local.contains(name), !system.contains(name) {
                        unresolved.insert(item)
                    }
                }
            } catch {
                errors.append(file.path)
            }
        }

        private mutating func systemNames(for architecture: String) -> Set<String> {
            guard let prefix else { return [] }
            let windows = prefix.appending(path: "drive_c/windows")
            if let cached = architectureFiles[architecture] { return cached }
            let wow64 = windows.appending(path: "syswow64")
            let system = architecture == "x86" && FileManager.default.fileExists(atPath: wow64.path)
                ? wow64 : windows.appending(path: "system32")
            var available = names(in: system)
            let assemblies = windows.appending(path: "winsxs")
            let children = (try? FileManager.default.contentsOfDirectory(
                at: assemblies, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )) ?? []
            let family = architecture == "x86" ? "x86_microsoft.vc" : "amd64_microsoft.vc"
            for child in children where child.lastPathComponent.lowercased().hasPrefix(family) {
                let attributes = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard attributes?.isDirectory == true, attributes?.isSymbolicLink == false else { continue }
                available.formUnion(names(in: child))
            }
            architectureFiles[architecture] = available
            return available
        }

        private mutating func names(in directory: URL) -> Set<String> {
            if let names = directoryFiles[directory] { return names }
            let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
            let files = (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: Array(keys)
            )) ?? []
            let names = Set(files.compactMap { file -> String? in
                let values = try? file.resourceValues(forKeys: keys)
                guard values?.isRegularFile == true, values?.isSymbolicLink == false else { return nil }
                return file.lastPathComponent.lowercased()
            })
            directoryFiles[directory] = names
            return names
        }
    }
}
