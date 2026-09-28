//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderMemoComparatorTests.swift
//
//  The conditional `Equatable` conformances on the containers and modifier
//  wrappers are the staleness guard for `.equatable()` memoization:
//  `RenderCache.lookup` renders from the memo only while `oldView == view`,
//  and `lookupSize` answers from it on the measure side. A comparator that
//  forgets a stored property returns true for views that differ, and the memo
//  serves the previous frame's buffer (or, for an interactive subtree the
//  buffer store refuses, the previous frame's `ViewSize`).
//
//  Twenty of these comparators had never been executed. The suite renders
//  `HStack { … }.equatable()` in one place, but only ONCE — a first render is
//  a cache miss with no prior entry, so `==` is never reached. Only VStack's,
//  rendered twice, was ever run.
//
//  Two assertions per type, and a third that keeps the file honest: the number
//  of variants must equal the type's stored-property count, so adding a
//  property fails this test until someone has decided whether `==` compares it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Render-memo comparators")
struct RenderMemoComparatorTests {

    /// Asserts the whole contract for one conditionally-`Equatable` view.
    ///
    /// - Parameters:
    ///   - base: The reference value.
    ///   - identical: A value built the same way — separately, so `==` really
    ///     runs rather than comparing a value with itself.
    ///   - variants: One value per stored property, each differing from `base`
    ///     in that property alone.
    private func expectDistinguishes<V: Equatable>(
        _ label: String,
        _ base: V,
        identical: V,
        variants: [(String, V)],
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            base == identical, "\(label): two identically-built values must compare equal",
            sourceLocation: sourceLocation)
        // `Mirror` reports stored properties only, so a computed helper (say
        // `_ContainerViewCore.footerPadding`) does not count against this.
        let stored = Mirror(reflecting: base).children.count
        #expect(
            stored == variants.count,
            """
            \(label) has \(stored) stored properties but \(variants.count) are varied here. \
            A property was added or removed: decide whether `==` must compare it, then \
            add or drop the matching variant.
            """,
            sourceLocation: sourceLocation)
        for (name, variant) in variants {
            #expect(base != variant, "\(label): `==` ignores `\(name)`", sourceLocation: sourceLocation)
        }
    }

    // MARK: - Stacks

    @Test("HStack, ZStack and the lazy stacks compare every stored property")
    func stacks() {
        expectDistinguishes(
            "HStack", HStack { Text("a") }, identical: HStack { Text("a") },
            variants: [
                ("alignment", HStack(alignment: .top) { Text("a") }),
                ("spacing", HStack(spacing: 3) { Text("a") }),
                ("content", HStack { Text("b") }),
            ])
        expectDistinguishes(
            "ZStack", ZStack { Text("a") }, identical: ZStack { Text("a") },
            variants: [
                ("alignment", ZStack(alignment: .topLeading) { Text("a") }),
                ("content", ZStack { Text("b") }),
            ])
        expectDistinguishes(
            "LazyVStack", LazyVStack { Text("a") }, identical: LazyVStack { Text("a") },
            variants: [
                ("alignment", LazyVStack(alignment: .leading) { Text("a") }),
                ("spacing", LazyVStack(spacing: 3) { Text("a") }),
                ("content", LazyVStack { Text("b") }),
            ])
        expectDistinguishes(
            "LazyHStack", LazyHStack { Text("a") }, identical: LazyHStack { Text("a") },
            variants: [
                ("alignment", LazyHStack(alignment: .top) { Text("a") }),
                ("spacing", LazyHStack(spacing: 3) { Text("a") }),
                ("content", LazyHStack { Text("b") }),
            ])
        expectDistinguishes(
            "Group", Group { Text("a") }, identical: Group { Text("a") },
            variants: [("content", Group { Text("b") })])
    }

    // MARK: - Scrolling

    @Test("ScrollView compares its focus identity and disabled flag, not just its content")
    func scrollView() {
        let base = ScrollView { Text("a") }
        expectDistinguishes(
            "ScrollView", base, identical: ScrollView { Text("a") },
            variants: [
                ("axes", ScrollView(.horizontal) { Text("a") }),
                ("content", ScrollView { Text("b") }),
                ("explicitFocusID", base.focusID("elsewhere")),
                ("isDisabled", base.disabled()),
            ])
        expectDistinguishes(
            "ViewThatFits", ViewThatFits { Text("a") }, identical: ViewThatFits { Text("a") },
            variants: [
                ("axes", ViewThatFits(in: .horizontal) { Text("a") }),
                ("content", ViewThatFits { Text("b") }),
            ])
    }

    // MARK: - Framed containers

    @Test("Dialog, Panel and Card compare their whole configuration")
    func framedContainers() {
        let title = "Title"
        expectDistinguishes(
            "Dialog",
            Dialog(title: title, content: { Text("a") }, footer: { Text("f") }),
            identical: Dialog(title: title, content: { Text("a") }, footer: { Text("f") }),
            variants: [
                ("title", Dialog(title: "Other", content: { Text("a") }, footer: { Text("f") })),
                ("content", Dialog(title: title, content: { Text("b") }, footer: { Text("f") })),
                ("footer", Dialog(title: title, content: { Text("a") }, footer: { Text("g") })),
                (
                    "config",
                    Dialog(
                        title: title, borderStyle: .doubleLine, content: { Text("a") },
                        footer: { Text("f") })
                ),
            ])
        expectDistinguishes(
            "Panel",
            Panel(title, content: { Text("a") }, footer: { Text("f") }),
            identical: Panel(title, content: { Text("a") }, footer: { Text("f") }),
            variants: [
                ("title", Panel("Other", content: { Text("a") }, footer: { Text("f") })),
                ("content", Panel(title, content: { Text("b") }, footer: { Text("f") })),
                ("footer", Panel(title, content: { Text("a") }, footer: { Text("g") })),
                (
                    "config",
                    Panel(
                        title, borderStyle: .doubleLine, content: { Text("a") },
                        footer: { Text("f") })
                ),
            ])
        expectDistinguishes(
            "Card",
            Card(title: title, content: { Text("a") }, footer: { Text("f") }),
            identical: Card(title: title, content: { Text("a") }, footer: { Text("f") }),
            variants: [
                ("title", Card(title: "Other", content: { Text("a") }, footer: { Text("f") })),
                ("content", Card(title: title, content: { Text("b") }, footer: { Text("f") })),
                ("footer", Card(title: title, content: { Text("a") }, footer: { Text("g") })),
                (
                    "config",
                    Card(
                        title: title, borderStyle: .doubleLine, content: { Text("a") },
                        footer: { Text("f") })
                ),
                (
                    "backgroundColor",
                    Card(
                        title: title, backgroundColor: .red, content: { Text("a") },
                        footer: { Text("f") })
                ),
            ])
    }

    @Test("Box, ContainerView and its core compare every stored property")
    func containers() {
        expectDistinguishes(
            "Box", Box { Text("a") }, identical: Box { Text("a") },
            variants: [
                ("content", Box { Text("b") }),
                ("borderStyle", Box(.doubleLine) { Text("a") }),
                ("borderColor", Box(color: .red) { Text("a") }),
            ])

        func container(
            title: String? = "T", titleColor: Color? = nil, body: String = "a",
            footer: String = "f", style: ContainerStyle = .default,
            padding: EdgeInsets = EdgeInsets(horizontal: 1, vertical: 0)
        ) -> ContainerView<Text, Text> {
            ContainerView(
                title: title, titleColor: titleColor, style: style, padding: padding,
                content: { Text(body) }, footer: { Text(footer) })
        }
        expectDistinguishes(
            "ContainerView", container(), identical: container(),
            variants: [
                ("title", container(title: "Other")),
                ("titleColor", container(titleColor: .red)),
                ("content", container(body: "b")),
                ("footer", container(footer: "g")),
                ("style", container(style: ContainerStyle(hasBorder: false))),
                ("padding", container(padding: EdgeInsets(all: 2))),
            ])

        func core(
            title: String? = "T", titleColor: Color? = nil, body: String = "a",
            footer: String = "f", style: ContainerStyle = .default,
            padding: EdgeInsets = EdgeInsets(horizontal: 1, vertical: 0)
        ) -> _ContainerViewCore<Text, Text> {
            _ContainerViewCore(
                title: title, titleColor: titleColor, content: Text(body), footer: Text(footer),
                style: style, padding: padding)
        }
        expectDistinguishes(
            "_ContainerViewCore", core(), identical: core(),
            variants: [
                ("title", core(title: "Other")),
                ("titleColor", core(titleColor: .red)),
                ("content", core(body: "b")),
                ("footer", core(footer: "g")),
                ("style", core(style: ContainerStyle(hasBorder: false))),
                ("padding", core(padding: EdgeInsets(all: 2))),
            ])
    }

    // MARK: - Leaves with configuration

    @Test("ProgressView and GeometryProxy compare every stored property")
    func valueViews() {
        let base = ProgressView(
            fractionCompleted: 0, style: .block, label: Text("l"),
            currentValueLabel: Text("v"))
        expectDistinguishes(
            "ProgressView", base,
            identical: ProgressView(
                fractionCompleted: 0, style: .block, label: Text("l"),
                currentValueLabel: Text("v")),
            variants: [
                (
                    "fraction",
                    ProgressView(
                        fractionCompleted: 0.25, style: .block, label: Text("l"),
                        currentValueLabel: Text("v"))
                ),
                (
                    // The base is determinate at 0, the stored fraction an
                    // indeterminate bar also holds: only the flag differs.
                    "isDeterminate",
                    ProgressView(
                        fractionCompleted: nil, style: .block, label: Text("l"),
                        currentValueLabel: Text("v"))
                ),
                (
                    "style",
                    ProgressView(
                        fractionCompleted: 0, style: .bar, label: Text("l"),
                        currentValueLabel: Text("v"))
                ),
                (
                    "label",
                    ProgressView(
                        fractionCompleted: 0, style: .block, label: Text("other"),
                        currentValueLabel: Text("v"))
                ),
                (
                    "currentValueLabel",
                    ProgressView(
                        fractionCompleted: 0, style: .block, label: Text("l"),
                        currentValueLabel: Text("other"))
                ),
            ])

        expectDistinguishes(
            "GeometryProxy", GeometryProxy(width: 4, height: 5),
            identical: GeometryProxy(width: 4, height: 5),
            variants: [
                ("size", GeometryProxy(width: 6, height: 5)),
                ("globalOrigin", GeometryProxy(width: 4, height: 5, globalOrigin: (x: 1, y: 2))),
            ])
    }

    // MARK: - Modifier wrappers

    @Test("FlexibleFrameView compares all eight of its constraints")
    func flexibleFrame() {
        expectDistinguishes(
            "FlexibleFrameView",
            FlexibleFrameView(
                content: Text("a"), minWidth: 1, idealWidth: 2, maxWidth: nil, minHeight: 3,
                idealHeight: 4, maxHeight: nil, alignment: .center),
            identical: FlexibleFrameView(
                content: Text("a"), minWidth: 1, idealWidth: 2, maxWidth: nil, minHeight: 3,
                idealHeight: 4, maxHeight: nil, alignment: .center),
            variants: [
                (
                    "content",
                    FlexibleFrameView(
                        content: Text("b"), minWidth: 1, idealWidth: 2, maxWidth: nil,
                        minHeight: 3, idealHeight: 4, maxHeight: nil, alignment: .center)
                ),
                (
                    "minWidth",
                    FlexibleFrameView(
                        content: Text("a"), minWidth: 9, idealWidth: 2, maxWidth: nil,
                        minHeight: 3, idealHeight: 4, maxHeight: nil, alignment: .center)
                ),
                (
                    "idealWidth",
                    FlexibleFrameView(
                        content: Text("a"), minWidth: 1, idealWidth: 9, maxWidth: nil,
                        minHeight: 3, idealHeight: 4, maxHeight: nil, alignment: .center)
                ),
                (
                    "maxWidth",
                    FlexibleFrameView(
                        content: Text("a"), minWidth: 1, idealWidth: 2, maxWidth: .infinity,
                        minHeight: 3, idealHeight: 4, maxHeight: nil, alignment: .center)
                ),
                (
                    "minHeight",
                    FlexibleFrameView(
                        content: Text("a"), minWidth: 1, idealWidth: 2, maxWidth: nil,
                        minHeight: 9, idealHeight: 4, maxHeight: nil, alignment: .center)
                ),
                (
                    "idealHeight",
                    FlexibleFrameView(
                        content: Text("a"), minWidth: 1, idealWidth: 2, maxWidth: nil,
                        minHeight: 3, idealHeight: 9, maxHeight: nil, alignment: .center)
                ),
                (
                    "maxHeight",
                    FlexibleFrameView(
                        content: Text("a"), minWidth: 1, idealWidth: 2, maxWidth: nil,
                        minHeight: 3, idealHeight: 4, maxHeight: .infinity, alignment: .center)
                ),
                (
                    "alignment",
                    FlexibleFrameView(
                        content: Text("a"), minWidth: 1, idealWidth: 2, maxWidth: nil,
                        minHeight: 3, idealHeight: 4, maxHeight: nil, alignment: .topLeading)
                ),
            ])
    }

    @Test("The modifier wrappers compare their payload as well as their content")
    func modifierWrappers() {
        expectDistinguishes(
            "OverlayModifier",
            OverlayModifier(base: Text("a"), overlay: Text("o"), alignment: .center),
            identical: OverlayModifier(base: Text("a"), overlay: Text("o"), alignment: .center),
            variants: [
                ("base", OverlayModifier(base: Text("b"), overlay: Text("o"), alignment: .center)),
                (
                    "overlay",
                    OverlayModifier(base: Text("a"), overlay: Text("p"), alignment: .center)
                ),
                (
                    "alignment",
                    OverlayModifier(base: Text("a"), overlay: Text("o"), alignment: .topLeading)
                ),
            ])

        expectDistinguishes(
            "BadgeModifier", BadgeModifier(content: Text("a"), value: .int(1)),
            identical: BadgeModifier(content: Text("a"), value: .int(1)),
            variants: [
                ("content", BadgeModifier(content: Text("b"), value: .int(1))),
                ("value", BadgeModifier(content: Text("a"), value: .int(2))),
            ])

        expectDistinguishes(
            "SelectionDisabledModifier",
            SelectionDisabledModifier(content: Text("a"), isDisabled: false),
            identical: SelectionDisabledModifier(content: Text("a"), isDisabled: false),
            variants: [
                ("content", SelectionDisabledModifier(content: Text("b"), isDisabled: false)),
                ("isDisabled", SelectionDisabledModifier(content: Text("a"), isDisabled: true)),
            ])

        expectDistinguishes(
            "ListRowSeparatorModifier",
            ListRowSeparatorModifier(content: Text("a"), visibility: .visible, edges: .top),
            identical: ListRowSeparatorModifier(
                content: Text("a"), visibility: .visible, edges: .top),
            variants: [
                (
                    "content",
                    ListRowSeparatorModifier(
                        content: Text("b"), visibility: .visible, edges: .top)
                ),
                (
                    "visibility",
                    ListRowSeparatorModifier(
                        content: Text("a"), visibility: .hidden, edges: .top)
                ),
                (
                    "edges",
                    ListRowSeparatorModifier(
                        content: Text("a"), visibility: .visible, edges: .bottom)
                ),
            ])

        expectDistinguishes(
            "DimmedModifier", DimmedModifier(content: Text("a")),
            identical: DimmedModifier(content: Text("a")),
            variants: [("content", DimmedModifier(content: Text("b")))])

        expectDistinguishes(
            "_ZIndexView", _ZIndexView(zIndexValue: 1, content: Text("a")),
            identical: _ZIndexView(zIndexValue: 1, content: Text("a")),
            variants: [
                ("zIndexValue", _ZIndexView(zIndexValue: 2, content: Text("a"))),
                ("content", _ZIndexView(zIndexValue: 1, content: Text("b"))),
            ])
    }
}
