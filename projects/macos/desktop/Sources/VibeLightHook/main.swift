import Foundation
import VibeLightCore

let input = FileHandle.standardInput.readDataToEndOfFile()

do {
    let event = try HookPayloadDecoder().decode(input)
    try EventLog().append(event)

    let packet = StatusPacket(event: event)
    FileHandle.standardOutput.write(try packet.encodedJSON())
    FileHandle.standardOutput.write(Data("\n".utf8))
} catch {
    FileHandle.standardError.write(Data("vibe-light-hook: \(error)\n".utf8))
    exit(0)
}
