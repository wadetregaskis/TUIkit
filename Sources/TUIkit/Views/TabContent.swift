//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TabContent.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Tab extraction

/// A tab recovered from the content closure before its value has been matched
/// to the `TabView`'s concrete selection-value type. Mirrors `_RawPickerOption`.
struct _RawTab {
    let value: AnyHashable
    let title: String
    /// The tab's content, type-erased. `AnyView` is `Layoutable` and forwards
    /// `sizeThatFits` to the wrapped view, so measuring `content` (see the call
    /// sites in `_TabViewCore`) sizes a `Layoutable` child — e.g. a `ScrollView`
    /// — via its own `sizeThatFits` (its content's size), not a render-to-measure
    /// pass that would let a flexible child fill the viewport and defeat
    /// size-to-content. (Before AnyView became `Layoutable` this needed a bespoke
    /// concrete-type `measure` closure captured pre-erasure; the forward made it
    /// redundant.)
    let content: AnyView
}

/// A view that can contribute tabs to a ``TabView``.
///
/// Mirrors the `PickerOptionProvider` pattern: rather than reflecting over the
/// view tree, each view type that may appear in a tab-view content closure
/// declares how to surface its tabs. `TupleView` / `ForEach` recurse.
@MainActor
protocol TabContentProvider {
    func tabs() -> [_RawTab]
}

extension EmptyView: TabContentProvider {
    func tabs() -> [_RawTab] { [] }
}

extension TupleView: TabContentProvider {
    func tabs() -> [_RawTab] {
        var result: [_RawTab] = []
        func collect<Child: View>(_ view: Child) {
            if let provider = view as? TabContentProvider {
                result.append(contentsOf: provider.tabs())
            }
        }
        repeat collect(each children)
        return result
    }
}

extension ForEach: TabContentProvider {
    func tabs() -> [_RawTab] {
        data.flatMap { element -> [_RawTab] in
            (content(element) as? TabContentProvider)?.tabs() ?? []
        }
    }
}
