//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextFieldStyleTests.swift
//
//  `.textFieldStyle(.automatic)` vs `.plain` — the two things a terminal can
//  tell apart about a field: whether it draws a surface, and whether that
//  surface costs cells.
//
//  The measure/render agreement tests are the ones that matter. A style that
//  changes a control's chrome width has to change it in BOTH passes, and the
//  cap arithmetic lives in four places (two views × two passes) — which is
//  exactly the shape that drifts.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitCore

@testable import TUIkit

@MainActor
@Suite("TextFieldStyle")
struct TextFieldStyleTests {

    /// The half-block caps an `.automatic` field wraps its content in.
    private let openCap = "▐"
    private let closeCap = "▌"

    private func context(width: Int, focusManager: FocusManager) -> RenderContext {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        return RenderContext(
            availableWidth: width, availableHeight: 1, environment: environment,
            tuiContext: TUIContext(), identity: ViewIdentity(path: "")
        ).isolatingRenderCache()
    }

    /// Renders twice — the first pass registers the focus handler, the second
    /// observes the resolved state — and returns the raw ANSI-bearing line.
    private func rawLine(_ view: some View, context: RenderContext) -> String {
        _ = renderToBuffer(view, context: context)
        return renderToBuffer(view, context: context).lines.first ?? ""
    }

    // MARK: - The chrome

    @Test("The default style caps the field; .plain does not")
    func plainDrawsNoCaps() {
        let width = 24
        for (style, expectsCaps) in [(AnyTextFieldStyle.automatic, true), (.plain, false)] {
            let focusManager = FocusManager()
            let line = rawLine(
                style.apply(to: TextField("Name", text: .constant("hi")).focusID("tf")),
                context: context(width: width, focusManager: focusManager)
            ).stripped

            #expect(line.hasPrefix(openCap) == expectsCaps, "leading cap: \(line.debugDescription)")
            #expect(
                line.hasSuffix(closeCap) == expectsCaps,
                "trailing cap: \(line.debugDescription)")
            // Either way the field occupies the whole width it was offered —
            // the caps are drawn INSIDE it, not added to it.
            #expect(line.count == width)
        }
    }

    /// The escape sequence immediately preceding `fragment` in `line`.
    ///
    /// Asserting on the WHOLE line would be wrong: a focused field's caret
    /// paints its own cell on the cursor colour whatever the style says, so the
    /// line always carries one background escape. The claim is about the text.
    private func escape(before fragment: String, in line: String) -> String {
        guard let text = line.range(of: fragment) else { return "" }
        let head = line[line.startIndex..<text.lowerBound]
        guard let start = head.range(of: "\u{1B}[", options: .backwards) else { return "" }
        return String(head[start.lowerBound...])
    }

    @Test("A plain field paints no background behind its text")
    func plainPaintsNoBackground() {
        let focusManager = FocusManager()
        let line = rawLine(
            TextField("Name", text: .constant("hi")).focusID("tf").textFieldStyle(.plain),
            context: context(width: 24, focusManager: focusManager))
        // A background SGR (48;…) is the only way a cell can claim a colour it
        // was not given; without one the text takes whatever is behind it.
        #expect(
            !escape(before: "hi", in: line).contains("48;"),
            "no background escape before the text in \(line.debugDescription)")
    }

    @Test("The default style DOES paint a surface behind its text")
    func automaticPaintsASurface() {
        let focusManager = FocusManager()
        let line = rawLine(
            TextField("Name", text: .constant("hi")).focusID("tf"),
            context: context(width: 24, focusManager: focusManager))
        #expect(
            escape(before: "hi", in: line).contains("48;"),
            "a background escape before the text in \(line.debugDescription)")
    }

    // MARK: - Measure / render agreement

    @Test("Measured width matches rendered width, under both styles")
    func measureMatchesRender() {
        for style in [AnyTextFieldStyle.automatic, .plain] {
            for width in [8, 12, 24, 40] {
                let focusManager = FocusManager()
                let view = style.apply(to: TextField("Name", text: .constant("hello")))
                let renderContext = context(width: width, focusManager: focusManager)
                let measured = measureChild(
                    view, proposal: ProposedSize(width: width, height: 1),
                    context: renderContext)
                let rendered = rawLine(view, context: renderContext).stripped
                #expect(
                    measured.width == rendered.count,
                    "\(style.name) at \(width): measured \(measured.width), drew \(rendered.count)")
            }
        }
    }

    @Test("Unproposed, a plain field is exactly the two cap cells narrower")
    func naturalWidthDropsTheCaps() {
        let focusManager = FocusManager()
        let renderContext = context(width: 80, focusManager: focusManager)
        let field = TextField("Name", text: .constant(""))
        let capped = measureChild(
            field, proposal: ProposedSize(width: nil, height: 1), context: renderContext)
        let plain = measureChild(
            field.textFieldStyle(.plain), proposal: ProposedSize(width: nil, height: 1),
            context: renderContext)
        #expect(capped.width - plain.width == 2, "\(capped.width) vs \(plain.width)")
    }

    // MARK: - Hit testing

    /// The click-to-caret map is measured from the buffer's left edge and
    /// subtracts the leading cap. A plain field has none, so the SAME click
    /// column means one character further along — hard-coding the 1 would put
    /// every plain-field click one character to the left of where it looks.
    ///
    /// Observed by TYPING after the click, rather than by reading the caret out
    /// of `StateStorage`: the two styles differ by a modifier, so their handler
    /// boxes sit at different identities, and a lookup that missed would have
    /// returned a fresh handler reading 0 — passing the "plain is 0" half of
    /// this by accident. Where the character lands cannot lie.
    @Test("The same click column lands one character apart under the two styles")
    func clickAccountsForTheLeadingCap() {
        func typed(afterClickingColumn column: Int, into view: some View, text: Box) -> String {
            let tui = TUIContext()
            var environment = EnvironmentValues()
            let focusManager = FocusManager()
            environment.focusManager = focusManager
            environment.applyRuntimeServices(from: tui)
            let renderContext = RenderContext(
                availableWidth: 20, availableHeight: 1, environment: environment, tuiContext: tui)

            tui.mouseEventDispatcher.beginRenderPass()
            tui.stateStorage.beginRenderPass()
            focusManager.beginRenderPass()
            let buffer = renderToBuffer(view, context: renderContext)
            focusManager.endRenderPass()
            tui.mouseEventDispatcher.setRegions(buffer.hitTestRegions)
            _ = tui.mouseEventDispatcher.dispatch(
                MouseEvent(button: .left, phase: .pressed, x: column, y: 0))
            _ = focusManager.dispatchKeyEvent(KeyEvent(key: .character("X")))
            return text.value
        }

        let cappedText = Box("abcdef")
        let capped = typed(
            afterClickingColumn: 3,
            into: TextField("Name", text: cappedText.binding).focusID("tf"),
            text: cappedText)
        let plainText = Box("abcdef")
        let plain = typed(
            afterClickingColumn: 3,
            into: TextField("Name", text: plainText.binding).focusID("tf")
                .textFieldStyle(.plain),
            text: plainText)

        #expect(capped == "abXcdef", "column 3 is past the cap and two characters in")
        #expect(plain == "abcXdef", "column 3 of a plain field is three characters in")
    }
}

// MARK: - Support

/// A mutable string reachable from a `Binding` — `.constant` cannot observe an
/// edit, which is the whole point of the typing assertion above.
@MainActor
private final class Box {
    var value: String
    init(_ value: String) { self.value = value }
    var binding: Binding<String> {
        Binding(get: { self.value }, set: { self.value = $0 })
    }
}

/// A style choice a test can put in an array.
///
/// `textFieldStyle(_:)` is generic over a concrete style, so the two cases
/// cannot share a variable without erasing them — and erasing them here, at the
/// call, keeps the tests reading as one parameterised statement instead of two
/// copies that can drift apart.
@MainActor
private enum AnyTextFieldStyle {
    case automatic
    case plain

    var name: String {
        switch self {
        case .automatic: "automatic"
        case .plain: "plain"
        }
    }

    func apply(to view: some View) -> AnyView {
        switch self {
        case .automatic: AnyView(view.textFieldStyle(.automatic))
        case .plain: AnyView(view.textFieldStyle(.plain))
        }
    }
}
