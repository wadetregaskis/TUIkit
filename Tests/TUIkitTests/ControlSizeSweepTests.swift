//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ControlSizeSweepTests.swift
//
//  Renders every public control across a sweep of pathological sizes (down
//  to 1x1, up to 200x60) and degenerate inputs (empty data, zero/negative/
//  overflowing values, inverted ranges, CJK and emoji text), asserting the
//  two universal invariants: no crash, and no output past the offered
//  extent. New controls should be added to the sweep.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

@MainActor
@Suite("Control size sweep")
struct ControlSizeSweepTests {
    private func render(_ view: some View, w: Int, h: Int) -> FrameBuffer {
        let context = makeRenderContext(width: w, height: h)
        return renderToBuffer(view, context: context)
    }

    @Test("Every control survives a size sweep and stays inside its bounds")
    func sizeSweep() {
        let sizes: [(Int, Int)] = [(1, 1), (2, 1), (1, 2), (3, 3), (5, 2), (10, 1), (2, 10), (80, 24), (200, 60)]
        var failures: [String] = []

        func check(_ name: String, _ make: () -> any View) {
            for (w, h) in sizes {
                let buffer = render(AnyView(make()), w: w, h: h)
                if buffer.width > w || buffer.height > h {
                    failures.append("\(name) @ \(w)x\(h): buffer \(buffer.width)x\(buffer.height) overflows")
                }
                for (i, line) in buffer.lines.enumerated() where line.stripped.strippedLength > w {
                    failures.append("\(name) @ \(w)x\(h): line \(i) is \(line.stripped.strippedLength) wide")
                    break
                }
            }
        }

        check("Text") { Text("Hello, world of terminals") }
        check("Text-CJK") { Text("你好世界你好世界") }
        check("Text-emoji") { Text("🎉🎊🎈🎁🎀") }
        check("Text-empty") { Text("") }
        check("Button") { Button("Press me now") {} }
        check("Toggle") { Toggle("Enable the thing", isOn: .constant(true)) }
        check("Checkbox") { Toggle("Check", isOn: .constant(false)).toggleStyle(.checkbox) }
        check("Slider") { Slider(value: .constant(0.5), in: 0...1) }
        check("Slider-degenerate") { Slider(value: .constant(0), in: 0...0) }
        check("Stepper") { Stepper("Count", value: .constant(5), in: 0...10) }
        check("ProgressView") { ProgressView(value: 0.5, total: 1) }
        check("ProgressView-over") { ProgressView(value: 5, total: 1) }
        check("ProgressView-negative") { ProgressView(value: -3, total: 1) }
        check("ProgressView-zero-total") { ProgressView(value: 0, total: 0) }
        check("ProgressView-indeterminate") { ProgressView() }
        check("Gauge") { Gauge(value: 0.7, in: 0...1) { Text("G") } }
        check("Gauge-inverted-range") { Gauge(value: 0.5, in: 1...1) { Text("G") } }
        check("Spinner") { Spinner("Working") }
        check("List-empty") { List("T", selection: .constant(String?.none)) { EmptyView() } }
        check("List") { List("Items", selection: .constant(String?.none)) { ForEach(0..<5) { Text("Row \($0)") } } }
        struct Row: Identifiable { let id: Int; let name: String }
        check("Table") {
            Table([Row(id: 1, name: "a"), Row(id: 2, name: "bb")], selection: .constant(Int?.none)) {
                TableColumn("Col", value: \Row.name)
            }
        }
        check("Table-empty") {
            Table([Row](), selection: .constant(Int?.none)) {
                TableColumn("Col", value: \Row.name)
            }
        }
        check("Picker") { Picker("P", selection: .constant(0)) { ForEach(0..<3) { Text("Opt \($0)").tag($0) } } }
        check("Menu") { Menu(title: "Menu", items: [MenuItem(label: "A"), MenuItem(label: "B")]) }
        check("TextField") { TextField("Placeholder", text: .constant("hello")) }
        check("SecureField") { SecureField("Pass", text: .constant("secret")) }
        check("TextEditor") { TextEditor(text: .constant("line 1\nline 2\nline 3")) }
        check("TextEditor-empty") { TextEditor(text: .constant("")) }
        check("DatePicker") { DatePicker("Date", selection: .constant(Date(timeIntervalSince1970: 1_700_000_000))) }
        check("Card") { Card(title: "T") { Text("body") } }
        check("Panel") { Panel("P") { Text("body") } }
        check("Divider") { Divider() }
        check("Gauge-circular") { Gauge(value: 0.5, in: 0...1) { Text("50") }.gaugeStyle(.accessoryCircular) }
        check("ScrollView") { ScrollView { VStack { ForEach(0..<20) { Text("Line \($0)") } } } }
        check("Form") { Form { Toggle("A", isOn: .constant(true)); TextField("B", text: .constant("x")) } }
        check("Link") { Link("Example", destination: URL(string: "https://example.com")!) }
        check("Badge") { Text("x").badge(5) }
        check("ContentUnavailableView") {
            ContentUnavailableView {
                Text("Empty")
            } description: {
                Text("d")
            } actions: {
                Button("Retry") {}
            }
        }

        #expect(failures.isEmpty, "size-sweep violations:\n\(failures.joined(separator: "\n"))")
    }
}
