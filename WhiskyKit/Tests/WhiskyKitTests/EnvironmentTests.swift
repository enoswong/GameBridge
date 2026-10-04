// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import XCTest
@testable import WhiskyKit

final class EnvironmentTests: XCTestCase {
    func testArchiveRefusesRunningEnvironment() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let coordinator = try EnvironmentCoordinator(root: root)
        let record = try await coordinator.create(name: "active", manifest: RuntimeFixture.manifest(), backend: .dxmt, synchronization: "none")
        let lease = try await coordinator.lease(id: record.id)
        try await coordinator.markStatus(.running, lease: lease)
        do { try await coordinator.archive(lease: lease); XCTFail("active environment archived") }
        catch { XCTAssertEqual(error as? RuntimeError, .environmentBusy) }
        let visible = try await coordinator.environments()
        XCTAssertEqual(visible.map(\.id), [record.id])
    }
    func testArchiveRetainsFilesAndSurvivesReopenThenRestore() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let coordinator = try EnvironmentCoordinator(root: root)
        let record = try await coordinator.create(name: "keep saves", manifest: RuntimeFixture.manifest(), backend: .dxmt, synchronization: "none")
        let save = record.prefix.appending(path: "save.txt")
        try Data("save".utf8).write(to: save)
        var lease: EnvironmentLease? = try await coordinator.lease(id: record.id)
        try await coordinator.archive(lease: lease!)
        lease = nil
        let reopened = try EnvironmentCoordinator(root: root)
        let visible = try await reopened.environments()
        XCTAssertTrue(visible.isEmpty)
        XCTAssertEqual(try Data(contentsOf: save), Data("save".utf8))
        do { _ = try await reopened.lease(id: record.id); XCTFail("archived environment launched") } catch {}
        try await reopened.restore(id: record.id)
        let restored = try await reopened.environments()
        XCTAssertEqual(restored.map(\.id), [record.id])
    }
    func testBindingCannotSwitchCPUOrUnsupportedBackend() throws {
        let manifest = RuntimeFixture.manifest()
        let correct = RuntimeBinding(engineID: manifest.id, cpuMode: .rosettaX86_64, backend: .dxmt, synchronization: "none")
        XCTAssertNoThrow(try correct.validate(against: manifest))
        var wrong = correct
        wrong.cpuMode = .arm64
        XCTAssertThrowsError(try wrong.validate(against: manifest))
        wrong = correct; wrong.backend = .d3dMetal
        XCTAssertThrowsError(try wrong.validate(against: manifest))
    }
    func testEnvironmentCreationUsesOwnRootAndPersistsBinding() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = RuntimeFixture.manifest()
        let coordinator = try EnvironmentCoordinator(root: root)
        let record = try await coordinator.create(name: "中文 Test", manifest: manifest, backend: .dxmt, synchronization: "none")
        XCTAssertTrue(record.prefix.path.hasPrefix(root.path + "/Environments/"))
        XCTAssertEqual(record.binding.engineID, manifest.id)
        let reopened = try EnvironmentCoordinator(root: root)
        let records = try await reopened.environments()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.name, "中文 Test")
        XCTAssertEqual(records.first?.status, .created)
    }
    func testSameEnvironmentCannotHaveTwoWriters() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let coordinator = try EnvironmentCoordinator(root: root)
        let record = try await coordinator.create(name: "one", manifest: RuntimeFixture.manifest(), backend: .dxmt, synchronization: "none")
        var first: EnvironmentLease? = try await coordinator.lease(id: record.id)
        do { _ = try await coordinator.lease(id: record.id); XCTFail("two writers") }
        catch { XCTAssertEqual(error as? RuntimeError, .environmentBusy) }
        XCTAssertNotNil(first)
        first = nil
        _ = try await coordinator.lease(id: record.id)
    }
    func testRecoveryRetainsExclusivityWithoutSilentlyChangingState() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let coordinator = try EnvironmentCoordinator(root: root)
        let record = try await coordinator.create(name: "recovery", manifest: RuntimeFixture.manifest(), backend: .dxmt, synchronization: "none")
        var original: EnvironmentLease? = try await coordinator.lease(id: record.id)
        try await coordinator.markStatus(.needsAttention, lease: original!)
        do { _ = try await coordinator.recoveryLease(id: record.id); XCTFail("recovery bypassed active writer") }
        catch { XCTAssertEqual(error as? RuntimeError, .environmentBusy) }
        original = nil
        let recovery = try await coordinator.recoveryLease(id: record.id)
        XCTAssertEqual(recovery.environment.status, .needsAttention)
        let persisted = try await coordinator.environment(id: record.id)
        XCTAssertEqual(persisted.status, .needsAttention)
        do { _ = try await coordinator.lease(id: record.id); XCTFail("recovery lost lock") }
        catch { XCTAssertEqual(error as? RuntimeError, .environmentBusy) }
        withExtendedLifetime(recovery) {}
    }

    func testClonePreservesOriginalAndCopiesLinksWithoutFollowingThem() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let coordinator = try EnvironmentCoordinator(root: root)
        let original = try await coordinator.create(name: "original", manifest: RuntimeFixture.manifest(), backend: .dxmt, synchronization: "none")
        try Data("save".utf8).write(to: original.prefix.appending(path: "save.dat"))
        try FileManager.default.createSymbolicLink(atPath: original.prefix.appending(path: "external").path, withDestinationPath: "/unavailable-external-target")
        try FileManager.default.createSymbolicLink(atPath: original.prefix.appending(path: "alias").path, withDestinationPath: original.prefix.appending(path: "save.dat").path)
        let lease = try await coordinator.lease(id: original.id)
        var manifest = RuntimeFixture.manifest(); manifest.id = "new-engine"
        let copied = try await coordinator.cloneIdleEnvironment(source: lease, name: "copy", manifest: manifest, backend: .dxmt)
        XCTAssertNotEqual(original.id, copied.id)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: copied.prefix.appending(path: "external").path), "/unavailable-external-target")
        try Data("new save".utf8).write(to: copied.prefix.appending(path: "alias"))
        XCTAssertEqual(try Data(contentsOf: copied.prefix.appending(path: "save.dat")), Data("new save".utf8))
        XCTAssertEqual(try Data(contentsOf: original.prefix.appending(path: "save.dat")), Data("save".utf8))
        let record = try await coordinator.environment(id: original.id)
        XCTAssertEqual(record.binding.engineID, "test-engine-1")
    }

    func testHostPolicyRequiresArchitectureOSAndRosetta() throws {
        let manifest = RuntimeFixture.manifest()
        var host = HostSnapshot(macOSVersion: "15.0.0", macOSBuild: "test", architecture: "arm64", physicalMemoryBytes: 16 * 1024 * 1024 * 1024, gpuName: "Fixture", metalFamilies: ["apple1"], rosettaInstalled: true, storageFileSystem: "apfs", storageIsLocal: true, availableStorageBytes: 100_000_000)
        XCTAssertNoThrow(try host.validate(for: manifest))
        host.rosettaInstalled = false
        XCTAssertThrowsError(try host.validate(for: manifest))
        host.rosettaInstalled = true; host.architecture = "x86_64"
        XCTAssertThrowsError(try host.validate(for: manifest))
        host.architecture = "arm64"; host.macOSVersion = "14.0.0"
        XCTAssertThrowsError(try host.validate(for: manifest))
    }
}
