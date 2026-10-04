//
//  Process+Extensions.swift
//  WhiskyKit
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import Foundation
import Darwin
import os.log

public enum ProcessOutput: Hashable {
    case started(Process)
    case message(String)
    case error(String)
    case terminated(Process)
}

public extension Process {
    /// Drain both pipes concurrently; emit termination only after their final bytes.
    func runStream(name: String, fileHandle: FileHandle?, drainTimeout: TimeInterval? = nil) throws -> AsyncStream<ProcessOutput> {
        let drainDeadline = drainTimeout.map { ProcessInfo.processInfo.systemUptime + $0 }
        let output = Pipe()
        let errors = Pipe()
        standardOutput = output
        standardError = errors
        let (stream, continuation) = AsyncStream<ProcessOutput>.makeStream()
        let state = ProcessStreamState(continuation: continuation, log: fileHandle)
        let group = DispatchGroup()
        group.enter() // child exit
        terminationHandler = { _ in group.leave() }
        continuation.onTermination = { [weak self] reason in
            if case .cancelled = reason, let self, self.isRunning { self.terminate() }
        }
        do {
            try run()
        } catch {
            terminationHandler = nil
            group.leave()
            try? fileHandle?.close()
            continuation.finish()
            throw error
        }
        continuation.yield(.started(self))
        for (handle, isError) in [(output.fileHandleForReading, false), (errors.fileHandleForReading, true)] {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                defer { try? handle.close(); group.leave() }
                var decoder = ProcessUTF8Decoder()
                do {
                    while let bytes = try ProcessPipeReader.read(handle, deadline: drainDeadline), !bytes.isEmpty {
                        state.emit(decoder.append(bytes), isError: isError)
                    }
                    state.emit(decoder.finish(), isError: isError)
                } catch {
                    state.emit("Output read failed: \(error.localizedDescription)", isError: true)
                }
            }
        }
        group.notify(queue: .global(qos: .utility)) {
            state.finish(process: self)
        }
        return stream
    }

    private func logTermination(name: String) {
        if terminationStatus == 0 {
            Logger.wineKit.info(
                "Terminated \(name) with status code '\(self.terminationStatus, privacy: .public)'"
            )
        } else {
            Logger.wineKit.warning(
                "Terminated \(name) with status code '\(self.terminationStatus, privacy: .public)'"
            )
        }
    }

    private func logProcessInfo(name: String) {
        Logger.wineKit.info("Running process \(name)")

        if let arguments = arguments {
            Logger.wineKit.info("Arguments: `\(arguments.joined(separator: " "))`")
        }
        if let executableURL = executableURL {
            Logger.wineKit.info("Executable: `\(executableURL.path(percentEncoded: false))`")
        }
        if let directory = currentDirectoryURL {
            Logger.wineKit.info("Directory: `\(directory.path(percentEncoded: false))`")
        }
        if let environment = environment {
            Logger.wineKit.info("Environment: \(environment)")
        }
    }
}

// The two pipe readers serialize log writes and stream completion through this object.
private final class ProcessStreamState: @unchecked Sendable {
    private let lock = NSLock()
    private let continuation: AsyncStream<ProcessOutput>.Continuation
    private let log: FileHandle?

    init(continuation: AsyncStream<ProcessOutput>.Continuation, log: FileHandle?) {
        self.continuation = continuation
        self.log = log
    }

    func emit(_ text: String, isError: Bool) {
        guard !text.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        continuation.yield(isError ? .error(text) : .message(text))
        log?.write(line: text)
    }

    func finish(process: Process) {
        lock.lock()
        defer { lock.unlock() }
        try? log?.close()
        continuation.yield(.terminated(process))
        continuation.finish()
    }
}

/// Retains at most the incomplete trailing UTF-8 sequence between pipe reads.
struct ProcessUTF8Decoder {
    private var pending = Data()

    mutating func append(_ bytes: Data) -> String {
        pending.append(bytes)
        let values = Array(pending)
        var end = values.count
        var start = end
        while start > 0 && end - start < 3 && values[start - 1] & 0xc0 == 0x80 { start -= 1 }
        if start > 0 {
            let lead = values[start - 1]
            let required = lead >= 0xf0 && lead <= 0xf4 ? 4 :
                (lead >= 0xe0 && lead <= 0xef ? 3 : (lead >= 0xc2 && lead <= 0xdf ? 2 : 1))
            if required > end - (start - 1) { end = start - 1 }
        }
        let text = String(decoding: pending.prefix(end), as: UTF8.self)
        pending = Data(pending.dropFirst(end))
        return text
    }

    mutating func finish() -> String {
        defer { pending.removeAll() }
        return String(decoding: pending, as: UTF8.self)
    }
}

private enum ProcessPipeReader {
    static func read(_ handle: FileHandle, deadline: TimeInterval?) throws -> Data? {
        guard let deadline else { return try handle.read(upToCount: 65536) }
        // A version probe may exit while a descendant still owns a pipe. Bound pipe
        // drain separately from direct-process termination, without killing other Wine sessions.
        while ProcessInfo.processInfo.systemUptime < deadline {
            var descriptor = pollfd(fd: handle.fileDescriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
            let result = poll(&descriptor, 1, 50)
            if result < 0 {
                if errno == EINTR { continue }
                throw RuntimeError.io("poll child output")
            }
            if result == 0 { continue }
            var data = Data(count: 65536)
            let count = data.withUnsafeMutableBytes { Darwin.read(handle.fileDescriptor, $0.baseAddress, $0.count) }
            if count < 0 {
                if errno == EINTR { continue }
                throw RuntimeError.io("read child output")
            }
            data.count = count
            return data
        }
        return nil
    }
}
