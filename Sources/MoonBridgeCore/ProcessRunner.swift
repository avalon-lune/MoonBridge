import Foundation
import Darwin

public struct ProcessResult: Sendable {
    public let code: Int32
    public let output: String
}
public enum ProcessRunner {
    public static func run(_ executable: URL, _ arguments: [String], environment: [String: String]? = nil, directory: URL? = nil, timeout: TimeInterval = 120, log: URL? = nil) throws -> ProcessResult {
        let temporary = log == nil
        let outputURL = log ?? FileManager.default.temporaryDirectory.appendingPathComponent("moonbridge-" + UUID().uuidString + ".log")
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: outputURL.path) { FileManager.default.createFile(atPath: outputURL.path, contents: nil) }
        let handle = try FileHandle(forWritingTo: outputURL)
        defer { try? handle.close(); if temporary { try? FileManager.default.removeItem(at: outputURL) } }
        try handle.seekToEnd()
        let process = Process(); process.executableURL = executable; process.arguments = arguments
        process.environment = environment; process.currentDirectoryURL = directory
        process.standardOutput = handle; process.standardError = handle; process.standardInput = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning {
            process.terminate(); Thread.sleep(forTimeInterval: 0.3)
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            throw BridgeError("操作超时。请在运行日志中查看详情，或停止该游戏后重试。")
        }
        process.waitUntilExit(); try? handle.synchronize()
        let reader = try FileHandle(forReadingFrom: outputURL); defer { try? reader.close() }
        let size = (try? reader.seekToEnd()) ?? 0
        try reader.seek(toOffset: size > 4_000_000 ? size - 4_000_000 : 0)
        let data = try reader.readToEnd() ?? Data()
        return ProcessResult(code: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
    public static func append(_ text: String, to url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }; _ = try? handle.seekToEnd(); try? handle.write(contentsOf: Data(text.utf8))
    }
}
