//  🖥️ TUIKit — Terminal UI Kit for Swift
//  FrameBuffer+VerticalAlignment.swift
//
//  Created by LAYERED.work
//  License: MIT

extension FrameBuffer {
    /// Returns a copy padded with blank rows up to `height`, placing the
    /// existing content within that height according to `alignment`.
    ///
    /// Buffers already at least `height` tall are returned unchanged. Overlay
    /// layers and hit-test regions shift down with the content by the amount of
    /// top padding, so a click on a non-top-aligned child still lands on it.
    ///
    /// Shared by `HStack` and `LazyHStack`: both lay children out on the
    /// horizontal axis and must position each child within the row's height
    /// (`appendHorizontally` itself only ever top-aligns).
    func verticallyAligned(toHeight height: Int, alignment: VerticalAlignment) -> FrameBuffer {
        guard self.height < height else { return self }
        let topPadding = alignment.childOffset(childHeight: self.height, in: height)
        let bottomPadding = (height - self.height) - topPadding
        let emptyLine = String(repeating: " ", count: width)
        var lines = Array(repeating: emptyLine, count: topPadding)
        lines += self.lines
        lines += Array(repeating: emptyLine, count: bottomPadding)
        return replacingLines(lines, overlayShiftY: topPadding)
    }
}
