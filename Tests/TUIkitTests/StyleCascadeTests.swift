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

    // MARK: - Scoped colour

    @Test("A scoped foreground colours text via the cascade")
    func cascadeForeground() {
        let view = VStack { Text("Hi") }.style(.text, StyleAttributes(foreground: .rgb(10, 20, 30)))
        let line = renderToBuffer(view, context: context()).lines.joined()
        #expect(line.contains("38;2;10;20;30"))
    }

    @Test("A role-scoped foreground recolours only text with that palette role")
    func cascadeSemanticForeground() {
        let view = VStack {
            Text("primary")
            Text("secondary").foregroundStyle(.palette.foregroundSecondary)
        }
        .style(.semanticColor(.foregroundSecondary), StyleAttributes(foreground: .rgb(1, 2, 3)))
        let line = renderToBuffer(view, context: context()).lines.joined()
        #expect(line.contains("38;2;1;2;3"), "secondary text should be recoloured")
    }

    // MARK: - Chrome roles (Section header/footer)

    @Test("A section header is bold + dim by default")
    func chromeHeaderDefault() {
        let section = Section("Header") { Text("Body") }
        let header = renderToBuffer(section, context: context()).lines.first ?? ""
        // bold (1) then dim (2) as the leading style codes.
        #expect(header.contains("\u{1B}[1;2"))
    }

    @Test("A .chrome(.sectionHeader) override turns off the default bold, keeping dim")
    func chromeHeaderBoldOff() {
        let section = Section("Header") { Text("Body") }
            .style(.chrome(.sectionHeader)) { $0.bold = false }
        let header = renderToBuffer(section, context: context()).lines.first ?? ""
        #expect(!header.contains("\u{1B}[1;2"), "bold should be off")
        #expect(header.contains("\u{1B}[2;") || header.contains("\u{1B}[2m"), "dim should remain")
    }

    @Test("A .chrome(.sectionHeader) override can uppercase the header")
    func chromeHeaderUppercase() {
        let section = Section("Header") { Text("Body") }
            .style(.chrome(.sectionHeader)) { $0.textCase = .uppercase }
        let lines = renderToBuffer(section, context: context()).lines
        #expect(lines.contains { $0.contains("HEADER") }, "header should be uppercased")
        #expect(lines.contains { $0.contains("Body") }, "body should be unaffected")
    }
}

@MainActor
@Suite("Button style cascade")
struct ButtonStyleCascadeTests {

    @Test(".buttonTextStyle colours the button label")
    func buttonTextForeground() {
        let view = Button("Save") {}.buttonTextStyle { $0.foreground = .rgb(7, 8, 9) }
        let line = renderToBuffer(view, context: makeRenderContext()).lines.joined()
        #expect(line.contains("38;2;7;8;9"))
    }

    @Test("A destructive role keeps its colour despite a broad button override")
    func destructiveStaysLoadBearing() {
        let view = Button("Delete", role: .destructive) {}
            .buttonTextStyle { $0.foreground = .rgb(7, 8, 9) }
        let line = renderToBuffer(view, context: makeRenderContext()).lines.joined()
        #expect(!line.contains("38;2;7;8;9"), "destructive label must not take the broad override")
    }

    @Test("Variant scoping targets only the matching button variant")
    func variantScoping() {
        // .automatic targets the default style → applies.
        let matched = Button("A") {}.buttonTextStyle(.automatic) { $0.foreground = .rgb(7, 8, 9) }
        #expect(renderToBuffer(matched, context: makeRenderContext()).lines.joined().contains("38;2;7;8;9"))
        // .primary targets the primary style → does not apply to a default button.
        let unmatched = Button("A") {}.buttonTextStyle(.primary) { $0.foreground = .rgb(7, 8, 9) }
        #expect(!renderToBuffer(unmatched, context: makeRenderContext()).lines.joined().contains("38;2;7;8;9"))
    }
}
