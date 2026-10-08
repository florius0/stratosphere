import Foundation

public enum RailPointerBounds {
    /// The native rail has a stable trailing edge; use its rendered width, not its host envelope.
    public static func frame(host: CGRect, renderedSize: CGSize, inset: CGFloat) -> CGRect {
        CGRect(x: host.maxX - inset - renderedSize.width, y: host.maxY - inset - renderedSize.height,
               width: renderedSize.width, height: renderedSize.height)
    }
}
