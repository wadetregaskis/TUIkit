//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ButtonMeasureParityTests.swift
//
//  A button now reports its size by MEASURING the style's body rather than by
//  drawing itself and reading the buffer's dimensions. That is only right while
//  the two agree to the cell, and a disagreement is a button laid out somewhere
//  it does not draw — wrong pixels, not a crash. So: render the matrix, measure
//  the matrix, compare.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("A button measures what it draws")
struct ButtonMeasureParityTests {
    private func context(width: Int) -> RenderContext {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tui)
        return RenderContext(
            availableWidth: width, availableHeight: 4, environment: environment,
            tuiContext: tui)
    }

    /// Every built-in style, against labels that fit, exactly fill, and overrun.
    @Test(
        "the measured size is the rendered size",
        arguments: [
            ButtonStyleCase.default, .primary, .success, .destructive, .plain,
        ],
        [
            "OK", "A rather longer label", "x",
            "an extremely long label that no narrow terminal could ever hope to fit",
        ])
    func measuredEqualsRendered(style: ButtonStyleCase, label: String) {
        for width in [4, 8, 12, 20, 40, 120] {
            let base = Button(label) {}
            let view = style.apply(to: base)
            let rendered = renderToBuffer(view, context: context(width: width))
            let measured = measureChild(
                view, proposal: .unspecified, context: context(width: width))

            #expect(
                measured.width == rendered.width,
                "\(style) \(label.count)ch at \(width): measured \(measured.width), drew \(rendered.width)"
            )
            #expect(
                measured.height == rendered.height,
                "\(style) \(label.count)ch at \(width): measured \(measured.height) tall, drew \(rendered.height)"
            )
        }
    }

    @Test("a @ViewBuilder label still agrees")
    func viewBuilderLabelAgrees() {
        for width in [6, 20, 60] {
            let view = Button(action: {}, label: { Text("Label").bold() })
            let rendered = renderToBuffer(view, context: context(width: width))
            let measured = measureChild(
                view, proposal: .unspecified, context: context(width: width))
            #expect(measured.width == rendered.width, "at \(width)")
            #expect(measured.height == rendered.height, "at \(width)")
        }
    }

    /// The plain style draws its focus prefix in front of the label, so the
    /// label has the width less the prefix to draw in, as a string label has.
    /// Offered the whole width, a label as wide as that was drawn two cells
    /// past it and clipped by the parent: `left … right` came out
    /// `left … rig`, and a long text lost its ellipsis.
    @Test("a @ViewBuilder label is drawn whole inside the chrome", arguments: [ButtonStyleCase.default, .plain])
    func viewBuilderLabelFitsInsideTheChrome(style: ButtonStyleCase) {
        for width in [16, 20, 40] {
            let filling = style.apply(
                to: Button(
                    action: {},
                    label: {
                        HStack(spacing: 1) {
                            Text(verbatim: "left")
                            Spacer()
                            Text(verbatim: "right")
                        }
                    }))
            let drawn = renderToBuffer(filling, context: context(width: width))
            let row = drawn.lines.first?.stripped ?? ""
            #expect(row.hasSuffix("right") || row.hasSuffix("right ▌"), "\(style) at \(width): |\(row)|")
            #expect(drawn.width == width, "\(style) at \(width): |\(row)|")

            let long = style.apply(
                to: Button(action: {}, label: { Text(verbatim: String(repeating: "x", count: 60)) }))
            let truncated = renderToBuffer(long, context: context(width: width)).lines.first?.stripped ?? ""
            #expect(truncated.contains("…"), "\(style) at \(width): |\(truncated)|")
        }
    }

    /// A label that fills its width — the navigation row's `Text`, `Spacer`,
    /// `Text` — draws the button as wide as whatever it is offered, so the
    /// button's measure has to say so. Reported rigid at the width of one
    /// offer, it read to a parent that keeps widths as a button exactly that
    /// wide, and a windowed stack of navigation links answered every wider ask
    /// with the narrower width its render had offered.
    @Test("a @ViewBuilder label that fills makes the button fill", arguments: [ButtonStyleCase.default, .plain])
    func fillingLabelIsFlexible(style: ButtonStyleCase) {
        let filling = style.apply(
            to: Button(
                action: {},
                label: {
                    HStack(spacing: 1) {
                        Text(verbatim: "note")
                        Spacer()
                        Text(verbatim: "#1")
                    }
                }))
        let hugging = style.apply(to: Button(action: {}, label: { Text(verbatim: "note") }))
        for width in [20, 60] {
            let proposal = ProposedSize(width: width, height: nil)
            let fills = measureChild(filling, proposal: proposal, context: context(width: width))
            #expect(fills.width == renderToBuffer(filling, context: context(width: width)).width)
            #expect(fills.isWidthFlexible, "\(style) at \(width): \(fills)")
            let hugs = measureChild(hugging, proposal: proposal, context: context(width: width))
            #expect(!hugs.isWidthFlexible, "\(style) at \(width): \(hugs)")
        }
    }
}

/// The built-in styles, as a value a test can iterate.
enum ButtonStyleCase: CustomStringConvertible {
    case `default`, primary, success, destructive, plain

    var description: String {
        switch self {
        case .default: "default"
        case .primary: "primary"
        case .success: "success"
        case .destructive: "destructive"
        case .plain: "plain"
        }
    }

    @MainActor
    func apply(to button: Button) -> AnyView {
        switch self {
        case .default: AnyView(button.buttonStyle(.default))
        case .primary: AnyView(button.buttonStyle(.primary))
        case .success: AnyView(button.buttonStyle(.success))
        case .destructive: AnyView(button.buttonStyle(.destructive))
        case .plain: AnyView(button.buttonStyle(.plain))
        }
    }
}
