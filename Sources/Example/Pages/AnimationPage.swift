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
/// - the curves and the springs, side by side on one trigger
/// - a fade that never ends, which costs no render passes at all
struct AnimationPage: View {
    @State private var fraction: Double = 0.2
    @State private var curve: Int = 0
    @State private var isDimmed = false
    @State private var breathes = false
    @State private var isWide = false
    @State private var isWarm = false
    @State private var showsPanel = false
    @State private var transition = 0

    /// The curves the two bars can be driven with. `.smooth`, `.snappy` and
    /// `.bouncy` are springs, so the last of them visibly overshoots the target
    /// and comes back — a thing an easing curve cannot do.
    private static let curves: [(key: String, animation: Animation)] = [
        ("page.animation.curve.easeInOut", .easeInOut(duration: 0.6)),
        ("page.animation.curve.linear", .linear(duration: 0.6)),
        ("page.animation.curve.easeOut", .easeOut(duration: 0.6)),
        ("page.animation.curve.snappy", .snappy),
        ("page.animation.curve.bouncy", .bouncy),
    ]

    private var animation: Animation { Self.curves[curve].animation }

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

            DemoSection("page.animation.section.change") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.animation.change.hint")
                        .foregroundStyle(.palette.foregroundSecondary)
                    // The bar is an `Animatable` view of this app's own — see
                    // `AnimatedBar` below. Nothing else here knows it moves.
                    AnimatedBar(fraction: fraction, width: 32)
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
                }
            }

            DemoSection("page.animation.section.curve") {
                Picker("page.animation.curve.label", selection: $curve) {
                    ForEach(Array(Self.curves.enumerated()), id: \.offset) { entry in
                        // `L(_:)`, not the key: a `Text` built from a String
                        // VARIABLE takes the disfavoured overload and is shown
                        // verbatim, so the raw key would appear on screen.
                        Text(L(entry.element.key)).tag(entry.offset)
                    }
                }
            }

            DemoSection("page.animation.section.atTheView") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.animation.atTheView.hint")
                        .foregroundStyle(.palette.foregroundSecondary)
                    // No `withAnimation` at the toggle: the view says how
                    // changes to `isDimmed` should be shown, and the control
                    // that writes it knows nothing about that.
                    Toggle("page.animation.dim", isOn: $isDimmed)
                    Text("page.animation.fadingText")
                        .opacity(isDimmed ? 0.25 : 1)
                        .animation(.easeInOut(duration: 0.5), value: isDimmed)
                }
            }

            DemoSection("page.animation.section.forever") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.animation.forever.hint")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Toggle("page.animation.breathe", isOn: $breathes)
                        .onChange(of: breathes) { _, isOn in
                            withAnimation(
                                isOn
                                    ? .easeInOut(duration: 0.9)
                                        .repeatForever(autoreverses: true)
                                    : nil
                            ) {
                                // The value the fade runs BETWEEN. Turning it
                                // off is the same change with no animation, so
                                // the text simply returns to full.
                                breathingOpacity = isOn ? 0.2 : 1
                            }
                        }
                    Text("page.animation.breathingText")
                        .foregroundStyle(.palette.accent)
                        .opacity(breathingOpacity)
                }
            }

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
                    // A frame, a padding and a border colour, all moving from
                    // one `withAnimation`. None of these views is `Animatable`
                    // — the MODIFIERS are.
                    Text("page.animation.box")
                        .padding(.leading, isWide ? 6 : 1)
                        .frame(width: isWide ? 40 : 20)
                        .border(isWarm ? .palette.warning : .palette.border)
                }
            }

            DemoSection("page.animation.section.transition") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.animation.transition.hint")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Picker("page.animation.transition.label", selection: $transition) {
                        ForEach(Array(Self.transitions.enumerated()), id: \.offset) { entry in
                            Text(L(entry.element.key)).tag(entry.offset)
                        }
                    }
                    Button("page.animation.button.toggle") {
                        withAnimation(.easeInOut(duration: 0.5)) { showsPanel.toggle() }
                    }
                    // The optional IS what is rendered here, so the removal has
                    // a slot to play out in — see `View.transition(_:)`.
                    (showsPanel ? Text("page.animation.panel") : nil)
                        .map {
                            $0.padding(1)
                                .border(.palette.accent)
                                .transition(Self.transitions[transition].transition)
                        }
                }
            }

            DemoSection("page.animation.section.state") {
                ValueDisplayRow(
                    "\(L("page.animation.value")):", String(format: "%.2f", fraction))
            }
        }
    }

    /// What the never-ending fade animates between. Separate from `breathes` so
    /// the toggle stays a plain `Bool` for the control and the opacity stays a
    /// `Double` for the animation.
    @State private var breathingOpacity: Double = 1
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
        // Clamped because a spring overshoots — `.bouncy` really does pass 1
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
