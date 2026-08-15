import CoreGraphics

/// Geometry shared between Cocoa and Accessibility coordinate spaces.
///
/// Cocoa puts the origin at the bottom-left of the primary display with y
/// increasing upward. Accessibility puts it at the top-left with y increasing
/// downward. Every rectangle crossing that boundary goes through `flip`.
public enum AXGeometry {

    /// Converts a rectangle between Cocoa and Accessibility space. The conversion is
    /// its own inverse, so the same function serves both directions.
    public static func flip(_ rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.origin.x,
               y: primaryScreenHeight - rect.origin.y - rect.height,
               width: rect.width,
               height: rect.height)
    }

    /// The index of the screen `rect` overlaps most, or — when it overlaps none of
    /// them — the screen whose centre is nearest. Nil only when there are no screens.
    public static func screenIndex(for rect: CGRect, screenFrames: [CGRect]) -> Int? {
        guard !screenFrames.isEmpty else { return nil }

        var bestIndex = 0
        var bestArea: CGFloat = 0
        for (index, frame) in screenFrames.enumerated() {
            let overlap = frame.intersection(rect)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > bestArea {
                bestArea = area
                bestIndex = index
            }
        }
        if bestArea > 0 { return bestIndex }

        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (index, frame) in screenFrames.enumerated() {
            let dx = rect.midX - frame.midX
            let dy = rect.midY - frame.midY
            let distance = dx * dx + dy * dy
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    /// True when `frame` sits within `tolerance` of `reference` on every edge.
    public static func matches(_ frame: CGRect, _ reference: CGRect, tolerance: CGFloat) -> Bool {
        abs(frame.minX - reference.minX) <= tolerance &&
        abs(frame.minY - reference.minY) <= tolerance &&
        abs(frame.maxX - reference.maxX) <= tolerance &&
        abs(frame.maxY - reference.maxY) <= tolerance
    }

    /// The frame a window should be given to fill its screen. Both arrays are in
    /// Accessibility space and must be parallel — index `i` of `visibleFrames` is the
    /// usable area of `screenFrames[i]`.
    public static func fillTarget(for windowFrame: CGRect,
                                  screenFrames: [CGRect],
                                  visibleFrames: [CGRect]) -> CGRect? {
        guard screenFrames.count == visibleFrames.count,
              let index = screenIndex(for: windowFrame, screenFrames: screenFrames)
        else { return nil }
        return visibleFrames[index]
    }
}
