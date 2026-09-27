//  🖥️ TUIkit — Terminal UI Kit for Swift
//  InboxVariants.swift
//
//  The inbox, put where a value-trusting memo (Option C) has to draw its rows
//  again, or cannot tell whether it must: under a tint that moves, on a pushed
//  screen, in a sheet, and with its selection bound through `@Bindable`. The
//  same script plays against the same data as `inbox`, so each variant's
//  counts and costs read against `inbox`'s: what C keeps of inbox's saving
//  in each place is the difference.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import TUIkit

// MARK: - Where the inbox is put

/// Where the inbox is put, and how its selection is bound.
enum InboxVariant: String, CaseIterable {
    /// Under a `.tint` that the session flips now and then: an environment
    /// write above every row, which C compares and must draw the rows again
    /// for.
    case tinted = "inbox-tinted"
    /// Pushed onto a `NavigationStack`, so every row is drawn under the pushed
    /// screen's dismiss action, which C cannot compare until its box lands.
    case pushed = "inbox-pushed"
    /// Presented in a sheet, so every row is drawn under the sheet's dismiss
    /// action, which C cannot compare until its box lands.
    case sheet = "inbox-sheet"
    /// The selection bound through `@Bindable` to the model, as an app binds
    /// an `@Observable`'s property: the list reads it through a `Binding`,
    /// which nothing observes today.
    case observable = "inbox-observable"

    /// What the variant does to the inbox, for `--sessions`.
    var summary: String {
        switch self {
        case .tinted: "under a .tint the session flips"
        case .pushed: "pushed onto a NavigationStack"
        case .sheet: "presented in a sheet"
        case .observable: "its selection bound through @Bindable"
        }
    }
}

/// Where the variant's inbox sits: what the pushed screen or the sheet is
/// over, and what flips the tint.
@Observable
@MainActor
final class InboxPlacement {
    /// What is pushed over the root: the inbox, once. A `String`, so the
    /// destination is not the list's own selection type.
    var path: [String] = []
    /// Whether the sheet holding the inbox is presented.
    var presented = false
    /// Which of two tints the inbox is under.
    var tinted = false
}

/// The inbox page, put where `variant` puts it.
struct InboxVariantPage: View {
    let inbox: Inbox
    let placement: InboxPlacement
    let variant: InboxVariant

    var body: some View {
        switch variant {
        case .tinted:
            InboxPage(inbox: inbox).tint(placement.tinted ? Color.orange : Color.cyan)
        case .pushed:
            NavigationStack(path: Binding(get: { placement.path }, set: { placement.path = $0 })) {
                Text(verbatim: "Inbox").navigationDestination(for: String.self) { _ in InboxPage(inbox: inbox) }
            }
        case .sheet:
            Text(verbatim: "Inbox")
                .sheet(isPresented: Binding(get: { placement.presented }, set: { placement.presented = $0 })) {
                    InboxPage(inbox: inbox)
                }
        case .observable:
            InboxPage(inbox: inbox, bindsThroughBindable: true)
        }
    }
}

// MARK: - The script

/// `inbox`'s script, played against the inbox where `variant` puts it: opened
/// there before the first frame, and, under a tint, the tint flipped every
/// so often.
@MainActor
final class InboxVariantSession: StressSession {
    private let inbox: InboxSession
    private let placement = InboxPlacement()
    private let variant: InboxVariant

    init(config: StressConfig, variant: InboxVariant) {
        self.variant = variant
        inbox = InboxSession(config: config)
        inbox.countsAnywhere = variant == .pushed || variant == .sheet
        inbox.searches = variant != .pushed
        placement.path = variant == .pushed ? ["inbox"] : []
        placement.presented = variant == .sheet
    }

    var page: InboxVariantPage { InboxVariantPage(inbox: inbox.inbox, placement: placement, variant: variant) }

    /// `inbox`'s step; under a tint, every 23rd flips the tint as well, a
    /// write outside any event, as a theme following the time of day is.
    func step(_ index: Int) -> SessionStep {
        var step = inbox.step(index)
        if variant == .tinted, index > 0, index.isMultiple(of: 23) {
            placement.tinted.toggle()
            step.action += "+tint"
        }
        return step
    }

    func check(_ screen: [String], after index: Int) -> String? {
        inbox.check(screen, after: index)
    }

    static func descriptor(_ variant: InboxVariant) -> SessionDescriptor {
        SessionDescriptor(
            id: variant.rawValue,
            summary: "the inbox, \(variant.summary)",
            exercises:
                "inbox's script against inbox's data, with the list where a value-trusting memo must draw "
                + "its rows again or cannot tell: what it keeps of inbox's saving there",
            make: { config, width, height, cold in
                DrivenSession(
                    InboxVariantSession(config: config, variant: variant), width: width, height: height, cold: cold)
            })
    }
}
