// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import XCTest
@testable import WhiskyKit

final class ProcessStreamTests: XCTestCase {
    func testUTF8SplitAcrossReadsIsPreserved() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf '\\344'; sleep 0.1; printf '\\270'; sleep 0.1; printf '\\255'; printf ' done'"]
        var text = ""
        var ended = false
        for await output in try process.runStream(name: "utf8-fixture", fileHandle: nil) {
            switch output {
            case .message(let chunk): text += chunk
            case .terminated: ended = true
            default: break
            }
        }
        XCTAssertEqual(text, "中 done")
        XCTAssertTrue(ended)
    }

    func testBothPipesAreDrainedBeforeTermination() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "awk 'BEGIN { for (i=0;i<16384;i++) printf \"abcdefgh\"; }'; printf 'stderr-tail' >&2; exit 7"]
        var stdout = ""
        var stderr = ""
        var exitStatus: Int32?
        for await output in try process.runStream(name: "drain-fixture", fileHandle: nil) {
            switch output {
            case .message(let chunk):
                XCTAssertNil(exitStatus)
                stdout += chunk
            case .error(let chunk): stderr += chunk
            case .terminated(let child): exitStatus = child.terminationStatus
            default: break
            }
        }
        XCTAssertEqual(stdout, String(repeating: "abcdefgh", count: 16384))
        XCTAssertEqual(stderr, "stderr-tail")
        XCTAssertEqual(exitStatus, 7)
    }

    func testEOFBeforeExitDoesNotFinishTheStreamEarly() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf 'tail'; exec 1>&- 2>&-; sleep 0.1; exit 3"]
        var status: Int32?
        for await output in try process.runStream(name: "eof-fixture", fileHandle: nil) {
            if case .terminated(let child) = output { status = child.terminationStatus }
        }
        XCTAssertEqual(status, 3)
    }
}
