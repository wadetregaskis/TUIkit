//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ListRowExtractor.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - List Row

/// A single row in a list, containing an ID and rendered content.
///
/// `ListRow` wraps user-provided content and associates it with an identifier
/// for selection tracking. Rows can span multiple lines (multi-line content).
struct ListRow<ID: Hashable> {
    /// The unique identifier for this row.
    let id: ID

    /// The rendered content buffer for this row.
    let buffer: FrameBuffer

    /// The badge value for this row (from environment).
    let badge: BadgeValue?

    /// The height of this row in lines.
    var height: Int { buffer.height }
}

// MARK: - List Row Extractor Protocol

/// Protocol for views that can provide list rows with IDs.
@MainActor
protocol ListRowExtractor {
    /// Extracts list rows with their associated IDs.
    func extractListRows<ID: Hashable>(context: RenderContext) -> [ListRow<ID>]
}

// MARK: - ForEach Conformance

extension ForEach: ListRowExtractor {
    func extractListRows<RowID: Hashable>(context: RenderContext) -> [ListRow<RowID>] {
        data.enumerated().compactMap { (index, element) -> ListRow<RowID>? in
            let elementID = element[keyPath: idKeyPath]
            let view = content(element)

            // Extract badge if the view is wrapped in a BadgeModifier
            let badge = extractBadgeValue(from: view)

            // Render the view
            let buffer = TUIkit.renderToBuffer(view, context: context)

            // Prefer the element's natural ID when its type matches
            // the row ID type the caller asked for.
            if let rowID = elementID as? RowID {
                return ListRow(id: rowID, buffer: buffer, badge: badge)
            }
            // Otherwise fall back to the row index. This makes
            // selectionless Lists with the Int-defaulted overload
            // pick up ForEach rows whose natural IDs are of a
            // different type (e.g. String). The Int-defaulted
            // overload is what Swift's overload resolution picks
            // for `List("title") { ForEach(strings, id: \.self) { ... } }`
            // because there's no other constraint to pin
            // SelectionValue, so without this fallback the cast
            // above would fail for every element and the list would
            // render as empty.
            if let indexID = index as? RowID {
                return ListRow(id: indexID, buffer: buffer, badge: badge)
            }
            return nil
        }
    }
}
