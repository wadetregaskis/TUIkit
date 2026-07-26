//  TUIKit - Terminal UI Kit for Swift
//  ControlLabel.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Control Labels

/// Shared treatment for a control's own label views.
enum _ControlLabel {
    /// A disabled control dims its label WITH it — the label is part of the
    /// control, not adjacent content. The dim is the same recipe every
    /// built-in control uses for its disabled chrome, applied as the
    /// environment foreground so a label with its own explicit colour still
    /// wins. Enabled controls get the label back untouched.
    ///
    /// - Parameter controlDisabled: The control's OWN `.disabled()` flag —
    ///   the per-control method bypasses the `\.isEnabled` environment, so
    ///   callers pass it explicitly; either source of disablement dims.
    @MainActor
    static func dimmingWhenDisabled<Label: View>(
        _ label: Label, context: RenderContext, controlDisabled: Bool = false
    ) -> AnyView {
        guard controlDisabled || !context.environment.isEnabled else { return AnyView(label) }
        let palette = context.environment.palette
        return AnyView(
            label.foregroundStyle(
                palette.foregroundTertiary.opacity(
                    ViewConstants.disabledForeground, over: palette.background)))
    }
}

/// Renders an inline control label followed by one separating space — or
/// nothing when the label is empty/blank/absent, so the control isn't preceded
/// by a stray space.
///
/// This is the shared building block for every control whose label sits to the
/// LEFT of the control on the same line, which is what macOS SwiftUI does for
/// `Stepper`, `Slider` and `Picker`. Measured 2026-07-25 against real SwiftUI
/// (hosted in an `NSHostingView`, drawn controls captured via `cacheDisplay`):
///
/// ```
/// Slider(value: $a) { Text("Volume") }   ->  "Volume  ▬▬▬▬●▬▬▬▬"
/// Slider(value: $b)                      ->  "▬▬▬▬▬▬▬●▬▬▬▬▬▬▬"
/// Picker("Theme", selection: $t) { … }   ->  "Theme  [ Dark ⌄ ]"
/// Picker("", selection: $t) { … }        ->  "[ Dark ⌄ ]"
/// ```
///
/// i.e. the label takes space on the same line and the control shrinks to fit,
/// and an absent label reserves NOTHING — no leading gap. Composing it as an
/// HStack sibling (rather than drawing it inside the control's own core) also
/// keeps the core's internal x-offsets — hit regions, arrow zones, track
/// origin — measured from its own buffer, because the stack shifts them.
struct _CollapsingLabel<Label: View>: View, Renderable, Layoutable {
    let label: Label?

    /// The control's own `.disabled()` flag — it bypasses the environment,
    /// so the label must be told explicitly.
    let controlDisabled: Bool

    var body: Never { fatalError("_CollapsingLabel renders via Renderable") }

    /// Size from one render (it drops to nothing for a blank label and adds a
    /// trailing space otherwise — both need the render), flexibility from the label.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let size = measureFixedByRendering(self, proposal: proposal, context: context)
        let labelFlexible = label.map {
            measureChild($0, proposal: proposal, context: context).isWidthFlexible
        } ?? false
        return ViewSize(width: size.width, height: size.height, isWidthFlexible: labelFlexible)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        guard let label, !(label is EmptyView) else { return FrameBuffer() }
        let buffer = TUIkit.renderToBuffer(
            _ControlLabel.dimmingWhenDisabled(
                label, context: context, controlDisabled: controlDisabled),
            context: context)
        guard !buffer.isBlank else { return FrameBuffer() }
        return FrameBuffer(lines: buffer.lines.map { $0 + " " })
    }
}
