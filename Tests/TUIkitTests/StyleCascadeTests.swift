//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StyleCascadeTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Style cascade")
struct StyleCascadeTests {

    private func context(width: Int = 40, height: Int = 8) -> RenderContext {
        RenderContext(availableWidth: width, availableHeight: height, tuiContext: TUIContext())
    }

    /// All SGR parameter codes present across a rendered buffer (e.g. "1" = bold,
    /// "2" = dim, "3" = italic, "4" = underline, "9" = strikethrough).
    private func sgrCodes(_ buffer: FrameBuffer) -> Set<String> {
        var codes: Set<String> = []
        for line in buffer.lines {
            var rest = Substring(line)
            while let start = rest.range(of: "\u{1B}[") {
                rest = rest[start.upperBound...]
                guard let m = rest.firstIndex(of: "m") else { break }
                for code in rest[..<m].split(separator: ";") { codes.insert(String(code)) }
                rest = rest[rest.index(after: m)...]
            }
        }
        return codes
    }

    // MARK: - StyleAttributes.merged

    @Test("merged: self wins per property, base fills the rest")
    func mergedPerProperty() {
        let base = StyleAttributes(bold: true, dim: true)
        let over = StyleAttributes(bold: false, italic: true)
        let result = over.merged(over: base)
        #expect(result.bold == false)     // over wins
        #expect(result.italic == true)    // only over sets it
        #expect(result.dim == true)       // only base sets it
    }

    // MARK: - StyleCascade.resolve

    @Test("resolve: innermost matching entry wins, per property")
    func resolveProximityPerProperty() {
        let cascade = StyleCascade()
            .appending(.text, StyleAttributes(bold: true, dim: true))      // outer
            .appending(.text, StyleAttributes(bold: false))                // inner
        let resolved = cascade.resolve(for: [.all, .text])
        #expect(resolved.bold == false)   // inner overrides
        #expect(resolved.dim == true)     // outer persists (inner didn't set it)
    }

    @Test("resolve: only entries whose scope matches apply")
    func resolveScopeMatching() {
        let cascade = StyleCascade()
            .appending(.control(.button), StyleAttributes(bold: true))
            .appending(.semanticColor(.foregroundSecondary), StyleAttributes(dim: true))
        // A plain text view matches .all/.text but neither of the above.
        #expect(cascade.resolve(for: [.all, .text]).bold == nil)
        #expect(cascade.resolve(for: [.all, .text]).dim == nil)
        // Add the secondary role to the scope path → the dim entry now applies.
        #expect(cascade.resolve(for: [.all, .text, .semanticColor(.foregroundSecondary)]).dim == true)
    }

    @Test("appending empty attributes is a no-op")
    func appendingEmptyIsNoop() {
        #expect(StyleCascade().appending(.text, StyleAttributes()).isEmpty)
    }

    // MARK: - Text integration

    @Test("Container .bold() makes descendant text bold")
    func containerBold() {
        let view = VStack { Text("Hi") }.bold()
        #expect(sgrCodes(renderToBuffer(view, context: context())).contains("1"))
    }

    @Test("italic / underline / strikethrough cascade to text")
    func otherAttributesCascade() {
        #expect(sgrCodes(renderToBuffer(Text("Hi").style(.text, StyleAttributes(italic: true)), context: context())).contains("3"))
        #expect(sgrCodes(renderToBuffer(Text("Hi").underline(), context: context())).contains("4"))
        #expect(sgrCodes(renderToBuffer(Text("Hi").strikethrough(), context: context())).contains("9"))
    }

    @Test("Proximity: an inner .bold(false) overrides an outer .bold()")
    func innerOverridesOuter() {
        let view = VStack { Text("Hi").bold(false) }.bold()
        #expect(!sgrCodes(renderToBuffer(view, context: context())).contains("1"))
    }

    @Test("Per-Text .bold() wins over a container .bold(false)")
    func perTextWins() {
        let view = VStack { Text("Hi").bold() }.bold(false)
        #expect(sgrCodes(renderToBuffer(view, context: context())).contains("1"))
    }

    @Test("Role-scoped dim applies only to text drawn with that palette role")
    func semanticRoleScoped() {
        let view = VStack {
            Text("plain")
            Text("secondary").foregroundStyle(.palette.foregroundSecondary)
        }
        .style(.semanticColor(.foregroundSecondary)) { $0.dim = true }
        // The secondary-coloured text must render dim ("2"); the plain text alone
        // would not, so the presence of "2" proves the role-scoped entry matched.
        #expect(sgrCodes(renderToBuffer(view, context: context())).contains("2"))
    }

    @Test("textCase transforms the rendered text")
    func textCaseTransforms() {
        let upper = renderToBuffer(VStack { Text("Hello") }.textCase(.uppercase), context: context())
        #expect(upper.lines.contains { $0.contains("HELLO") })
        let lower = renderToBuffer(VStack { Text("Hello") }.textCase(.lowercase), context: context())
        #expect(lower.lines.contains { $0.contains("hello") })
    }

    @Test("fontWeight maps to bold / faint")
    func fontWeightMapping() {
        #expect(sgrCodes(renderToBuffer(Text("Hi").fontWeight(.bold), context: context())).contains("1"))
        #expect(sgrCodes(renderToBuffer(Text("Hi").fontWeight(.light), context: context())).contains("2"))
    }
}
