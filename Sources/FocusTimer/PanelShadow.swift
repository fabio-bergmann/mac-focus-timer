import AppKit

/// The panel's shadow, cast by hand in a window of its own.
///
/// The system's window shadow can't be tuned, and it comes with a thin dark rim
/// hugging the window's edge, which around this light panel read as a black
/// border. This one is softer, reaches further down, and has no rim.
enum PanelShadow {
    /// How far the shadow reaches past the panel, and so how much bigger its
    /// window is on every side.
    static let margin: CGFloat = 110

    private static let casts: [(radius: CGFloat, drop: CGFloat, opacity: Float)] = [
        (radius: 32, drop: 20, opacity: 0.2), // the depth
        (radius: 3, drop: 1, opacity: 0.08), // just enough to find the edge on a white page
    ]

    /// Sets `layer` up to cast the shadow of a rounded rectangle and show none
    /// of it inside: shadow under the glass would be blurred into the panel
    /// and darken it.
    static func configure(_ layer: CALayer, bounds: CGRect, around rect: CGRect, cornerRadius: CGFloat) {
        let shape = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        layer.sublayers = casts.map { cast in
            let sublayer = CALayer()
            sublayer.frame = bounds
            sublayer.shadowPath = shape
            sublayer.shadowColor = .black
            sublayer.shadowOpacity = cast.opacity
            sublayer.shadowRadius = cast.radius
            // A view's layers measure up from the bottom, so negative falls downwards.
            sublayer.shadowOffset = CGSize(width: 0, height: -cast.drop)
            return sublayer
        }

        let outside = CGMutablePath()
        outside.addRect(bounds)
        outside.addPath(shape)
        let mask = CAShapeLayer()
        mask.frame = bounds
        mask.path = outside
        mask.fillRule = .evenOdd
        layer.mask = mask
    }

    /// The same shadow drawn with Core Graphics, for the previews, which can't
    /// render layers. `scale` is the bitmap's pixels per point: Core Graphics
    /// measures shadows in pixels and ignores the current transform, and its
    /// blur is twice a layer's shadow radius.
    static func draw(around rect: CGRect, cornerRadius: CGFloat, scale: CGFloat, in context: CGContext) {
        let shape = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        context.saveGState()
        context.addRect(context.boundingBoxOfClipPath)
        context.addPath(shape)
        context.clip(using: .evenOdd)
        context.setFillColor(.black)
        for cast in casts {
            context.setShadow(
                offset: CGSize(width: 0, height: -cast.drop * scale),
                blur: cast.radius * 2 * scale,
                color: CGColor(gray: 0, alpha: CGFloat(cast.opacity))
            )
            context.addPath(shape)
            context.fillPath()
        }
        context.restoreGState()
    }
}

final class PanelShadowView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = CALayer()
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PanelShadowView is created in code")
    }

    override func layout() {
        super.layout()
        guard let layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        PanelShadow.configure(
            layer, bounds: bounds,
            around: bounds.insetBy(dx: PanelShadow.margin, dy: PanelShadow.margin),
            cornerRadius: PanelController.cornerRadius
        )
        CATransaction.commit()
    }
}
