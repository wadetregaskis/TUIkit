//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ValueHashOpenerTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitStyling
@testable import TUIkitView

/// A value holding one existential, as a view's environment modifier holds a
/// style: the existential is the field the plan steps through.
private struct Holds<Existential> {
    let value: Existential
    let tail: UInt8
}

/// An opener is an optimisation and nothing else: a table given one opens an
/// existential of its static type directly, where a table without one opens it
/// by a cast, and the two must mix the same words — or a value would hash one
/// way under an app's caches and another under a bare one's.
@MainActor
@Suite("An existential's opener mixes what the cast would")
struct ValueHashOpenerTests {
    /// Tables live as long as the test: a plan read from a table that has gone
    /// is read from freed memory.
    private let opened = ValueHashPlans.tuikit()
    private let cast = ValueHashPlans()

    private func hash<V>(_ value: V, _ plans: ValueHashPlans) -> Int? {
        withUnsafePointer(to: value) { plans.valueHash(at: $0) }
    }

    /// Checks `value` both ways, and returns the static type it checked.
    @discardableResult
    private func check<Existential>(
        _ value: Existential, sourceLocation: SourceLocation = #_sourceLocation
    ) -> ObjectIdentifier {
        let holder = Holds(value: value, tail: 7)
        let viaOpener = hash(holder, opened)
        #expect(viaOpener != nil, sourceLocation: sourceLocation)
        #expect(viaOpener == hash(holder, cast), sourceLocation: sourceLocation)
        #expect(
            opened.plan(for: Holds<Existential>.self).pointee.stepDescriptions
                == ["0: existential opened by \(Existential.self)"], sourceLocation: sourceLocation)
        #expect(
            cast.plan(for: Holds<Existential>.self).pointee.stepDescriptions
                == ["0: existential cast from \(Existential.self)"], sourceLocation: sourceLocation)
        return ObjectIdentifier(Existential.self)
    }

    @Test("Every opener TUIkit registers mixes the words the cast mixes, and each is checked here")
    func everyOpener() {
        var checked: Set<ObjectIdentifier> = [
            check(DefaultButtonStyle() as any ButtonStyle),
            check(AutomaticFormStyle() as any FormStyle),
            check(DefaultGaugeStyle() as any GaugeStyle),
            check(DefaultLabelStyle() as any LabelStyle),
            check(InsetGroupedListStyle() as any ListStyle),
            check(DefaultMenuStyle() as any MenuStyle),
            check(AutomaticNavigationSplitViewStyle() as any NavigationSplitViewStyle),
            check(AutomaticPickerStyle() as any PickerStyle),
            check(DefaultTextFieldStyle() as any TextFieldStyle),
            check(DefaultToggleStyle() as any ToggleStyle),
        ]
        // `AnyLayout`'s box is of a protocol private to its file, so it is
        // checked through the layout that holds it.
        let layout = AnyLayout(HStackLayout())
        #expect(hash(layout, opened) != nil)
        #expect(hash(layout, opened) == hash(layout, cast))
        let boxType = ValueHashOpener.tuikit.first { "\($0.type)" == "AnyLayoutBox" }?.type
        #expect(boxType != nil)
        if let boxType { checked.insert(ObjectIdentifier(boxType)) }
        #expect(opened.plan(for: AnyLayout.self).pointee.stepDescriptions == ["0: existential opened by AnyLayoutBox"])
        // A new opener fails here until it is checked above.
        #expect(Set(ValueHashOpener.tuikit.map { ObjectIdentifier($0.type) }) == checked)
    }

    @Test("Different payloads behind one opener hash apart")
    func differentPayloads() {
        #expect(
            hash(Holds(value: DefaultMenuStyle() as any MenuStyle, tail: 0), opened)
                != hash(Holds(value: InlineMenuStyle() as any MenuStyle, tail: 0), opened))
        #expect(
            hash(Holds(value: DefaultButtonStyle() as any ButtonStyle, tail: 0), opened)
                != hash(Holds(value: PlainButtonStyle() as any ButtonStyle, tail: 0), opened))
        #expect(hash(AnyLayout(HStackLayout()), opened) != hash(AnyLayout(VStackLayout()), opened))
    }

    /// A palette is opened directly by every table — the value hash's own
    /// module can name the protocol — and must mix what the cast would.
    @Test("A palette is opened directly by every table, as the cast would open it")
    func palette() {
        let holder = Holds(value: SystemPalette(.green) as any Palette, tail: 3)
        #expect(cast.plan(for: Holds<any Palette>.self).pointee.stepDescriptions == ["0: existential palette"])
        var direct = hashFoldSeed
        var viaCast = hashFoldSeed
        withUnsafePointer(to: holder.value) { pointer in
            #expect(ExistentialField.palette.mix(at: pointer, into: &direct, plans: cast))
            #expect(ExistentialField.other((any Palette).self).mix(at: pointer, into: &viaCast, plans: cast))
        }
        #expect(direct == viaCast)
        #expect(hash(holder, cast) != hash(Holds(value: SystemPalette(.amber) as any Palette, tail: 3), cast))
    }

    /// A plan's step holds its opener, closure and all, so a table must
    /// release what an opener captured when the table goes — every context
    /// and every test cache makes one and drops it. TUIkit's own openers
    /// capture nothing; an opener that does must not leak it.
    @Test("A table that goes releases what its openers captured")
    func openerCaptureIsReleased() {
        final class Sentinel {}
        weak var released: Sentinel?
        do {
            let sentinel = Sentinel()
            released = sentinel
            let opener = ValueHashOpener((any ButtonStyle).self) { _, _, _ in
                withExtendedLifetime(sentinel) { true }
            }
            let plans = ValueHashPlans(openers: [opener])
            #expect(
                plans.plan(for: Holds<any ButtonStyle>.self).pointee.stepDescriptions
                    == ["0: existential opened by \((any ButtonStyle).self)"])
        }
        #expect(released == nil)
    }
}
