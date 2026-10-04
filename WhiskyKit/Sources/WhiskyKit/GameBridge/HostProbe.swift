// SPDX-License-Identifier: GPL-3.0-or-later
import Darwin
import Foundation
import Metal

public struct HostSnapshot: Codable, Sendable {
    public var macOSVersion: String
    public var macOSBuild: String
    public var architecture: String
    public var physicalMemoryBytes: UInt64
    public var gpuName: String?
    public var metalFamilies: [String]
    public var rosettaInstalled: Bool
    public var storageFileSystem: String
    public var storageIsLocal: Bool
    public var availableStorageBytes: Int64?

    public func validate(for manifest: EngineManifest) throws {
        guard architecture == "arm64", let actual = OSVersion(macOSVersion),
              let required = OSVersion(manifest.minimumMacOS), actual >= required,
              storageIsLocal, storageFileSystem == "apfs",
              manifest.cpuMode != .rosettaX86_64 || rosettaInstalled,
              !manifest.backends.contains(.dxmt) || gpuName != nil
        else { throw RuntimeError.unsupportedHost }
    }
}
public enum HostProbe {
    public static func inspect(storageURL: URL) throws -> HostSnapshot {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let volume = try storageURL.resourceValues(forKeys: [.volumeIsLocalKey, .volumeAvailableCapacityForImportantUsageKey])
        var information = statfs()
        guard statfs(storageURL.path, &information) == 0 else { throw RuntimeError.io("inspect filesystem") }
        let fileSystem = withUnsafeBytes(of: information.f_fstypename) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        let device = MTLCreateSystemDefaultDevice()
        let families: [(String, MTLGPUFamily)] = [("apple1", .apple1), ("apple2", .apple2), ("apple3", .apple3), ("apple4", .apple4), ("apple5", .apple5), ("apple6", .apple6), ("apple7", .apple7), ("apple8", .apple8), ("apple9", .apple9)]
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        return HostSnapshot(macOSVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
                            macOSBuild: sysctlString("kern.osversion"), architecture: architecture,
                            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
                            gpuName: device?.name, metalFamilies: families.filter { device?.supportsFamily($0.1) == true }.map(\.0),
                            rosettaInstalled: Rosetta2.isRosettaInstalled, storageFileSystem: fileSystem,
                            storageIsLocal: volume.volumeIsLocal == true,
                            availableStorageBytes: volume.volumeAvailableCapacityForImportantUsage)
    }
    private static func sysctlString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return "unknown" }
        return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }
}
