//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderCache+Lapse.swift
//
//  Whether a size kept until the clock moves still holds at the frame being
//  drawn — the one question an answer with a lapse (`SizeHold`) asks, asked the
//  same way by the size memo here and by a windowed stack's width in `@State`.
//
//  Split out of `RenderCache.swift`, which is at the file-length ceiling.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitCore

extension RenderCache {
    /// Whether an answer that lapses at `instant` still holds at the frame
    /// being drawn: always when it has no lapse, and otherwise while the
    /// frame's instant is before it.
    ///
    /// The frame's instant is ``frameDate``, the one date every walk of the
    /// frame resolves a timeline against, so an answer is kept or dropped for
    /// the whole frame together, never between its measure and its render.
    /// Where nothing stamps frames, the clock, as a timeline reads it there.
    package func holds(lapsingAt instant: Date?) -> Bool {
        Self.holds(lapsingAt: instant, in: self)
    }

    /// ``holds(lapsingAt:)`` for an answer kept OUTSIDE the cache, which may be
    /// asked where there is no cache — and then asks the clock.
    package static func holds(lapsingAt instant: Date?, in cache: RenderCache?) -> Bool {
        guard let instant else { return true }
        return (cache?.frameDate ?? Date()) < instant
    }
}
