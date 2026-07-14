//  🖥️ TUIKit — Terminal UI Kit for Swift
//  GradientRenderingTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Gradient strip rendering")
struct GradientRenderingTests {

    private func makeContext() -> RenderContext {
        makeRenderContext(width: 80, height: 5)
    }

    @Test("ForEach<Range, id: \\.self> inside HStack renders its glyphs")
    func foreachRangeWithIDSelfInsideHStack() {
        let context = makeContext()
        let view = HStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { index in
                let value = UInt8(index * 50)
                Text("▇").foregroundStyle(.rgb(value, 0, 255 - value))
            }
        }
        let buffer = renderToBuffer(view, context: context)
        let joined = buffer.lines.joined()
        let glyphCount = joined.components(separatedBy: "▇").count - 1
        #expect(glyphCount == 5, "expected 5 ▇ glyphs, got \(glyphCount); buffer was: \(joined)")
    }

    @Test("ForEach<Range> (no id) inside HStack renders its glyphs")
    func foreachRangeInsideHStack() {
        let context = makeContext()
        let view = HStack(spacing: 0) {
            ForEach(0..<5) { index in
                let value = UInt8(index * 50)
                Text("▇").foregroundStyle(.rgb(value, 0, 255 - value))
            }
        }
        let buffer = renderToBuffer(view, context: context)
        let joined = buffer.lines.joined()
        let glyphCount = joined.components(separatedBy: "▇").count - 1
        #expect(glyphCount == 5, "expected 5 ▇ glyphs, got \(glyphCount); buffer was: \(joined)")
    }

    @Test("Inlined Text views inside HStack render fine")
    func inlinedTextsInsideHStack() {
        let context = makeContext()
        let view = HStack(spacing: 0) {
            Text("▇").foregroundStyle(.rgb(255, 0, 0))
            Text("▇").foregroundStyle(.rgb(200, 0, 50))
            Text("▇").foregroundStyle(.rgb(150, 0, 100))
            Text("▇").foregroundStyle(.rgb(100, 0, 150))
            Text("▇").foregroundStyle(.rgb(50, 0, 200))
        }
        let buffer = renderToBuffer(view, context: context)
        let joined = buffer.lines.joined()
        let glyphCount = joined.components(separatedBy: "▇").count - 1
        #expect(glyphCount == 5, "expected 5 ▇ glyphs, got \(glyphCount); buffer was: \(joined)")
    }
}
