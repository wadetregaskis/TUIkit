//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DisclosureGroup.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - DisclosureGroup

/// A view that shows or hides another view, behind a disclosure triangle.
///
/// ```swift
/// DisclosureGroup("Advanced") {
///     Toggle("Verbose logging", isOn: $verbose)
///     Toggle("Keep temporary files", isOn: $keepTemps)
/// }
/// ```
///
/// ```
///   ▶ Advanced                 ▼ Advanced
///                                □ Verbose logging
///                                □ Keep temporary files
/// ```
///
/// The header is a Tab stop: **Return**, **Enter** or **Space** toggles it, and
/// so does a click anywhere on the row — the triangle and the label are one
/// control, as they are on macOS. **Right** opens it and **Left** closes it, as
/// they do in ``OutlineGroup`` and in a `List(_:children:)`; those two *set* the
/// state rather than toggling it, so holding Right on an open group does
/// nothing. Right stays the group's even then, while a Left with nothing left
/// to close goes back to being ordinary focus movement. The content is indented
/// to start under the label, so nesting groups inside one another draws a tree.
///
/// ## Who owns the expansion
///
/// By default the group owns it, starting collapsed. Pass `isExpanded:` to own
/// it yourself — to expand a group in response to something else, to collapse
/// every sibling when one opens, or to persist which sections were open:
///
/// ```swift
/// @State private var showingDetails = false
///
/// DisclosureGroup("Details", isExpanded: $showingDetails) {
///     DetailRows()
/// }
/// Button("Show me") { showingDetails = true }
/// ```
///
/// ## The content is not built while collapsed — but it is remembered
///
/// `content` is a closure, exactly as in SwiftUI, and a collapsed group never
/// calls it. So the rows of a closed group cost nothing per frame — not their
/// views, not their measurement — which is what makes a page of collapsed
/// sections cheap enough to be the default shape of a settings screen.
///
/// What a closed group *does* keep is the state its content had: a nested group
/// you opened is still open when you reopen its parent, and a field you typed
/// in still has your text. This is a deliberate divergence from SwiftUI, where
/// collapsing takes the content out of the hierarchy and its `@State` with it —
/// see `_DisclosedStateRetainer`. It lasts only while the group itself is on
/// screen: a group that leaves the tree takes everything below it along.
///
/// - Note: SwiftUI's `DisclosureGroupStyle` is not implemented; a terminal
///   disclosure is a triangle and an indent, and there is no second geometry to
///   express. The glyphs come from ``TerminalSymbols``.
public struct DisclosureGroup<Label: View, Content: View>: View {
    /// The label shown beside the disclosure triangle.
    let label: Label

    /// Builds the disclosed content. Called only while expanded.
    let content: () -> Content

    /// The caller's expansion binding, or `nil` when this group owns its own.
    let externalIsExpanded: Binding<Bool>?

    /// The expansion this group owns, used when no binding was supplied.
    ///
    /// Bound to persistent storage by the group's own render identity, so two
    /// `DisclosureGroup`s in the same stack expand independently and a group
    /// keeps its state across frames.
    @State private var localIsExpanded = false

    /// Creates a disclosure group with a custom label.
    ///
    /// - Parameters:
    ///   - content: The content shown while expanded.
    ///   - label: A view describing what the group discloses.
    public init(
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self.label = label()
        self.content = content
        self.externalIsExpanded = nil
    }

    /// Creates a disclosure group whose expansion the caller owns.
    ///
    /// - Parameters:
    ///   - isExpanded: A binding to whether the content is shown.
    ///   - content: The content shown while expanded.
    ///   - label: A view describing what the group discloses.
    public init(
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self.label = label()
        self.content = content
        self.externalIsExpanded = isExpanded
    }

    /// The binding actually in force — the caller's if given, this group's own
    /// otherwise.
    private var expansion: Binding<Bool> {
        externalIsExpanded ?? $localIsExpanded
    }

    public var body: some View {
        // Captured once: the closure below runs on a later key or click, long
        // after this body returned, and must write through the same binding
        // this frame read — see the note on environment reads in event
        // closures. A `Binding` is a pair of closures, so this is a copy of
        // two references, not a snapshot of the value.
        let expansion = self.expansion
        _DisclosedStateRetainer(isCollapsed: !expansion.wrappedValue) {
            groupBody(expansion: expansion)
        }
    }

    /// The header and, while open, the content.
    @ViewBuilder
    private func groupBody(expansion: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(
                action: { expansion.wrappedValue.toggle() },
                label: {
                    HStack(spacing: DisclosureMetrics.glyphSpacing) {
                        // `verbatim`: a triangle is a glyph, not a localization key.
                        Text(verbatim: expansion.wrappedValue
                            ? TerminalSymbols.disclosureExpanded
                            : TerminalSymbols.disclosureCollapsed)
                        label
                    }
                }
            )
            .buttonStyle(.plain)
            // Left closes and Right opens, which is what an outline view does
            // everywhere else in this framework — a `List(_:children:)` has
            // answered these keys since it gained a tree, and a disclosure that
            // did not was the odd one out. They SET rather than toggle, so
            // holding Right on an open group does nothing rather than shutting
            // it.
            .buttonKeyExtras(keys: [.left, .right]) { event in
                let wanted = event.key == .right
                guard expansion.wrappedValue != wanted else {
                    // Nothing to do here. Right is still the disclosure's — a
                    // group that is already open should not hand the key on and
                    // move the focus sideways. Left is not: once there is
                    // nothing left to close, it belongs to whatever encloses
                    // this group.
                    return wanted
                }
                expansion.wrappedValue = wanted
                return true
            }

            if expansion.wrappedValue {
                content().padding(.leading, DisclosureMetrics.contentIndent)
            }
        }
    }
}

// MARK: - Keeping a closed section's contents

/// Keeps the state of a collapsed group's content alive for as long as the
/// group itself is on screen.
///
/// A collapsed group does not build its content — that is the promise that
/// makes a page of closed sections cheap — and state whose view did not render
/// is normally collected at the end of the pass. Together those meant that
/// closing a section reset everything inside it: a nested group you had opened
/// was shut again when you reopened its parent, a field you had typed in was
/// blank. Reported as "the inner disclosure should preserve its state, no?",
/// and it should.
///
/// ``StateStorage/retainSubtree(_:)`` already says exactly this — it is what a
/// windowed list uses for the rows it scrolled past — so a collapsed group says
/// it too. The declaration is per-pass and made only while collapsed: an open
/// group's content renders and marks itself active in the ordinary way, and
/// when the group ITSELF leaves the tree nothing renews the claim, so the whole
/// subtree is collected on the next pass. Nothing is kept alive by a section
/// that is no longer there.
///
/// - Note: This is a deliberate divergence from SwiftUI, where a collapsed
///   group's content leaves the hierarchy and takes its `@State` with it. The
///   retention is not total: it covers `@State`, `onChange` baselines and
///   conditional-branch records, and not `.task`s or `onDisappear`, which
///   `LifecycleManager` sweeps on its own terms.
private struct _DisclosedStateRetainer<Content: View>: View, Renderable, Layoutable {
    let isCollapsed: Bool
    @ViewBuilder let content: Content

    var body: Never {
        fatalError("_DisclosedStateRetainer renders via Renderable")
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Render path only. A measure must not write persistent state, and the
        // claim is a per-pass declaration — the render that follows makes it.
        if isCollapsed, !context.isMeasuring {
            context.stateStorage?.retainSubtree(context.identity)
        }
        return TUIkitView.renderToBuffer(content, context: context)
    }

    /// Transparent: the wrapper adds no chrome and no identity step, so it
    /// measures exactly as what it wraps.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

// MARK: - Metrics

/// The cell arithmetic of a disclosure row.
///
/// Its own type because a generic type cannot hold a static stored property,
/// and because these are the numbers a test should assert against rather than
/// re-deriving them from a rendered line.
enum DisclosureMetrics {
    /// Cells between the triangle and the label.
    static let glyphSpacing = 1

    /// How far the content is indented, in cells: past the header's focus
    /// gutter, past the triangle, past the space after it — so the content
    /// starts exactly under the label.
    ///
    /// Derived rather than written as a literal, because each part of it is
    /// owned elsewhere: change the focus indicator's width or the triangle and
    /// the indent follows.
    static var contentIndent: Int {
        BorderRenderer.focusIndicatorWidth + triangleColumnWidth
    }

    /// The triangle plus the blank cell after it.
    ///
    /// ``OutlineGroup`` makes exactly this its toggle button's label, so the
    /// blank is part of the target: with the focus gutter in front of it that
    /// is four clickable cells around a one-cell glyph, which is the
    /// difference between a triangle you can hit and one you cannot.
    static var triangleColumnWidth: Int {
        TerminalSymbols.disclosureCollapsed.strippedLength + glyphSpacing
    }
}

// MARK: - DisclosureGroup Initializers (Text Label)

extension DisclosureGroup where Label == Text {
    /// Creates a disclosure group with a localized title.
    ///
    /// A string *literal* binds here and is looked up, exactly as it is in
    /// ``Text/init(_:)-(LocalizedStringKey)``.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the group's title.
    ///   - content: The content shown while expanded.
    public init(
        _ titleKey: LocalizedStringKey,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(content: content, label: { Text(titleKey) })
    }

    /// Creates a disclosure group with a localized title, whose expansion the
    /// caller owns.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the group's title.
    ///   - isExpanded: A binding to whether the content is shown.
    ///   - content: The content shown while expanded.
    public init(
        _ titleKey: LocalizedStringKey,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(isExpanded: isExpanded, content: content, label: { Text(titleKey) })
    }

    /// Creates a disclosure group titled with a string you computed, displayed
    /// as-is.
    ///
    /// - Parameters:
    ///   - label: The group's title.
    ///   - content: The content shown while expanded.
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ label: S,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(content: content, label: { Text(label) })
    }

    /// Creates a disclosure group titled with a string you computed, whose
    /// expansion the caller owns.
    ///
    /// - Parameters:
    ///   - label: The group's title.
    ///   - isExpanded: A binding to whether the content is shown.
    ///   - content: The content shown while expanded.
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ label: S,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(isExpanded: isExpanded, content: content, label: { Text(label) })
    }
}
