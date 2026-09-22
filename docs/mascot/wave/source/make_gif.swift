// Builds ../claudy-wave.gif from the exported PNG frames and the sequence in ../wave.json.
// The sequence starts and ends on the idle pose, so the loop point is invisible.
//
//     swift make_gif.swift
import Foundation
import ImageIO
import UniformTypeIdentifiers

let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let root = here.deletingLastPathComponent()

struct Step: Decodable { let frame: String; let ms: Int }
struct Spec: Decodable { let sequence: [Step] }
let spec = try JSONDecoder().decode(Spec.self, from: Data(contentsOf: root.appendingPathComponent("wave.json")))

// Two idle steps in a row (end of loop, start of loop) are merged into one, for a seamless seam.
var steps = spec.sequence
if let first = steps.first, let last = steps.last, first.frame == last.frame, steps.count > 1 {
    steps[0] = Step(frame: first.frame, ms: first.ms + last.ms)
    steps.removeLast()
}

let output = root.appendingPathComponent("claudy-wave.gif")
guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString, steps.count, nil) else {
    fatalError("cannot create \(output.path)")
}
CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
for step in steps {
    let url = root.appendingPathComponent("frames/\(step.frame).png")
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("missing \(url.path)") }
    let delay = Double(step.ms) / 1000
    CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [
        kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay
    ]] as CFDictionary)
}
guard CGImageDestinationFinalize(destination) else { fatalError("GIF not written") }
print("\(steps.count) steps → \(output.lastPathComponent)")
