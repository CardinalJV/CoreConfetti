//
//  ConfettiCannon.swift
//  CoreConfetti
//

import SwiftUI
import UIKit

extension View {

    /// Fires confetti from the middle of this view whenever `trigger` changes.
    ///
    /// A CoreAnimation stand-in for ConfettiSwiftUI: same cone, same throw and
    /// fall curves, same flip and spin, so a burst looks like the one that came
    /// before it — but each confetto is a cached bitmap on a layer with four
    /// animations, rather than a SwiftUI view redrawing itself sixty times a
    /// second. Nothing runs on the main thread once a volley is in the air, and
    /// the shapes can be SF Symbols.
    ///
    /// Drawn as an overlay: the cannon never takes part in layout, and confetti
    /// are free to travel outside the view they were fired from.
    ///
    ///     Text("Winner")
    ///         .confettiCannon(trigger: score, settings: .init(shapes: [.symbol("music.note")]))
    public func confettiCannon<Trigger: Equatable>(
        trigger: Trigger,
        settings: ConfettiSettings = ConfettiSettings()
    ) -> some View {
        overlay {
            ConfettiCannonView(trigger: trigger, settings: settings)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// The bridge: a change of `trigger` fires the view underneath, and nothing else
/// SwiftUI does to this view does anything at all.
private struct ConfettiCannonView<Trigger: Equatable>: UIViewRepresentable {
    let trigger: Trigger
    let settings: ConfettiSettings

    func makeCoordinator() -> Coordinator {
        // Seeded with the value it is born with, so appearing on screen is not
        // itself a burst.
        Coordinator(trigger: trigger)
    }

    func makeUIView(context: Context) -> ConfettiCannonUIView {
        let view = ConfettiCannonUIView()
        view.settings = settings
        return view
    }

    func updateUIView(_ uiView: ConfettiCannonUIView, context: Context) {
        uiView.settings = settings
        guard context.coordinator.trigger != trigger else { return }
        context.coordinator.trigger = trigger
        uiView.fire()
    }

    @MainActor
    final class Coordinator {
        var trigger: Trigger

        init(trigger: Trigger) {
            self.trigger = trigger
        }
    }
}

/// The cannon itself: builds a volley of layers, hands them to the render
/// server, and clears them once they have landed.
final class ConfettiCannonUIView: UIView {

    var settings = ConfettiSettings()

    /// One entry per trigger, so a volley can be swept up on its own schedule
    /// while later ones are still in the air.
    private struct Volley {
        let layer: CALayer
        let cleanup: Task<Void, Never>
    }

    private var volleys: [Volley] = []
    private var hapticTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        prepare()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        prepare()
    }

    private func prepare() {
        isUserInteractionEnabled = false
        isOpaque = false
        backgroundColor = .clear
        // Confetti spend their whole flight outside these bounds.
        clipsToBounds = false
    }

    /// Leaving the screen ends every volley: a sheet that is dismissed mid-burst
    /// leaves no timers and no layers behind.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window == nil else { return }
        clear()
    }

    func fire() {
        guard settings.count > 0,
              settings.repetitions > 0,
              !settings.shapes.isEmpty
        else { return }

        let still = settings.respectsReduceMotion && UIAccessibility.isReduceMotionEnabled
        let muzzle = CGPoint(
            x: bounds.minX + bounds.width * settings.muzzle.x,
            y: bounds.minY + bounds.height * settings.muzzle.y
        )
        let scale = traitCollection.displayScale
        let now = CACurrentMediaTime()
        var generator = SystemRandomNumberGenerator()

        let volleyLayer = CALayer()
        volleyLayer.frame = bounds

        // Building the layers is the only main-thread work a trigger costs, and
        // it happens once: the repetitions are scheduled by `beginTime` rather
        // than by a timer that would wake the main thread four more times.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for repetition in 0..<settings.repetitions {
            let beginTime = now + Double(repetition) * settings.repetitionInterval
            for _ in 0..<settings.count {
                let flight = ConfettiFlight.random(settings: settings, using: &generator)
                guard let particle = makeParticle(flight, muzzle: muzzle, beginTime: beginTime, scale: scale, still: still) else { continue }
                volleyLayer.addSublayer(particle)
            }
        }
        layer.addSublayer(volleyLayer)
        CATransaction.commit()

        let lifetime = settings.volleyDuration + Self.sweepGrace
        let cleanup = Task { [weak self] in
            try? await Task.sleep(for: .seconds(lifetime))
            guard !Task.isCancelled else { return }
            self?.sweep(volleyLayer)
        }
        volleys.append(Volley(layer: volleyLayer, cleanup: cleanup))

        if settings.hapticFeedback { playHaptics() }
    }

    /// A confetto on its layer, with the four animations that fly it.
    ///
    /// `still` is Reduce Motion: the confetto is put down where the throw would
    /// have carried it and only fades in and out there. Same burst, same spread,
    /// same colours, nothing that moves.
    private func makeParticle(
        _ flight: ConfettiFlight,
        muzzle: CGPoint,
        beginTime: CFTimeInterval,
        scale: CGFloat,
        still: Bool
    ) -> CALayer? {
        guard let image = ConfettiImageStore.image(
            for: flight.shape,
            color: flight.color,
            size: settings.size,
            scale: scale
        ) else { return nil }

        // Spinning around a corner makes that corner the point the flight moves,
        // so the whole flight shifts by the corner's offset from the middle.
        let pivot = CGPoint(
            x: (flight.spinAnchor - 0.5) * image.size.width,
            y: (flight.spinAnchor - 0.5) * image.size.height
        )

        let particle = CALayer()
        particle.bounds = CGRect(origin: .zero, size: image.size)
        particle.anchorPoint = CGPoint(x: flight.spinAnchor, y: flight.spinAnchor)
        particle.sublayerTransform = Self.perspective
        // Model values are where the flight ends. Everything before that is two
        // additive animations walking back from here to the muzzle. Standing
        // still, the throw is where it ends: the confetto never leaves the spread.
        let resting = still ? flight.throwOffset : flight.landingOffset
        particle.position = CGPoint(
            x: muzzle.x + pivot.x + resting.x,
            y: muzzle.y + pivot.y + resting.y
        )
        particle.opacity = Float(flight.landingOpacity)

        let face = CALayer()
        face.frame = particle.bounds
        face.contents = image.cgImage
        face.contentsScale = scale
        face.contentsGravity = .resizeAspect
        particle.addSublayer(face)

        guard !still else {
            particle.add(fade(flight, beginTime: beginTime), forKey: "fade")
            return particle
        }

        // The throw and the fall add up rather than replace one another, and
        // that is the whole shape of a burst: the throw reaches its full radius
        // on its own curve while the fall, a frame later, layers the drift and
        // the fade over it. Each animation carries the distance its own phase
        // still owes, so before either starts the pair cancel out to the muzzle,
        // and once both have run they cancel out to nothing.
        particle.add(
            additive(
                "position",
                from: NSValue(cgPoint: CGPoint(x: -flight.throwOffset.x, y: -flight.throwOffset.y)),
                curve: Self.throwTiming,
                duration: flight.throwDuration,
                beginTime: beginTime
            ),
            forKey: "throw"
        )
        particle.add(
            additive(
                "position",
                from: NSValue(cgPoint: CGPoint(x: 0, y: -flight.rainHeight)),
                curve: Self.fallTiming,
                duration: flight.fallDuration,
                beginTime: beginTime + flight.fallDelay
            ),
            forKey: "fall"
        )
        particle.add(fade(flight, beginTime: beginTime), forKey: "fade")

        // The flip is on the face and the spin on the particle: two rotations on
        // one layer would fight over the same transform, and nesting them also
        // gets the order right — the confetto flips, and the flipped thing spins.
        particle.add(
            turn(
                keyPath: "transform.rotation.z",
                duration: flight.spinDuration,
                direction: flight.spinDirection,
                beginTime: beginTime,
                lifetime: flight.duration
            ),
            forKey: "spin"
        )
        face.add(
            turn(
                keyPath: "transform.rotation.x",
                duration: flight.flipDuration,
                direction: flight.flipDirection,
                beginTime: beginTime,
                lifetime: flight.duration
            ),
            forKey: "flip"
        )

        return particle
    }

    /// How visible the confetto is across its whole flight, sampled from the
    /// flight itself.
    ///
    /// The fade cannot be two additive animations the way the movement is: the
    /// render server clamps opacity to 0...1 between additive steps, so the
    /// fade-in's -1 clamped to 0 and left the fade-out's +1 standing — every
    /// confetto still waiting for its repetition sat at the muzzle at full
    /// opacity, all of them stacked into the one icon that hung on the button
    /// until the last repetition went up. One keyframe of the summed curve says
    /// the same thing with nothing to clamp, and filling backwards from its
    /// first value holds a waiting confetto invisible.
    private func fade(_ flight: ConfettiFlight, beginTime: CFTimeInterval) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        let duration = max(0.001, flight.duration)
        animation.values = (0...Self.fadeSamples).map { step in
            NSNumber(value: flight.opacity(at: duration * Double(step) / Double(Self.fadeSamples)))
        }
        animation.calculationMode = .linear
        animation.duration = duration
        animation.beginTime = beginTime
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        return animation
    }

    /// One phase of a flight: how much of a property that phase still owes,
    /// worked off along its own curve and added to whatever the other phase is
    /// doing. Filling both ways is what holds a confetto at the muzzle until its
    /// repetition comes round.
    private func additive(
        _ keyPath: String,
        from value: Any,
        curve: CAMediaTimingFunction,
        duration: TimeInterval,
        beginTime: CFTimeInterval
    ) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = value
        animation.toValue = value is NSNumber ? NSNumber(value: 0) : NSValue(cgPoint: .zero)
        animation.isAdditive = true
        animation.duration = max(0.001, duration)
        animation.beginTime = beginTime
        animation.timingFunction = curve
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        return animation
    }

    private func turn(
        keyPath: String,
        duration: TimeInterval,
        direction: Double,
        beginTime: CFTimeInterval,
        lifetime: TimeInterval
    ) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = 0
        animation.toValue = direction * 2 * Double.pi
        animation.duration = max(0.01, duration)
        // Turning stops when the confetto lands rather than going on forever, so
        // a volley that is swept late costs nothing while it waits.
        animation.repeatDuration = lifetime
        animation.beginTime = beginTime
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        return animation
    }

    /// One tap per repetition, matching what the burst does on screen.
    private func playHaptics() {
        hapticTask?.cancel()
        let repetitions = settings.repetitions
        let interval = settings.repetitionInterval
        hapticTask = Task {
            let feedback = UIImpactFeedbackGenerator(style: .heavy)
            feedback.prepare()
            for repetition in 0..<repetitions {
                if repetition > 0 {
                    try? await Task.sleep(for: .seconds(interval))
                    guard !Task.isCancelled else { return }
                }
                feedback.impactOccurred()
            }
        }
    }

    private func sweep(_ volleyLayer: CALayer) {
        volleyLayer.removeFromSuperlayer()
        volleys.removeAll { $0.layer === volleyLayer }
    }

    private func clear() {
        hapticTask?.cancel()
        hapticTask = nil
        for volley in volleys {
            volley.cleanup.cancel()
            volley.layer.removeFromSuperlayer()
        }
        volleys.removeAll()
    }

    /// Steps in the sampled fade. Enough that the two curves' overlap reads as
    /// a curve rather than as segments.
    private static let fadeSamples = 30

    /// How long after the last confetto lands the layers are torn down.
    private static let sweepGrace: TimeInterval = 0.2

    /// Just enough depth for a flip to read as a turn rather than as a squash.
    private static let perspective: CATransform3D = {
        var transform = CATransform3DIdentity
        transform.m34 = -1 / 500
        return transform
    }()

    private static let throwTiming = CAMediaTimingFunction(controlPoints: 0.1, 0.8, 0, 1)
    private static let fallTiming = CAMediaTimingFunction(controlPoints: 0.12, 0, 0.39, 0)
}

/// A preview needs somewhere to keep its trigger. `@Previewable` would do it in
/// one line, but that is iOS 17, and the cannon itself runs on 16.
private struct CannonPreview<Label: View>: View {
    let settings: ConfettiSettings
    @ViewBuilder var label: () -> Label

    @State private var trigger = 0

    var body: some View {
        VStack(spacing: 40) {
            label()
                .font(.system(size: 90))
                .confettiCannon(trigger: trigger, settings: settings)

            Button("Fire") { trigger += 1 }
                .buttonStyle(.borderedProminent)
        }
    }
}

#Preview("Confetti cannon") {
    CannonPreview(
        settings: ConfettiSettings(
            shapes: [.symbol("music.note"), .symbol("music.quarternote.3"), .circle, .slimRectangle],
            colors: [.purple],
            size: 15,
            repetitions: 5,
            repetitionInterval: 0.25
        )
    ) {
        Text("🏆")
    }
}

#Preview("Confetti cannon (paper)") {
    CannonPreview(settings: ConfettiSettings(count: 40)) {
        Text("🎉")
    }
}

#Preview("Stars") {
    CannonPreview(settings: .stars) {
        Text("⭐️")
    }
}
