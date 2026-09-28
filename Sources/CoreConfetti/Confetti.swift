//
//  Confetti.swift
//  CoreConfetti
//

import SwiftUI

/// What a single confetto is drawn as.
///
/// The five paper shapes are the ones ConfettiSwiftUI throws; `symbol` is the
/// reason this cannon exists at all — any SF Symbol can be a confetto, drawn at
/// the confetti size in the confetto's colour.
public enum ConfettiShape: Hashable, Sendable {
    case circle
    case square
    case triangle
    /// A wide flat sliver: the paper streamer.
    case slimRectangle
    case roundedCross
    /// An SF Symbol, by name.
    case symbol(String)
    /// A short string, usually one emoji. Emoji keep their own colours.
    case text(String)

    /// What a cannon throws when no shapes are asked for.
    public static let paper: [ConfettiShape] = [.circle, .triangle, .square, .slimRectangle, .roundedCross]
}

/// Everything a burst is made of. The defaults match ConfettiSwiftUI's, so a
/// cannon left alone throws what the package threw.
public struct ConfettiSettings: Sendable {
    /// Confetti per repetition.
    public var count: Int = 20
    public var shapes: [ConfettiShape] = ConfettiShape.paper
    public var colors: [Color] = [.blue, .red, .green, .yellow, .pink, .purple, .orange]
    /// Per-shape palettes. A shape listed here is drawn in its own colours;
    /// every other shape draws from `colors`.
    public var shapeColors: [ConfettiShape: [Color]] = [:]
    /// Side length for the paper shapes, point size for symbols and text.
    public var size: CGFloat = 10
    public var opacity: Double = 1
    /// Where in the view the cannon sits. The middle by default; `.top` turns
    /// the burst into rain down the screen.
    public var muzzle: UnitPoint = .center
    /// The cone the burst is thrown into, counter-clockwise from the muzzle:
    /// 60° to 120° is straight up.
    public var openingAngle: Angle = .degrees(60)
    public var closingAngle: Angle = .degrees(120)
    /// How far the throw carries a confetto.
    public var radius: CGFloat = 300
    /// How far a confetto falls afterwards, on top of wherever it was thrown.
    public var rainHeight: CGFloat = 600
    public var fadesOut: Bool = true
    /// How many bursts one trigger fires.
    public var repetitions: Int = 1
    public var repetitionInterval: TimeInterval = 1
    /// Off by default: a library has no business reaching for the Taptic Engine
    /// unless it was asked to.
    public var hapticFeedback: Bool = false
    /// Honours the system's Reduce Motion setting. When that setting is on, the
    /// burst is drawn as a still scatter that fades in and out rather than
    /// thrown: confetti are a decoration, and nobody should have to feel ill to
    /// see one. Turn it off only if the cannon is the content itself.
    public var respectsReduceMotion: Bool = true

    /// Every knob, each with the default a cannon left alone uses.
    public init(
        count: Int = 20,
        shapes: [ConfettiShape] = ConfettiShape.paper,
        colors: [Color] = [.blue, .red, .green, .yellow, .pink, .purple, .orange],
        shapeColors: [ConfettiShape: [Color]] = [:],
        size: CGFloat = 10,
        opacity: Double = 1,
        muzzle: UnitPoint = .center,
        openingAngle: Angle = .degrees(60),
        closingAngle: Angle = .degrees(120),
        radius: CGFloat = 300,
        rainHeight: CGFloat = 600,
        fadesOut: Bool = true,
        repetitions: Int = 1,
        repetitionInterval: TimeInterval = 1,
        hapticFeedback: Bool = false,
        respectsReduceMotion: Bool = true
    ) {
        self.count = count
        self.shapes = shapes
        self.colors = colors
        self.shapeColors = shapeColors
        self.size = size
        self.opacity = opacity
        self.muzzle = muzzle
        self.openingAngle = openingAngle
        self.closingAngle = closingAngle
        self.radius = radius
        self.rainHeight = rainHeight
        self.fadesOut = fadesOut
        self.repetitions = repetitions
        self.repetitionInterval = repetitionInterval
        self.hapticFeedback = hapticFeedback
        self.respectsReduceMotion = respectsReduceMotion
    }

    /// The palette one shape draws from: its own if it has one, the burst's
    /// otherwise.
    public func colors(for shape: ConfettiShape) -> [Color] {
        guard let own = shapeColors[shape], !own.isEmpty else { return colors }
        return own
    }

    /// How long the longest confetto is in the air. The fall almost always
    /// outlasts the throw, but a wide cannon with nowhere to rain does not.
    public var flightDuration: TimeInterval {
        max(
            ConfettiPhysics.longestThrowDuration(radius: radius),
            ConfettiPhysics.fallDelay(radius: radius)
                + ConfettiPhysics.fallDuration(radius: radius, rainHeight: rainHeight)
        )
    }

    /// How long a whole trigger lasts, last repetition included.
    public var volleyDuration: TimeInterval {
        Double(max(0, repetitions - 1)) * repetitionInterval + flightDuration
    }
}

/// Ready-made bursts. Each one is a plain value, so it can be taken as a
/// starting point and adjusted:
///
///     var settings = ConfettiSettings.stars
///     settings.count = 50
extension ConfettiSettings {

    /// The paper burst: what the cannon throws when nothing is asked of it.
    public static let paper = ConfettiSettings()

    /// Stars and sparkles, in gold.
    public static let stars = ConfettiSettings(
        shapes: [.symbol("star.fill"), .symbol("sparkle")],
        colors: [.yellow, .orange],
        size: 16
    )

    /// Hearts, in the colours they are usually drawn in.
    public static let hearts = ConfettiSettings(
        shapes: [.symbol("heart.fill")],
        colors: [.pink, .red, .purple],
        size: 16
    )

    /// A volley rather than a single burst: three bursts a quarter-second apart.
    public static let celebration = ConfettiSettings(
        count: 30,
        size: 12,
        repetitions: 3,
        repetitionInterval: 0.25
    )

    /// Confetti falling down the whole screen rather than fired from a point.
    /// Attach this one to something that fills the screen.
    public static let rain = ConfettiSettings(
        count: 40,
        size: 12,
        muzzle: .top,
        openingAngle: .degrees(0),
        closingAngle: .degrees(180),
        radius: 220,
        rainHeight: 1200
    )
}
