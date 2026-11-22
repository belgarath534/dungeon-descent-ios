import SwiftUI

/// A grid that lays out every cell at once, for buttons and cards. SwiftUI's
/// LazyVGrid builds cells as they scroll into view and rebuilds them when the
/// screen updates, and VoiceOver lost its place every time (the fight buttons,
/// co-op, the shops). Same columns and spacing as LazyVGrid: .flexible
/// columns (one per GridItem) or one .adaptive(minimum:) column that fits as
/// many as the width allows.
struct EagerGrid: Layout {
    var columns: [GridItem]
    var spacing: CGFloat? = nil

    private var hSpacing: CGFloat { columns.first?.spacing ?? 8 }
    private var vSpacing: CGFloat { spacing ?? 8 }

    private func count(_ width: CGFloat) -> Int {
        if columns.count == 1, case .adaptive(let minimum, _) = columns[0].size {
            return max(1, Int((width + hSpacing) / (minimum + hSpacing)))
        }
        return max(1, columns.count)
    }

    private func rows(_ subviews: Subviews, width: CGFloat) -> (cols: Int, colWidth: CGFloat, heights: [CGFloat]) {
        let n = count(width)
        let colWidth = max(0, (width - hSpacing * CGFloat(n - 1)) / CGFloat(n))
        var heights: [CGFloat] = []
        var i = 0
        while i < subviews.count {
            let row = subviews[i..<min(i + n, subviews.count)]
            heights.append(row.map { $0.sizeThatFits(ProposedViewSize(width: colWidth, height: nil)).height }.max() ?? 0)
            i += n
        }
        return (n, colWidth, heights)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let r = rows(subviews, width: width)
        let height = r.heights.reduce(0, +) + vSpacing * CGFloat(max(0, r.heights.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let r = rows(subviews, width: bounds.width)
        var y = bounds.minY
        for (rowIndex, h) in r.heights.enumerated() {
            for c in 0..<r.cols {
                let i = rowIndex * r.cols + c
                guard i < subviews.count else { break }
                let x = bounds.minX + CGFloat(c) * (r.colWidth + hSpacing)
                subviews[i].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                  proposal: ProposedViewSize(width: r.colWidth, height: h))
            }
            y += h + vSpacing
        }
    }
}
