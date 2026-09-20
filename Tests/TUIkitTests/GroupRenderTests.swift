//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GroupRenderTests.swift
//
//  Buffer-level render audit for Group. Group imposes no layout of its
//  own: it must be transparent, flattening its children into the
//  surrounding container.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Group rendering")
struct GroupRenderTests {

    private func ctx(width: Int = 30, height: Int = 8) -> RenderContext {
        makeBareRenderContext(width: width, height: height)
    }

    // MARK: - Transparency

    @Test("A bare Group stacks its children vertically like an implicit VStack")
    func bareGroupStacksChildren() {
        let buffer = renderToBuffer(
            Group {
                Text("First")
                Text("Second")
            },
            context: ctx()
        )
        #expect(buffer.lines.count == 2)
        #expect(buffer.lines[0].stripped == "First")
        #expect(buffer.lines[1].stripped == "Second")
    }

    @Test("A single-view Group renders exactly that view")
    func singleViewGroup() {
        let buffer = renderToBuffer(Group { Text("only") }, context: ctx())
        #expect(buffer.lines.count == 1)
        #expect(buffer.lines[0].stripped == "only")
    }

    // MARK: - Flattening into a VStack

    @Test("Group flattens into a VStack so spacing applies between grouped views")
    func flattensIntoVStack() {
        // If Group nested instead of flattening, the VStack spacing would
        // not appear between A and B.
        let buffer = renderToBuffer(
            VStack(spacing: 1) {
                Group {
                    Text("A")
                    Text("B")
                }
            },
            context: ctx()
        )
        #expect(buffer.lines.count == 3, "Expected A, blank, B")
        #expect(buffer.lines[0].stripped == "A")
        #expect(buffer.lines[1].stripped.trimmingCharacters(in: .whitespaces).isEmpty)
        #expect(buffer.lines[2].stripped == "B")
    }

    @Test("Group siblings interleave with non-grouped siblings in a VStack")
    func interleavesInVStack() {
        let buffer = renderToBuffer(
            VStack(alignment: .leading) {
                Group {
                    Text("one")
                    Text("two")
                }
                Text("three")
            },
            context: ctx()
        )
        #expect(buffer.lines.count == 3)
        // The VStack pads shorter lines to the widest line's width ("three").
        #expect(
            buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
                == ["one", "two", "three"]
        )
    }

    // MARK: - Flattening into an HStack

    @Test("Group flattens into an HStack so children lay out horizontally")
    func flattensIntoHStack() {
        let buffer = renderToBuffer(
            HStack(spacing: 1) {
                Group {
                    Text("A")
                    Text("B")
                }
            },
            context: ctx()
        )
        #expect(buffer.lines.count == 1)
        #expect(buffer.lines[0].stripped == "A B", "Grouped children spaced like direct HStack children")
    }

    // MARK: - Modifier propagation

    @Test("A modifier on a Group applies to all grouped children")
    func modifierAppliesToChildren() {
        // foregroundColor should not change the stripped text, but must
        // not collapse or drop children either.
        let buffer = renderToBuffer(
            VStack(alignment: .leading) {
                Group {
                    Text("x")
                    Text("y")
                }
                .foregroundStyle(.red)
            },
            context: ctx()
        )
        #expect(buffer.lines.count == 2)
        #expect(buffer.lines.map { $0.stripped } == ["x", "y"])
    }

    @Test("A modifier on a Group applies to each member, not to the group")
    func modifiedGroupAppliesToEachMember() {
        // SwiftUI's Group documentation: "The modifier applies to all members
        // of the group --- and not to the group itself." The oracle is
        // therefore the same views with the modifier written on each of them:
        // a Group carrying a modifier must render identically.
        //
        // `.padding` is the spelling that goes through `ModifiedView`; the
        // `.foregroundStyle` twin below is the one the audit reported, and it
        // goes through a wrapper of its own.
        let grouped = renderToBuffer(
            HStack(spacing: 1) {
                Group {
                    Text("A")
                    Text("B")
                }
                .padding(.horizontal, 1)
            },
            context: ctx()
        )
        let written = renderToBuffer(
            HStack(spacing: 1) {
                Text("A").padding(.horizontal, 1)
                Text("B").padding(.horizontal, 1)
            },
            context: ctx()
        )
        #expect(grouped.lines.map { $0.stripped } == written.lines.map { $0.stripped })
    }

    /// The half the ``ModifiedView`` conformance does NOT reach, pinned so it
    /// cannot be believed closed.
    ///
    /// `.foregroundStyle` does not build a `ModifiedView`: it builds
    /// `_StyleEnvironmentView`, one of the dozens of single-content wrapper
    /// types a `View` modifier can return (§3 of
    /// `Documentation/SwiftUI-compatibility.md` bounds the scan), and every one
    /// of them is as opaque to child resolution as `ModifiedView` was. Closing
    /// this for every spelling is the
    /// forwarding-protocol decision the audit's root cause 1 raised and the
    /// owner deferred, not this change — so these two fail with the modifier
    /// the audit's own examples used, and pass with `.padding` above.
    ///
    /// `withKnownIssue` fails if the issue does NOT occur, so this flips to a
    /// plain failure the day the wrappers forward, which is when it should be
    /// deleted.
    @Test("A Spacer inside a modified Group is still a spacer to the stack")
    func modifiedGroupKeepsSpacerMetadata() {
        // The member's spacer flag is read from the static `View` witness, and
        // no wrapper forwards that witness — so re-reading it off the wrapper
        // the distribution puts around each member would answer `false` and the
        // spacer would render as a zero-width buffer instead of eating slack.
        let buffer = renderToBuffer(
            HStack(spacing: 0) {
                Group {
                    Text("A")
                    Spacer()
                    Text("B")
                }
                .padding(.vertical, 0)
            },
            context: ctx(width: 10)
        )
        #expect(buffer.lines.count == 1)
        #expect(buffer.lines[0].stripped == "A        B", "the spacer pushed B to the far edge")
    }

    @Test("A cosmetic modifier on a Group does not rotate the layout 90°")
    func modifiedGroupKeepsTheRowAxis() {
        let plain = renderToBuffer(
            HStack(spacing: 1) {
                Group {
                    Text("A")
                    Text("B")
                }
            },
            context: ctx()
        )
        let modified = renderToBuffer(
            HStack(spacing: 1) {
                Group {
                    Text("A")
                    Text("B")
                }
                .foregroundStyle(.red)
            },
            context: ctx()
        )
        withKnownIssue("_StyleEnvironmentView is not a ChildViewProvider, so the members are one opaque child") {
            #expect(modified.lines.count == 1, "a modified Group must not stack its members vertically")
            #expect(modified.lines.map { $0.stripped } == plain.lines.map { $0.stripped })
        }
    }

    @Test("A modifier on a Group leaves the enclosing stack's spacing intact")
    func modifiedGroupKeepsStackSpacing() {
        let buffer = renderToBuffer(
            VStack(spacing: 1) {
                Group {
                    Text("A")
                    Text("B")
                }
                .foregroundStyle(.red)
            },
            context: ctx()
        )
        withKnownIssue("as above: the spacing is lost because the pair arrives as one child") {
            // Written as one comparison so a wrong height reports rather than traps.
            #expect(
                buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) } == ["A", "", "B"],
                "Expected A, blank, B — the members are the VStack's own children")
        }
    }

    // MARK: - Transparent Child Resolution (the metadata channel)
    //
    // Everything above travels the two-pass `childViews` path, which is what
    // the stacks use. `childInfos` is the OTHER channel — the single-pass one
    // `TupleView` splices through for row extraction — and it was unexecuted
    // for `Group` while `Section`'s twin was covered. It is also the channel
    // per-child metadata rides on, so a `Group` that returned one opaque info
    // for the whole group would compile, render plausibly, and quietly eat
    // every child's spacer flag and z-index.

    @Test("Group.childInfos splices its children rather than wrapping them in one")
    func childInfosSplicesChildren() {
        let infos = Group {
            Text("A")
            Text("B")
        }
        .childInfos(context: ctx())

        #expect(infos.count == 2, "one info per grouped child, not one for the Group")
        #expect(infos[0].buffer?.lines.first?.stripped == "A")
        #expect(infos[1].buffer?.lines.first?.stripped == "B")
    }

    @Test("A Spacer inside a Group keeps its spacer flag through childInfos")
    func childInfosPreservesSpacerMetadata() {
        let infos = Group {
            Spacer()
            Text("tail")
        }
        .childInfos(context: ctx())

        #expect(infos.count == 2)
        #expect(infos[0].isSpacer, "an opaque wrapper would render the spacer to a buffer instead")
        #expect(infos[0].buffer == nil)
        #expect(!infos[1].isSpacer)
    }

    @Test("A z-index inside a Group survives childInfos")
    func childInfosPreservesZIndex() {
        let infos = Group {
            Text("under")
            Text("over").zIndex(3)
        }
        .childInfos(context: ctx())

        #expect(infos.count == 2)
        #expect(infos[0].zIndex == 0)
        #expect(infos[1].zIndex == 3, "an opaque wrapper would report the group's own z-index, 0")
    }

    /// The path a real tree takes to `Group.childInfos`: `TupleView` splices
    /// any child that is a `ChildInfoProvider`, so a nested `Group` is asked
    /// for its own children rather than rendered whole.
    @Test("A Group nested in a Group is spliced by the enclosing TupleView")
    func nestedGroupIsSpliced() {
        let infos = Group {
            Group {
                Text("A")
                Text("B")
            }
            Text("C")
        }
        .childInfos(context: ctx())

        #expect(infos.count == 3, "the inner Group contributes two siblings, not one")
        #expect(infos.compactMap { $0.buffer?.lines.first?.stripped } == ["A", "B", "C"])
    }

    // MARK: - Equatable

    @Test("Group equality is its content's equality")
    func equality() {
        // Bound to `let`s rather than written inline: two literally identical
        // expressions trip SwiftLint's identical_operands, which exists for
        // exactly the case this test is deliberately making.
        let group = Group { Text("same") }
        let twin = Group { Text("same") }
        let other = Group { Text("different") }

        #expect(group == twin)
        #expect(group != other)
    }

    // MARK: - Exceeding the ViewBuilder limit

    @Test("Group renders all children when used to exceed the 10-view limit")
    func manyChildren() {
        let buffer = renderToBuffer(
            VStack(alignment: .leading) {
                Group {
                    Text("0"); Text("1"); Text("2"); Text("3"); Text("4")
                    Text("5"); Text("6"); Text("7"); Text("8"); Text("9")
                }
            },
            context: ctx(width: 10, height: 12)
        )
        #expect(buffer.lines.count == 10)
        #expect(buffer.lines.first?.stripped == "0")
        #expect(buffer.lines.last?.stripped == "9")
    }
}
