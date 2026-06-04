//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Trees.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// Representative view trees for the Mode A profiling harness.
///
/// These mirror shapes already exercised by the test suite and the
/// `ordo-one` render benchmarks, chosen to stress different parts of the
/// render pipeline:
///
/// - ``alignmentRow()`` — three flexible bordered boxes sharing a row via
///   `.frame(maxWidth: .infinity)`. Heavy on the two-pass **measure** path,
///   in particular `FlexibleFrameView`'s render-to-measure fallback.
/// - ``nestedRow()`` — a Panel column beside that alignment row, so the
///   flexible-width sharing nests two levels deep (the demo's worst case).
/// - ``mixedForm()`` — a settings-style page mixing interactive controls;
///   broad coverage of the modifier chain + focus registration.
enum Trees {
    /// Three flexible bordered boxes sharing a row. Mirrors the
    /// "Content Alignment" demo and `AlignmentBoxSquishTests`.
    @MainActor
    static func alignmentRow() -> some View {
        HStack(spacing: 1) {
            VStack(alignment: .leading) {
                Text("Leading align")
                Text("short")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .border()

            VStack(alignment: .center) {
                Text("Center align")
                Text("short")
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .border()

            VStack(alignment: .trailing) {
                Text("Trailing align")
                Text("short")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .border()
        }
    }

    /// A Panel column beside the alignment row, nesting flexible-width
    /// sharing two levels deep. Mirrors `AlignmentBoxSquishTests`'
    /// full-nested shape (minus the `AnyView` wrapper, which would erase
    /// the concrete type the profile is meant to reflect).
    @MainActor
    static func nestedRow() -> some View {
        HStack(spacing: 2) {
            VStack(alignment: .leading) {
                Text("Panel (Header + Footer)").bold().underline()
                VStack(alignment: .leading) {
                    Text("Primary text (foreground)")
                    Text("Secondary text (foregroundSecondary)")
                    Text("Tertiary text (foregroundTertiary)")
                }
                .border()
            }
            VStack(alignment: .leading) {
                Text("Content Alignment").bold().underline()
                alignmentRow()
            }
        }
    }

    /// Bare flexible frames stacked directly (no border wrapper), so each
    /// `FlexibleFrameView` is the direct child a `VStack` measures — i.e. it
    /// is itself the view that hits `measureChild`'s render-to-measure
    /// fallback. Isolates `FlexibleFrameView`'s measure cost (the alignment
    /// row instead routes that fallback through the enclosing `.border()`).
    /// Mixes the three constraint shapes: fill (`maxWidth: .infinity`),
    /// content-dependent (`minWidth:`), and fixed (`width:`).
    @MainActor
    static func frames() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Fill leading").frame(maxWidth: .infinity, alignment: .leading)
            Text("Fill centre").frame(maxWidth: .infinity, alignment: .center)
            Text("Fill trailing").frame(maxWidth: .infinity, alignment: .trailing)
            Text("Min width").frame(minWidth: 10, alignment: .leading)
            Text("Fixed width").frame(width: 20, alignment: .center)
        }
    }

    /// A Panel (with a button footer) beside a Card, each wrapping multi-line
    /// content. Exercises the labeled-container measure path: `_PanelCore` /
    /// `_CardCore` wrap `renderContainer` → `ContainerView` → `_ContainerViewCore`.
    /// Mirrors the container demos and the Panel/Card showcase pages.
    @MainActor
    static func paneled() -> some View {
        HStack(spacing: 2) {
            Panel("Settings") {
                VStack(alignment: .leading) {
                    Text("Network")
                    Text("Display")
                    Text("Audio")
                }
            } footer: {
                ButtonRow {
                    Button("Save") {}
                    Button("Cancel") {}
                }
            }
            Card {
                VStack(alignment: .leading) {
                    Text("Card line one")
                    Text("Card line two")
                    Text("Card line three")
                }
            }
        }
    }

    /// A column of `.equatable()` bordered rows — the case the value-based
    /// measure memo targets. The outer `VStack` re-measures every row each
    /// frame (its first pass measures children at `.unspecified`); with the
    /// memo, an unchanged row's measurement is served from `RenderCache` after
    /// the first frame instead of re-measuring the bordered subtree. Mirrors a
    /// long list of memoized rows.
    @MainActor
    static func memoRows() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<24, id: \.self) { index in
                MemoRow(index: index).equatable()
            }
        }
    }

    /// A long `List` of `ForEach` rows. `_ListCore` renders EVERY row to a
    /// buffer each frame (then windows to the viewport), so the cost scales with
    /// the total row count, not what's visible. Because the rows are a pure
    /// function of an `Equatable` element, `ForEach` auto-memoizes them by value
    /// (see `extractListRows`): the first frame stores 200 row buffers, every
    /// later frame serves them from the cache. Pre-memo baseline at 80x24 was
    /// ~15.2s / 2000 iters; ~3.8s with the memo.
    @MainActor
    static func list() -> some View {
        let items = (0..<200).map {
            ListItem(id: $0, title: "Item \($0)", detail: "detail line for row number \($0)")
        }
        return List {
            ForEach(items) { item in
                HStack {
                    Text(item.title)
                    Spacer()
                    Text(item.detail)
                }
            }
        }
    }

    /// A settings-style page mixing interactive controls. Mirrors the
    /// `render/Mixed-form page` benchmark.
    @MainActor
    static func mixedForm() -> some View {
        VStack(alignment: .leading) {
            Text("Settings").bold().underline()
            HStack {
                Text("Username:")
                TextField("user", text: .constant("alice"))
            }
            HStack {
                Text("Notifications:")
                Toggle("On", isOn: .constant(true))
            }
            HStack {
                Text("Volume:")
                Slider(value: .constant(0.7), in: 0...1)
            }
            HStack {
                Text("Retries:")
                Stepper("Retries", value: .constant(3), in: 0...10)
            }
            HStack {
                Button("Cancel") { }
                Button("Save") { }
            }
        }
    }
}

/// A model row for the ``Trees/list()`` tree — `Identifiable` for `ForEach`
/// and `Equatable` so a row memo could key on it.
struct ListItem: Identifiable, Equatable {
    let id: Int
    let title: String
    let detail: String
}

/// An `Equatable` row for the ``Trees/memoRows()`` tree: a small bordered
/// two-line block whose measurement is non-trivial (it goes through the
/// container measure path). Wrapped in `.equatable()`, an unchanged row is
/// measured once and then served from the cache.
struct MemoRow: View, Equatable {
    let index: Int

    var body: some View {
        VStack(alignment: .leading) {
            Text("Row \(index): primary content line")
            Text("secondary detail")
        }
        .padding()
        .border()
    }
}
