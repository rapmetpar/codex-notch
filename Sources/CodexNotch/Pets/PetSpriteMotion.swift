import CoreGraphics
import Foundation

struct PetSpriteMotionSample: Equatable {
    /// Top-left/y-down scene coordinates, measured in points. Entire untrimmed cell stays safe.
    let center: CGPoint
    let size: CGSize
    let floorY: CGFloat
    let bottomContact: CGPoint
    let isGrounded: Bool
}

/// Stateless bounded sampling. Callers retain startingX and a common baseline across pet/clip
/// changes; elapsed is scene-local (not a wall clock or a view position). Never moves NSWindows.
enum PetSpriteMotion: Equatable {
    case stationary
    /// A smooth out-and-back walk returning to startingX, with zero velocity at reversals.
    case walk(distance: CGFloat, duration: TimeInterval)
    /// One anticipation/lift/settle arc. Returns to precisely the original floor contact.
    case jump(height: CGFloat, duration: TimeInterval)

    func sample(elapsed: TimeInterval, in safeRect: CGRect, spriteSize: CGSize,
                baseline: CGFloat, startingX: CGFloat) -> PetSpriteMotionSample {
        guard safeRect.origin.x.isFinite, safeRect.origin.y.isFinite,
              safeRect.width.isFinite, safeRect.height.isFinite,
              safeRect.width > 0, safeRect.height > 0 else {
            return PetSpriteMotionSample(center: .zero, size: .zero, floorY: 0,
                                         bottomContact: .zero, isGrounded: true)
        }
        let requestedWidth = spriteSize.width.isFinite ? max(0, spriteSize.width) : 0
        let requestedHeight = spriteSize.height.isFinite ? max(0, spriteSize.height) : 0
        let scale = min(1, safeRect.width / max(1, requestedWidth), safeRect.height / max(1, requestedHeight))
        let size = CGSize(width: requestedWidth * scale, height: requestedHeight * scale)
        let minX = safeRect.minX + size.width / 2
        let maxX = safeRect.maxX - size.width / 2
        let x = min(maxX, max(minX, startingX.isFinite ? startingX : safeRect.midX))
        let floor = min(safeRect.maxY, max(safeRect.minY + size.height,
                                         baseline.isFinite ? baseline : safeRect.maxY))
        let time = elapsed.isFinite ? max(0, elapsed) : 0
        var resultX = x
        var lift: CGFloat = 0
        switch self {
        case .stationary: break
        case .walk(let distance, let duration):
            if duration.isFinite, duration > 0, distance.isFinite {
                let phase = time.truncatingRemainder(dividingBy: duration) / duration
                let excursion = CGFloat((1 - cos(phase * .pi * 2)) / 2)
                // Clamp excursion before sampling; never hit a wall at nonzero velocity.
                let boundedDistance = min(maxX - x, max(minX - x, distance))
                resultX += boundedDistance * excursion
            }
        case .jump(let height, let duration):
            if duration.isFinite, duration > 0, height.isFinite {
                let progress = min(1, time / duration)
                // First/last fifth reserve authored anticipation and contact frames.
                let airborne = min(1, max(0, (progress - 0.2) / 0.6))
                let arc = pow(sin(airborne * .pi), 2)
                lift = min(max(0, height), max(0, floor - size.height - safeRect.minY)) * arc
            }
        }
        let center = CGPoint(x: resultX, y: floor - size.height / 2 - lift)
        return PetSpriteMotionSample(center: center, size: size, floorY: floor,
                                     bottomContact: CGPoint(x: resultX, y: floor - lift),
                                     isGrounded: lift < 0.000001)
    }
}

/// Precomputed path for a native position keyframe animation; no callback or clock ownership.
struct PetSpriteMotionTrack {
    let samples: [PetSpriteMotionSample]
    let keyTimes: [Double]
    let duration: TimeInterval
    let repeats: Bool
}

extension PetSpriteMotion {
    /// At most 901 samples (30 seconds at 30 Hz), including both contact endpoints.
    /// Reject over-budget input rather than silently changing authored movement timing.
    func track(in safeRect: CGRect, spriteSize: CGSize, baseline: CGFloat,
               startingX: CGFloat) -> PetSpriteMotionTrack? {
        let duration: TimeInterval
        let repeats: Bool
        switch self {
        case .stationary: return nil
        case .walk(_, let value): duration = value; repeats = true
        case .jump(_, let value): duration = value; repeats = false
        }
        guard duration.isFinite, duration > 0, duration <= 30 else { return nil }
        let intervals = max(1, Int(ceil(duration * 30)))
        let times = (0...intervals).map { Double($0) / Double(intervals) }
        return PetSpriteMotionTrack(samples: times.map {
            sample(elapsed: $0 * duration, in: safeRect, spriteSize: spriteSize,
                   baseline: baseline, startingX: startingX)
        }, keyTimes: times, duration: duration, repeats: repeats)
    }
}
