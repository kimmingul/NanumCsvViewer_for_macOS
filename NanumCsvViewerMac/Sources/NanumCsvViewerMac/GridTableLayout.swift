import AppKit

enum GridTableLayout {
    struct Decision: Equatable {
        let needsHorizontalScroller: Bool
        let fillDelta: CGFloat
    }

    /// Decides horizontal-scroller visibility and how much the fill column must
    /// grow, from the table's MEASURED natural width (AppKit tiling, including
    /// intercell spacing and style insets) — never from summed column widths.
    static func decide(naturalWidth: CGFloat, viewportWidth: CGFloat, epsilon: CGFloat = 0.5) -> Decision {
        guard viewportWidth > 0, naturalWidth >= 0 else {
            return Decision(needsHorizontalScroller: false, fillDelta: 0)
        }
        if naturalWidth > viewportWidth + epsilon {
            return Decision(needsHorizontalScroller: true, fillDelta: 0)
        }
        return Decision(needsHorizontalScroller: false, fillDelta: max(0, viewportWidth - naturalWidth))
    }
}
