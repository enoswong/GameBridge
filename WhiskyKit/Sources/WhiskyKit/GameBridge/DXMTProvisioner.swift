// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Version-one internal package layout. Every source digest is in the signed manifest.
/// Only the prefix is modified; installed engines remain immutable.
public enum DXMTProvisioner {
    static let names = ["d3d11.dll", "dxgi.dll", "d3d10core.dll", "winemetal.dll"]
    public static var requiredPaths: [String] {
        ["x64", "x32"].flatMap { arch in names.map { "Libraries/DXMT/\(arch)/\($0)" } } + [
            "Libraries/Wine/lib/wine/x86_64-unix/winemetal.so",
            "Libraries/Wine/lib/wine/x86_64-windows/winemetal.dll",
            "Libraries/Wine/lib/wine/i386-windows/winemetal.dll"
        ]
    }
    public static func validate(engine: InstalledEngine) throws {
        guard let hashes = engine.manifest.dxmtFileSHA256s,
              Set(hashes.keys) == Set(requiredPaths) else { throw RuntimeError.invalidManifest("DXMT signed file inventory") }
        for path in requiredPaths {
            let file = try ManagedPath.child(path, under: engine.directory)
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  try DigestTools.sha256(file: file, maximumBytes: 128 * 1024 * 1024).hash == hashes[path]
            else { throw RuntimeError.archiveHashMismatch }
            if path.hasSuffix(".dll") { try WindowsSteamCommand.validatePE(file) }
            if path.contains("/DXMT/"), !path.hasSuffix("/winemetal.dll") {
                let handle = try FileHandle(forReadingFrom: file)
                defer { try? handle.close() }
                try handle.seek(toOffset: 64)
                let marker = try handle.read(upToCount: 17)
                guard marker != Data("Wine builtin DLL\0".utf8) else {
                    throw RuntimeError.invalidManifest("DXMT requires native D3D DLLs")
                }
            }
        }
    }
    public static func provision(engine: InstalledEngine, prefix: URL) throws {
        try validate(engine: engine) // All sources checked before any prefix writes.
        var copies: [(URL, URL, String)] = []
        for (architecture, systemDirectory) in [("x64", "system32"), ("x32", "syswow64")] {
            let directory = try ManagedPath.child("drive_c/windows/" + systemDirectory, under: prefix)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw RuntimeError.io("Initialize Windows before provisioning DXMT")
            }
            for name in names {
                let path = "Libraries/DXMT/\(architecture)/\(name)"
                let source = try ManagedPath.child(path, under: engine.directory)
                let destination = try ManagedPath.child("drive_c/windows/\(systemDirectory)/\(name)", under: prefix)
                copies.append((source, destination, engine.manifest.dxmtFileSHA256s![path]!))
            }
        }
        for (source, destination, hash) in copies {
            if FileManager.default.fileExists(atPath: destination.path),
               try DigestTools.sha256(file: destination, maximumBytes: 128 * 1024 * 1024).hash == hash { continue }
            // Atomic replacement; interrupted multi-file application is safe to retry under lease.
            try Data(contentsOf: source).write(to: destination, options: .atomic)
            guard try DigestTools.sha256(file: destination, maximumBytes: 128 * 1024 * 1024).hash == hash else {
                throw RuntimeError.archiveHashMismatch
            }
        }
    }
    static let overrides = "winemenubuilder.exe=d;d3d11,dxgi,d3d10core=n;winemetal=b"
}
