//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MeasureMemoErasedIdentityTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// The measure memo's key held the view's VALUE BYTES, and for an ``AnyView``
/// those bytes are a pointer to a heap box. A pointer names a value only while
/// that value is alive: free the box and allocate another, and the second is
/// handed the first's address by an allocator doing exactly its job. The key was
/// then identical for two different views, and the memo answered the second
/// question with the first's answer. The value hash opens an erased view now —
/// its content's type, then the content — and never hashes the box's address,
/// in an `AnyView` or in a view that stores one; these keep it that way.
@MainActor
@Suite("An erased view is keyed by an address it does not own")
struct MeasureMemoErasedIdentityTests {

    /// The render loop's shape: an isolated cache and the volatile-read tracker
    /// whose presence is what turns the memo on at all.
    private func memoisedContext() -> RenderContext {
        var context = makeRenderContext(width: 80, height: 24)
        let storage = StateStorage()
        context.environment.stateStorage = storage
        context.stateStorage = storage
        context.environment.installVolatileReadTracker(VolatileReadTracker())
        return context
    }

    private func naturalWidth(of view: some View, context: RenderContext) -> Int {
        measureChild(view, proposal: ProposedSize(width: nil, height: nil), context: context).width
    }

    /// Both labels are short enough to live inside their `String` rather than
    /// behind another pointer, so the only allocation either measurement makes
    /// is the box `AnyView` puts its content in — which is the whole point.
    /// Each is created inside the loop and released at the end of its
    /// iteration, so the second asks the allocator for a box the instant after
    /// the first gave one back.
    @Test("Two erased Texts measured at one identity keep their own widths")
    func recycledBoxDoesNotAlias() {
        let context = memoisedContext()
        var widths: [Int] = []
        for label in ["aaaa", "bbbbbbbbbbbb"] {
            widths.append(naturalWidth(of: AnyView(Text(label)), context: context))
        }

        #expect(widths == [4, 12])
    }

    /// The residual, and the reason the witness is not the whole answer: a
    /// VIEW that stores an `AnyView` holds that address in its own bytes, and
    /// nothing about the outer view says so.
    @Test("A view storing an erased label keeps its own width")
    func recycledBoxInsideAViewDoesNotAlias() {
        let context = memoisedContext()
        var widths: [Int] = []
        for label in ["aaaa", "bbbbbbbbbbbb"] {
            widths.append(naturalWidth(of: Toggle(isOn: .constant(false)) { Text(label) }, context: context))
        }

        #expect(widths[0] != widths[1])
    }

    /// The control: the same two measurements with both views alive at once, so
    /// no address can be recycled. If this one fails the test above is about
    /// something else entirely.
    @Test("With both alive at once they keep their own widths")
    func distinctBoxesDoNotAlias() {
        let context = memoisedContext()
        let first = AnyView(Text("aaaa"))
        let second = AnyView(Text("bbbbbbbbbbbb"))

        #expect(naturalWidth(of: first, context: context) == 4)
        #expect(naturalWidth(of: second, context: context) == 12)
    }
}
