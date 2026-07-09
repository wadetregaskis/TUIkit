//  🖥️ TUIKit — Terminal UI Kit for Swift
//  FileBrowser.swift
//
//  A small real-filesystem model shared by the List and Table file-browser
//  demos: read a directory into rows (folders first), with a ".." parent entry.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkit

/// One row in a file-browser demo — a real filesystem entry, or the synthetic
/// ".." parent that navigates up a level.
struct BrowserEntry: Identifiable, Sendable {
    /// The absolute path — unique and stable, so it doubles as the selection id.
    let id: String
    let name: String
    let isDirectory: Bool
    let isParent: Bool
    let url: URL
    let size: String
    let modified: String

    /// The leading emoji glyph: a "back up" arrow for "..", a folder or a file.
    /// Emoji (not SF Symbols) so it renders on Linux too, matching the other demos.
    var icon: String {
        if isParent { return "🔙" }
        return isDirectory ? "📁" : "📄"
    }

    /// A short type label for the Table's Type column.
    var typeLabel: String {
        if isParent { return "Parent" }
        if isDirectory { return "Directory" }
        let ext = (name as NSString).pathExtension
        return ext.isEmpty ? "File" : ext
    }
}

/// Reads directories into ``BrowserEntry`` rows. Every filesystem call is
/// best-effort (`try?`) so a permission-denied or vanished directory simply
/// yields an empty listing rather than crashing the demo.
enum FileBrowser {
    /// Where a browser demo starts — the user's home directory.
    static func seedDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    /// The contents of `url`: a ".." parent row first (unless already at the
    /// filesystem root), then folders, then files — each group sorted
    /// case-insensitively by name.
    static func entries(at url: URL) -> [BrowserEntry] {
        var rows: [BrowserEntry] = []

        let parent = url.deletingLastPathComponent()
        if parent.path != url.path {  // deletingLastPathComponent("/") == "/"
            rows.append(
                BrowserEntry(
                    id: url.path + "/..", name: "..", isDirectory: true, isParent: true,
                    url: parent, size: "", modified: ""))
        }

        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        let contents =
            (try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []

        let mapped: [BrowserEntry] = contents.map { child in
            let values = try? child.resourceValues(forKeys: Set(keys))
            let isDir = values?.isDirectory ?? false
            return BrowserEntry(
                id: child.path,
                name: child.lastPathComponent,
                isDirectory: isDir,
                isParent: false,
                url: child,
                size: isDir ? "" : formatSize(values?.fileSize),
                modified: formatDate(values?.contentModificationDate))
        }

        rows.append(
            contentsOf: mapped.sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.lowercased() < rhs.name.lowercased()
            })
        return rows
    }

    private static func formatSize(_ bytes: Int?) -> String {
        guard let bytes else { return "" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private static func formatDate(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
