import Foundation
import VibeLightCore

let input = FileHandle.standardInput.readDataToEndOfFile()
let arguments = CommandLine.arguments
let source: VibeSource = {
    guard let sourceIndex = arguments.firstIndex(of: "--source"),
          arguments.indices.contains(sourceIndex + 1) else {
        return .other
    }
    return VibeSource(rawValue: arguments[sourceIndex + 1]) ?? .other
}()

do {
    let event = try HookPayloadDecoder(defaultSource: source).decode(input)
    try EventLog().append(event)
} catch {
    FileHandle.standardError.write(Data("vibe-light-hook: \(error)\n".utf8))
    exit(0)
}
