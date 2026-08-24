//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimationPage.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// `withAnimation` demo page.
///
/// Everything here is the SwiftUI-shaped API and nothing on the page computes
/// an offset, reads a clock, or names a frame:
/// - a view of the app's own conforming to `Animatable`
/// - `withAnimation` at the change, and `.animation(_:value:)` at the view
/// - one curve, editable at the top, driving every demo below it
/// - a fade that never ends, which costs no render passes at all
struct AnimationPage: View {

    // MARK: - The one animation, edited at the top of the page

    @State private var curve: Int = Curve.easeInOut.rawValue
    @State private var duration: Double = 0.6
    @State private var speed: Double = 1
    @State private var bounce: Double = 0.3
    @State private var p1x: Double = 0.42
    @State private var p1y: Double = 0
    @State private var p2x: Double = 0.58
    @State private var p2y: Double = 1

    // MARK: - What each demo is showing

    @State private var fraction: Double = 0.2
    @State private var isDimmed = false
    @State private var breathes = false
    @State private var breathingOpacity: Double = 1
    @State private var isWide = false
    @State private var isWarm = false
    @State private var showsPanel = false
    @State private var transition = 0
    @State private var reservesSpace = false

    /// The shapes a change can be given. Each is a family rather than a preset:
    /// the pace, the speed and — where it means anything — the springiness are
    /// the sliders below, so the same curve can be tried slow and lazy or fast
    /// and sharp without editing the page.
    private enum Curve: Int, CaseIterable {
        case easeInOut, linear, easeIn, easeOut, custom, spring

        var key: String {
            switch self {
            case .easeInOut: "page.animation.curve.easeInOut"
            case .linear: "page.animation.curve.linear"
            case .easeIn: "page.animation.curve.easeIn"
            case .easeOut: "page.animation.curve.easeOut"
            case .custom: "page.animation.curve.custom"
            case .spring: "page.animation.curve.spring"
            }
        }
    }

    private var selectedCurve: Curve { Curve(rawValue: curve) ?? .easeInOut }

    /// The page's animation, assembled from the controls above it.
    ///
    /// One computed property read by every demo — which is the point of the
    /// layout: the settings are not next to any one demo because they belong to
    /// all of them.
    private var animation: Animation {
        let base: Animation =
            switch selectedCurve {
            case .easeInOut: .easeInOut(duration: duration)
            case .linear: .linear(duration: duration)
            case .easeIn: .easeIn(duration: duration)
            case .easeOut: .easeOut(duration: duration)
            case .custom: .timingCurve(p1x, p1y, p2x, p2y, duration: duration)
            case .spring: .spring(duration: duration, bounce: bounce)
            }
        return speed == 1 ? base : base.speed(speed)
    }

    /// The transitions the panel can come and go with.
    private static let transitions: [(key: String, transition: AnyTransition)] = [
        ("page.animation.transition.opacity", .opacity),
        ("page.animation.transition.slide", .slide),
        ("page.animation.transition.moveTop", .move(edge: .top)),
        ("page.animation.transition.scale", .scale),
        ("page.animation.transition.both", .move(edge: .leading).combined(with: .opacity)),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            settings
            change
            atTheView
            forever
            modifiers
            comingAndGoing
            DemoSection("page.animation.section.state") {
                ValueDisplayRow(
                    "\(L("page.animation.value")):", String(format: "%.2f", fraction))
            }
            KeyboardHelpSection(shortcuts: [
                "page.animation.help.tab",
                "page.animation.help.activate",
                "page.animation.help.arrows",
            ])
        }
        .padding(.horizontal, 1)
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader("menu.item.animation", subtitle: "page.animation.subtitle")
        }
    }

    // MARK: - Page-wide settings

    /// First on the page, and labelled as governing all of it — the previous
    /// layout put the curve picker between two demos, where it read as an
    /// option belonging to whichever one you were looking at.
    private var settings: some View {
        DemoSection("page.animation.section.settings") {
            VStack(alignment: .leading, spacing: 0) {
                Text("page.animation.settings.hint")
                    .foregroundStyle(.palette.foregroundSecondary)
                Picker("page.animation.curve.label", selection: $curve) {
                    ForEach(Curve.allCases, id: \.rawValue) { entry in
                        // `L(_:)`, not the key: a `Text` built from a String
                        // VARIABLE takes the disfavoured overload and is shown
                        // verbatim, so the raw key would appear on screen.
                        Text(L(entry.key)).tag(entry.rawValue)
                    }
                }
                // Side by side where the terminal is wide enough for two
                // readable tracks, stacked where it is not.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 3) {
                        paceSliders
                        shapeSliders
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        paceSliders
                        shapeSliders
                    }
                }
            }
        }
    }

    /// How fast, in the two independent senses SwiftUI gives them: `duration`
    /// is the curve's own length, written into the curve itself
    /// (`.easeInOut(duration:)`); `speed` is a multiplier applied over the top
    /// of a finished animation (`.speed(_:)`), which is how you scale one you
    /// were handed and whose duration you may not know. They multiply out, so
    /// the second slider reports what the two of them come to — the one number
    /// that says how long the picture will actually take.
    private var paceSliders: some View {
        VStack(alignment: .leading, spacing: 0) {
            Slider(value: $duration, in: 0.1...2.5, step: 0.05) {
                caption("\(L("page.animation.duration")) \(String(format: "%.2fs", duration))")
            }
            Slider(value: $speed, in: 0.25...4, step: 0.25) {
                caption(
                    "\(L("page.animation.speed")) "
                        + String(format: "%.2f× → %.2fs", speed, duration / speed))
            }
        }
    }

    /// What the curve is shaped like. Only one of these means anything at a
    /// time, so the other is disabled rather than hidden: a control that
    /// vanishes takes the page's layout with it every time the picker moves.
    @ViewBuilder private var shapeSliders: some View {
        VStack(alignment: .leading, spacing: 0) {
            Slider(value: $bounce, in: -0.5...0.9, step: 0.05) {
                caption("\(L("page.animation.bounce")) \(String(format: "%.2f", bounce))")
            }
            .disabled(selectedCurve != .spring)
            // Four tracks abreast need real width to stay readable; two rows of
            // two is the fallback, and one column the last resort.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 2) {
                    controlPoint($p1x, "p1x")
                    controlPoint($p1y, "p1y")
                    controlPoint($p2x, "p2x")
                    controlPoint($p2y, "p2y")
                }
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 2) {
                        controlPoint($p1x, "p1x")
                        controlPoint($p1y, "p1y")
                    }
                    HStack(spacing: 2) {
                        controlPoint($p2x, "p2x")
                        controlPoint($p2y, "p2y")
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    controlPoint($p1x, "p1x")
                    controlPoint($p1y, "p1y")
                    controlPoint($p2x, "p2x")
                    controlPoint($p2y, "p2y")
                }
            }
            .disabled(selectedCurve != .custom)
        }
    }

    // MARK: - The demos

    private var change: some View {
        DemoSection("page.animation.section.change") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.animation.change.hint")
                    .foregroundStyle(.palette.foregroundSecondary)
                // The bar is an `Animatable` view of this app's own — see
                // `AnimatedBar` below. Nothing else here knows it moves. It
                // takes the width it is given rather than a number written into
                // the page, less a cell at each end so it does not run into the
                // terminal's edges.
                GeometryReader { proxy in
                    AnimatedBar(fraction: fraction, width: max(4, proxy.size.width - 4))
                        .padding(.horizontal, 2)
                }
                .frame(height: 1)
                HStack(spacing: 2) {
                    Button("page.animation.button.empty") {
                        withAnimation(animation) { fraction = 0 }
                    }
                    Button("page.animation.button.half") {
                        withAnimation(animation) { fraction = 0.5 }
                    }
                    Button("page.animation.button.full") {
                        withAnimation(animation) { fraction = 1 }
                    }
                    Button("page.animation.button.snap") {
                        // No `withAnimation`: the same change, arriving all
                        // at once. The contrast is the point.
                        fraction = fraction > 0.5 ? 0 : 1
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var atTheView: some View {
        DemoSection("page.animation.section.atTheView") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.animation.atTheView.hint")
                    .foregroundStyle(.palette.foregroundSecondary)
                // No `withAnimation` at the toggle: the view says how changes
                // to `isDimmed` should be shown, and the control that writes it
                // knows nothing about that.
                Toggle("page.animation.dim", isOn: $isDimmed)
                Text("page.animation.fadingText")
                    .opacity(isDimmed ? 0.25 : 1)
                    .animation(animation, value: isDimmed)
            }
        }
    }

    private var forever: some View {
        DemoSection("page.animation.section.forever") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.animation.forever.hint")
                    .foregroundStyle(.palette.foregroundSecondary)
                Toggle("page.animation.breathe", isOn: $breathes)
                    .onChange(of: breathes) { _, isOn in
                        withAnimation(
                            isOn ? animation.repeatForever(autoreverses: true) : nil
                        ) {
                            // The value the fade runs BETWEEN. Turning it off
                            // is the same change with no animation, so the text
                            // simply returns to full.
                            breathingOpacity = isOn ? 0.2 : 1
                        }
                    }
                Text("page.animation.breathingText")
                    .foregroundStyle(.palette.accent)
                    .opacity(breathingOpacity)
            }
        }
    }

    private var modifiers: some View {
        DemoSection("page.animation.section.modifiers") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.animation.modifiers.hint")
                    .foregroundStyle(.palette.foregroundSecondary)
                HStack(spacing: 2) {
                    Button("page.animation.button.resize") {
                        withAnimation(animation) { isWide.toggle() }
                    }
                    Button("page.animation.button.recolour") {
                        withAnimation(animation) { isWarm.toggle() }
                    }
                }
                // A frame, a padding and a border colour, all moving from one
                // `withAnimation`. None of these views is `Animatable` — the
                // MODIFIERS are.
                Text("page.animation.box")
                    .padding(.leading, isWide ? 6 : 1)
                    .frame(width: isWide ? 40 : 20)
                    .border(isWarm ? .palette.warning : .palette.border)
            }
        }
    }

    private var comingAndGoing: some View {
        DemoSection("page.animation.section.transition") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.animation.transition.hint")
                    .foregroundStyle(.palette.foregroundSecondary)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 3) {
                        transitionPicker
                        transitionControls
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        transitionPicker
                        transitionControls
                    }
                }
                panelSlot
            }
        }
    }

    private var transitionPicker: some View {
        Picker("page.animation.transition.label", selection: $transition) {
            ForEach(Array(Self.transitions.enumerated()), id: \.offset) { entry in
                Text(L(entry.element.key)).tag(entry.offset)
            }
        }
    }

    private var transitionControls: some View {
        HStack(spacing: 2) {
            Button("page.animation.button.toggle") {
                withAnimation(animation) { showsPanel.toggle() }
            }
            Toggle("page.animation.reserveSpace", isOn: $reservesSpace)
        }
    }

    /// The panel, and the two answers to "what happens to the space it was in?"
    ///
    /// Either way the removal itself plays out — the slot a `nil` leaves behind
    /// holds the panel's rows open until the transition has finished. The
    /// toggle is about what happens *after* that: reclaimed, and the page
    /// closes up; reserved, and the gap stays so nothing below ever moves.
    @ViewBuilder private var panelSlot: some View {
        let panel = (showsPanel ? Text("page.animation.panel") : nil)
            .map {
                $0.padding(1)
                    .border(.palette.accent)
                    .transition(Self.transitions[transition].transition)
            }
        // One frame either way, with a height of `nil` when the space is not
        // reserved — NOT `if reserved { panel.frame(…) } else { panel }`.
        // Swapping the wrapper is a change of view IDENTITY: every `@State`
        // below it is recreated at its initial value the moment the toggle
        // flips, which is a bug this page would have been an unusually good
        // place to demonstrate accidentally.
        //
        // Five rows, which is what the panel IS: a text row, a row of padding
        // each side of it, and the border's two. Reserving three left the
        // padding fighting the border for one row.
        panel.frame(height: reservesSpace ? 5 : nil, alignment: .top)
    }

    /// One Bézier control-point coordinate. Named rather than localized: these
    /// are the `cubic-bezier` parameter names, and they read the same in every
    /// language a CSS author has ever met them in.
    private func controlPoint(_ value: Binding<Double>, _ name: String) -> some View {
        Slider(value: value, in: 0...1, step: 0.02) { caption(name) }
    }

    /// A slider's own label, in the page's quiet caption colour.
    private func caption(_ text: String) -> some View {
        Text(text).foregroundStyle(.palette.foregroundSecondary)
    }
}

// MARK: - An animatable view of the app's own

/// A bar whose fill is one continuous number.
///
/// The whole of what an app writes to make something animate: name the value in
/// ``Animatable/animatableData`` and draw the view from it. Every frame between
/// one fraction and the next is then the framework's problem.
private struct AnimatedBar: View, Animatable {
    var fraction: Double
    let width: Int

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    var body: some View {
        // Clamped because a spring overshoots — a bouncy one really does pass 1
        // on the way, which is what makes it look like a spring.
        let clamped = min(max(fraction, 0), 1)
        let filled = Int((Double(width) * clamped).rounded())
        HStack(spacing: 0) {
            Text(String(repeating: "█", count: filled))
                .foregroundStyle(.palette.accent)
            Text(String(repeating: "░", count: width - filled))
                .foregroundStyle(.palette.border)
        }
    }
}
