//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderCacheStyleContractTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

// MARK: - Fixtures

/// A memoizable view whose whole appearance comes from the ``LabelStyle`` in
/// force above it — the two halves are plain views, so neither depends on an
/// SF Symbol resolving on the host.
///
/// Like ``CachePicker`` and unlike the rest of these fixtures, what this draws
/// is readable straight out of the buffer: `.titleOnly` shows `Inbox` and
/// `.iconOnly` shows `*`, with no character in common. That is what lets the label's safety arm assert the
/// drawing rather than a hit count.
private struct CacheLabel: View, Equatable {
    var body: some View {
        Label { Text(verbatim: "Inbox") } icon: { Text(verbatim: "*") }
    }
}

/// A real ``Picker``, whose whole presentation comes from the ``PickerStyle`` in
/// force above it.
///
/// Like ``CacheLabel``, what this draws is readable straight out of the buffer,
/// and the two presentations share no line: `.radioGroup` draws a row per
/// option, `.menu` one collapsed row. Unlike ``CacheLabel`` it is the shipped
/// control rather than a stand-in for one — a picker memoizes, so the safety arm
/// can swap the style under a buffer that is genuinely a picker's.
private struct CachePicker: View, Equatable {
    var body: some View {
        Picker(selection: .constant(1)) {
            Text(verbatim: "One").tag(1)
            Text(verbatim: "Two").tag(2)
        } label: {
            Text(verbatim: "N")
        }
    }
}

/// A real ``Form``, whose whole layout comes from the ``FormStyle`` in force
/// above it.
///
/// Like ``CachePicker`` it is the shipped control rather than a stand-in for
/// one, and what separates the two built-in layouts is readable straight out of
/// the buffer without matching any text: ``GroupedFormStyle`` draws each section
/// as a bordered box, ``ColumnsFormStyle`` draws no border at all. So a stale
/// serve across that swap would leave a box drawn around a form that no longer
/// asks for one.
private struct CacheForm: View, Equatable {
    var body: some View {
        Form {
            Section("General") {
                LabeledContent("Name", value: "Alice")
            }
        }
    }
}

/// A caller's own menu style with no `Equatable` conformance, so nothing can
/// tell whether the value it injects has changed.
private struct UncomparableMenuStyle: MenuStyle {
    let token = 0

    @MainActor
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

// MARK: - Tests

/// One clause of the `RenderCache` contract, asked once per style family.
///
/// `EnvironmentModifier` compares the value it applied at a slot against the one
/// it applied there last pass, and a value it cannot compare may have changed
/// under a buffer it is about to serve with nothing able to notice — so every
/// memo below an uncomparable value declines to cache at all. Every
/// `.someStyle(_:)` modifier injects an `any SomeStyle` through exactly that
/// route, which makes each built-in style's `Equatable` conformance the
/// difference between a styled subtree that memoizes and one that does not.
///
/// Each family gets two arms:
///
/// - **the store** — every built-in of the family, asked in its own context,
///   because conforming only some would leave the rest exactly as they were;
/// - **the swap** — one built-in replaced by another at the same slot, which
///   must NOT serve the first one's buffer. This is the arm the conformance's
///   downcast answers, and the one that would turn a performance fix into a
///   stale serve if it ever compared equal across a type change.
///
/// Split out of `RenderCacheContractTests` when the file passed the project's
/// 600-line ceiling: the series had grown to eight style families (menu,
/// button, list, toggle, label, text field, picker, form) and is the half that
/// grows again whenever a style family is added — gauge, the ninth, arrived in
/// the commit after the split.
@MainActor
@Suite("RenderCache style contracts", .serialized)
struct RenderCacheStyleContractTests: RenderCacheHarness {

    @Test("A built-in menu style does not stop the subtree below it caching")
    func builtInMenuStyleKeepsCaching() {
        let shared = context()
        let cache = shared.environment.renderCache!

        // `.menuStyle(_:)` injects an `any MenuStyle`, and what decides whether
        // a memo below it may store is the DYNAMIC type's `Equatable`
        // conformance. The built-in styles carry one; without it every memo
        // under a styled menu declined, which is every row of an inline menu.
        frame(shared, CacheLeaf(text: "hi").equatable().menuStyle(.inline))
        #expect(!cache.isEmpty, "a memo under a built-in menu style must store")

        let before = cache.stats
        frame(shared, CacheLeaf(text: "hi").equatable().menuStyle(.inline))
        let delta = cache.stats.delta(since: before)
        #expect(delta.hits >= 1, "and must be served on the next frame: \(delta)")
    }

    @Test("A built-in button style does not stop the subtree below it caching")
    func builtInButtonStyleKeepsCaching() {
        let shared = context()
        let cache = shared.environment.renderCache!

        // The same clause as the menu case, on the key path a terminal app
        // reaches for far more often: `.buttonStyle(_:)` injects an
        // `any ButtonStyle`, and what decides whether a memo below it may store
        // is the DYNAMIC type's `Equatable` conformance. Without one on the
        // built-in styles, every memo under a styled button — or under a
        // container that styles the buttons it holds — declined.
        frame(shared, CacheLeaf(text: "hi").equatable().buttonStyle(.plain))
        #expect(!cache.isEmpty, "a memo under a built-in button style must store")

        let before = cache.stats
        frame(shared, CacheLeaf(text: "hi").equatable().buttonStyle(.plain))
        let delta = cache.stats.delta(since: before)
        #expect(delta.hits >= 1, "and must be served on the next frame: \(delta)")
    }

    @Test("Neither built-in list style stops the subtree below it caching")
    func builtInListStyleKeepsCaching() {
        // The same clause once more, on a container key path rather than a
        // control's: `.listStyle(_:)` injects an `any ListStyle`, and what
        // decides whether a memo below it may store is the DYNAMIC type's
        // `Equatable` conformance. Without one the refusal covered every row of
        // the styled list, and `_ListCore`'s own hug-width size memo with them.
        //
        // Both built-ins are asked, in their own contexts, because conforming
        // only one would leave the other's lists exactly as they were.
        func styleStoresAndServes<S: ListStyle>(_ style: S, _ spelling: String) {
            let shared = context()
            let cache = shared.environment.renderCache!

            frame(shared, CacheLeaf(text: "hi").equatable().listStyle(style))
            #expect(!cache.isEmpty, "a memo under \(spelling) must store")

            let before = cache.stats
            frame(shared, CacheLeaf(text: "hi").equatable().listStyle(style))
            let delta = cache.stats.delta(since: before)
            #expect(delta.hits >= 1, "and must be served on the next frame: \(delta)")
        }

        styleStoresAndServes(.plain, ".listStyle(.plain)")
        styleStoresAndServes(.insetGrouped, ".listStyle(.insetGrouped)")
    }

    @Test("No built-in toggle style stops the subtree below it caching")
    func builtInToggleStyleKeepsCaching() {
        // The same clause again, on the control key path an app reaches for
        // whenever it spells a toggle differently: `.toggleStyle(_:)` injects an
        // `any ToggleStyle`, and what decides whether a memo below it may store
        // is the DYNAMIC type's `Equatable` conformance. Without one, every memo
        // under a `.toggleStyle(...)` declined — the toggle's own label, and
        // whatever `Toggle/toggleContent(_:)` puts under it.
        //
        // All three built-ins are asked, in their own contexts, because
        // conforming only one would leave the others exactly as they were.
        func styleStoresAndServes<S: ToggleStyle>(_ style: S, _ spelling: String) {
            let shared = context()
            let cache = shared.environment.renderCache!

            frame(shared, CacheLeaf(text: "hi").equatable().toggleStyle(style))
            #expect(!cache.isEmpty, "a memo under \(spelling) must store")

            let before = cache.stats
            frame(shared, CacheLeaf(text: "hi").equatable().toggleStyle(style))
            let delta = cache.stats.delta(since: before)
            #expect(delta.hits >= 1, "and must be served on the next frame: \(delta)")
        }

        styleStoresAndServes(.automatic, ".toggleStyle(.automatic)")
        styleStoresAndServes(.checkbox, ".toggleStyle(.checkbox)")
        styleStoresAndServes(.switch, ".toggleStyle(.switch)")
    }

    /// The safety half, in the shape this key path makes it take.
    ///
    /// None of the three toggle styles holds anything, so there is no stored
    /// value to change under a served buffer the way ``_ColorSwatchButtonStyle``'s
    /// colour can. What varies here is the TYPE: `_ToggleCore` picks its branch
    /// with `toggleStyle is SwitchToggleStyle` and nothing else, so a switch and a
    /// checkbox at the same slot really do draw differently. The only thing
    /// standing between that and a stale serve is the downcast in
    /// `Equatable.isEqual(to:)` — without it a comparison across the swap could
    /// answer "equal" and hand the subtree the buffer drawn for the other style.
    @Test("Swapping one built-in toggle style for another clears the subtree below it")
    func toggleStyleTypeChangeClearsCaching() {
        let shared = context()
        let cache = shared.environment.renderCache!

        frame(shared, CacheLeaf(text: "hi").equatable().toggleStyle(.checkbox))
        #expect(!cache.isEmpty, "a memo under a built-in toggle style must store")

        let before = cache.stats
        frame(shared, CacheLeaf(text: "hi").equatable().toggleStyle(.switch))
        let delta = cache.stats.delta(since: before)
        #expect(
            delta.hits == 0,
            "a checkbox replaced by a switch must not serve the checkbox's buffer: \(delta)")
    }

    @Test("No built-in gauge style stops the subtree below it caching")
    func builtInGaugeStyleKeepsCaching() {
        // The same clause on the key path `.gaugeStyle(_:)` opened up: it used to
        // inject a closed `enum` the compiler made `Equatable` for free, and now
        // injects an `any GaugeStyle` whose dynamic type has to declare it. A
        // built-in that forgot to would turn the cache off for everything under
        // the modifier — the gauge's own four labels, and whatever else a
        // dashboard puts inside the container that carries the style.
        //
        // All seven are asked, in their own contexts, because conforming only
        // some would leave the rest exactly as they were.
        func styleStoresAndServes<S: GaugeStyle>(_ style: S, _ spelling: String) {
            let shared = context()
            let cache = shared.environment.renderCache!

            frame(shared, CacheLeaf(text: "hi").equatable().gaugeStyle(style))
            #expect(!cache.isEmpty, "a memo under \(spelling) must store")

            let before = cache.stats
            frame(shared, CacheLeaf(text: "hi").equatable().gaugeStyle(style))
            let delta = cache.stats.delta(since: before)
            #expect(delta.hits >= 1, "and must be served on the next frame: \(delta)")
        }

        styleStoresAndServes(.automatic, ".gaugeStyle(.automatic)")
        styleStoresAndServes(.linearCapacity, ".gaugeStyle(.linearCapacity)")
        styleStoresAndServes(.accessoryLinear, ".gaugeStyle(.accessoryLinear)")
        styleStoresAndServes(.accessoryLinearCapacity, ".gaugeStyle(.accessoryLinearCapacity)")
        styleStoresAndServes(.accessoryCircular, ".gaugeStyle(.accessoryCircular)")
        styleStoresAndServes(.accessoryCircularCapacity, ".gaugeStyle(.accessoryCircularCapacity)")
        styleStoresAndServes(.accessoryCircularTiny, ".gaugeStyle(.accessoryCircularTiny)")
    }

    /// The safety half. None of the seven gauge styles holds anything, so what
    /// varies is the TYPE — and it varies loudly: `builtInShape` reads the
    /// dynamic type and nothing else, so a bar at one slot and a ring at the
    /// same slot differ in height as well as in glyphs. The only thing standing
    /// between that and a stale serve is the downcast in
    /// `Equatable.isEqual(to:)`.
    @Test("Swapping one built-in gauge style for another clears the subtree below it")
    func gaugeStyleTypeChangeClearsCaching() {
        let shared = context()
        let cache = shared.environment.renderCache!

        frame(shared, CacheLeaf(text: "hi").equatable().gaugeStyle(.linearCapacity))
        #expect(!cache.isEmpty, "a memo under a built-in gauge style must store")

        let before = cache.stats
        frame(shared, CacheLeaf(text: "hi").equatable().gaugeStyle(.accessoryCircular))
        let delta = cache.stats.delta(since: before)
        #expect(
            delta.hits == 0,
            "a bar replaced by a ring must not serve the bar's buffer: \(delta)")
    }

    @Test("No built-in label style stops the subtree below it caching")
    func builtInLabelStyleKeepsCaching() {
        // The same clause once more, on the key path a whole screen reaches
        // for at once: `.labelStyle(_:)` injects an `any LabelStyle`, and what
        // decides whether a memo below it may store is the DYNAMIC type's
        // `Equatable` conformance. Without one, a toolbar that drops to
        // `.iconOnly` when the terminal narrows — the case the protocol's own
        // documentation offers — turned the cache off for everything under it.
        //
        // All four built-ins are asked, in their own contexts, because
        // conforming only one would leave the others exactly as they were.
        func styleStoresAndServes<S: LabelStyle>(_ style: S, _ spelling: String) {
            let shared = context()
            let cache = shared.environment.renderCache!

            frame(shared, CacheLeaf(text: "hi").equatable().labelStyle(style))
            #expect(!cache.isEmpty, "a memo under \(spelling) must store")

            let before = cache.stats
            frame(shared, CacheLeaf(text: "hi").equatable().labelStyle(style))
            let delta = cache.stats.delta(since: before)
            #expect(delta.hits >= 1, "and must be served on the next frame: \(delta)")
        }

        styleStoresAndServes(.automatic, ".labelStyle(.automatic)")
        styleStoresAndServes(.titleOnly, ".labelStyle(.titleOnly)")
        styleStoresAndServes(.iconOnly, ".labelStyle(.iconOnly)")
        styleStoresAndServes(.titleAndIcon, ".labelStyle(.titleAndIcon)")
    }

    /// The safety half, asked of the drawing instead of the statistics.
    ///
    /// Every other style in this series contributes to a buffer some `_*Core`
    /// assembles, so the nearest an in-process test can get to "the wrong style
    /// was served" is `hits == 0`. A label style contributes the composition
    /// itself, and the two halves here share no character: if the downcast in
    /// `Equatable.isEqual(to:)` ever answered "equal" across a type change, the
    /// frame below would keep the buffer reading `Inbox` while the tree now says
    /// `.iconOnly`. So this asks the buffer.
    ///
    /// Vacuous before the conformances — nothing stored, so nothing could be
    /// served stale — and an assertion only after them, which is why it belongs
    /// with them rather than on its own.
    @Test("Swapping one built-in label style for another redraws the label below it")
    func labelStyleTypeChangeRedrawsTheLabel() {
        let shared = context()
        let cache = shared.environment.renderCache!

        func drawn(_ buffer: FrameBuffer) -> String {
            buffer.lines.map(\.stripped).joined().trimmingCharacters(in: .whitespaces)
        }

        let titled = frame(shared, CacheLabel().equatable().labelStyle(.titleOnly))
        #expect(drawn(titled) == "Inbox", "the title-only style draws the title")
        #expect(!cache.isEmpty, "a memo under a built-in label style must store")

        // The premise, without which the swap below would pass for a label that
        // is never served from cache at all: the SAME style twice is a hit, so
        // there really is a stored buffer for the swap to have to invalidate.
        let before = cache.stats
        frame(shared, CacheLabel().equatable().labelStyle(.titleOnly))
        let repeated = cache.stats.delta(since: before)
        #expect(repeated.hits >= 1, "an unchanged label style must serve the memo: \(repeated)")

        let iconed = frame(shared, CacheLabel().equatable().labelStyle(.iconOnly))
        #expect(
            drawn(iconed) == "*",
            "a title-only label was served under .iconOnly: \(drawn(iconed))")
    }

    @Test("Neither built-in text field style stops the subtree below it caching")
    func builtInTextFieldStyleKeepsCaching() {
        // The same clause once more: `.textFieldStyle(_:)` injects an
        // `any TextFieldStyle`, and what decides whether a memo below it may
        // store is the DYNAMIC type's `Equatable` conformance. Without one the
        // refusal covered everything under the modifier — Example's Text Input
        // page puts two fields and their surrounding rows under a
        // `.textFieldStyle(.plain)` (TextInputPage.swift:130 and :139), and none
        // of it could cache.
        //
        // What this is NOT, whatever this comment and `684785f1`'s message said
        // until the count was taken: "the one key path in this series an app in
        // this repo already writes". Example writes EIGHT of the nine key paths
        // this clause has been fixed on, and only `.labelStyle(_:)` goes
        // unwritten. Two of them are in the same position as this one — no
        // framework-internal injection anywhere in `Sources/TUIkit`, so the
        // refusal fires only where the app itself writes the modifier — and both
        // were fixed BEFORE it: `.listStyle(_:)` (ListPage.swift:269 and :284,
        // `d76f8d15`) and `.toggleStyle(_:)` (TogglePage.swift:90-92 and
        // :127-128, `9feef329`). The picker test below says the same of its own
        // key path, at thirteen sites. What is true of this one is narrower and
        // is all the subject claims: `.plain` is the only text field style the
        // app sets.
        //
        // Both built-ins are asked, in their own contexts, because conforming
        // only one would leave the other's fields exactly as they were.
        func styleStoresAndServes<S: TextFieldStyle>(_ style: S, _ spelling: String) {
            let shared = context()
            let cache = shared.environment.renderCache!

            frame(shared, CacheLeaf(text: "hi").equatable().textFieldStyle(style))
            #expect(!cache.isEmpty, "a memo under \(spelling) must store")

            let before = cache.stats
            frame(shared, CacheLeaf(text: "hi").equatable().textFieldStyle(style))
            let delta = cache.stats.delta(since: before)
            #expect(delta.hits >= 1, "and must be served on the next frame: \(delta)")
        }

        styleStoresAndServes(.automatic, ".textFieldStyle(.automatic)")
        styleStoresAndServes(.plain, ".textFieldStyle(.plain)")
    }

    /// The safety half, in the shape this key path makes it take.
    ///
    /// Neither text field style holds anything, so there is no stored value to
    /// change under a served buffer the way ``_ColorSwatchButtonStyle``'s colour
    /// can. What varies here is the TYPE, and it varies in both directions at
    /// once: `drawsFieldSurface` decides whether `FieldChrome` paints a surface
    /// and caps, and whether it is two cells wide or none — so a swap changes
    /// what a field DRAWS and what it MEASURES. The only thing standing between
    /// that and a stale serve, of a buffer or of a size, is the downcast in
    /// `Equatable.isEqual(to:)`.
    ///
    /// Asked of the statistics rather than of a drawing, because a text field
    /// style contributes to a buffer `_TextFieldCore` assembles rather than
    /// composing the view the way a ``LabelStyle`` does: a memo below the
    /// modifier holds ordinary content, so `hits == 0` is as near as an
    /// in-process test gets to "the wrong style was served".
    @Test("Swapping one built-in text field style for another clears the subtree below it")
    func textFieldStyleTypeChangeClearsCaching() {
        let shared = context()
        let cache = shared.environment.renderCache!

        frame(shared, CacheLeaf(text: "hi").equatable().textFieldStyle(.automatic))
        #expect(!cache.isEmpty, "a memo under a built-in text field style must store")

        let before = cache.stats
        frame(shared, CacheLeaf(text: "hi").equatable().textFieldStyle(.plain))
        let delta = cache.stats.delta(since: before)
        #expect(
            delta.hits == 0,
            "a capped field replaced by a plain one must not serve the capped buffer: \(delta)")
    }

    @Test("No built-in picker style stops the subtree below it caching")
    func builtInPickerStyleKeepsCaching() {
        // The same clause once more, on the key path with the most styles in
        // it: `.pickerStyle(_:)` injects an `any PickerStyle`, and what decides
        // whether a memo below it may store is the DYNAMIC type's `Equatable`
        // conformance. Without one the refusal covered everything under the
        // modifier, which in this repo's own app is whole configuration
        // panels — Example writes `.pickerStyle(...)` at thirteen places, six
        // of them on the Theme page.
        //
        // All four built-ins are asked, in their own contexts, because
        // conforming only one would leave the others exactly as they were.
        //
        // The blast radius includes the picker itself: a `Picker` is memoizable,
        // so what the missing conformance blocked first was the control its own
        // style was applied to — see the swap test below, where the same picker
        // stores and is served.
        func styleStoresAndServes<S: PickerStyle>(_ style: S, _ spelling: String) {
            let shared = context()
            let cache = shared.environment.renderCache!

            frame(shared, CacheLeaf(text: "hi").equatable().pickerStyle(style))
            #expect(!cache.isEmpty, "a memo under \(spelling) must store")

            let before = cache.stats
            frame(shared, CacheLeaf(text: "hi").equatable().pickerStyle(style))
            let delta = cache.stats.delta(since: before)
            #expect(delta.hits >= 1, "and must be served on the next frame: \(delta)")
        }

        styleStoresAndServes(.automatic, ".pickerStyle(.automatic)")
        styleStoresAndServes(.menu, ".pickerStyle(.menu)")
        styleStoresAndServes(.inline, ".pickerStyle(.inline)")
        styleStoresAndServes(.radioGroup, ".pickerStyle(.radioGroup)")
    }

    /// The safety half, and the one key path in this series that can be asked of
    /// a REAL control's drawing rather than of a fixture's or of the statistics.
    ///
    /// None of the four styles holds anything, so there is no stored value to
    /// change under a served buffer the way ``_ColorSwatchButtonStyle``'s colour
    /// can. What varies is the TYPE, and ``PickerStyle/resolvesToMenu`` turns it
    /// into two presentations that share no line: a menu picker is one collapsed
    /// row, a radio group is a row per option. So a stale serve here would be
    /// the wrong HEIGHT as well as the wrong glyphs, and the only thing standing
    /// between that and the frame below is the downcast in
    /// `Equatable.isEqual(to:)`.
    ///
    /// The picker is asked directly because, unlike a field or a toggle, it can
    /// be: with the conformances in place a `Picker` memoizes and is served — it
    /// was its OWN style that stopped it — so the buffer this swaps out is a
    /// real picker's, not a stand-in's.
    ///
    /// Vacuous before the conformances — nothing stored, so nothing could be
    /// served stale — and an assertion only after them, which is why it belongs
    /// with them rather than on its own.
    @Test("Swapping one built-in picker style for another redraws the picker below it")
    func pickerStyleTypeChangeRedrawsThePicker() {
        let shared = context(width: 40, height: 8)
        let cache = shared.environment.renderCache!

        func drawn(_ buffer: FrameBuffer) -> String {
            buffer.lines
                .map { $0.stripped.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " / ")
        }

        let radio = frame(shared, CachePicker().equatable().pickerStyle(.radioGroup))
        #expect(drawn(radio) == "N ● One / ◯ Two", "the radio group draws a row per option")
        #expect(!cache.isEmpty, "a memo under a built-in picker style must store")

        // The premise, without which the swap below would pass for a picker that
        // is never served from cache at all: the SAME style twice is a hit, so
        // there really is a stored buffer for the swap to have to invalidate.
        let before = cache.stats
        frame(shared, CachePicker().equatable().pickerStyle(.radioGroup))
        let repeated = cache.stats.delta(since: before)
        #expect(repeated.hits >= 1, "an unchanged picker style must serve the memo: \(repeated)")

        let menu = frame(shared, CachePicker().equatable().pickerStyle(.menu))
        #expect(
            drawn(menu) == "N ▐ One ▾ ▌",
            "a radio group was served under .menu: \(drawn(menu))")
    }

    @Test("No built-in form style stops the subtree below it caching")
    func builtInFormStyleKeepsCaching() {
        // The same clause on the last of the eight style key paths.
        // `.formStyle(_:)` injects an `any FormStyle`, and what decides whether
        // a memo below it may store is the DYNAMIC type's `Equatable`
        // conformance. Without one the refusal covered everything under the
        // modifier — a form is a whole settings panel, so that is typically a
        // screenful.
        //
        // All three built-ins are asked, in their own contexts, because
        // conforming only one would leave the other two exactly as they were.
        func styleStoresAndServes<S: FormStyle>(_ style: S, _ spelling: String) {
            let shared = context()
            let cache = shared.environment.renderCache!

            frame(shared, CacheLeaf(text: "hi").equatable().formStyle(style))
            #expect(!cache.isEmpty, "a memo under \(spelling) must store")

            let before = cache.stats
            frame(shared, CacheLeaf(text: "hi").equatable().formStyle(style))
            let delta = cache.stats.delta(since: before)
            #expect(delta.hits >= 1, "and must be served on the next frame: \(delta)")
        }

        styleStoresAndServes(.automatic, ".formStyle(.automatic)")
        styleStoresAndServes(.columns, ".formStyle(.columns)")
        styleStoresAndServes(.grouped, ".formStyle(.grouped)")
    }

    /// The safety half, asked of a real ``Form``'s drawing rather than of a hit
    /// count.
    ///
    /// None of the three styles holds anything, so there is no stored value to
    /// change under a served buffer the way ``_ColorSwatchButtonStyle``'s colour
    /// can. What varies is the TYPE, and ``Form`` reads nothing off the style
    /// BUT its type — so the whole of what a swap can change is the layout that
    /// type selects, and between grouped and columns that is the section's
    /// border. A stale serve would draw a box around a form that asked for none,
    /// and the only thing standing between that and the frame below is the
    /// downcast in `Equatable.isEqual(to:)`.
    ///
    /// Vacuous before the conformances — nothing stored, so nothing could be
    /// served stale — and an assertion only after them, which is why it belongs
    /// with them rather than on its own.
    @Test("Swapping one built-in form style for another redraws the form below it")
    func formStyleTypeChangeRedrawsTheForm() {
        let shared = context(width: 30, height: 10)
        let cache = shared.environment.renderCache!

        func isBoxed(_ buffer: FrameBuffer) -> Bool {
            buffer.lines.contains { $0.stripped.contains("\u{2500}") || $0.stripped.contains("\u{2502}") }
        }

        let grouped = frame(shared, CacheForm().equatable().formStyle(.grouped))
        #expect(isBoxed(grouped), "the grouped style draws its section as a bordered box")
        #expect(!cache.isEmpty, "a memo under a built-in form style must store")

        // The premise, without which the swap below would pass for a form that
        // is never served from cache at all: the SAME style twice is a hit, so
        // there really is a stored buffer for the swap to have to invalidate.
        let before = cache.stats
        frame(shared, CacheForm().equatable().formStyle(.grouped))
        let repeated = cache.stats.delta(since: before)
        #expect(repeated.hits >= 1, "an unchanged form style must serve the memo: \(repeated)")

        let columns = frame(shared, CacheForm().equatable().formStyle(.columns))
        #expect(!isBoxed(columns), "a grouped form was served under .columns")
    }

    /// The half the menu styles cannot pin, and the reason this is a safety
    /// question before it is a performance one.
    ///
    /// Neither built-in menu style holds anything, so `==` there is vacuous —
    /// every instance really is every other. Two of the button styles DO hold
    /// something (`_ColorSwatchButtonStyle` a `Color` and a `Bool`,
    /// `_LinkButtonStyle` a ``LinkFocusIndicator``), and both are built fresh
    /// from live binding data each frame. For those the conformance is
    /// load-bearing: a comparison that answered "equal" across a colour change
    /// would hand the swatch below it the buffer painted in the old colour, and
    /// that would convert this commit from a performance fix into a stale
    /// serve. So the store is only half of it — the invalidation is the rest.
    @Test("A button style's stored value changing clears the subtree below it")
    func buttonStyleStorageChangeClearsCaching() {
        let shared = context()
        let cache = shared.environment.renderCache!

        frame(
            shared,
            CacheLeaf(text: "hi").equatable()
                .buttonStyle(_ColorSwatchButtonStyle(color: .red)))
        #expect(!cache.isEmpty, "a memo under a style that holds a value must still store")

        let before = cache.stats
        frame(
            shared,
            CacheLeaf(text: "hi").equatable()
                .buttonStyle(_ColorSwatchButtonStyle(color: .blue)))
        let delta = cache.stats.delta(since: before)
        #expect(
            delta.hits == 0,
            "a style whose stored colour changed must not serve the old buffer: \(delta)")
    }

    @Test("A menu style that cannot be compared still declines caching")
    func uncomparableMenuStyleDeclinesCaching() {
        let shared = context()
        let cache = shared.environment.renderCache!

        // The other half of the same rule. A caller's style is free not to be
        // `Equatable`, and one that is not can change its stored values under a
        // served subtree with nothing to notice — so it declines, exactly as
        // any other uncomparable value does.
        frame(shared, CacheLeaf(text: "hi").equatable().menuStyle(UncomparableMenuStyle()))
        #expect(cache.isEmpty, "nothing may be stored under an uncomparable menu style")
    }
}
