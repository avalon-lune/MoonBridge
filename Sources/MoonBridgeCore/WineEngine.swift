import Foundation

public struct RuntimeReport: Sendable {
    public var wineVersion = "未就绪"
    public var wineReady = false
    public var archiverReady = false
    public var rosettaReady = false
    public var mediaReady = false
    public var detail = ""
    public init() {}
}
public struct WineEngine: Sendable {
    public let paths: ProjectPaths
    public init(paths: ProjectPaths) { self.paths = paths }
    public var bin: URL { paths.root.appendingPathComponent("Runtime/Wine/Wine Stable.app/Contents/Resources/wine/bin") }
    public var wine: URL { bin.appendingPathComponent("wine") }
    public var server: URL { bin.appendingPathComponent("wineserver") }
    public func environment(for game: Game) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let cache = paths.root.appendingPathComponent("Library/Cache")
        env["WINEPREFIX"] = paths.prefix(game.id).path
        env["WINEARCH"] = "win64"
        env["WINEDLLOVERRIDES"] = "winemenubuilder.exe=d"
        env["WINEDEBUG"] = "-all,err+all"
        env["LANG"] = game.profile.locale.unix
        env["LC_ALL"] = game.profile.locale.unix
        env["PATH"] = bin.path + ":/usr/bin:/bin:/usr/sbin:/sbin"
        env["XDG_CACHE_HOME"] = cache.path
        env["XDG_CONFIG_HOME"] = paths.prefix(game.id).appendingPathComponent("xdg-config").path
        env["XDG_DATA_HOME"] = paths.prefix(game.id).appendingPathComponent("xdg-data").path
        env["GST_REGISTRY_1_0"] = cache.appendingPathComponent("gstreamer-" + game.id.uuidString + ".bin").path
        let frameworks = paths.root.appendingPathComponent("Runtime/Media/Library/Frameworks")
        let gst = frameworks.appendingPathComponent("GStreamer.framework/Versions/1.0")
        env["DYLD_FALLBACK_FRAMEWORK_PATH"] = frameworks.path + ":/Library/Frameworks:/System/Library/Frameworks"
        env["DYLD_FALLBACK_LIBRARY_PATH"] = bin.deletingLastPathComponent().appendingPathComponent("lib").path + ":" + gst.appendingPathComponent("lib").path + ":/usr/lib"
        if FileManager.default.fileExists(atPath: gst.path) {
            env["GST_PLUGIN_SYSTEM_PATH_1_0"] = gst.appendingPathComponent("lib/gstreamer-1.0").path
            env["GST_PLUGIN_SCANNER_1_0"] = gst.appendingPathComponent("libexec/gstreamer-1.0/gst-plugin-scanner").path
        }
        return env
    }
    public func check() -> RuntimeReport {
        var report = RuntimeReport()
        report.archiverReady = FileManager.default.isExecutableFile(atPath: paths.sevenZip.path)
        report.rosettaReady = (try? ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/arch"), ["-x86_64", "/usr/bin/true"], timeout: 10).code) == 0
        if FileManager.default.isExecutableFile(atPath: wine.path), let result = try? ProcessRunner.run(wine, ["--version"], timeout: 20) {
            report.wineReady = result.code == 0
            report.wineVersion = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        report.mediaReady = FileManager.default.fileExists(atPath: paths.root.appendingPathComponent("Runtime/Media/Library/Frameworks/GStreamer.framework").path) || FileManager.default.fileExists(atPath: "/Library/Frameworks/GStreamer.framework")
        report.detail = "Wine：\(report.wineVersion)\nRosetta：\(report.rosettaReady ? "就绪" : "缺失")\n7-Zip：\(report.archiverReady ? "就绪" : "缺失")\n视频组件：\(report.mediaReady ? "已安装" : "基础支持，特殊格式待验证")\n项目位置：\(paths.root.path)\n\n运行环境按游戏分开；实际兼容性需以画面、音频、视频与存读档测试为准。"
        return report
    }
    public func prepare(_ game: Game, progress: @Sendable (String) -> Void = { _ in }) throws {
        guard FileManager.default.isExecutableFile(atPath: wine.path) else { throw BridgeError("Wine 运行库未找到，请检查运行环境。") }
        try paths.makeDirectories()
        let prefix = paths.prefix(game.id); let env = environment(for: game); let log = paths.log(game.id)
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let profileData = try encoder.encode(game.profile)
        let marker = prefix.appendingPathComponent(".moonbridge-ready")
        if (try? Data(contentsOf: marker)) == profileData, FileManager.default.fileExists(atPath: prefix.appendingPathComponent("system.reg").path) {
            try synchronizeGameDrive(game)
            return
        }
        if !FileManager.default.fileExists(atPath: prefix.appendingPathComponent("system.reg").path) {
            progress("首次启动：正在创建独立 Windows 环境…")
            ProcessRunner.append("\n[MoonBridge] 创建独立运行环境 \(Date())\n", to: log)
            let boot = try ProcessRunner.run(wine, ["wineboot", "--init"], environment: env, timeout: 300, log: log)
            guard boot.code == 0 else { throw BridgeError("Windows 环境初始化失败。请查看运行日志。\n" + String(boot.output.suffix(1800))) }
        }
        try isolateUserFolders(prefix: prefix)
        try synchronizeGameDrive(game)
        progress("正在配置字体、语言区域与显示模式…")
        let configDirectory = prefix.appendingPathComponent("drive_c/MoonBridge")
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        let reg = registry(for: game)
        var data = Data([0xff, 0xfe]); data.append(reg.data(using: .utf16LittleEndian)!)
        try data.write(to: configDirectory.appendingPathComponent("profile.reg"), options: .atomic)
        let result = try ProcessRunner.run(wine, ["regedit", "/S", "C:\\MoonBridge\\profile.reg"], environment: env, timeout: 90, log: log)
        guard result.code == 0 else { throw BridgeError("运行配置写入失败，请查看日志。") }
        let wait = try ProcessRunner.run(server, ["-w"], environment: env, timeout: 90, log: log)
        guard wait.code == 0 else { throw BridgeError("初始化进程未正常结束，请停止运行环境后重试。") }
        try profileData.write(to: marker, options: .atomic)
    }
    private func synchronizeGameDrive(_ game: Game) throws {
        let devices = paths.prefix(game.id).appendingPathComponent("dosdevices")
        try FileManager.default.createDirectory(at: devices, withIntermediateDirectories: true)
        let drive = devices.appendingPathComponent("g:")
        // Relative to Library/Prefixes/<id>/dosdevices; survives moving the entire project.
        let relativeTarget = "../../../Games/" + game.id.uuidString + "/content"
        if let current = try? FileManager.default.destinationOfSymbolicLink(atPath: drive.path) {
            if current == relativeTarget { return }
            try FileManager.default.removeItem(at: drive)
        } else if FileManager.default.fileExists(atPath: drive.path) {
            throw BridgeError("游戏盘映射位置包含普通文件，已保留该文件。请检查运行环境。")
        }
        try FileManager.default.createSymbolicLink(atPath: drive.path, withDestinationPath: relativeTarget)
    }
    public func launchAndWait(_ game: Game, progress: @Sendable (String) -> Void = { _ in }) throws -> ProcessResult {
        guard !game.selectedExecutable.isEmpty else { throw BridgeError("没有找到可启动的 EXE，请重新扫描或选择游戏主程序。") }
        let executable = try paths.url(game.selectedExecutable)
        guard FileManager.default.fileExists(atPath: executable.path) else { throw BridgeError("主程序不存在，请重新扫描。") }
        try prepare(game, progress: progress)
        let env = environment(for: game); let log = paths.log(game.id)
        let windowsPath = try windowsPath(for: executable, game: game)
        var args = [windowsPath]
        if game.profile.display == .desktop {
            let width = max(640, min(7680, game.profile.width)); let height = max(480, min(4320, game.profile.height))
            args = ["explorer", "/desktop=MoonBridge,\(width)x\(height)", windowsPath]
        }
        ProcessRunner.append("\n[MoonBridge] 启动：\(game.title)\n程序：\(game.selectedExecutable)\n区域：\(game.profile.locale.windows)，显示：\(game.profile.display.title)\n时间：\(Date())\n", to: log)
        progress(game.selected?.isInstaller == true ? "安装程序已启动，完成后可重新扫描" : "游戏运行中")
        let result = try ProcessRunner.run(wine, args, environment: env, directory: executable.deletingLastPathComponent(), timeout: 7 * 24 * 3600, log: log)
        _ = try? ProcessRunner.run(server, ["-w"], environment: env, timeout: 7 * 24 * 3600, log: log)
        ProcessRunner.append("\n[MoonBridge] 会话结束，退出码 \(result.code)\n", to: log)
        return result
    }
    public func stop(_ game: Game) throws {
        let result = try ProcessRunner.run(server, ["-k"], environment: environment(for: game), timeout: 30, log: paths.log(game.id))
        guard result.code == 0 else { throw BridgeError("停止请求未成功，请查看日志。") }
    }
    public func openConfiguration(_ game: Game) throws {
        try prepare(game)
        _ = try ProcessRunner.run(wine, ["winecfg"], environment: environment(for: game), timeout: 3600, log: paths.log(game.id))
    }
    public func windowsPath(for file: URL, game: Game) throws -> String {
        let source = paths.content(game.id).path
        let driveC = paths.prefix(game.id).appendingPathComponent("drive_c").path
        if file.path.hasPrefix(source + "/") { return "G:\\" + String(file.path.dropFirst(source.count + 1)).replacingOccurrences(of: "/", with: "\\") }
        if file.path.hasPrefix(driveC + "/") { return "C:\\" + String(file.path.dropFirst(driveC.count + 1)).replacingOccurrences(of: "/", with: "\\") }
        throw BridgeError("主程序不在当前游戏的运行目录中。")
    }
    private func isolateUserFolders(prefix: URL) throws {
        let users = prefix.appendingPathComponent("drive_c/users")
        for user in (try? FileManager.default.contentsOfDirectory(at: users, includingPropertiesForKeys: nil)) ?? [] {
            for name in ["Desktop", "Documents", "Downloads", "Pictures", "Music", "Videos", "My Documents", "My Pictures", "My Music", "My Videos"] {
                let folder = user.appendingPathComponent(name)
                if (try? folder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                    try FileManager.default.removeItem(at: folder)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                }
            }
        }
    }
    private func registry(for game: Game) -> String {
        let version = ["win10", "win7", "winxp"].contains(game.profile.windowsVersion) ? game.profile.windowsVersion : "win10"
        return """
        Windows Registry Editor Version 5.00

        [HKEY_CURRENT_USER\\Software\\Wine]
        "Version"="\(version)"

        [HKEY_CURRENT_USER\\Software\\Wine\\Fonts\\Replacements]
        "MS Gothic"="Hiragino Sans"
        "MS PGothic"="Hiragino Sans"
        "MS UI Gothic"="Hiragino Sans"
        "Meiryo"="Hiragino Sans"
        "SimSun"="Songti SC"
        "Microsoft YaHei"="Hiragino Sans GB"

        [HKEY_CURRENT_USER\\Control Panel\\International]
        "LocaleName"="\(game.profile.locale.windows)"
        "Locale"="\(game.profile.locale.localeID)"

        [HKEY_LOCAL_MACHINE\\System\\CurrentControlSet\\Control\\Nls\\CodePage]
        "ACP"="\(game.profile.locale.codePage)"
        "OEMCP"="\(game.profile.locale.codePage)"

        [HKEY_CURRENT_USER\\Software\\Wine\\Mac Driver]
        "RetinaMode"="N"

        [HKEY_CURRENT_USER\\Control Panel\\Desktop]
        "LogPixels"=dword:00000060

        """
    }
}
