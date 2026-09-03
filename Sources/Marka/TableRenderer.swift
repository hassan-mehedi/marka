import AppKit

@MainActor
enum TableRenderer {
    private static let cellPaddingX: CGFloat = 10
    private static let cellPaddingY: CGFloat = 6
    private static let border: CGFloat = 1
    private static let radius: CGFloat = 6

    static func image(
        rows: [[NSAttributedString]],
        alignments: [TableBlock.Alignment],
        maxWidth: CGFloat,
        theme: Theme
    ) -> NSImage {
        let columns = alignments.count
        let widths = columnWidths(rows: rows, columns: columns, maxWidth: maxWidth)
        let heights = rows.map { row in
            (0..<columns).reduce(CGFloat(0)) { tallest, column in
                let bounds = row[column].boundingRect(
                    with: CGSize(width: widths[column] - 2 * cellPaddingX, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading]
                )
                return max(tallest, ceil(bounds.height))
            } + 2 * cellPaddingY
        }

        let size = CGSize(
            width: widths.reduce(0, +) + CGFloat(columns + 1) * border,
            height: heights.reduce(0, +) + CGFloat(rows.count + 1) * border
        )
        let lineColor = theme.resolvedMarker.withAlphaComponent(0.55)

        return NSImage(size: size, flipped: true) { frame in
            let outline = NSBezierPath(roundedRect: frame.insetBy(dx: border / 2, dy: border / 2), xRadius: radius, yRadius: radius)
            NSGraphicsContext.saveGraphicsState()
            outline.addClip()
            theme.resolvedCodeBackground.setFill()
            NSRect(x: 0, y: 0, width: size.width, height: heights[0] + 2 * border).fill()
            NSGraphicsContext.restoreGraphicsState()

            lineColor.setFill()
            var y = border
            for height in heights.dropLast() {
                y += height
                NSRect(x: 0, y: y, width: size.width, height: border).fill()
                y += border
            }
            var x = border
            for width in widths.dropLast() {
                x += width
                NSRect(x: x, y: 0, width: border, height: size.height).fill()
                x += border
            }
            lineColor.setStroke()
            outline.lineWidth = border
            outline.stroke()

            y = border
            for (row, height) in zip(rows, heights) {
                x = border
                for column in 0..<columns {
                    let cell = NSMutableAttributedString(attributedString: row[column])
                    let style = NSMutableParagraphStyle()
                    style.alignment = switch alignments[column] {
                    case .left: .left
                    case .center: .center
                    case .right: .right
                    }
                    cell.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: cell.length))
                    cell.draw(
                        with: NSRect(
                            x: x + cellPaddingX,
                            y: y + cellPaddingY,
                            width: widths[column] - 2 * cellPaddingX,
                            height: height - 2 * cellPaddingY
                        ),
                        options: [.usesLineFragmentOrigin, .usesFontLeading]
                    )
                    x += widths[column] + border
                }
                y += height + border
            }
            return true
        }
    }

    // Columns keep their natural width until the table overflows; then the
    // widest columns share what is left after the narrow ones are satisfied.
    private static func columnWidths(rows: [[NSAttributedString]], columns: Int, maxWidth: CGFloat) -> [CGFloat] {
        var natural = (0..<columns).map { column in
            rows.reduce(CGFloat(24)) { max($0, ceil($1[column].size().width) + 2 * cellPaddingX) }
        }
        let available = maxWidth - CGFloat(columns + 1) * border
        guard natural.reduce(0, +) > available else { return natural }

        var flexible = Set(0..<columns)
        var remaining = available
        while !flexible.isEmpty {
            let share = remaining / CGFloat(flexible.count)
            let satisfied = flexible.filter { natural[$0] <= share }
            if satisfied.isEmpty {
                for column in flexible { natural[column] = floor(share) }
                break
            }
            for column in satisfied {
                remaining -= natural[column]
                flexible.remove(column)
            }
        }
        return natural
    }
}
