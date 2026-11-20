// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public struct LegacyGameAudit: Encodable, Sendable {
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
              ) else { throw SteamMetadataError.unavailable(directory.path) }
        var scan = Scan(prefix: prefix)
        var visited = 0
        for case let file as URL in files {
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

    static func component(for name: String) -> String? {
        guard name.lowercased().hasSuffix(".dll") else { return nil }
        let families = [
            ("80", "2005"), ("90", "2008"), ("100", "2010"), ("110", "2012"), ("120", "2013"), ("140", "v14")
        ]
        let prefixes = ["msvcr", "msvcp", "msvcm", "mfc", "mfcm", "atl", "vcomp", "vcruntime", "concrt", "vccorlib"]
        let basename = String(name.lowercased().dropLast(4))
        let family = families.first { version, _ in
            prefixes.contains { prefix in
                let stem = prefix + version
                return basename == stem || basename == stem + "u" || basename.hasPrefix(stem + "_")
            }
        }
        if let family { return "Visual C++ " + family.1 }
        if ["d3dx9_", "d3dx10_", "d3dx11_", "xactengine", "x3daudio1_"].contains(where: basename.hasPrefix)
            || ["xinput1_3", "xaudio2_7", "d3dcompiler_43"].contains(basename) {
            return "DirectX June 2010"
        }
        if basename == "mscoree" { return ".NET Framework" }
        if ["openal32", "wrap_oal"].contains(basename) { return "OpenAL" }
        if ["physxloader", "physxloader64", "physxcore"].contains(basename) { return "PhysX" }
        if basename.hasPrefix("microsoft.xna.framework") { return "XNA Framework" }
        return nil
    }

    private struct Scan {
        let prefix: URL?
        var count = 0
        var errors: [String] = []
        var runtime = Set<Import>()
        var unresolved = Set<Import>()
        var directoryFiles: [URL: Set<String>] = [:]

        mutating func inspect(_ file: URL) {
            do {
                let imports = try WindowsImportReader.read(file)
                count += 1
                let local = names(in: file.deletingLastPathComponent())
                let system = systemNames(for: imports.architecture)
                for name in imports.libraries {
                    let item = Import(
                        name: name, architecture: imports.architecture, component: LegacyGameAudit.component(for: name)
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
            let wow64 = windows.appending(path: "syswow64")
            if architecture == "x86", FileManager.default.fileExists(atPath: wow64.path) {
                return names(in: wow64)
            }
            return names(in: windows.appending(path: "system32"))
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
