//
//  ConfettiFlight.swift
//  CoreConfetti
//

import CoreGraphics
import Foundation
import SwiftUI

/// The numbers behind a burst, kept together because they are the ones that have
/// to stay in step with ConfettiSwiftUI for a burst to look unchanged.
enum ConfettiPhysics {
    /// The throw: nearly all of its distance is covered in the first frames.
    static let throwCurve = UnitBezier(0.1, 0.8, 0, 1)
    /// The fall: flat for most of its length, then a plunge. Gravity, as a curve.
    static let fallCurve = UnitBezier(0.12, 0, 0.39, 0)

    /// A wider throw takes longer, in proportion.
    static func throwSpan(radius: CGFloat) -> TimeInterval {
        Double(radius) / 1300
    }

    /// Every throw takes this long plus a share of the jitter, so a volley never
    /// travels as one sheet.
    static func longestThrowDuration(radius: CGFloat) -> TimeInterval {
        0.2 + throwSpan(radius: radius) + throwJitter.upperBound
    }

    /// How long the confetto has been in the air before the fall joins in — a
    /// tenth of the throw, a frame or two.
    static func fallDelay(radius: CGFloat) -> TimeInterval {
        throwSpan(radius: radius) * 0.1
    }

    /// The fall is paced by the throw's radius as well as the rain: a confetto
    /// thrown further has further to come down from.
    static func fallDuration(radius: CGFloat, rainHeight: CGFloat) -> TimeInterval {
        Double(rainHeight + radius) / 200
    }

    /// The spread of throw durations across a burst.
    static let throwJitter: ClosedRange<Double> = 0...(999.0 / 2100.0)
    /// Seconds for one turn, on either axis.
    static let spinSpeeds: ClosedRange<Double> = 0.501...2.201
}

/// One confetto's whole flight, drawn up front.
///
/// The throw and the fall are not two halves of a path: they are two animations
/// that *add up*. The throw runs its own course to the full radius while the
/// fall, starting a frame later, layers a downward drift and the fade over it.
/// That is what SwiftUI does with the two animations the package starts on the
/// same value, and it is why a burst pops to its full width and then sinks
/// rather than easing to a stop. Two additive CoreAnimation animations per
/// property say the same thing to the render server, exactly, with no sampling.
struct ConfettiFlight: Sendable {
    let shape: ConfettiShape
    let color: Color
    /// Where the throw is aiming, as an offset from the muzzle.
    let throwOffset: CGPoint
    /// How far the fall carries the confetto down from wherever the throw left it.
    let rainHeight: CGFloat
    let throwDuration: TimeInterval
    let fallDelay: TimeInterval
    let fallDuration: TimeInterval
    /// The opacity the throw fades in to, and the one the fall leaves behind.
    let peakOpacity: Double
    let landingOpacity: Double
    /// One turn around the horizontal axis — the flip that shows a confetto edge
    /// on — and its direction.
    let flipDuration: TimeInterval
    let flipDirection: Double
    /// One turn in the plane, around a corner rather than around the middle.
    let spinDuration: TimeInterval
    let spinDirection: Double
    /// The corner spun around: 0 or 1 on both axes.
    let spinAnchor: CGFloat

    /// Where the confetto comes to rest, as an offset from the muzzle.
    var landingOffset: CGPoint {
        CGPoint(x: throwOffset.x, y: throwOffset.y + rainHeight)
    }

    /// How long this confetto is in the air, whichever of the two lasts longer.
    var duration: TimeInterval {
        max(throwDuration, fallDelay + fallDuration)
    }

    /// Draws one confetto's flight from the settings' spread of angles,
    /// distances, speeds and shapes.
    static func random<G: RandomNumberGenerator>(
        settings: ConfettiSettings,
        using generator: inout G
    ) -> ConfettiFlight {
        let angle = randomAngle(settings: settings, using: &generator)
        let radians = angle * .pi / 180
        // Distances crowd towards the rim: without the root the middle of the
        // cone takes almost every confetto and the burst reads as a fountain.
        let spread = pow(Double.random(in: 0.01...1, using: &generator), 2.0 / 7.0)
        let distance = spread * Double(settings.radius)

        // Shape first, because a shape with its own palette picks from that one
        // rather than from the burst's.
        let shape = settings.shapes.randomElement(using: &generator) ?? .circle
        let palette = settings.colors(for: shape)

        return ConfettiFlight(
            shape: shape,
            color: palette.randomElement(using: &generator) ?? .purple,
            throwOffset: CGPoint(x: cos(radians) * distance, y: -sin(radians) * distance),
            rainHeight: settings.rainHeight,
            throwDuration: 0.2
                + ConfettiPhysics.throwSpan(radius: settings.radius)
                + Double.random(in: ConfettiPhysics.throwJitter, using: &generator),
            fallDelay: ConfettiPhysics.fallDelay(radius: settings.radius),
            fallDuration: ConfettiPhysics.fallDuration(radius: settings.radius, rainHeight: settings.rainHeight),
            peakOpacity: settings.opacity,
            landingOpacity: settings.fadesOut ? 0 : settings.opacity,
            flipDuration: Double.random(in: ConfettiPhysics.spinSpeeds, using: &generator),
            flipDirection: Bool.random(using: &generator) ? 1 : -1,
            spinDuration: Double.random(in: ConfettiPhysics.spinSpeeds, using: &generator),
            spinDirection: Bool.random(using: &generator) ? 1 : -1,
            spinAnchor: Bool.random(using: &generator) ? 1 : 0
        )
    }

    /// Where the confetto is, as an offset from the muzzle, at a moment in its
    /// flight: the throw plus the fall, one laid over the other.
    ///
    /// CoreAnimation is told the two curves rather than these points — this is
    /// here so the flight can be read, and checked, without a screen.
    func offset(at time: TimeInterval) -> CGPoint {
        let thrown = ConfettiPhysics.throwCurve.value(at: time / throwDuration)
        let fallen = ConfettiPhysics.fallCurve.value(at: (time - fallDelay) / fallDuration)
        return CGPoint(
            x: throwOffset.x * thrown,
            y: throwOffset.y * thrown + rainHeight * fallen
        )
    }

    /// The same, for how visible the confetto is: it fades in on the throw and
    /// out on the fall, both at once.
    func opacity(at time: TimeInterval) -> Double {
        let thrown = ConfettiPhysics.throwCurve.value(at: time / throwDuration)
        let fallen = ConfettiPhysics.fallCurve.value(at: (time - fallDelay) / fallDuration)
        return peakOpacity * thrown + (landingOpacity - peakOpacity) * fallen
    }

    /// An angle inside the cone, counter-clockwise from the muzzle. A cone that
    /// wraps past 0° — opening after closing — is walked the long way round and
    /// folded back.
    private static func randomAngle<G: RandomNumberGenerator>(
        settings: ConfettiSettings,
        using generator: inout G
    ) -> Double {
        let opening = settings.openingAngle.degrees
        let closing = settings.closingAngle.degrees
        guard opening > closing else {
            return Double.random(in: opening...closing, using: &generator)
        }
        let wrapped = max(opening, closing + 360)
        return Double.random(in: opening...wrapped, using: &generator)
            .truncatingRemainder(dividingBy: 360)
    }
}

/// A cubic bezier timing curve, solved the way CoreAnimation and SwiftUI solve
/// theirs: find the parameter whose x is the elapsed fraction, read its y.
///
/// CoreAnimation is handed the curves themselves, so this is not what drives a
/// burst — it is what lets one be read off without a screen, and tested.
struct UnitBezier: Sendable {
    private let ax, bx, cx: Double
    private let ay, by, cy: Double

    init(_ p1x: Double, _ p1y: Double, _ p2x: Double, _ p2y: Double) {
        cx = 3 * p1x
        bx = 3 * (p2x - p1x) - cx
        ax = 1 - cx - bx
        cy = 3 * p1y
        by = 3 * (p2y - p1y) - cy
        ay = 1 - cy - by
    }

    /// The curve's value at an elapsed fraction of the duration.
    func value(at fraction: Double) -> Double {
        guard fraction > 0 else { return 0 }
        guard fraction < 1 else { return 1 }
        return sampleY(parameter(forX: fraction))
    }

    private func sampleX(_ t: Double) -> Double { ((ax * t + bx) * t + cx) * t }
    private func sampleY(_ t: Double) -> Double { ((ay * t + by) * t + cy) * t }
    private func slopeX(_ t: Double) -> Double { (3 * ax * t + 2 * bx) * t + cx }

    /// Newton-Raphson first, bisection once the slope goes flat and Newton stops
    /// converging: the standard solver.
    private func parameter(forX x: Double) -> Double {
        var t = x
        for _ in 0..<8 {
            let error = sampleX(t) - x
            if abs(error) < Self.epsilon { return t }
            let slope = slopeX(t)
            if abs(slope) < Self.epsilon { break }
            t -= error / slope
        }

        var low = 0.0
        var high = 1.0
        t = x
        while low < high {
            let sampled = sampleX(t)
            if abs(sampled - x) < Self.epsilon { return t }
            if x > sampled { low = t } else { high = t }
            let next = (high - low) / 2 + low
            if abs(next - t) < Self.epsilon { return next }
            t = next
        }
        return t
    }

    private static let epsilon = 1e-6
}
