import Foundation

/// 文件日志服务，将日志同时输出到控制台和文件
final class FileLogger: @unchecked Sendable {
    static let shared = FileLogger()

    private let fileHandle: FileHandle?
    private let queue = DispatchQueue(label: "com.viDesk.logger")
    let logFileURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        logFileURL = docs.appendingPathComponent("viDesk.log")

        // 每次启动清空日志
        FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        fileHandle = FileHandle(forWritingAtPath: logFileURL.path)
        fileHandle?.seekToEndOfFile()

        // 设置 C 层日志文件路径
        logFileURL.path.withCString { path in
            viDesk_setLogFile(path)
        }

        log("========== ViDesk 启动 ==========")
        log("时间: \(Date())")
        log("系统: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        log("日志文件: \(logFileURL.path)")
    }

    func log(_ message: String, file: String = #file, line: Int = #line) {
        let timestamp = Self.formatter.string(from: Date())
        let fileName = (file as NSString).lastPathComponent
        let entry = "[\(timestamp)] [\(fileName):\(line)] \(message)\n"

        // 控制台
        print(entry, terminator: "")

        // 文件
        queue.async { [weak self] in
            if let data = entry.data(using: .utf8) {
                self?.fileHandle?.write(data)
            }
        }
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    deinit {
        fileHandle?.closeFile()
    }
}

// 全局快捷方法
func vLog(_ message: String, file: String = #file, line: Int = #line) {
    FileLogger.shared.log(message, file: file, line: line)
}
