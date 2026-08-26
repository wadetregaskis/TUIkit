//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LabeledContentTests.swift
//
//  `LabeledContent` OUTSIDE a Form, where it lays itself out. (Inside one the
//  form owns the row — see `FormTests`.)
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("LabeledContent standalone")
struct LabeledContentTests {

    private func line(_ view: some View, width: Int = 40) -> String {
        renderToBuffer(view, context: makeRenderContext(width: width, height: 3))
            .lines.first?.stripped ?? ""
    }

    @Test("A fixed value sits at the trailing edge")
    func valueIsTrailing() {
        let out = line(LabeledContent("Version", value: "1.0.3"))
        #expect(out.hasPrefix("Version"), "label leads: \(out.debugDescription)")
        #expect(
            out.trimmingCharacters(in: .whitespaces).hasSuffix("1.0.3"),
            "value trails: \(out.debugDescription)")
    }

    @Test("A flexible control gets the whole remainder, not half of it")
    func flexibleContentTakesTheRest() {
        // The bug: the body put a `Spacer` between the label and the content,
        // and a spacer is width-flexible exactly like a `TextField` — so the
        // stack split the leftover evenly and a labelled field spent half the
        // line on the gap in front of it.
        let out = line(
            LabeledContent("Note") { TextField("", text: .constant("")) }, width: 40)
        let fieldStart = out.firstIndex(of: "▐").map { out.distance(from: out.startIndex, to: $0) }
        #expect(fieldStart != nil, "a field was drawn: \(out.debugDescription)")
        // "Note" (4) + one space of stack spacing: the field starts right after
        // the label, not halfway across the line.
        #expect(fieldStart == 5, "the field starts at \(fieldStart ?? -1): \(out.debugDescription)")
    }
}
