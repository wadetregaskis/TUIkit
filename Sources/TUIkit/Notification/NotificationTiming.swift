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
