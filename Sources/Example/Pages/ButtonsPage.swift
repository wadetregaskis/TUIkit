//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ButtonsPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIkit

/// Buttons and focus demo page.
///
/// Shows interactive button features including:
/// - Different button styles (default, primary, success, destructive)
/// - Disabled buttons
/// - Plain style (no border)
/// - ButtonRow for horizontal groups
/// - Focus navigation with Tab
/// - Live click counter demonstrating `@State` persistence across re-renders
struct ButtonsPage: View {
    @State private var clickCount: Int = 0
    @State private var tintToggle: Bool = true

    /// Read so the demo's tint can be chosen against the palette in force, and
    /// re-chosen when the theme changes.
    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView {
            content
        }
        .appHeader {
            DemoAppHeader("menu.item.buttons")
        }
    }

    /// A tint that is visibly *not* this theme's own accent.
    ///
    /// The section's whole point is that `.tint` changes something, which it
    /// cannot show if the tint IS the accent — and the demo used to hardcode
    /// `.palette.success`, which under the default Green theme is exactly that.
    /// So it picks whichever of the palette's semantic colours sits furthest
    /// from the accent, and picks again whenever the theme changes.
    ///
    /// Distance in plain RGB rather than contrast ratio: contrast is luminance
    /// only, so a red and a green of the same brightness score as identical —
    /// which is the pair this most needs to tell apart.
    private var demoTint: Color {
        let accent = palette.accent.resolve(with: palette).rgbComponents ?? (0, 0, 0)
        let candidates: [Color] = [.palette.info, .palette.warning, .palette.error, .palette.success]
        func distance(_ color: Color) -> Int {
            guard let rgb = color.resolve(with: palette).rgbComponents else { return 0 }
            let dr = Int(rgb.red) - Int(accent.red)
            let dg = Int(rgb.green) - Int(accent.green)
            let db = Int(rgb.blue) - Int(accent.blue)
            return dr * dr + dg * dg + db * db
        }
        return candidates.max { distance($0) < distance($1) } ?? .palette.info
    }

    /// How a button is styled.
    @ViewBuilder
    private var stylingColumn: some View {
        VStack(alignment: .leading, spacing: 1) {
            counter
            styles
            disabledButtons
        }
    }

    /// How a modifier on a container reaches the controls inside it.
    @ViewBuilder
    private var cascadeColumn: some View {
        VStack(alignment: .leading, spacing: 1) {
            cascadingDisabled
            tinted
            plainStyle
        }
    }

    /// How buttons compose — with each other, with a text style, with a URL.
    @ViewBuilder
    private var compositionColumn: some View {
        VStack(alignment: .leading, spacing: 1) {
            buttonRowSection
            themeableText
            linksSection
        }
    }

    @ViewBuilder
    private var counter: some View {
            DemoSection("page.buttons.section.counter") {
                HStack(spacing: 2) {
                    Button("+1") {
                        clickCount += 1
                    }
                    .buttonStyle(.primary)
                    Button("+10") {
                        clickCount += 10
                    }
                    .buttonStyle(.success)
                    Button("page.buttons.reset") {
                        clickCount = 0
                    }
                    .buttonStyle(.destructive)
                    Text("\(L("page.buttons.clicks")): \(clickCount)")
                        .bold()
                        .foregroundStyle(.palette.accent)
                }
            }
    }

    @ViewBuilder
    private var styles: some View {
            DemoSection("page.buttons.section.styles") {
                HStack(spacing: 2) {
                    Button("page.buttons.default") {
                        clickCount += 1
                    }
                    Button("page.buttons.primary") {
                        clickCount += 1
                    }
                    .buttonStyle(.primary)
                    Button("page.buttons.success") {
                        clickCount += 1
                    }
                    .buttonStyle(.success)
                    Button("page.buttons.destructive") {
                        clickCount += 1
                    }
                    .buttonStyle(.destructive)
                }
            }
    }

    @ViewBuilder
    private var disabledButtons: some View {
            DemoSection("page.buttons.section.disabled") {
                HStack(spacing: 2) {
                    Button("page.buttons.enabled") { clickCount += 1 }
                    Button("page.buttons.disabled") {}.disabled()
                }
            }
    }

    @ViewBuilder
    private var cascadingDisabled: some View {
            DemoSection("page.buttons.section.cascadingDisabled") {
                // .disabled on a container cascades to every control inside.
                VStack(alignment: .leading, spacing: 1) {
                    Button("page.buttons.cantClick") { clickCount += 1 }
                    Toggle("page.buttons.cantToggle", isOn: .constant(true))
                }
                .disabled(true)
            }
    }

    @ViewBuilder
    private var tinted: some View {
            DemoSection("page.buttons.section.tinted") {
                // .tint cascades the accent to every control inside. The toggle
                // drives it: flip it off and the tint (on the button AND on the
                // toggle's own checkbox) disappears — a live cascade demo.
                VStack(alignment: .leading, spacing: 1) {
                    Button("page.buttons.primary") { clickCount += 1 }.buttonStyle(.primary)
                    Toggle("page.buttons.toggle", isOn: $tintToggle)
                }
                .tint(tintToggle ? demoTint : nil)
            }
    }

    @ViewBuilder
    private var plainStyle: some View {
            DemoSection("page.buttons.section.plain") {
                HStack(spacing: 2) {
                    Button("\(L("page.buttons.link")) 1") { clickCount += 1 }
                        .buttonStyle(.plain)
                    Button("\(L("page.buttons.link")) 2") { clickCount += 1 }
                        .buttonStyle(.plain)
                }
            }
    }

    @ViewBuilder
    private var buttonRowSection: some View {
            DemoSection("page.buttons.section.buttonRow") {
                ButtonRow(spacing: 3) {
                    Button("page.buttons.cancel") { clickCount += 1 }
                    Button("page.buttons.save") { clickCount += 1 }
                }
                .buttonStyle(.primary)
            }
    }

    @ViewBuilder
    private var themeableText: some View {
            DemoSection("page.buttons.section.themeableText") {
                VStack(alignment: .leading, spacing: 1) {
                    // .buttonTextStyle re-themes the label text of every button in
                    // the subtree; the brackets/background stay as the style draws
                    // them.
                    HStack(spacing: 2) {
                        Button("page.buttons.one") { clickCount += 1 }
                        Button("page.buttons.two") { clickCount += 1 }
                        Button("page.buttons.delete", role: .destructive) { clickCount += 1 }
                    }
                    .buttonTextStyle { $0.bold = true; $0.foreground = .green }

                    Text("page.buttons.themeableNote")
                    .foregroundStyle(.palette.foregroundSecondary)
                }
            }

            // A Link is a button that opens a URL, so it belongs with the other
            // activatable controls: Tab to it and press Enter, or click it.
    }

    @ViewBuilder
    private var linksSection: some View {
            DemoSection("page.buttons.section.links") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.newControls.linkHint").foregroundStyle(.palette.foregroundSecondary)
                    Link("swift.org", destination: URL(string: "https://swift.org")!)
                    Link(destination: URL(string: "https://github.com/apple/swift")!) {
                        Label("apple/swift", systemImage: "swift")
                    }
                }
            }
    }

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: 1) {

            // Nine short sections that ran straight down the page and used 41%
            // of a wide terminal. Preferred arrangement first, then
            // progressively narrower ones — the `ViewThatFits(in: .horizontal)`
            // shape the Animation page and the track editor use. Grouped by
            // what each demonstrates: how a button is styled, how a modifier
            // cascades into a group, and how buttons compose with other things.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 4) {
                    stylingColumn
                    cascadeColumn
                    compositionColumn
                }
                HStack(alignment: .top, spacing: 4) {
                    VStack(alignment: .leading, spacing: 1) {
                        stylingColumn
                        cascadeColumn
                    }
                    compositionColumn
                }
                VStack(alignment: .leading, spacing: 1) {
                    stylingColumn
                    cascadeColumn
                    compositionColumn
                }
            }

            KeyboardHelpSection(
                "page.buttons.section.focusNav",
                shortcuts: [
                    "page.buttons.help.tab",
                    "page.buttons.help.enterSpace",
                ]
            )
        }
    }
}
