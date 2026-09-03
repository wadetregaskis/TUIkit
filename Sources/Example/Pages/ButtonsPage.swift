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
/// Records the links TUIkit opened itself.
///
/// A reference type, and `@unchecked Sendable`, because `OpenURLAction`'s
/// handler is `@Sendable` and so cannot mutate the page's main-actor `@State`
/// — the same shape `LinkTests` uses for the same reason. It is sound for the
/// same reason `TerminalImageStore`'s is: every write comes from a `Link`'s
/// button action and every read from a render, both on the run loop's own
/// thread, one pass at a time.
///
/// It needs no change notification of its own. The click that causes an open IS
/// an input event, so the loop renders a frame straight after it and that frame
/// reads these values.
private final class LinkOpenLog: @unchecked Sendable {
    private(set) var last = ""
    /// How many opens TUIkit has performed. Named `opens` rather than `count`
    /// so the emptiness check below reads as arithmetic and not as a
    /// collection being probed — which is what `count > 0` looks like.
    private(set) var opens = 0

    var hasOpened: Bool { opens > 0 }

    func record(_ url: URL) {
        last = url.absoluteString
        opens += 1
    }
}

struct ButtonsPage: View {
    @State private var clickCount: Int = 0
    @State private var tintToggle: Bool = true

    /// Which focus affordance the two links below use. Off is the default a
    /// `Link` ships with — the words themselves breathe, and nothing is
    /// reserved beside them, which is what lets a link sit inside a sentence.
    @State private var linkBullet: Bool = false

    /// How links reveal their destination, applied to the whole page — the
    /// modifier cascades, so one picker changes every link on it including the
    /// ones inside the sentence below.
    @State private var linkDisplay: LinkDisplay = .automatic

    /// Where TUIkit's OWN opens are recorded.
    ///
    /// Worth instrumenting because the two openers are otherwise
    /// indistinguishable: where a terminal honours OSC 8 it may open a link on
    /// a click the application never sees, and where it does not — or on a
    /// gesture it does not claim — the click reaches `Link`'s button and
    /// `OpenURLAction` opens the same URL. Same browser, same page, no way to
    /// tell which one did it. This only moves for the second.
    @State private var openLog = LinkOpenLog()

    /// Read so the demo's tint can be chosen against the palette in force, and
    /// re-chosen when the theme changes.
    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView {
            content
        }
        // Page-level, so every link reports — the ones in the prose section
        // below included, not just the two beside the readout.
        .environment(\.openURL, recordingOpener)
        // …and page-level for the same reason: the picker sits beside two
        // links and governs all of them, including the ones inside the
        // sentence, which is where the difference between the modes is
        // actually worth looking at.
        .linkDisplay(linkDisplay)
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

    /// Records every activation TUIkit handles, then hands the URL on exactly
    /// as the default action would.
    ///
    /// `.systemAction`, not `.handled`: the demo must show what a real app
    /// does, and what a real app does is defer — which since 2026-09-03 means
    /// the framework declines to launch anything unless
    /// `TerminalClient.urlOpeningSupport` says this machine is the user's. So
    /// this readout says the click reached the APP rather than the terminal,
    /// which is the distinction that cannot otherwise be seen.
    private var recordingOpener: OpenURLAction {
        let log = openLog
        return OpenURLAction { url in
            log.record(url)
            return .systemAction
        }
    }

    @ViewBuilder
    private var linksSection: some View {
            DemoSection("page.buttons.section.links") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.newControls.linkHint").foregroundStyle(.palette.foregroundSecondary)
                    Toggle("page.buttons.links.bulletToggle", isOn: $linkBullet)
                    Picker("page.buttons.links.displayMode", selection: $linkDisplay) {
                        Text("page.buttons.links.display.automatic").tag(LinkDisplay.automatic)
                        Text("page.buttons.links.display.popover").tag(LinkDisplay.popover)
                        Text("page.buttons.links.display.parentheses")
                            .tag(LinkDisplay.urlInParentheses)
                        Text("page.buttons.links.display.urlOnly").tag(LinkDisplay.urlOnly)
                    }
                    // Scoped to these two, not to the page: the sentence in the
                    // section below is the case the default exists for, and
                    // watching it grow two cells per link would demonstrate the
                    // wrong thing.
                    VStack(alignment: .leading, spacing: 1) {
                        Link("swift.org", destination: URL(string: "https://swift.org")!)
                        Link(destination: URL(string: "https://github.com/apple/swift")!) {
                            Label("apple/swift", systemImage: "swift")
                        }
                    }
                    .linkFocusIndicator(linkBullet ? .bullet : .text)
                }
            }
    }

    /// What TUIkit itself opened.
    ///
    /// In the full-width section, NOT beside the links it reports on, and that
    /// is a layout constraint rather than a preference: it is prose, the links
    /// live in a `ViewThatFits` column, and a paragraph in one of those columns
    /// makes every horizontal arrangement fail to fit — collapsing the whole
    /// page to a single narrow stack. Which it did, until the first click
    /// shortened this text and the page silently rearranged itself.
    @ViewBuilder
    private var appOpenedReadout: some View {
        if openLog.hasOpened {
            // Two rows rather than one interpolated `Text`: an interpolated
            // literal becomes a key with `%@` in it, and
            // `page.buttons.links.openedCount %@` is not a key anybody wants to
            // find in a translation table.
            HStack(spacing: 3) {
                ValueDisplayRow("page.buttons.links.openedByApp", openLog.last)
                ValueDisplayRow("page.buttons.links.openedCount", "\(openLog.opens)")
            }
        } else {
            Text("page.buttons.links.openedNothingYet")
                .foregroundStyle(.palette.foregroundTertiary)
        }
    }

    /// What the terminal painting this app does with the OSC 8 escape a `Link`
    /// carries — asked live rather than written down.
    ///
    /// Its own full-width section, below the three columns rather than inside
    /// one, because it is the only part of this page that is mostly prose: in a
    /// column it made that column tall enough that `ViewThatFits` gave up on
    /// every horizontal arrangement and the whole page fell to one narrow
    /// stack.
    ///
    /// Live and not a static paragraph, because the escape is invisible either
    /// way: "hover a link and your terminal shows you the URL" is true on two
    /// of the five hosts TUIkit models and false on the rest, and nothing on
    /// screen tells the reader which one they are looking at. That IS the
    /// incomplete support, so the demo has to name it.
    @ViewBuilder
    private var hyperlinkSection: some View {
        DemoSection("page.buttons.section.hyperlinks") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.buttons.links.osc8")
                    .foregroundStyle(.palette.foregroundSecondary)

                // A link in its natural habitat: a phrase inside a sentence,
                // not an address on a line of its own. `HStack(spacing: 0)`
                // rather than one `Text`, because a destination belongs to a
                // `Link` and the prose either side of it does not.
                //
                // The prose fragments carry their own word spaces, which is
                // only true because a focused `Link` breathes its own words
                // rather than growing a bullet beside them — see
                // `.linkFocusIndicator(_:)`. Under `.bullet` the same sentence
                // gains two cells before each linked phrase, which is what the
                // toggle above the two links is for.
                //
                // The sentence is kept SHORT for the same reason its
                // explanation is a separate paragraph below: a `Text` that
                // wraps inside an `HStack` wraps within its own column, so a
                // long clause after a link starts its second line under the
                // link rather than at the margin.
                HStack(spacing: 0) {
                    Text("page.buttons.links.proseA")
                    Link(
                        L("page.buttons.links.linkGuide"),
                        destination: URL(string: "https://www.swift.org/documentation/")!)
                    Text("page.buttons.links.proseB")
                    Link(
                        L("page.buttons.links.linkSource"),
                        destination: URL(string: "https://github.com/swiftlang/swift")!)
                    Text("page.buttons.links.proseC")
                }
                Text("page.buttons.links.inlineNote")
                    .foregroundStyle(.palette.foregroundSecondary)

                // …and the same shape with the escape suppressed. Deliberately
                // NOT spelled as an address: terminals scan displayed text for
                // things that look like URLs and linkify those on their own, so
                // an example claiming to carry no hyperlink would be made one
                // anyway if it were written like a URL — demonstrating the
                // opposite of what it says.
                HStack(spacing: 0) {
                    Link(
                        L("page.buttons.links.linkStarted"),
                        destination: URL(string: "https://www.swift.org/getting-started/")!)
                        .terminalHyperlinks(false)
                    Text("page.buttons.links.proseD")
                }
                Text("page.buttons.links.suppressedNote")
                    .foregroundStyle(.palette.foregroundSecondary)
                Text("page.buttons.links.autodetect")
                    .foregroundStyle(.palette.foregroundTertiary)

                terminalHyperlinkStatus
                appOpenedReadout
            }
        }
    }

    /// This terminal's answer, and why it answers that way.
    @ViewBuilder
    private var terminalHyperlinkStatus: some View {
        // `.effective` rather than `.current` — it is what
        // `hyperlinksSupported` itself reads, so simulating a host (the
        // TerminalClientQuirks app, or `TUIKIT_TERM_PROGRAM`) moves the name and
        // the verdict together. Asking `.current` here would print one
        // terminal's name beside another terminal's answer.
        let program = TerminalClient.effective.program
        VStack(alignment: .leading) {
            HStack(spacing: 3) {
                ValueDisplayRow("page.buttons.links.terminal", Self.displayName(of: program))
                // The same question the renderer asks before emitting, so this
                // row and the bytes on the wire cannot disagree.
                ValueDisplayRow(
                    "page.buttons.links.osc8Status",
                    L(
                        TerminalClient.hyperlinksSupported
                            ? "page.buttons.links.honoured" : "page.buttons.links.notHonoured"))
            }
            // `L(...)`, not `Text(computedKey)`: only a string LITERAL is a
            // lookup key. A computed `String` binds to the disfavoured overload
            // and would print the key itself.
            Text(L(Self.hyperlinkNoteKey(for: program)))
                .foregroundStyle(.palette.foregroundTertiary)
        }
    }

    /// The terminal's name as a person writes it.
    ///
    /// Not `Program.termProgramName`, which spells these `Apple_Terminal` and
    /// `iTerm.app`: that is how the environment variable names the host, not
    /// how the product does, and this row is read by a human.
    private static func displayName(of program: TerminalClient.Program) -> String {
        switch program {
        case .appleTerminal: "Apple Terminal"
        case .iTerm2: "iTerm2"
        case .ghostty: "Ghostty"
        case .warp: "Warp"
        case .tmux: "tmux"
        // The only one of the six that is a description rather than a name.
        case .unidentified: L("page.buttons.links.unidentified")
        }
    }

    /// Why this host answers the way it does — one observed reason each, from
    /// `Documentation/Terminal-compatibility.md`, which is where any correction
    /// to them belongs first.
    private static func hyperlinkNoteKey(for program: TerminalClient.Program) -> String {
        switch program {
        case .iTerm2: "page.buttons.links.noteITerm2"
        case .ghostty: "page.buttons.links.noteGhostty"
        case .tmux: "page.buttons.links.noteTmux"
        case .appleTerminal: "page.buttons.links.noteAppleTerminal"
        case .warp: "page.buttons.links.noteWarp"
        case .unidentified: "page.buttons.links.noteUnidentified"
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

            hyperlinkSection

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
