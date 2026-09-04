//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Terminal+FrameDump.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

extension Terminal {
    /// `tuikit-frame (yyyyMMdd-HHmmss).ansi`, in the local time zone.
    ///
    /// A fixed pattern in a fixed locale, NOT `Date.formatted(date:time:)`:
    /// that style renders in `Locale.autoupdatingCurrent`, and in fifteen
    /// locales — European Portuguese and its regional variants among them —
    /// the abbreviated date carries `/`, which `URL(fileURLWithPath:)` reads
    /// as a directory separator. The dump then targeted a directory that did
    /// not exist and silently never happened.
    static func frameDumpFilename(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "tuikit-frame (\(formatter.string(from: date))).ansi"
    }
}
