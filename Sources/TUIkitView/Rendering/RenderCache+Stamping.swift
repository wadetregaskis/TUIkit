//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderCache+Stamping.swift
//
//  What a hit serves: the stored buffer, or — where its animated cells have
//  moved on since it was drawn — the stored buffer stamped with the frames they
//  show now. In a file of its own because `RenderCache.swift` is at its
//  file-length ceiling.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

extension RenderCache {
    /// The buffer a hit on `entry` serves at the frame being drawn.
    ///
    /// The stored buffer, unless its runs show other pictures at ``frameInstant``
    /// than at the instant it was drawn and it has a ``CacheEntry/stencil``: then
    /// the stored buffer with those runs' frames for this instant put in their
    /// cuts, which is what drawing the subtree again would have produced — see
    /// `AnimationStencil`. An entry without a stencil is never a hit once its runs
    /// have moved on (``lookupEntry(identity:view:contextWidth:contextHeight:gradientFrame:surfaceBackground:effectScope:animationMustBeCurrent:)``),
    /// so it is served as stored.
    ///
    /// Stamped afresh from the stored buffer each time, never from a previous
    /// stamping: the entry keeps the one buffer, and a line is rebuilt only when
    /// a run on it has moved. Each stamping is counted in ``Stats/restamps``.
    ///
    /// Not for a measure pass, which is served the buffer as stored: a frame
    /// changes no cell's width, and a measure draws nothing.
    package func servedBuffer(of entry: CacheEntry) -> FrameBuffer {
        guard let stencil = entry.stencil, let drawnAt = entry.drawnAt, let frameInstant,
            frameInstant != drawnAt,
            let stamped = stencil.stamping(entry.buffer, at: frameInstant)
        else { return entry.buffer }
        stats.restamps += 1
        logDebug("STAMP \(entry.identity.path)")
        return stamped
    }
}
