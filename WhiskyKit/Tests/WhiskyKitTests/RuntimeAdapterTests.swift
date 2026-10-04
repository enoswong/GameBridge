// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import XCTest
@testable import WhiskyKit

final class RuntimeAdapterTests: XCTestCase {
    func testFreshPrefixUsesInstallRatherThanRepairForVisualCpp() {
        XCTAssertEqual(CommonRuntimeComponent.visualCppX64.installArguments.first, "/install")
        XCTAssertEqual(CommonRuntimeComponent.visualCppX86.installArguments.first, "/install")
        XCTAssertFalse(CommonRuntimeComponent.visualCppX64.installArguments.contains("/repair"))
        XCTAssertTrue(CommonRuntimeComponent.visualCppX64.installArguments.contains("/norestart"))
        XCTAssertEqual(CommonRuntimeComponent.legacyDirectX.installArguments, ["/silent"])
    }
    func testCommonComponentRepairKeepsQuietFlagsAndSeparateArchitectureLogs() {
        XCTAssertEqual(CommonRuntimeComponent.visualCppX64.arguments,
                       ["/repair", "/quiet", "/norestart", "/log", "C:\\gamebridge-vc-x64.log"])
        XCTAssertEqual(CommonRuntimeComponent.visualCppX86.arguments.last, "C:\\gamebridge-vc-x86.log")
        XCTAssertEqual(CommonRuntimeComponent.legacyDirectX.arguments, ["/silent"])
        XCTAssertFalse(CommonRuntimeComponent.legacyDirectX.acceptsExitStatus(194))
        XCTAssertTrue(CommonRuntimeComponent.visualCppX64.acceptsExitStatus(194))
        XCTAssertFalse(CommonRuntimeComponent.visualCppX64.acceptsExitStatus(67))
    }
    func testInstalledVisualCppLibrariesTakePriorityWithoutDisablingGraphicsPolicy() {
        XCTAssertEqual(RuntimeAdapter.dllOverrides(dxmt: false),
                       "winemenubuilder.exe=d;vcruntime140,vcruntime140_1,msvcp140_2=n,b")
        XCTAssertEqual(RuntimeAdapter.dllOverrides(dxmt: true),
                       "winemenubuilder.exe=d;d3d11,dxgi,d3d10core=n;winemetal=b;vcruntime140,vcruntime140_1,msvcp140_2=n,b")
    }
    func testWindowTraceIsScopedToOneExecutableAndRejectsChannelInjection() throws {
        XCTAssertEqual(try RuntimeAdapter.debugChannels(dxmt: true, traceProcess: nil), "fixme-all,+loaddll")
        let trace = try RuntimeAdapter.debugChannels(dxmt: true, traceProcess: "Deskrawl.exe")
        XCTAssertTrue(trace.contains("Deskrawl.exe:trace+event"))
        XCTAssertFalse(trace.contains(",+event"))
        for invalid in ["", "../game.exe", "game.exe,+relay", "game:trace+all", "game.exe\n", "game"] {
            XCTAssertThrowsError(try RuntimeAdapter.debugChannels(dxmt: true, traceProcess: invalid))
        }
    }
    func testUnprovisionedGraphicsAndSynchronizationAreRejected() throws {
        var manifest = RuntimeFixture.manifest()
        var binding = RuntimeBinding(engineID: manifest.id, cpuMode: manifest.cpuMode, backend: .dxmt, synchronization: "none")
        XCTAssertThrowsError(try RuntimeAdapter.validateExecution(binding: binding, manifest: manifest))
        manifest.backends = [.wineD3D]; binding.backend = .wineD3D
        XCTAssertNoThrow(try RuntimeAdapter.validateExecution(binding: binding, manifest: manifest))
        manifest.synchronizationModes = ["none", "msync"]; binding.synchronization = "msync"
        XCTAssertThrowsError(try RuntimeAdapter.validateExecution(binding: binding, manifest: manifest))
    }
    func testCancellationRetainsLeaseUntilOwnedProcessExits() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let coordinator = try EnvironmentCoordinator(root: root)
        let environment = try await coordinator.create(name: "lease", manifest: RuntimeFixture.manifest(), backend: .dxmt, synchronization: "none")
        let started = expectation(description: "child started")
        let operation = Task {
            let lease = try await coordinator.lease(id: environment.id)
            return try await RuntimeAdapter.retainingSession(lease: lease) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = ["-c", "sleep 0.3; exit 7"]
                var status: Int32?
                for await event in try process.runStream(name: "lease-test", fileHandle: nil) {
                    if case .started = event { started.fulfill() }
                    if case .terminated(let child) = event { status = child.terminationStatus }
                }
                return status
            }
        }
        await fulfillment(of: [started], timeout: 2)
        operation.cancel()
        do { _ = try await coordinator.lease(id: environment.id); XCTFail("cancel released a live session") }
        catch { XCTAssertEqual(error as? RuntimeError, .environmentBusy) }
        let status = try await operation.value
        XCTAssertEqual(status, 7)
        _ = try await coordinator.lease(id: environment.id)
    }

    func testVersionProbeTerminatesAnUnresponsiveExecutable() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appending(path: "probe")
        try Data("#!/bin/sh\ntrap '' TERM\nwhile :; do :; done\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let start = Date()
        do { _ = try await RuntimeAdapter.probeExecutable(executable, timeout: 0.1); XCTFail("probe had no deadline") }
        catch { XCTAssertLessThan(Date().timeIntervalSince(start), 5) }
    }

    func testVersionProbeDeadlineIncludesInheritedPipes() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appending(path: "probe")
        try Data("#!/bin/sh\nsleep 2 &\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let start = Date()
        do { _ = try await RuntimeAdapter.probeExecutable(executable, timeout: 0.1); XCTFail("inherited pipe ignored deadline") }
        catch { XCTAssertLessThan(Date().timeIntervalSince(start), 1.5) }
    }

    func testInterruptedEnvironmentCannotBeLeasedAfterReopen() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let coordinator = try EnvironmentCoordinator(root: root)
        let environment = try await coordinator.create(name: "crash", manifest: RuntimeFixture.manifest(), backend: .dxmt, synchronization: "none")
        var lease: EnvironmentLease? = try await coordinator.lease(id: environment.id)
        try await coordinator.markStatus(.initializing, lease: lease!)
        lease = nil
        let reopened = try EnvironmentCoordinator(root: root)
        do { _ = try await reopened.lease(id: environment.id); XCTFail("interrupted session silently reused") }
        catch { XCTAssertEqual(error as? RuntimeError, .environmentBusy) }
    }
}
