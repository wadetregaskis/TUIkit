//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ValueHashOpeners.swift
//
//  The existentials of TUIkit's own protocols that views hold, opened
//  directly by the per-pass memos' value hash rather than by a cast.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitView

extension ValueHashPlans {
    /// A plan table that opens the existentials of TUIkit's own protocols a
    /// view holds directly (``ValueHashOpener/tuikit``) — what an app's render
    /// caches are to be made with.
    package static func tuikit() -> ValueHashPlans {
        ValueHashPlans(openers: ValueHashOpener.tuikit)
    }
}

extension ValueHashOpener {
    /// One opener for each protocol of this module that a view stores as an
    /// existential: the style protocols, held by the environment modifier
    /// every `.buttonStyle(_:)`, `.menuStyle(_:)` … makes, and `AnyLayout`'s
    /// erased box.
    ///
    /// A static type the value hash cannot name is opened by a cast otherwise
    /// — a box for an `Any` and a dynamic cast, 2.2% of a `menus` frame, whose
    /// buttons each hold an `any ButtonStyle`. Each opener mixes the words the
    /// cast would have (`ValueHashOpenerTests` holds them to it), so a table
    /// without them hashes every value the same, only slower.
    package static var tuikit: [ValueHashOpener] {
        [
            .init((any ButtonStyle).self) { pointer, hash, plans in
                func open<Style: ButtonStyle>(_ style: Style) -> Bool { mixOpened(style, into: &hash, plans: plans) }
                return open(pointer.assumingMemoryBound(to: (any ButtonStyle).self).pointee)
            },
            .init((any FormStyle).self) { pointer, hash, plans in
                func open<Style: FormStyle>(_ style: Style) -> Bool { mixOpened(style, into: &hash, plans: plans) }
                return open(pointer.assumingMemoryBound(to: (any FormStyle).self).pointee)
            },
            .init((any GaugeStyle).self) { pointer, hash, plans in
                func open<Style: GaugeStyle>(_ style: Style) -> Bool { mixOpened(style, into: &hash, plans: plans) }
                return open(pointer.assumingMemoryBound(to: (any GaugeStyle).self).pointee)
            },
            .init((any LabelStyle).self) { pointer, hash, plans in
                func open<Style: LabelStyle>(_ style: Style) -> Bool { mixOpened(style, into: &hash, plans: plans) }
                return open(pointer.assumingMemoryBound(to: (any LabelStyle).self).pointee)
            },
            .init((any ListStyle).self) { pointer, hash, plans in
                func open<Style: ListStyle>(_ style: Style) -> Bool { mixOpened(style, into: &hash, plans: plans) }
                return open(pointer.assumingMemoryBound(to: (any ListStyle).self).pointee)
            },
            .init((any MenuStyle).self) { pointer, hash, plans in
                func open<Style: MenuStyle>(_ style: Style) -> Bool { mixOpened(style, into: &hash, plans: plans) }
                return open(pointer.assumingMemoryBound(to: (any MenuStyle).self).pointee)
            },
            .init((any NavigationSplitViewStyle).self) { pointer, hash, plans in
                func open<Style: NavigationSplitViewStyle>(_ style: Style) -> Bool {
                    mixOpened(style, into: &hash, plans: plans)
                }
                return open(pointer.assumingMemoryBound(to: (any NavigationSplitViewStyle).self).pointee)
            },
            .init((any PickerStyle).self) { pointer, hash, plans in
                func open<Style: PickerStyle>(_ style: Style) -> Bool { mixOpened(style, into: &hash, plans: plans) }
                return open(pointer.assumingMemoryBound(to: (any PickerStyle).self).pointee)
            },
            .init((any TextFieldStyle).self) { pointer, hash, plans in
                func open<Style: TextFieldStyle>(_ style: Style) -> Bool { mixOpened(style, into: &hash, plans: plans) }
                return open(pointer.assumingMemoryBound(to: (any TextFieldStyle).self).pointee)
            },
            .init((any ToggleStyle).self) { pointer, hash, plans in
                func open<Style: ToggleStyle>(_ style: Style) -> Bool { mixOpened(style, into: &hash, plans: plans) }
                return open(pointer.assumingMemoryBound(to: (any ToggleStyle).self).pointee)
            },
            AnyLayout.valueHashOpener,
        ]
    }
}
