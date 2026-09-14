//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EffectJournal.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Effect Journal

/// The per-frame registrations a memoized subtree made while it rendered, kept
/// so that serving its cached buffer can make them again.
///
/// Several services a view registers into are emptied before every walk and
/// refilled by the tree as it renders: the key dispatcher, the shortcut
/// registry, the status bar, the focus ring. A value memo that serves a cached
/// buffer skips the body that registers, so until now a subtree that registered
/// anything declined the cache (`VolatileReadTracker.sideEffects`). A
/// registration that can go through here instead is *replayable*: while a memo
/// renders on a miss it records one ``Entry`` per registration, stores them
/// with the buffer, and runs them again at the same place in the walk on every
/// hit. The registries and their per-walk clears stay exactly as they are.
///
/// Owned by `RenderCache`, one per cache, and main-actor only in practice:
/// every append and every replay happens during a render walk.
///
/// ## Recording
///
/// A registrar makes its live call exactly as it would without a memo. Only
/// while ``isRecording`` does it also append an entry, whose closure calls the
/// same registration with the values it captured. The closure is built inside
/// that check, never on the live path, so a registration outside any memo
/// allocates nothing extra. It must not capture a service: it looks the
/// dispatcher, registry or bar up from the context it is run against, because
/// a hit's context is a later frame's.
///
/// Memos nest, so recording has a depth. Each memo notes where its slice of
/// ``entries`` starts, and the journal empties when the outermost one finishes.
///
/// ## Channel tokens
///
/// A subtree can swap its key channels partway down: `.dimmed()` and the page
/// beneath a modal render their content with throwaway ones, and so does the
/// windowed stack's focus-reach probe. What such content registers goes to the
/// throwaways and is discarded with them. Replayed from the memo's own position
/// it would land in the LIVE services instead. So every entry carries the
/// ``Entry/channelToken`` of the channels it registered into, and a memo keeps
/// only the entries whose token matches its own context's.
///
/// The token is an `ObjectIdentifier`, which is only unique among live objects.
/// That is enough here: a memo compares entries appended during its own render
/// against its own context's channels, which that context keeps alive for the
/// whole render, so no entry appended then can carry a reused address equal to
/// it.
package final class EffectJournal {

    /// What kind of registration an entry makes.
    ///
    /// Only compared, never dispatched on: an entry's closure is opaque, so the
    /// render-memo verifier compares the kinds and the count a fresh render
    /// records against the ones a hit would replay.
    package struct Kind: Equatable, Sendable, CustomStringConvertible {
        /// A short name for reports, such as `onKeyPress`.
        package let name: String

        /// Creates a kind named `name`.
        package init(_ name: String) {
            self.name = name
        }

        package var description: String { name }
    }

    /// One recorded registration.
    package struct Entry {
        /// What the registration is.
        package let kind: Kind

        /// The key channels the registration went into, as
        /// `EnvironmentValues.keyChannelToken` read where it registered.
        package let channelToken: ObjectIdentifier?

        /// Makes the registration again, into the services of the context it
        /// is given.
        package let apply: @MainActor (RenderContext) -> Void

        /// Creates an entry.
        package init(
            kind: Kind, channelToken: ObjectIdentifier?,
            apply: @escaping @MainActor (RenderContext) -> Void
        ) {
            self.kind = kind
            self.channelToken = channelToken
            self.apply = apply
        }

        /// The same registration, tagged as made into `token`'s channels.
        package func retagged(_ token: ObjectIdentifier?) -> Self {
            Self(kind: kind, channelToken: token, apply: apply)
        }
    }

    /// Everything recorded since the outermost recording memo began.
    package private(set) var entries: [Entry] = []

    /// How many memos are recording, outermost to innermost.
    package private(set) var recordingDepth = 0

    /// Whether a registrar should append what it registers.
    package var isRecording: Bool { recordingDepth > 0 }

    /// Creates an empty journal that is not recording.
    package init() {}

    /// Begins a memo's recording and returns where its slice starts.
    package func beginRecording() -> Int {
        recordingDepth += 1
        return entries.count
    }

    /// Ends the innermost recording, emptying the journal when it was the
    /// outermost.
    package func endRecording() {
        recordingDepth -= 1
        if recordingDepth == 0 { entries.removeAll(keepingCapacity: true) }
    }

    /// Appends a registration. A caller checks ``isRecording`` first, so the
    /// closure is never built when nothing records.
    package func append(_ entry: Entry) {
        entries.append(entry)
    }

    /// The entries appended since `start`, a value ``beginRecording()``
    /// returned.
    package func entries(since start: Int) -> ArraySlice<Entry> {
        entries[start...]
    }
}

extension RenderContext {
    /// The render cache's effect journal while a value memo is recording, and
    /// `nil` otherwise — so a registrar builds its replay closure only when
    /// something will keep it.
    package var recordingEffectJournal: EffectJournal? {
        guard let journal = renderCache?.effectJournal, journal.isRecording else { return nil }
        return journal
    }
}
