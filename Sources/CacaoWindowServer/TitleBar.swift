//
//  TitleBar.swift
//  CacaoWindowServer
//

import CacaoRender
import CacaoTokens
import Foundation
import Silica
import SilicaCairo

/// The title bar the compositor draws for windows that ask for server-side
/// decorations: Mac apps on Perry, Qt apps and SDL games.
///
/// It looks like the one Cacao apps draw for themselves (Cacao's
/// `_DesktopTitleBar` and `_WindowButtons`), from the same style tokens: the
/// title centered on a shaded bar with a line along its bottom, and the
/// window buttons at its leading end.
struct TitleBar: Equatable {

    var width: Int

    var title: String

    var isActive: Bool

    var isMaximized: Bool

    /// The button the pointer went down on and hasn't come up from.
    var pressedButton: WindowButtonLayout.Button?

    /// The style the title bar is drawn in.
    nonisolated(unsafe) static var tokens = StyleTokens()

    /// The buttons and the end they're at, as the desktop's settings have
    /// them.
    nonisolated(unsafe) static var layout = WindowButtonLayout.standard

    static var height: Int {
        Int(tokens.metrics.titleBarHeight.rounded())
    }

    // MARK: Hit testing

    /// The window button at a point in the title bar, if any.
    static func button(at point: CGPoint, width: Int) -> WindowButtonLayout.Button? {
        for (button, frame) in buttonFrames(width: width) {
            // A little larger than the circle, so the buttons are easy to hit.
            if frame.insetBy(dx: -2, dy: -2).contains(point) {
                return button
            }
        }
        return nil
    }

    /// Where each window button is, in the title bar's coordinates.
    static func buttonFrames(width: Int) -> [(WindowButtonLayout.Button, CGRect)] {
        let metrics = tokens.metrics
        let size = metrics.windowButtonSize
        let y = (CGFloat(height) - size) / 2
        var frames: [(WindowButtonLayout.Button, CGRect)] = []
        for (index, button) in layout.leading.enumerated() {
            let x = metrics.windowButtonInset + CGFloat(index) * (size + metrics.windowButtonSpacing)
            frames.append((button, CGRect(x: x, y: y, width: size, height: size)))
        }
        for (index, button) in layout.trailing.reversed().enumerated() {
            let x = CGFloat(width) - metrics.windowButtonInset - size - CGFloat(index) * (size + metrics.windowButtonSpacing)
            frames.append((button, CGRect(x: x, y: y, width: size, height: size)))
        }
        return frames
    }

    /// The room the buttons take at each end, with the space around them.
    static func buttonsWidth(_ buttons: [WindowButtonLayout.Button]) -> CGFloat {
        guard !buttons.isEmpty else { return 0 }
        let metrics = tokens.metrics
        let count = CGFloat(buttons.count)
        return metrics.windowButtonInset * 2 + count * metrics.windowButtonSize + (count - 1) * metrics.windowButtonSpacing
    }

    // MARK: Drawing

    /// The title bar's pixels: premultiplied RGBA, top row first.
    func draw() -> Silica.Image? {
        Self.registerBackend
        let height = Self.height
        guard width > 0,
              let context = BitmapContext(width: Double(width), height: Double(height))
        else {
            return nil
        }
        let tokens = Self.tokens
        let colors = tokens.titleBar
        drawBackground(isActive ? colors.background : colors.inactiveBackground, in: context)

        // The line along the bottom.
        let separator = tokens.metrics.separatorWidth
        context.setFillColor(colors.separator)
        context.addRect(Rect(CGRect(x: 0, y: CGFloat(height) - separator, width: CGFloat(width), height: separator)))
        context.fillPath()

        drawTitle(in: context)
        for (button, frame) in Self.buttonFrames(width: width) {
            drawButton(button, in: frame, context: context)
        }
        return context.makeImage()
    }

    /// The bar's shading, top to bottom, a row at a time.
    private func drawBackground(_ gradient: StyleTokens.Gradient, in context: GraphicsContext) {
        let height = Self.height
        let top = gradient.top
        let bottom = gradient.bottom
        for row in 0..<height {
            let t = gradient.isFlat || height < 2 ? 0 : Float(row) / Float(height - 1)
            context.setFillColor(ResolvedColor(
                red: top.red + (bottom.red - top.red) * t,
                green: top.green + (bottom.green - top.green) * t,
                blue: top.blue + (bottom.blue - top.blue) * t,
                opacity: top.opacity + (bottom.opacity - top.opacity) * t
            ))
            context.addRect(Rect(x: 0, y: Double(row), width: Double(width), height: 1))
            context.fillPath()
        }
    }

    /// The title, centered between the buttons, cut short with an ellipsis
    /// when it doesn't fit.
    private func drawTitle(in context: GraphicsContext) {
        let tokens = Self.tokens
        let resolved = tokens.fonts.windowTitle
        guard !title.isEmpty, let font = Self.font(for: resolved) else { return }
        let size = resolved.size
        let inset = max(Self.buttonsWidth(Self.layout.leading), Self.buttonsWidth(Self.layout.trailing), tokens.metrics.spacing)
        let available = CGFloat(width) - inset * 2
        guard available > size else { return }

        var scalars = Array(title.unicodeScalars)
        func advances(_ scalars: [Unicode.Scalar]) -> (glyphs: [Glyph], widths: [CGFloat]) {
            let glyphs = scalars.map { font.glyph(for: $0) }
            let widths = font.advances(for: glyphs).map { CGFloat($0) * size }
            return (glyphs, widths)
        }
        var shaped = advances(scalars)
        if shaped.widths.reduce(0, +) > available {
            let ellipsis = advances(["\u{2026}"]).widths.first ?? size
            while !scalars.isEmpty, shaped.widths.reduce(0, +) + ellipsis > available {
                scalars.removeLast()
                shaped.glyphs.removeLast()
                shaped.widths.removeLast()
            }
            while scalars.last == " " {
                scalars.removeLast()
                shaped.glyphs.removeLast()
                shaped.widths.removeLast()
            }
            scalars.append("\u{2026}")
            shaped = advances(scalars)
        }
        let textWidth = shaped.widths.reduce(0, +)
        let ascent = font.ascent * size
        let descent = -font.descent * size
        let baseline = ((CGFloat(Self.height) - (ascent + descent)) / 2 + ascent).rounded()
        var x = ((CGFloat(width) - textWidth) / 2).rounded()
        var glyphs: [(glyph: Glyph, position: Point)] = []
        for (index, glyph) in shaped.glyphs.enumerated() {
            if scalars[index] != " " {
                glyphs.append((glyph, Point(x: Double(x), y: Double(baseline))))
            }
            x += shaped.widths[index]
        }
        let colors = tokens.titleBar
        context.setFont(Font(face: font, size: Double(size)))
        context.setFillColor(isActive ? colors.text : colors.inactiveText)
        context.showGlyphs(glyphs.map(\.glyph), at: glyphs.map(\.position))
    }

    /// A window button: a circle with a glyph, red while pressed for close.
    private func drawButton(_ button: WindowButtonLayout.Button, in frame: CGRect, context: GraphicsContext) {
        let tokens = Self.tokens
        let colors = tokens.titleBar.windowButton
        let isPressed = pressedButton == button
        let warns = button == .close && isPressed
        let fill = warns ? colors.closeHoverFill : isPressed ? colors.pressedFill : colors.fill
        context.setFillColor(fill)
        context.addEllipse(in: Rect(frame))
        context.fillPath()

        let glyphSize = tokens.metrics.windowButtonGlyphSize
        let rect = CGRect(
            x: frame.midX - glyphSize / 2,
            y: frame.midY - glyphSize / 2,
            width: glyphSize,
            height: glyphSize
        )
        context.beginPath()
        switch button {
        case .close:
            context.move(to: Point(CGPoint(x: rect.minX, y: rect.minY)))
            context.addLine(to: Point(CGPoint(x: rect.maxX, y: rect.maxY)))
            context.move(to: Point(CGPoint(x: rect.maxX, y: rect.minY)))
            context.addLine(to: Point(CGPoint(x: rect.minX, y: rect.maxY)))
        case .minimize:
            context.move(to: Point(CGPoint(x: rect.minX, y: rect.midY)))
            context.addLine(to: Point(CGPoint(x: rect.maxX, y: rect.midY)))
        case .maximize where isMaximized:
            // Two squares: restore.
            let side = rect.width * 0.75
            let offset = rect.width - side
            context.addRect(Rect(CGRect(x: rect.minX, y: rect.minY + offset, width: side, height: side)))
            context.move(to: Point(CGPoint(x: rect.minX + offset, y: rect.minY + offset)))
            context.addLine(to: Point(CGPoint(x: rect.minX + offset, y: rect.minY)))
            context.addLine(to: Point(CGPoint(x: rect.maxX, y: rect.minY)))
            context.addLine(to: Point(CGPoint(x: rect.maxX, y: rect.minY + side)))
            context.addLine(to: Point(CGPoint(x: rect.minX + side, y: rect.minY + side)))
        case .maximize:
            context.addRect(Rect(rect))
        @unknown default:
            // A button Cacao's layouts gain later: no glyph.
            break
        }
        context.setStrokeColor(warns ? colors.closeHoverGlyph : colors.glyph)
        context.setLineWidth(1.5)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.strokePath()
    }

    // MARK: Fonts

    nonisolated(unsafe) private static var fonts: [ResolvedFont: any FontFace] = [:]

    /// The fontconfig font for a resolved font, found as Cacao's text engine
    /// finds it.
    private static func font(for resolved: ResolvedFont) -> (any FontFace)? {
        if let font = fonts[resolved] {
            return font
        }
        let traits = resolved.weight >= 600 ? "-Bold" : ""
        var candidates: [String] = []
        if let name = resolved.name {
            candidates += [name + traits, name]
        }
        // fontconfig's generic family; Silica's names can't contain "-".
        candidates += ["Sans" + traits, "Sans"]
        for name in candidates {
            if let font = SilicaBackend.fontFace(named: name) {
                fonts[resolved] = font
                return font
            }
        }
        return nil
    }

    /// Silica draws through Cairo, once registered.
    private static let registerBackend: Void = {
        CairoBackend.register()
    }()
}

private extension GraphicsContext {

    func setFillColor(_ color: ResolvedColor) {
        setFillColor(red: Double(color.red), green: Double(color.green), blue: Double(color.blue), alpha: Double(color.opacity))
    }

    func setStrokeColor(_ color: ResolvedColor) {
        setStrokeColor(red: Double(color.red), green: Double(color.green), blue: Double(color.blue), alpha: Double(color.opacity))
    }
}

private extension Point {

    init(_ point: CGPoint) {
        self.init(x: Double(point.x), y: Double(point.y))
    }
}

private extension Rect {

    init(_ rect: CGRect) {
        self.init(x: Double(rect.minX), y: Double(rect.minY), width: Double(rect.width), height: Double(rect.height))
    }
}
