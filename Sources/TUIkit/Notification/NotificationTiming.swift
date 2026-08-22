//  🖥️ TUIKit — Terminal UI Kit for Swift
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
    /// How often to re-render while an opacity is actually CHANGING.
    ///
    /// ~42 fps, which is what the fades are drawn at. It is not how often to
    /// wake — see ``timeUntilOpacityChanges(elapsed:visibleDuration:)``.
    static let frameInterval: TimeInterval = 0.0238

    /// The longest this will sleep even when nothing is due to change.
    ///
    /// A notification posted while an existing one is mid-life does not restart
    /// the animation task — it is guarded by the lifecycle token — so the sleep
    /// in progress is what decides when the new one first draws. Sleeping the
    /// whole flat stretch would leave a toast invisible for up to three
    /// seconds; a quarter of a second is the compromise, and still deletes the
    /// overwhelming majority of the wakes.
    static let longestSleep: TimeInterval = 0.25

    /// How long until the opacity of a notification `elapsed` seconds old
    /// changes.
    ///
    /// The whole point: a notification's opacity is a flat **1.0** for its
    /// entire visible duration — three seconds of the usual three and a half —
    /// and only the two fades at either end actually vary. Waking 42 times a
    /// second throughout means ~126 of ~147 renders draw a byte-identical
    /// screen, each one a full measure/layout/render/diff.
    static func timeUntilOpacityChanges(
        elapsed: TimeInterval, visibleDuration: TimeInterval
    ) -> TimeInterval {
        // Mid-fade, either end: the value moves continuously, so draw it.
        if elapsed < fadeInDuration { return frameInterval }
        let afterFadeIn = elapsed - fadeInDuration
        // The flat stretch: nothing changes until it ends.
        if afterFadeIn < visibleDuration { return visibleDuration - afterFadeIn }
        let afterVisible = afterFadeIn - visibleDuration
        if afterVisible < fadeOutDuration { return frameInterval }
        // Gone. The caller stops on its own expiry check; this simply asks for
        // nothing more.
        return .infinity
    }

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
