//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ModuleResource.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

// MARK: - Finding this module's own resources

/// The URL of a file in this module's resource bundle — asked of the bundle
/// first, and worked out from the bundle's location second.
///
/// The second half is not belt and braces. `Bundle.module` resolves on every
/// platform this framework builds for, but `url(forResource:withExtension:
/// subdirectory:)` is implemented only where Foundation's bundle machinery is:
/// on WebAssembly it returns `nil` for a file sitting in the directory the
/// bundle names. Since the layout of a SwiftPM resource bundle is not a mystery
/// — the files are where the build put them, under the bundle URL — the
/// fallback simply looks.
///
/// The consequence of not having it is quiet rather than loud, which is why it
/// is worth a named function: the framework's own strings come back as their
/// keys (`statusbar.quit` across the bottom of the screen) and its version
/// reads `unknown`. That is exactly how the first WebAssembly build came up.
///
/// - Parameters:
///   - name: The resource's file name, without extension.
///   - extension: The extension, or `nil` for a file that has none.
///   - subdirectory: A directory within the bundle, or `nil` for its root.
/// - Returns: A URL that may or may not exist — the caller reads it and handles
///   failure, as it would have to with any bundle lookup.
func moduleResourceURL(
    named name: String,
    extension fileExtension: String?,
    subdirectory: String? = nil
) -> URL? {
    if let found = Bundle.module.url(
        forResource: name, withExtension: fileExtension, subdirectory: subdirectory)
    {
        return found
    }
    var url = Bundle.module.bundleURL
    if let subdirectory { url.appendPathComponent(subdirectory) }
    let fileName = fileExtension.map { "\(name).\($0)" } ?? name
    return url.appendingPathComponent(fileName)
}
