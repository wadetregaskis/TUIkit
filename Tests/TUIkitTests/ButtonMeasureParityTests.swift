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
