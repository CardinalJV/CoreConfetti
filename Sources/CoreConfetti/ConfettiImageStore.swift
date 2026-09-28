//
//  ConfettiImageStore.swift
//  CoreConfetti
//

import SwiftUI
import UIKit

/// A confetto's artwork: one bitmap, and the size it wants to be drawn at.
struct ConfettiImage {
    let cgImage: CGImage
    let size: CGSize
}

/// Draws every confetto shape once and keeps it.
///
/// A hundred confetti come from a handful of distinct bitmaps — a shape, a
/// colour, a size — so the drawing happens once per combination and every layer
/// after that just points at the same image. This is most of why the cannon is
/// cheap: the render server composites bitmaps it already has.
@MainActor
enum ConfettiImageStore {

    private struct Key: Hashable {
        let shape: ConfettiShape
        let color: Color
        let size: CGFloat
        let scale: CGFloat
    }

    private static var cache: [Key: ConfettiImage] = [:]

    static func image(for shape: ConfettiShape, color: Color, size: CGFloat, scale: CGFloat) -> ConfettiImage? {
        let key = Key(shape: shape, color: color, size: size, scale: scale)
        if let cached = cache[key] { return cached }

        let uiColor = UIColor(color)
        let pointSize = max(1, size)
        var drawn = draw(shape: shape, color: uiColor, size: pointSize, scale: scale)

        // A shape that cannot be drawn is nearly always a mistyped SF Symbol, and
        // dropping it silently is the worst way to say so: the burst comes out
        // thin, or empty, with nothing in the console to explain it. Loud in
        // debug, a plain disc in release — a burst of circles is a legible
        // symptom, an empty screen is not.
        if drawn == nil, case .symbol(let name) = shape {
            assertionFailure("ConfettiShape.symbol(\"\(name)\") is not an SF Symbol on this system. Falling back to a circle.")
            drawn = draw(shape: .circle, color: uiColor, size: pointSize, scale: scale)
        }

        guard let image = drawn else { return nil }
        // Bounded so a caller that randomises colours per burst can't grow this
        // forever; the working set of one screen is a dozen images at most.
        if cache.count >= cacheLimit { cache.removeAll(keepingCapacity: true) }
        cache[key] = image
        return image
    }

    private static let cacheLimit = 64

    private static func draw(shape: ConfettiShape, color: UIColor, size: CGFloat, scale: CGFloat) -> ConfettiImage? {
        switch shape {
        case .symbol(let name):
            return drawSymbol(named: name, color: color, pointSize: size, scale: scale)
        case .text(let text):
            return drawText(text, color: color, pointSize: size, scale: scale)
        case .circle, .square, .triangle, .slimRectangle, .roundedCross:
            return drawPaper(shape: shape, color: color, size: size, scale: scale)
        }
    }

    /// The paper shapes, filled into a square of the confetti size — the same
    /// paths ConfettiSwiftUI draws.
    private static func drawPaper(shape: ConfettiShape, color: UIColor, size: CGFloat, scale: CGFloat) -> ConfettiImage? {
        let bounds = CGRect(x: 0, y: 0, width: size, height: size)
        let image = renderer(size: bounds.size, scale: scale).image { _ in
            color.setFill()
            path(for: shape, in: bounds).fill()
        }
        guard let cgImage = image.cgImage else { return nil }
        return ConfettiImage(cgImage: cgImage, size: bounds.size)
    }

    private static func path(for shape: ConfettiShape, in rect: CGRect) -> UIBezierPath {
        switch shape {
        case .circle:
            return UIBezierPath(ovalIn: rect)
        case .square:
            return UIBezierPath(rect: rect)
        case .triangle:
            let path = UIBezierPath()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.close()
            return path
        case .slimRectangle:
            return UIBezierPath(rect: CGRect(
                x: rect.minX,
                y: 4 * rect.maxY / 5,
                width: rect.width,
                height: rect.maxY / 5
            ))
        case .roundedCross:
            let path = UIBezierPath()
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY / 3))
            path.addQuadCurve(to: CGPoint(x: rect.maxX / 3, y: rect.minY), controlPoint: CGPoint(x: rect.maxX / 3, y: rect.maxY / 3))
            path.addLine(to: CGPoint(x: 2 * rect.maxX / 3, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY / 3), controlPoint: CGPoint(x: 2 * rect.maxX / 3, y: rect.maxY / 3))
            path.addLine(to: CGPoint(x: rect.maxX, y: 2 * rect.maxY / 3))
            path.addQuadCurve(to: CGPoint(x: 2 * rect.maxX / 3, y: rect.maxY), controlPoint: CGPoint(x: 2 * rect.maxX / 3, y: 2 * rect.maxY / 3))
            path.addLine(to: CGPoint(x: rect.maxX / 3, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: 2 * rect.maxY / 3), controlPoint: CGPoint(x: rect.maxX / 3, y: 2 * rect.maxY / 3))
            path.close()
            return path
        case .symbol, .text:
            return UIBezierPath(rect: rect)
        }
    }

    /// An SF Symbol at the confetti's point size, flattened into the confetto's
    /// colour. Point size rather than a frame, so a symbol is as wide as it is
    /// drawn — the same thing `.font(.system(size:))` does to one in SwiftUI.
    private static func drawSymbol(named name: String, color: UIColor, pointSize: CGFloat, scale: CGFloat) -> ConfettiImage? {
        let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
        guard let symbol = UIImage(systemName: name, withConfiguration: configuration) else { return nil }

        let image = renderer(size: symbol.size, scale: scale).image { context in
            let rect = CGRect(origin: .zero, size: symbol.size)
            symbol.draw(in: rect)
            context.cgContext.setBlendMode(.sourceIn)
            color.setFill()
            context.cgContext.fill(rect)
        }
        guard let cgImage = image.cgImage else { return nil }
        return ConfettiImage(cgImage: cgImage, size: symbol.size)
    }

    private static func drawText(_ text: String, color: UIColor, pointSize: CGFloat, scale: CGFloat) -> ConfettiImage? {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: pointSize),
            .foregroundColor: color
        ]
        let bounds = (text as NSString).size(withAttributes: attributes)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let image = renderer(size: bounds, scale: scale).image { _ in
            (text as NSString).draw(at: .zero, withAttributes: attributes)
        }
        guard let cgImage = image.cgImage else { return nil }
        return ConfettiImage(cgImage: cgImage, size: bounds)
    }

    private static func renderer(size: CGSize, scale: CGFloat) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format)
    }
}
