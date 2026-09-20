//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PresentationDetent.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - PresentationDetent

/// A height a presented sheet can rest at. Matches SwiftUI's type of the same
/// name.
///
/// ```swift
/// .sheet(isPresented: $showing) {
///     DetailView()
///         .presentationDetents([.medium])
/// }
/// ```
///
/// > Note: SwiftUI's `.height(_:)` and `.fraction(_:)` take `CGFloat`; a
///   terminal measures in whole cells, so `.height(_:)` takes `Int` rows. The
///   fraction stays `Double` — it is multiplied by an extent and floored, which
///   is the one place fractional values belong (see the layout parity rule).
///   SwiftUI's `custom(_:)` (a `CustomPresentationDetent` type) is not here:
///   its resolution context exposes bitmap geometry.
public enum PresentationDetent: Hashable, Sendable {
    /// Roughly half the available height.
    case medium

    /// The full available height.
    case large

    /// A fraction of the available height.
    case fraction(Double)

    /// An exact number of rows.
    case height(Int)

    /// This detent's height within `extent` rows, clamped to it.
    ///
    /// Flooring the fraction rather than rounding is deliberate: a detent that
    /// rounded up could ask for one row more than the screen has, and the
    /// arithmetic that follows would have to defend against it.
    func resolved(in extent: Int) -> Int {
        let raw: Int
        switch self {
        case .medium: raw = extent / 2
        case .large: raw = extent
        case .fraction(let fraction): raw = Int((Double(extent) * fraction).rounded(.down))
        case .height(let rows): raw = rows
        }
        return max(1, min(extent, raw))
    }
}

// MARK: - Reading the detents

/// A view that carries presentation detents to whatever is presenting it.
///
/// Read by a static conformance check rather than a preference, for the reason
/// the navigation bar's height is a constant: a preference is only readable
/// *after* the subtree renders, and the detent has to be known *before* it, to
/// be the height it renders into. It is found through any other presentation
/// trait applied around it — see ``presentationTrait(_:of:)``.
@MainActor
protocol PresentationDetentsProviding {
    /// The detents this content offers.
    var detents: Set<PresentationDetent> { get }

    /// The detent currently chosen, if the caller bound one.
    var detentSelection: Binding<PresentationDetent>? { get }
}

extension PresentationDetentsProviding {
    /// The height to present at, in `extent` rows.
    ///
    /// With a selection binding, whatever it names. Without one, the SMALLEST
    /// detent — SwiftUI's own initial state. A terminal has no drag-grabber to
    /// move between them, so the binding is how a multi-detent sheet changes
    /// size; that is written down in `SwiftUI-compatibility.md` rather than
    /// left to be discovered.
    func resolvedHeight(in extent: Int) -> Int? {
        guard !detents.isEmpty else { return nil }
        if let selected = detentSelection?.wrappedValue, detents.contains(selected) {
            return selected.resolved(in: extent)
        }
        return detents.map { $0.resolved(in: extent) }.min()
    }
}

// MARK: - Carrying the resolved height to the sheet's box

/// The height a detented sheet's outermost *container* must render at, or `nil`
/// when the sheet is not detented.
private struct SheetDetentHeightKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

extension EnvironmentValues {
    /// The height the presented sheet's box must take, set by the modal host
    /// when the content named a detent.
    ///
    /// A detent is a height for the *sheet*, and in SwiftUI the sheet is a card
    /// with its own material, so the height is always something you can see. A
    /// terminal sheet has no material of its own — the presented content **is**
    /// the sheet — so the height has to reach the content's own box, which is
    /// what this value does: the outermost container (``Dialog``, ``Panel``,
    /// ``Card``, `.border()`) renders exactly this tall and encloses the
    /// leftover as empty interior.
    ///
    /// Consumed by that outermost container, which clears it for its children
    /// — the same one-shot discipline `focusIndicator` follows, and for the
    /// same reason: a `Panel` nested inside a detented `Dialog` must not also
    /// stretch to the sheet's height.
    ///
    /// Content with no box (a bare `Text`) has nothing to stretch, so it keeps
    /// its own size. The alternative — padding the presented buffer out to the
    /// detent — is what this replaced: those rows were blank, unstyled and
    /// *opaque*, so they punched a hole through the dialog's page rather than
    /// belonging to anything.
    var sheetDetentHeight: Int? {
        get { self[SheetDetentHeightKey.self] }
        set { self[SheetDetentHeightKey.self] = newValue }
    }
}

/// The wrapper `.presentationDetents(_:)` produces. Renders and measures as its
/// content; carrying the detents is its whole job.
struct _PresentationDetentsView<Content: View>: View, PresentationDetentsProviding {
    let content: Content
    let detents: Set<PresentationDetent>
    let detentSelection: Binding<PresentationDetent>?

    var body: Never {
        fatalError("_PresentationDetentsView renders via Renderable")
    }
}

extension _PresentationDetentsView: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIkit.renderToBuffer(content, context: context)
    }
}

extension _PresentationDetentsView: Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

extension _PresentationDetentsView: PresentationTraitWrapper {
    var presentationTraitContent: any View { content }
}

// MARK: - Modifier

extension View {
    /// Sets the available detents for the enclosing sheet. Matches SwiftUI's
    /// signature.
    ///
    /// Apply it to the sheet's **content**, as its outermost modifier:
    ///
    /// ```swift
    /// .sheet(isPresented: $showing) {
    ///     Settings()
    ///         .presentationDetents([.medium])
    /// }
    /// ```
    ///
    /// - Parameter detents: The heights the sheet may rest at. With more than
    ///   one and no selection, the smallest is used — see
    ///   ``presentationDetents(_:selection:)``.
    public func presentationDetents(_ detents: Set<PresentationDetent>) -> some View {
        _PresentationDetentsView(content: self, detents: detents, detentSelection: nil)
    }

    /// Sets the available detents and binds the one in use. Matches SwiftUI's
    /// signature.
    ///
    /// A terminal has no grabber to drag, so this binding is how a sheet moves
    /// between its detents — set it from a button, a key, or anything else.
    ///
    /// - Parameters:
    ///   - detents: The heights the sheet may rest at.
    ///   - selection: The detent currently in use.
    public func presentationDetents(
        _ detents: Set<PresentationDetent>,
        selection: Binding<PresentationDetent>
    ) -> some View {
        _PresentationDetentsView(content: self, detents: detents, detentSelection: selection)
    }
}

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``, so nothing about it is distributed to
/// the members of multi-view content.
extension _PresentationDetentsView: SingleContentWrapper {
    var wrappedContent: Content { content }
}
