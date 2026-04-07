import CoreText
import UIKit

protocol LineFragmentRendererDelegate: AnyObject {
    func string(in lineFragmentRenderer: LineFragmentRenderer) -> String?
}

final class LineFragmentRenderer {
    private enum HorizontalPosition {
        case character(Int)
        case endOfLine
    }

    weak var delegate: LineFragmentRendererDelegate?
    var lineFragment: LineFragment
    let invisibleCharacterConfiguration: InvisibleCharacterConfiguration
    var markedRange: NSRange?
    var markedTextBackgroundColor: UIColor = .systemFill
    var markedTextBackgroundCornerRadius: CGFloat = 0
    var highlightedRangeFragments: [HighlightedRangeFragment] = []
    
    private var cachedIndentLevel: Int = 0
    private var cachedString: String?
    
    private static let indentGuideColor: CGColor = UIColor(white: 0.5, alpha: 0.25).cgColor
    private static let indentGuideWidth: CGFloat = 2.0 / UIScreen.main.scale
    private var tabWidth: CGFloat
    private var cachedCharsPerLevel: Int = 0
    
    private var showInvisibleCharacters: Bool {
        invisibleCharacterConfiguration.showTabs
            || invisibleCharacterConfiguration.showSpaces
            || invisibleCharacterConfiguration.showLineBreaks
            || invisibleCharacterConfiguration.showSoftLineBreaks
    }
    
    init(lineFragment: LineFragment, invisibleCharacterConfiguration: InvisibleCharacterConfiguration, tabWidth: CGFloat) {
        self.lineFragment = lineFragment
        self.invisibleCharacterConfiguration = invisibleCharacterConfiguration
        self.tabWidth = tabWidth
    }
    
    func draw(to context: CGContext, inCanvasOfSize canvasSize: CGSize) {
        let string = delegate?.string(in: self)
        drawHighlightedRanges(to: context, inCanvasOfSize: canvasSize)
        drawMarkedRange(to: context)
        drawIndentGuides(to: context, string: string)
        if showInvisibleCharacters, let string = string {
            drawInvisibleCharacters(in: string)
        }
        drawText(to: context)
    }
}

private extension LineFragmentRenderer {
    private func drawIndentGuides(to context: CGContext, string: String?) {
        guard lineFragment.visibleRange.location == 0, let string = string else {
            return
        }
        let level: Int
        let charsPerLevel: Int
        if string == cachedString {
            level = cachedIndentLevel
            charsPerLevel = cachedCharsPerLevel
        } else {
            (level, charsPerLevel) = measureIndentLevel(string)
            cachedIndentLevel = level
            cachedCharsPerLevel = charsPerLevel
            cachedString = string
        }
        guard level > 0, charsPerLevel > 0 else { return }
        let height = lineFragment.scaledSize.height
        let chars = Array(string)
        context.saveGState()
        context.setStrokeColor(Self.indentGuideColor)
        context.setLineWidth(Self.indentGuideWidth)
        for i in 1 ... level {
            let charIndex = i * charsPerLevel
            guard charIndex < chars.count,
                  chars[charIndex] == "\t" else {
                continue
            }
            let x = CTLineGetOffsetForStringIndex(lineFragment.line, charIndex, nil)
            context.move(to: CGPoint(x: x, y: 0))
            context.addLine(to: CGPoint(x: x, y: height))
        }
        context.strokePath()
        context.restoreGState()
    }
    
    private func measureIndentLevel(_ string: String) -> (Int, Int) {
        var spaces = 0
        var tabs = 0
        for ch in string {
            if ch == "\t" { tabs += 1 }
            else if ch == " " { spaces += 1 }
            else { break }
        }
        if tabs > 0 {
            return (tabs, 1)
        } else if spaces > 0 {
            let tabW = max(1, Int(tabWidth))
            return (spaces / tabW, tabW)
        }
        return (0, 0)
    }

    private func drawHighlightedRanges(to context: CGContext, inCanvasOfSize canvasSize: CGSize) {
        guard !highlightedRangeFragments.isEmpty else { return }
        context.saveGState()
        for highlightedRange in highlightedRangeFragments {
            let startX = CTLineGetOffsetForStringIndex(lineFragment.line, highlightedRange.range.lowerBound, nil)
            let endX: CGFloat
            if shouldHighlightLineEnding(for: highlightedRange) {
                endX = canvasSize.width
            } else {
                endX = CTLineGetOffsetForStringIndex(lineFragment.line, highlightedRange.range.upperBound, nil)
            }
            let rect = CGRect(x: startX, y: 0, width: endX - startX, height: lineFragment.scaledSize.height)
            context.setFillColor(highlightedRange.color.cgColor)
            let roundedCorners = highlightedRange.roundedCorners
            if !roundedCorners.isEmpty && highlightedRange.cornerRadius > 0 {
                let cornerRadii = CGSize(width: highlightedRange.cornerRadius, height: highlightedRange.cornerRadius)
                let bezierPath = UIBezierPath(roundedRect: rect, byRoundingCorners: roundedCorners, cornerRadii: cornerRadii)
                context.addPath(bezierPath.cgPath)
                context.fillPath()
            } else {
                context.fill(rect)
            }
        }
        context.restoreGState()
    }

    private func drawMarkedRange(to context: CGContext) {
        guard let markedRange = markedRange else { return }
        context.saveGState()
        let startX = CTLineGetOffsetForStringIndex(lineFragment.line, markedRange.lowerBound, nil)
        let endX = CTLineGetOffsetForStringIndex(lineFragment.line, markedRange.upperBound, nil)
        let rect = CGRect(x: startX, y: 0, width: endX - startX, height: lineFragment.scaledSize.height)
        context.setFillColor(markedTextBackgroundColor.cgColor)
        if markedTextBackgroundCornerRadius > 0 {
            let path = CGPath(roundedRect: rect, cornerWidth: markedTextBackgroundCornerRadius, cornerHeight: markedTextBackgroundCornerRadius, transform: nil)
            context.addPath(path)
            context.fillPath()
        } else {
            context.fill(rect)
        }
        context.restoreGState()
    }

    private func drawText(to context: CGContext) {
        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: 0, y: lineFragment.scaledSize.height)
        context.scaleBy(x: 1, y: -1)
        let yPosition = lineFragment.descent + (lineFragment.scaledSize.height - lineFragment.baseSize.height) / 2
        context.textPosition = CGPoint(x: 0, y: yPosition)
        CTLineDraw(lineFragment.line, context)
        context.restoreGState()
    }

    private func drawInvisibleCharacters(in string: String) {
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: invisibleCharacterConfiguration.textColor,
            .font: invisibleCharacterConfiguration.font
        ]
        var indexInLineFragment = 0
        for substring in string {
            let indexInLine = lineFragment.visibleRange.location + indexInLineFragment
            indexInLineFragment += substring.utf16.count
            if invisibleCharacterConfiguration.showSpaces && substring == Symbol.Character.space {
                draw(invisibleCharacterConfiguration.spaceSymbol, at: .character(indexInLine), attrs: attrs)
            } else if invisibleCharacterConfiguration.showNonBreakingSpaces && substring == Symbol.Character.nonBreakingSpace {
                draw(invisibleCharacterConfiguration.nonBreakingSpaceSymbol, at: .character(indexInLine), attrs: attrs)
            } else if invisibleCharacterConfiguration.showTabs && substring == Symbol.Character.tab {
                draw(invisibleCharacterConfiguration.tabSymbol, at: .character(indexInLine), attrs: attrs)
            } else if invisibleCharacterConfiguration.showLineBreaks && isLineBreak(substring) {
                draw(invisibleCharacterConfiguration.lineBreakSymbol, at: .endOfLine, attrs: attrs)
            } else if invisibleCharacterConfiguration.showSoftLineBreaks && substring == Symbol.Character.lineSeparator {
                draw(invisibleCharacterConfiguration.softLineBreakSymbol, at: .endOfLine, attrs: attrs)
            }
        }
    }

    private func draw(_ symbol: String, at horizontalPosition: HorizontalPosition, attrs: [NSAttributedString.Key: Any]) {
        let size = symbol.size(withAttributes: attrs)
        let xPosition = xPosition(for: horizontalPosition)
        let yPosition = (lineFragment.scaledSize.height - size.height) / 2
        symbol.draw(in: CGRect(x: xPosition, y: yPosition, width: size.width, height: size.height), withAttributes: attrs)
    }

    private func xPosition(for horizontalPosition: HorizontalPosition) -> CGFloat {
        switch horizontalPosition {
        case .character(let index):
            return CTLineGetOffsetForStringIndex(lineFragment.line, index, nil)
        case .endOfLine:
            return CGFloat(CTLineGetTypographicBounds(lineFragment.line, nil, nil, nil))
        }
    }

    private func shouldHighlightLineEnding(for highlightedRangeFragment: HighlightedRangeFragment) -> Bool {
        guard highlightedRangeFragment.range.upperBound == lineFragment.range.upperBound else {
            return false
        }
        guard let string = delegate?.string(in: self), let lastCharacter = string.last else {
            return false
        }
        return isLineBreak(lastCharacter)
    }

    private func isLineBreak(_ string: String.Element) -> Bool {
        string == Symbol.Character.lineFeed || string == Symbol.Character.carriageReturn || string == Symbol.Character.carriageReturnLineFeed
    }
}
