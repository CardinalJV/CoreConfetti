import Foundation
import SwiftUI
#if canImport(Testing)
import Testing
@testable import CoreConfetti

/// The arithmetic behind a burst: the two timing curves, and the flight each
/// confetto is handed. CoreAnimation is told the curves rather than the points,
/// so this is where a burst can be read back and pinned down.
struct ConfettiFlightTests {

    // MARK: - Timing curves

    @Test
    func aCurvePinsBothEndsAndClampsBeyondThem() {
        let curve = ConfettiPhysics.throwCurve

        #expect(curve.value(at: 0) == 0)
        #expect(curve.value(at: 1) == 1)
        #expect(curve.value(at: -1) == 0)
        #expect(curve.value(at: 2) == 1)
    }

    @Test
    func theStraightBezierIsTheIdentity() {
        let curve = UnitBezier(1.0 / 3, 1.0 / 3, 2.0 / 3, 2.0 / 3)

        for step in 0...10 {
            let fraction = Double(step) / 10
            #expect(abs(curve.value(at: fraction) - fraction) < 0.001)
        }
    }

    @Test
    func neitherCurveEverGoesBackwards() {
        for curve in [ConfettiPhysics.throwCurve, ConfettiPhysics.fallCurve] {
            var previous = 0.0
            for step in 0...100 {
                let value = curve.value(at: Double(step) / 100)
                #expect(value >= previous - 1e-9)
                previous = value
            }
        }
    }

    /// A third of the way in, the throw is nearly spent and the fall has hardly
    /// begun. That gap is the shape of a burst: a pop, then a long sink.
    @Test
    func theThrowIsFrontLoadedAndTheFallHoldsBack() {
        #expect(ConfettiPhysics.throwCurve.value(at: 0.33) > 0.8)
        #expect(ConfettiPhysics.fallCurve.value(at: 0.33) < 0.2)
    }

    // MARK: - Where a confetto goes

    @Test
    func aThrowStaysInsideTheConeAndWithinTheRadius() {
        var generator = SeededGenerator(seed: 20_260_902)
        let settings = ConfettiSettings()

        for _ in 0..<500 {
            let thrown = ConfettiFlight.random(settings: settings, using: &generator).throwOffset

            #expect(hypot(thrown.x, thrown.y) <= settings.radius + 0.001)
            // The default cone is 60° to 120°: up, and never more than halfway
            // towards sideways.
            #expect(thrown.y <= 0.001)
            #expect(abs(thrown.x) <= abs(thrown.y) + 0.001)
        }
    }

    @Test
    func aConeThatWrapsPastZeroIsStillACone() {
        var generator = SeededGenerator(seed: 99)
        let settings = ConfettiSettings(openingAngle: .degrees(300), closingAngle: .degrees(60))

        for _ in 0..<200 {
            let thrown = ConfettiFlight.random(settings: settings, using: &generator).throwOffset
            let degrees = (atan2(-thrown.y, thrown.x) * 180 / .pi + 360)
                .truncatingRemainder(dividingBy: 360)

            // Everything lands in the right-hand half: past 300° or short of 60°.
            #expect(degrees >= 299.99 || degrees <= 60.01)
        }
    }

    /// The throw runs its full course even though the fall starts long before it
    /// ends — the two add up rather than one cutting the other short. A burst
    /// that only reached a third of its radius would be the giveaway.
    @Test
    func theThrowReachesItsFullRadiusWhileTheFallIsBarelyUnderway() {
        var generator = SeededGenerator(seed: 4)
        let flight = ConfettiFlight.random(settings: ConfettiSettings(), using: &generator)
        let landed = flight.offset(at: flight.throwDuration)

        #expect(abs(landed.x - flight.throwOffset.x) < 0.001)
        // Everything the confetto has dropped by then is the fall's doing, and
        // the fall has hardly started.
        let fallen = landed.y - flight.throwOffset.y
        #expect(fallen > 0)
        #expect(fallen < flight.rainHeight * 0.02)
    }

    @Test
    func aFlightEndsOneRainHeightBelowWhereItWasThrown() {
        var generator = SeededGenerator(seed: 512)
        let settings = ConfettiSettings(rainHeight: 400)
        let flight = ConfettiFlight.random(settings: settings, using: &generator)
        let landing = flight.offset(at: flight.duration)

        #expect(abs(flight.landingOffset.y - (flight.throwOffset.y + 400)) < 0.001)
        #expect(abs(landing.x - flight.landingOffset.x) < 0.001)
        #expect(abs(landing.y - flight.landingOffset.y) < 0.001)
    }

    /// A confetto is carried outwards the whole way, rises to roughly where the
    /// throw was aiming, and only then comes down past it.
    @Test
    func aConfettoRisesToTheThrowAndThenComesDown() {
        var generator = SeededGenerator(seed: 77)
        let flight = ConfettiFlight.random(settings: ConfettiSettings(), using: &generator)

        var highest = 0.0
        var previousX = 0.0
        for step in 0...200 {
            let now = flight.offset(at: Double(step) / 200 * flight.duration)
            #expect(abs(now.x) >= abs(previousX) - 0.001)
            highest = min(highest, now.y)
            previousX = now.x
        }

        // Up is negative: it gets most of the way to the throw before the fall
        // starts winning, and it ends one rain height below where it was aimed.
        #expect(highest < flight.throwOffset.y * 0.7)
        #expect(abs(flight.offset(at: flight.duration).y - flight.landingOffset.y) < 0.001)
    }

    // MARK: - How a confetto fades

    @Test
    func aConfettoFadesInOnTheThrowAndIsGoneOnLanding() {
        var generator = SeededGenerator(seed: 1_234)
        let flight = ConfettiFlight.random(settings: ConfettiSettings(), using: &generator)

        #expect(flight.opacity(at: 0) == 0)
        // All but solid by the time the throw is done, and still mostly there
        // halfway down: the fade is the fall's, and the fall saves it for the end.
        #expect(flight.opacity(at: flight.throwDuration) > 0.9)
        #expect(flight.opacity(at: flight.duration / 2) > 0.6)
        #expect(abs(flight.opacity(at: flight.duration)) < 0.001)
    }

    @Test
    func aConfettoThatDoesNotFadeOutKeepsItsOpacity() {
        var generator = SeededGenerator(seed: 8)
        let settings = ConfettiSettings(opacity: 0.6, fadesOut: false)
        let flight = ConfettiFlight.random(settings: settings, using: &generator)

        #expect(abs(flight.opacity(at: flight.throwDuration) - 0.6) < 0.001)
        #expect(abs(flight.opacity(at: flight.duration) - 0.6) < 0.001)
    }

    @Test
    func opacityNeverLeavesTheRangeItWasGiven() {
        var generator = SeededGenerator(seed: 31)
        let settings = ConfettiSettings(opacity: 0.9)

        for _ in 0..<50 {
            let flight = ConfettiFlight.random(settings: settings, using: &generator)
            for step in 0...100 {
                let opacity = flight.opacity(at: Double(step) / 100 * flight.duration)
                #expect(opacity >= -0.001)
                #expect(opacity <= 0.901)
            }
        }
    }

    // MARK: - What a volley is made of

    @Test
    func everyConfettoIsOneOfTheShapesAndColoursAskedFor() {
        var generator = SeededGenerator(seed: 61)
        let settings = ConfettiSettings(
            shapes: [.symbol("music.note"), .circle],
            colors: [.purple, .pink]
        )

        for _ in 0..<100 {
            let flight = ConfettiFlight.random(settings: settings, using: &generator)
            #expect(settings.shapes.contains(flight.shape))
            #expect(settings.colors.contains(flight.color))
        }
    }

    @Test
    func aVolleyLastsUntilTheLastRepetitionHasLanded() {
        let settings = ConfettiSettings(repetitions: 5, repetitionInterval: 0.25)

        #expect(abs(settings.volleyDuration - (1.0 + settings.flightDuration)) < 0.001)
        #expect(settings.flightDuration > 4.5)
    }

    @Test
    func oneRepetitionLastsExactlyOneFlight() {
        let settings = ConfettiSettings(repetitions: 1, repetitionInterval: 3)

        #expect(abs(settings.volleyDuration - settings.flightDuration) < 0.001)
    }

    /// A cannon with nowhere to rain is over when the throw is: the flight has
    /// to outlast whichever of the two takes longer, not just the fall.
    @Test
    func aFlightOutlastsWhicheverPhaseIsLonger() {
        var generator = SeededGenerator(seed: 5)
        let settings = ConfettiSettings(radius: 30, rainHeight: 0)
        let flight = ConfettiFlight.random(settings: settings, using: &generator)

        #expect(flight.throwDuration > flight.fallDelay + flight.fallDuration)
        #expect(abs(flight.duration - flight.throwDuration) < 0.001)
        #expect(settings.flightDuration >= flight.duration)
    }
}

/// SplitMix64, so a burst can be drawn the same way twice.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
#endif
