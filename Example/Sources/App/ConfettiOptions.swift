//
//  ConfettiOptions.swift
//  CoreConfetti
//

import SwiftUI
import CoreConfetti

/// The knobs the demo exposes in its sheet: how many confetti, in which
/// colours, drawn as which SF Symbols.
///
/// It is deliberately a small subset of `ConfettiSettings` — everything else
/// the cannon can do keeps its default.
@Observable
final class ConfettiOptions {

    /// Confetti per burst.
    var count: Int = 20

    /// The palette entries currently ticked. Never empty: the sheet keeps the
    /// last one from being unticked.
    var colorNames: Set<String> = ["Purple", "Pink", "Orange"]

    /// The symbols currently ticked. May be empty, in which case the cannon
    /// falls back to the paper shapes.
    var symbolNames: Set<String> = ["music.note", "star.fill"]

    /// A symbol's own colour, by palette name. A symbol with no entry here
    /// draws from the general palette like everything else.
    var symbolColorNames: [String: String] = [:]

    /// How many bursts one press of Fire sends up.
    var shots: Int = 3

    /// Every colour the sheet offers, in the order it shows them.
    static let palette: [(name: String, color: Color)] = [
        ("Purple", .purple),
        ("Pink", .pink),
        ("Orange", .orange),
        ("Red", .red),
        ("Yellow", .yellow),
        ("Green", .green),
        ("Mint", .mint),
        ("Blue", .blue),
        ("Indigo", .indigo)
    ]

    /// Every symbol the sheet offers.
    static let symbolChoices: [String] = [
        "music.note",
        "star.fill",
        "heart.fill",
        "sparkles",
        "bolt.fill",
        "flame.fill",
        "leaf.fill",
        "moon.stars.fill",
        "sun.max.fill",
        "drop.fill",
        "snowflake",
        "party.popper.fill",
        "gift.fill",
        "crown.fill",
        "pawprint.fill",
        "die.face.5.fill"
    ]

    var colors: [Color] {
        let picked = Self.palette.filter { colorNames.contains($0.name) }.map(\.color)
        return picked.isEmpty ? Self.palette.map(\.color) : picked
    }

    var shapes: [ConfettiShape] {
        let picked = Self.symbolChoices
            .filter { symbolNames.contains($0) }
            .map { ConfettiShape.symbol($0) }
        return picked.isEmpty ? ConfettiShape.paper : picked
    }

    /// Only the symbols that were given a colour of their own end up here; the
    /// rest are left out, so the cannon falls back to the general palette.
    var shapeColors: [ConfettiShape: [Color]] {
        var map: [ConfettiShape: [Color]] = [:]
        for name in symbolNames {
            guard let colorName = symbolColorNames[name],
                  let color = Self.color(named: colorName)
            else { continue }
            map[.symbol(name)] = [color]
        }
        return map
    }

    static func color(named name: String) -> Color? {
        palette.first { $0.name == name }?.color
    }

    /// What the cannon actually fires.
    var settings: ConfettiSettings {
        ConfettiSettings(
            count: count,
            shapes: shapes,
            colors: colors,
            shapeColors: shapeColors,
            size: 15,
            repetitions: shots,
            repetitionInterval: 0.25,
            // The cannon leaves haptics off; a demo of a cannon wants them.
            hapticFeedback: true
        )
    }
}
