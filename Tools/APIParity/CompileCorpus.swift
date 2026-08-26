//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CompileCorpus.swift
//
//  SwiftUI source, written the way SwiftUI's own documentation writes it, that
//  must COMPILE against TUIkit. It is never run — `swiftc -typecheck` is the
//  whole test (`Tools/APIParity/compile_corpus.sh`).
//
//  This is the half `api_parity.py` cannot see. That tool compares argument
//  labels, so it can tell you a name is absent; it cannot tell you whether the
//  call site a developer actually writes binds to anything. The two failure
//  directions it misses are opposite and both real:
//
//  * A symbol the tool reports as MISSING that in fact compiles, because
//    TUIkit's declaration adds optional parameters after SwiftUI's —
//    `alert(_:isPresented:actions:)` is spelled `…:borderStyle:borderColor:
//    titleColor:` here. `source_compatible` now models that, and this file is
//    what proves the model right rather than merely plausible.
//  * A symbol the tool reports as PRESENT that does not compile, because only
//    the labels match: a `@ViewBuilder` that is not one, a trailing closure in
//    a different position, a generic constraint the call cannot satisfy. The
//    `Alert.warning(…) { … }` defect was exactly this shape and the symbol
//    diff was blind to it.
//
//  Add a snippet whenever a signature's compilability is the interesting
//  question — not one per symbol; this is a corpus of the calls that could
//  plausibly break, not an inventory.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

// MARK: - Extra optional arguments must not break SwiftUI's spelling

/// Each of these is reported by `api_parity.py` as source-compatible rather
/// than missing, because TUIkit's declaration appends defaulted parameters of
/// its own. If a default is ever removed, this stops compiling — which is the
/// point: the tool would go on calling it compatible.
@MainActor
private struct AddedOptionalArguments: View {
    @State private var isPresented = false

    var body: some View {
        VStack {
            Text("body")
                // TUIkit adds borderStyle:/borderColor:/titleColor:.
                .alert("alert.title", isPresented: $isPresented) {
                    Button("button.ok") {}
                } message: {
                    Text("alert.message")
                }
                .alert("alert.title", isPresented: $isPresented) {
                    Button("button.ok") {}
                }
                // TUIkit adds style: BETWEEN the colour and the width, which
                // is the case a prefix rule would miss: Swift lets a call skip
                // a defaulted parameter from anywhere, not just the tail.
                .border(.red, width: 2)
                // TUIkit spells this fixedSize(horizontal:vertical:), both
                // defaulted to true — so this means what SwiftUI means.
                .fixedSize()
                // Two fully-defaulted EdgeInsets initialisers exist, so this
                // also pins that the call is not AMBIGUOUS — the symbol diff
                // can see that some overload accepts it, never that exactly
                // one does. (Swift's "fewer defaulted arguments" tie-break
                // picks `init(horizontal:vertical:)`; both are all-zero.)
                .padding(EdgeInsets())
            // Another mid-list default: showsIndicators: sits between the axes
            // and the content closure.
            ScrollView(.vertical) {
                Text("scrolled")
            }
        }
    }
}

// MARK: - Shapes a label diff cannot check

/// Trailing-closure position, `@ViewBuilder`-ness and generic inference: the
/// things that make a call bind or not bind once the labels already match.
@MainActor
private struct ClosureAndGenericShapes: View {
    @State private var quantity = 1
    @State private var isOn = false
    @State private var choice = 0

    var body: some View {
        VStack {
            // The receiver's Actions must be inferable from the closure alone.
            Button("button.save", systemImage: "square.and.arrow.down") {}
            Toggle("toggle.wifi", systemImage: "wifi", isOn: $isOn)
            Picker("picker.theme", systemImage: "paintpalette", selection: $choice) {
                Text("picker.light").tag(0)
                Text("picker.dark").tag(1)
            }
            // A value bound through a format style, not a String.
            TextField("field.quantity", value: $quantity, format: .number)
            LabeledContent("row.quantity", value: quantity, format: .number)
        }
        .frame(maxWidth: .infinity, alignment: .leadingFirstTextBaseline)
    }
}

// MARK: - Nested type names SwiftUI source spells out

/// SwiftUI nests these under `Text`, and its own documentation writes them that
/// way. Both are top-level types here, so the nested spellings only compile
/// because of the typealiases on ``Text`` — which is precisely the kind of
/// difference `api_parity.py` cannot see, both names being present somewhere.
@MainActor
private struct NestedTypeSpellings: View {
    private let mode: Text.TruncationMode = .middle
    private let casing: Text.Case = .uppercase
    private let weight: Font.Weight = .bold

    var body: some View {
        Text("text.body")
            .truncationMode(mode)
            .textCase(casing)
            .fontWeight(weight)
    }
}
