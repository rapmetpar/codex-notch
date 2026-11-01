// Local-only sampled movement preview. Compile together with PetSpriteAtlas.swift and
// PetSpriteMotion.swift, then pass: INPUT_ATLAS OUTPUT_DIRECTORY. No artwork is bundled.
// This offline GIF exercises crops/frame sampling/bounds, not live compositor smoothness.
import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

@main
struct PetSpritePreview {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            print("Usage: pet-sprite-preview INPUT_ATLAS OUTPUT_DIRECTORY")
            return
        }
        let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw PetSpriteError.invalidImage }
        guard image.width == 1536, [1872, 2288].contains(image.height) else { throw PetSpriteError.imageDimensions }
        let atlas = try PetSpriteAtlas(image: image,
            geometry: PetSpriteGeometry(columns: 8, rows: image.height / 208, cellWidth: 192, cellHeight: 208),
            clips: PetSpriteAtlas.standardClips())
        let states: [PetSpriteState] = [.idle, .workRunning, .runRight, .runLeft, .jump, .wave, .review, .failed, .waiting]
        let fps = 25.0 // GIF centiseconds: exact 40ms preview sampling (renderer keeps authored timings).
        let framesPerScene = 50
        let gifURL = output.appendingPathComponent("pet-motion-preview.gif")
        guard let destination = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString,
                                                               states.count * framesPerScene, nil) else {
            throw PetSpriteError.invalidImage
        }
        CGImageDestinationSetProperties(destination,
            [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for (scene, state) in states.enumerated() {
            let clip = atlas.clips[state]!
            for frame in 0..<framesPerScene {
                let elapsed = Double(frame) / fps
                let motion: PetSpriteMotion
                let start: CGFloat
                switch state {
                case .runRight: motion = .walk(distance: 240, duration: 4); start = 84
                case .runLeft: motion = .walk(distance: -240, duration: 4); start = 324
                case .jump: motion = .jump(height: 52, duration: clip.duration); start = 204
                default: motion = .stationary; start = 204
                }
                let sample = motion.sample(elapsed: elapsed, in: CGRect(x: 20, y: 42, width: 368, height: 145),
                    spriteSize: CGSize(width: 96, height: 104), baseline: 187, startingX: start)
                guard let context = CGContext(data: nil, width: 408, height: 212, bitsPerComponent: 8,
                    bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw PetSpriteError.invalidImage }
                context.setFillColor(CGColor(gray: 0.07, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: 408, height: 212))
                context.setStrokeColor(CGColor(gray: 0.35, alpha: 1))
                context.setLineWidth(1)
                context.move(to: CGPoint(x: 20, y: 212 - sample.floorY))
                context.addLine(to: CGPoint(x: 388, y: 212 - sample.floorY))
                context.strokePath()
                let index = clip.frameIndex(at: elapsed, looping: state != .jump && state != .wave)
                let cell = atlas.images(for: state)![index]
                context.interpolationQuality = .none
                context.draw(cell, in: CGRect(x: sample.center.x - sample.size.width / 2,
                    y: 212 - sample.center.y - sample.size.height / 2,
                    width: sample.size.width, height: sample.size.height))
                let label = NSAttributedString(string: "\(state.rawValue)  ·  bounded scene", attributes: [
                    .font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.white])
                context.textPosition = CGPoint(x: 20, y: 212 - 24)
                CTLineDraw(CTLineCreateWithAttributedString(label), context)
                let result = context.makeImage()!
                CGImageDestinationAddImage(destination, result,
                    [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps,
                                                    kCGImagePropertyGIFUnclampedDelayTime: 1 / fps]] as CFDictionary)
                if frame == 0 || (state == .jump && frame == 10) {
                    let url = output.appendingPathComponent("scene-\(scene)-\(frame).png")
                    let png = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
                    CGImageDestinationAddImage(png, result, nil)
                    guard CGImageDestinationFinalize(png) else { throw PetSpriteError.invalidImage }
                }
            }
        }
        guard CGImageDestinationFinalize(destination) else { throw PetSpriteError.invalidImage }
        print(gifURL.path)
    }
}
