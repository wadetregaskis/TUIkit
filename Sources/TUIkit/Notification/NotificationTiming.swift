//  🖥️ TUIkit — Terminal UI Kit for Swift
//  NotificationTiming.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - Notification Timing

/// Constants and utilities for notification animation timing.
///
/// Provides fade-in/fade-out durations, opacity calculation, and word-wrap
/// logic used by the `NotificationHostModifier` during rendering.
enum NotificationTiming {
    /// Duration of the fade-in phase in seconds.
    static let fadeInDuration: TimeInterval = 0.2

    /// Duration of the fade-out phase in seconds.
    static let fadeOutDuration: TimeInterval = 0.3

    /// How many ticks of 1/60 s a frame of a fade is drawn for: 2, a thirtieth of a
    /// second, the frame indeterminate bars and view animations step at.
    ///
    /// Not a sleep length: every wake the animation task plans is the instant a frame
    /// of 2 ticks begins on the clock the run loop stamps its frames with
    /// (``nextWakeNanos(after:due:)``), so a fade's renders land on instants the other
    /// animations on screen already change at. It used to sleep 23.8 ms from wherever
    /// its last sleep ended: about 42 renders a second, at instants no other animation
    /// shares, a rate a 60 Hz display cannot hold for a whole number of refreshes.
    static let frameTicks = 2

    /// The longest this will sleep even when nothing is due to change.
    ///
    /// A notification posted while an existing one is mid-life does not restart
    /// the animation task — it is guarded by the lifecycle token — so the sleep
    /// in progress is what decides when the new one first draws. Sleeping the
    /// whole flat stretch would leave a toast invisible for up to three
    /// seconds; a quarter of a second is the compromise, and still deletes the
    /// overwhelming majority of the wakes. The wake is the first frame instant at or
    /// after it, so up to one tick later.
    static let longestSleep: TimeInterval = 0.25

    /// How long until the opacity of a notification `elapsed` seconds old
    /// changes: 0 mid-fade, where it changes continuously.
    ///
    /// The whole point: a notification's opacity is a flat **1.0** for its
    /// entire visible duration — three seconds of the usual three and a half —
    /// and only the two fades at either end actually vary. Waking for every frame
    /// throughout means most renders draw a byte-identical screen, each one a full
    /// measure/layout/render/diff.
    static func timeUntilOpacityChanges(
        elapsed: TimeInterval, visibleDuration: TimeInterval
    ) -> TimeInterval {
        // Mid-fade, either end: the value moves continuously, so the next frame draws it.
        if elapsed < fadeInDuration { return 0 }
        let afterFadeIn = elapsed - fadeInDuration
        // The flat stretch: nothing changes until it ends.
        if afterFadeIn < visibleDuration { return visibleDuration - afterFadeIn }
        let afterVisible = afterFadeIn - visibleDuration
        if afterVisible < fadeOutDuration { return 0 }
        // Gone. The caller stops on its own expiry check; this simply asks for
        // nothing more.
        return .infinity
    }

    /// The instant the animation task wakes next, in nanoseconds on its clock, when it
    /// is `now` and the soonest opacity change is `due` seconds away
    /// (``timeUntilOpacityChanges(elapsed:visibleDuration:)``): the first instant a
    /// frame of ``frameTicks`` begins at or after that change, or after
    /// ``longestSleep`` if that comes first, and always after `now`, so mid-fade,
    /// where the change is now, it is the next frame's.
    ///
    /// Frames counted from tick zero of the clock, as every run's and scheduler grid's
    /// are, so the instants are the ones a bar or a view animation on the same screen
    /// changes at: a toast adds renders only where nothing else already renders.
    static func nextWakeNanos(after now: Int64, due: TimeInterval) -> Int64 {
        let change = now.addingReportingOverflow(AnimationClock.nanoseconds(max(0, min(longestSleep, due))))
        guard !change.overflow else { return .max }
        // A nanosecond before the change, so a change on a frame's first instant wakes
        // there; never before `now`, so a change due now wakes at the next frame.
        return AnimationClock.nanoseconds(
            ofNextTickMultiple: frameTicks, after: max(now, change.partialValue - 1))
    }

    /// Calculates the current opacity based on elapsed time and phase.
    ///
    /// The notification goes through three phases:
    /// 1. Fade-in (0 → 1.0 over `fadeInDuration`)
    /// 2. Visible (1.0 for `visibleDuration`)
    /// 3. Fade-out (1.0 → 0.0 over `fadeOutDuration`)
    ///
    /// - Parameters:
    ///   - elapsed: Time elapsed since the notification appeared.
    ///   - visibleDuration: How long the notification stays fully visible.
    /// - Returns: The current opacity value between 0.0 and 1.0.
    static func opacity(elapsed: TimeInterval, visibleDuration: TimeInterval) -> Double {
        if elapsed < fadeInDuration {
            return min(1.0, elapsed / fadeInDuration)
        }

        let afterFadeIn = elapsed - fadeInDuration
        if afterFadeIn < visibleDuration {
            return 1.0
        }

        let afterVisible = afterFadeIn - visibleDuration
        if afterVisible < fadeOutDuration {
            return max(0.0, 1.0 - afterVisible / fadeOutDuration)
        }

        return 0.0
    }

    /// Wraps text into lines that fit a maximum terminal cell width.
    ///
    /// Splits on word boundaries (spaces). Words longer than `maxWidth`
    /// are placed on their own line without further splitting.
    /// Uses terminal-aware width measurement so wide characters (CJK, emoji)
    /// that occupy 2 cells are counted correctly.
    ///
    /// - Parameters:
    ///   - text: The text to wrap.
    ///   - maxWidth: Maximum terminal cells per line.
    /// - Returns: An array of wrapped lines (never empty).
    static func wordWrap(_ text: String, maxWidth: Int) -> [String] {
        guard maxWidth > 0 else { return [text] }

        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        var lines: [String] = []
        var currentLine = ""
        var currentLineWidth = 0

        for word in words {
            let wordStr = String(word)
            let wordWidth = wordStr.strippedLength
            if currentLine.isEmpty {
                currentLine = wordStr
                currentLineWidth = wordWidth
            } else if currentLineWidth + 1 + wordWidth <= maxWidth {
                currentLine += " " + wordStr
                currentLineWidth += 1 + wordWidth
            } else {
                lines.append(currentLine)
                currentLine = wordStr
                currentLineWidth = wordWidth
            }
        }

        if !currentLine.isEmpty {
            lines.append(currentLine)
        }

        return lines.isEmpty ? [""] : lines
    }
}
