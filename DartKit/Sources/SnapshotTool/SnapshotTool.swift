#if os(macOS)
import AppKit
import SwiftUI
import DartCore
import DartUI

/// Renders every screen of `SnapshotCatalog` to PNG, in both languages.
/// Usage: swift run SnapshotTool [--out <directory>] [--lang fr|en] [--only <screen id>]
@main
struct SnapshotTool {
    @MainActor
    static func main() throws {
        var output = URL(fileURLWithPath: "build/snapshots")
        var languages = AppLanguage.allCases
        var only: String?
        var arguments = CommandLine.arguments.dropFirst().makeIterator()
        while let argument = arguments.next() {
            switch argument {
            case "--out": if let value = arguments.next() { output = URL(fileURLWithPath: value) }
            case "--lang": if let value = arguments.next(), let language = AppLanguage(rawValue: value) { languages = [language] }
            case "--only": only = arguments.next()
            default: FileHandle.standardError.write(Data("unknown argument: \(argument)\n".utf8)); exit(2)
            }
        }
        var failures = 0
        for language in languages {
            let directory = output.appendingPathComponent(language.rawValue)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for screen in SnapshotCatalog.all where only == nil || screen.id == only {
                for device in screen.devices {
                    let view = SnapshotCatalog.framed(screen.make(device), device: device, language: language)
                    let renderer = ImageRenderer(content: view)
                    renderer.proposedSize = ProposedViewSize(device.size)
                    renderer.scale = 2
                    let file = directory.appendingPathComponent("\(screen.id)@\(device.rawValue).png")
                    guard let image = renderer.cgImage,
                          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                        FileHandle.standardError.write(Data("render failed: \(file.lastPathComponent)\n".utf8))
                        failures += 1
                        continue
                    }
                    try png.write(to: file)
                    print(file.path)
                }
            }
        }
        exit(failures == 0 ? 0 : 1)
    }
}
#else
@main
struct SnapshotTool {
    static func main() {}
}
#endif
