import Foundation
import MoonBridgeCore

let args = CommandLine.arguments
let rootArgument = args.dropFirst().first(where: { !$0.hasPrefix("--") })
let root = URL(fileURLWithPath: rootArgument ?? FileManager.default.currentDirectoryPath)
let realPaths = ProjectPaths(root: root)
let work = root.appendingPathComponent("tests/work-" + UUID().uuidString)
let paths = ProjectPaths(root: work)
let fm = FileManager.default
var passed = 0
func require(_ condition: @autoclosure () -> Bool, _ text: String) throws {
    guard condition() else { throw BridgeError("FAILED: " + text) }
    passed += 1; print("PASS \(passed): \(text)")
}
func rejects(_ text: String) throws {
    var didReject = false
    do { try ArchiveGuard.validate(path: text) } catch { didReject = true }
    try require(didReject, "reject archive path " + text)
}
do {
    try paths.makeDirectories()
    try fm.createSymbolicLink(at: work.appendingPathComponent("Runtime"), withDestinationURL: root.appendingPathComponent("Runtime"))
    for bad in ["../outside", "/tmp/outside", "C:\\outside", "a\\..\\outside", "folder/../../bad", "file:stream"] { try rejects(bad) }
    try ArchiveGuard.validate(path: "日本語/汉化包/Game.exe"); try require(true, "accept Unicode game paths")
    try require(PEInspector.architecture(of: Data("not an executable".utf8)) == nil, "reject fake EXE")
    var imported: [Game] = []
    for bits in [32,64] {
        let fixture = root.appendingPathComponent("tests/fixtures/MoonBridge-自检-\(bits)位.zip")
        var game = try GameImporter(paths: paths).importGame(from: fixture)
        try require(game.candidates.count == 2, "\(bits)-bit archive import finds only real PE executables")
        try require(game.selected?.name == "Game.exe", "game launcher ranked above probe")
        try require(game.selected?.architecture.contains("\(bits) 位") == true, "PE\(bits) architecture detection")
        try require(game.bundledPatches.count == 1, "detect bundled Chinese patch")
        let patch = try paths.url(game.bundledPatches[0])
        let (patched, backup, count) = try GameImporter(paths: paths).applyPatch(patch, to: game, options: ImportOptions())
        let target = try paths.url(game.selectedExecutable).deletingLastPathComponent().appendingPathComponent("原版台词.txt")
        let old = try String(contentsOf: backup.appendingPathComponent("原版台词.txt"), encoding: .utf8)
        let new = try String(contentsOf: target, encoding: .utf8)
        try require(count == 2 && old.contains("Original") && new.contains("汉化后"), "patch overlay keeps original backup and replaces Unicode resource")
        try require(patched.candidates.contains(where: { $0.name == "GameCN.exe" }), "rescan discovers translation launcher")
        game = patched
        if args.contains("--runtime") {
            game.selectedExecutable = game.candidates.first(where: { $0.name == "Probe.exe" })!.relativePath
            let report = WineEngine(paths: paths).check()
            try require(report.wineReady && report.rosettaReady && report.archiverReady, "real runtime readiness")
            let result = try WineEngine(paths: paths).launchAndWait(game) { print($0) }
            try require(result.code == 37, "\(bits)-bit Windows process really executes ExitProcess(37)")
            let marker = paths.prefix(game.id).appendingPathComponent(".moonbridge-ready")
            let before = try fm.attributesOfItem(atPath: marker.path)[.modificationDate] as? Date
            try WineEngine(paths: paths).prepare(game)
            let after = try fm.attributesOfItem(atPath: marker.path)[.modificationDate] as? Date
            try require(before == after, "unchanged profile reuses prepared prefix without rewriting it")
        }
        let moved = ProjectPaths(root: work.appendingPathComponent("Relocation Test With Spaces/" + String(bits)))
        try moved.makeDirectories()
        try fm.createSymbolicLink(at: moved.root.appendingPathComponent("Runtime"), withDestinationURL: root.appendingPathComponent("Runtime"))
        try fm.createDirectory(at: moved.content(game.id), withIntermediateDirectories: true)
        let movedPrefix = moved.prefix(game.id)
        try fm.createDirectory(at: movedPrefix.appendingPathComponent("dosdevices"), withIntermediateDirectories: true)
        try Data("prepared prefix fixture".utf8).write(to: movedPrefix.appendingPathComponent("system.reg"))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(game.profile).write(to: movedPrefix.appendingPathComponent(".moonbridge-ready"))
        let movedDrive = movedPrefix.appendingPathComponent("dosdevices/g:")
        try fm.createSymbolicLink(atPath: movedDrive.path, withDestinationPath: "/old-location-that-no-longer-exists/content")
        try WineEngine(paths: moved).prepare(game)
        let relativeDrive = try fm.destinationOfSymbolicLink(atPath: movedDrive.path)
        try require(!relativeDrive.hasPrefix("/"), "cached prefix repairs an old absolute drive mapping")
        try require(movedDrive.resolvingSymlinksInPath().path == moved.content(game.id).path, "repaired mapping resolves in the new path with spaces")
        imported.append(game)
    }
    let library = LibraryDocument(games: imported); try library.save(to: paths)
    let loaded = try LibraryDocument.load(from: paths)
    try require(loaded.games.map(\.selectedExecutable) == imported.map(\.selectedExecutable), "game library atomic save/load preserves launch profiles")
    var rejected = false
    do { _ = try GameImporter(paths: paths).importGame(from: root.appendingPathComponent("tests/fixtures/unsafe-path.zip")) } catch { rejected = true }
    try require(rejected && !fm.fileExists(atPath: work.appendingPathComponent("Library/Games/escape.txt").path), "malicious archive is rejected before extraction")
    let report = "MoonBridge checks: \(passed) passed\nRuntime execution: \(args.contains("--runtime"))\nWork directory: \(work.path)\nDate: \(Date())\n"
    try report.write(to: root.appendingPathComponent("metadata/last-check.txt"), atomically: true, encoding: .utf8)
    print(report)
} catch { fputs("\(error.localizedDescription)\nWork directory: \(work.path)\n", stderr); exit(1) }
