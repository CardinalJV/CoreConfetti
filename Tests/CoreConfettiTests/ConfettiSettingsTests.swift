import Foundation
import SwiftUI
#if canImport(Testing) && canImport(UIKit)
import Testing
import UIKit
@testable import CoreConfetti

/// The settings a caller is handed: the defaults a library is entitled to pick
/// for them, and the presets shipped as finished bursts.
struct ConfettiSettingsTests {

    // MARK: - Presets

    /// A mistyped symbol in a shipped preset is the worst place for that typo:
    /// it asserts in the app of whoever tried the preset, not here. SF Symbols
    /// also come and go between OS versions, so this is checked against the
    /// system the tests run on rather than against a list.
    @MainActor
    @Test(arguments: [
        ("paper", ConfettiSettings.paper),
        ("stars", ConfettiSettings.stars),
        ("hearts", ConfettiSettings.hearts),
        ("celebration", ConfettiSettings.celebration),
        ("rain", ConfettiSettings.rain)
    ])
    func everySymbolInAPresetIsRealOnThisSystem(named: String, settings: ConfettiSettings) {
        for shape in settings.shapes {
            guard case .symbol(let name) = shape else { continue }
            #expect(
                UIImage(systemName: name) != nil,
                "preset .\(named) asks for SF Symbol \"\(name)\", which does not exist here"
            )
        }
    }

    @Test
    func everyPresetThrowsSomething() {
        for settings in [ConfettiSettings.paper, .stars, .hearts, .celebration, .rain] {
            #expect(settings.count > 0)
            #expect(settings.repetitions > 0)
            #expect(!settings.shapes.isEmpty)
            #expect(!settings.colors.isEmpty)
        }
    }

    /// Rain is the preset that exists to prove the muzzle moves.
    @Test
    func rainFallsFromTheTop() {
        #expect(ConfettiSettings.rain.muzzle == .top)
        #expect(ConfettiSettings.rain.rainHeight > ConfettiSettings().rainHeight)
    }

    // MARK: - Defaults

    /// The two defaults a library does not get to choose loosely: it does not
    /// touch the Taptic Engine unasked, and it does not ignore Reduce Motion.
    @Test
    func theDefaultsAreTheQuietOnes() {
        let settings = ConfettiSettings()

        #expect(settings.hapticFeedback == false)
        #expect(settings.respectsReduceMotion)
        #expect(settings.muzzle == .center)
    }
}
#endif
