import CoreGraphics
import Foundation
import ImageIO

/// Generic sprite metadata, independent of catalog versions, accounts and preferences.
enum PetSpriteState: String, CaseIterable, Codable {
    case idle, workRunning, runLeft, runRight, wave, jump, failed, waiting, review
}

enum PetSpriteError: Error, Equatable {
    case invalidGeometry, invalidClip, imageDimensions, imageTooLarge, invalidImage, duplicateState, missingClip
}

struct PetSpriteGeometry: Equatable {
    let columns: Int
    let rows: Int
    let cellWidth: Int
    let cellHeight: Int

    init(columns: Int, rows: Int, cellWidth: Int, cellHeight: Int) throws {
        guard (1...32).contains(columns), (1...32).contains(rows),
              (1...2048).contains(cellWidth), (1...2048).contains(cellHeight) else {
            throw PetSpriteError.invalidGeometry
        }
        self.columns = columns
        self.rows = rows
        self.cellWidth = cellWidth
        self.cellHeight = cellHeight
    }
}

struct PetSpriteClip: Equatable {
    let state: PetSpriteState
    let row: Int
    let columns: [Int]
    let durations: [TimeInterval]
    let staticFrameIndex: Int
    var duration: TimeInterval { durations.reduce(0, +) }

    init(state: PetSpriteState, row: Int, columns: [Int], durations: [TimeInterval],
         staticFrameIndex: Int = 0) throws {
        guard (0..<32).contains(row), !columns.isEmpty, columns.count <= 32,
              columns.count == durations.count, columns.allSatisfy({ (0..<32).contains($0) }),
              durations.allSatisfy({ $0.isFinite && $0 >= 0.02 && $0 <= 10 }),
              columns.indices.contains(staticFrameIndex) else { throw PetSpriteError.invalidClip }
        self.state = state
        self.row = row
        self.columns = columns
        self.durations = durations
        self.staticFrameIndex = staticFrameIndex
    }

    /// Frame starts plus terminal 1; a duplicate terminal image preserves the final hold.
    var keyTimes: [Double] {
        var elapsed = 0.0
        return durations.map { value in
            defer { elapsed += value }
            return elapsed / duration
        } + [1]
    }

    func frameIndex(at elapsed: TimeInterval, looping: Bool) -> Int {
        guard elapsed.isFinite, elapsed > 0 else { return 0 }
        if !looping && elapsed >= duration { return columns.count - 1 }
        let phase = looping ? elapsed.truncatingRemainder(dividingBy: duration) : elapsed
        var boundary = 0.0
        for (index, hold) in durations.enumerated() {
            boundary += hold
            if phase < boundary { return index }
        }
        return columns.count - 1
    }
}

/// Decodes once and crops whole cells once. No silhouette trimming, cell blending or bundle access.
final class PetSpriteAtlas {
    static let maximumPixels = 32 * 1024 * 1024
    let geometry: PetSpriteGeometry
    let clips: [PetSpriteState: PetSpriteClip]
    private let frames: [PetSpriteState: [CGImage]]

    init(image: CGImage, geometry: PetSpriteGeometry, clips: [PetSpriteClip]) throws {
        guard image.width <= 8192, image.height <= 8192,
              image.width * image.height <= Self.maximumPixels else { throw PetSpriteError.imageTooLarge }
        guard image.width == geometry.columns * geometry.cellWidth,
              image.height == geometry.rows * geometry.cellHeight else { throw PetSpriteError.imageDimensions }
        guard !clips.isEmpty, clips.count <= PetSpriteState.allCases.count else { throw PetSpriteError.invalidClip }
        var validated: [PetSpriteState: PetSpriteClip] = [:]
        var decoded: [PetSpriteState: [CGImage]] = [:]
        for clip in clips {
            guard validated[clip.state] == nil else { throw PetSpriteError.duplicateState }
            guard clip.row < geometry.rows, clip.columns.allSatisfy({ $0 < geometry.columns }) else {
                throw PetSpriteError.invalidClip
            }
            decoded[clip.state] = try clip.columns.map { column in
                // CGImage cropping uses image pixels: origin at the top-left of the source.
                let rect = CGRect(x: column * geometry.cellWidth, y: clip.row * geometry.cellHeight,
                                  width: geometry.cellWidth, height: geometry.cellHeight)
                guard let cell = image.cropping(to: rect) else { throw PetSpriteError.invalidImage }
                return cell
            }
            validated[clip.state] = clip
        }
        self.geometry = geometry
        self.clips = validated
        self.frames = decoded
    }

    convenience init(url: URL, geometry: PetSpriteGeometry, clips: [PetSpriteClip]) throws {
        guard url.isFileURL,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { throw PetSpriteError.invalidImage }
        guard width > 0, height > 0, width <= 8192, height <= 8192,
              width * height <= Self.maximumPixels else { throw PetSpriteError.imageTooLarge }
        guard width == geometry.columns * geometry.cellWidth,
              height == geometry.rows * geometry.cellHeight else { throw PetSpriteError.imageDimensions }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0,
            [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { throw PetSpriteError.invalidImage }
        try self.init(image: image, geometry: geometry, clips: clips)
    }

    func images(for state: PetSpriteState) -> [CGImage]? { frames[state] }

    /// Published v2 rows 0–8. Legacy 8x9 is accepted only with explicit matching geometry;
    /// look-direction rows are poses, not animation frames. Nothing guesses asset version.
    static func standardClips() -> [PetSpriteClip] {
        let rows: [(PetSpriteState, [Double])] = [
            (.idle, [280, 110, 110, 140, 140, 320]),
            (.runRight, [120, 120, 120, 120, 120, 120, 120, 220]),
            (.runLeft, [120, 120, 120, 120, 120, 120, 120, 220]),
            (.wave, [140, 140, 140, 280]), (.jump, [140, 140, 140, 140, 280]),
            (.failed, [140, 140, 140, 140, 140, 140, 140, 240]),
            (.waiting, [150, 150, 150, 150, 150, 260]),
            (.workRunning, [120, 120, 120, 120, 120, 220]),
            (.review, [150, 150, 150, 150, 150, 280])
        ]
        return rows.enumerated().map { row, entry in
            // Fixed, validated constants; asset-supplied metadata always uses the throwing initializer.
            try! PetSpriteClip(state: entry.0, row: row, columns: Array(entry.1.indices),
                               durations: entry.1.map { $0 / 1000 })
        }
    }
}
