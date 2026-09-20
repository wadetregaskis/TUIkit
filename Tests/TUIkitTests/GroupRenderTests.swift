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

    /// The metadata half of the distribution rule: a member's spacer flag has
    /// to survive the wrapper the distribution puts around it.
    ///
    /// Measured in the real framework rather than assumed —
    /// `HStack { Group { Text("AA"); Spacer(); Text("BB") }.foregroundStyle(.red) }`
    /// lays the two texts out at the extreme edges, identical to the
    /// unmodified control, so the `Spacer` is still a spacer to the enclosing
    /// stack. The flag is read from the static `View` witness and no wrapper
    /// forwards that witness, so it is carried across in `ChildView` instead
    /// of re-read off the wrapper.
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
        #expect(modified.lines.count == 1, "a modified Group must not stack its members vertically")
        #expect(modified.lines.map { $0.stripped } == plain.lines.map { $0.stripped })
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
        // Written as one comparison so a wrong height reports rather than traps.
        #expect(
            buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) } == ["A", "", "B"],
            "Expected A, blank, B — the members are the VStack's own children")
    }

    // MARK: - The Rule Through Wrappers That Are Not `ViewModifier`s
    //
    // `.foregroundStyle` above goes through `_StyleEnvironmentView`. These are
    // the other three wrappers `SwiftUI-compatibility.md` section 3 named as
    // opaque, each one its own type with its own initialiser: `.opacity` builds
    // `_OpacityView`, `.frame` builds `FlexibleFrameView`, `.disabled` builds
    // `DisabledModifier`. The oracle is the same one SwiftUI's sentence gives —
    // the modifier written on each member instead — so each test compares the
    // two spellings rather than asserting a literal the fix could be tuned to.

    @Test("An opacity on a Group does not rotate the layout 90 degrees")
    func opacityOnGroupKeepsTheRowAxis() {
        // Measured in the real framework with `ImageRenderer`: distributing the
        // fade and compositing the pair as one layer agree even for two FULLY
        // overlapping members, both giving rgb(156,99,53) where the unfaded
        // control gives rgb(255,84,62).
        let plain = renderToBuffer(
            HStack(spacing: 1) { Group { Text("A"); Text("B") } }, context: ctx())
        let modified = renderToBuffer(
            HStack(spacing: 1) { Group { Text("A"); Text("B") }.opacity(0.5) }, context: ctx())
        #expect(modified.lines.count == 1, "a faded Group must not stack its members vertically")
        #expect(modified.lines.map { $0.stripped } == plain.lines.map { $0.stripped })
    }

    @Test("A frame on a Group gives each member its own frame")
    func frameOnGroupAppliesPerMember() {
        // The case that distinguishes the two readings: one shared 5-wide box
        // would hold both letters, while a box EACH lays them out 5 apart.
        let grouped = renderToBuffer(
            HStack(spacing: 0) {
                Group { Text("A"); Text("B") }.frame(width: 5)
            },
            context: ctx()
        )
        let written = renderToBuffer(
            HStack(spacing: 0) {
                Text("A").frame(width: 5)
                Text("B").frame(width: 5)
            },
            context: ctx()
        )
        #expect(grouped.lines.map { $0.stripped } == written.lines.map { $0.stripped })
        #expect(grouped.lines.count == 1, "the members stay the HStack's own children")
    }

    @Test("A disabled Group does not rotate the layout 90 degrees")
    func disabledGroupKeepsTheRowAxis() {
        // `.disabled` publishes `\.isEnabled`, so distributing it changes no
        // pixel — what it changes is whether the members are the stack's own
        // children, which is the whole defect.
        let plain = renderToBuffer(
            HStack(spacing: 1) { Group { Text("A"); Text("B") } }, context: ctx())
        let modified = renderToBuffer(
            HStack(spacing: 1) { Group { Text("A"); Text("B") }.disabled(true) }, context: ctx())
        #expect(modified.lines.count == 1)
        #expect(modified.lines.map { $0.stripped } == plain.lines.map { $0.stripped })
    }

    // MARK: - The Environment and Paint Wrappers
    //
    // Fourteen more wrappers conform, and they fall into two families whose
    // equivalence is provable rather than measured. An ENVIRONMENT publisher
    // reaches a subtree whether it was set one level up or two, so publishing
    // around each member is the same value in the same places. A PAINT or
    // GEOMETRY wrapper rewrites or shifts cells the content already drew, and
    // the members of a stack do not overlap, so per member and over the pair
    // give the same cells. What changes in both families is only whether the
    // members reach the enclosing container as its own children — which is the
    // defect. One test per family plus the user-facing `.environment(_:_:)`,
    // rather than fourteen copies of the same assertion.

    /// The oracle every test in this section uses: the row axis. A `Group` of
    /// two `Text`s in an `HStack` is one line; an opaque wrapper around it
    /// makes two, because the `TupleView` beneath has already stacked them.
    ///
    /// Two `#expect`s rather than one returned `Bool`: a `Bool` helper reports
    /// the failure as two whole `FrameBuffer` descriptions and names neither
    /// defect, where these say "2 lines, expected 1" and show the two rows.
    private func expectRowAxis(
        _ modified: FrameBuffer, matches plain: FrameBuffer,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            modified.lines.count == 1,
            "a modified Group must not stack its members vertically",
            sourceLocation: sourceLocation)
        #expect(
            modified.lines.map { $0.stripped } == plain.lines.map { $0.stripped },
            sourceLocation: sourceLocation)
    }

    @Test("An .environment(_:_:) on a Group does not rotate the layout 90 degrees")
    func environmentOnGroupKeepsTheRowAxis() {
        let plain = renderToBuffer(
            HStack(spacing: 1) { Group { Text("A"); Text("B") } }, context: ctx())
        let modified = renderToBuffer(
            HStack(spacing: 1) {
                Group { Text("A"); Text("B") }.environment(\.lineLimit, .lines(3))
            },
            context: ctx()
        )
        expectRowAxis(modified, matches: plain)
    }

    @Test("A tint on a Group does not rotate the layout 90 degrees")
    func tintOnGroupKeepsTheRowAxis() {
        let plain = renderToBuffer(
            HStack(spacing: 1) { Group { Text("A"); Text("B") } }, context: ctx())
        let modified = renderToBuffer(
            HStack(spacing: 1) { Group { Text("A"); Text("B") }.tint(.blue) }, context: ctx())
        expectRowAxis(modified, matches: plain)
    }

    @Test("A redaction on a Group does not rotate the layout 90 degrees")
    func redactionOnGroupKeepsTheRowAxis() {
        let plain = renderToBuffer(
            HStack(spacing: 1) { Group { Text("A"); Text("B") } }, context: ctx())
        let modified = renderToBuffer(
            HStack(spacing: 1) {
                Group { Text("A"); Text("B") }.redacted(reason: .placeholder)
            },
            context: ctx()
        )
        // The characters are redacted in both spellings; what is asserted is the
        // axis, so `plain` is redacted too and only the grouping differs.
        let plainRedacted = renderToBuffer(
            HStack(spacing: 1) {
                Text("A").redacted(reason: .placeholder)
                Text("B").redacted(reason: .placeholder)
            },
            context: ctx()
        )
        #expect(modified.lines.count == 1)
        #expect(modified.lines.map { $0.stripped } == plainRedacted.lines.map { $0.stripped })
        #expect(plain.lines.count == 1, "the control is a row to begin with")
    }

    @Test("An offset on a Group shifts each member, as writing it on each does")
    func offsetOnGroupAppliesPerMember() {
        let grouped = renderToBuffer(
            HStack(spacing: 1) { Group { Text("A"); Text("B") }.offset(x: 1, y: 0) },
            context: ctx()
        )
        let written = renderToBuffer(
            HStack(spacing: 1) {
                Text("A").offset(x: 1, y: 0)
                Text("B").offset(x: 1, y: 0)
            },
            context: ctx()
        )
        #expect(grouped.lines.map { $0.stripped } == written.lines.map { $0.stripped })
    }

    @Test("A hidden Group hides each member, as writing it on each does")
    func hiddenOnGroupAppliesPerMember() {
        let grouped = renderToBuffer(
            HStack(spacing: 1) { Group { Text("A"); Text("B") }.hidden() }, context: ctx())
        let written = renderToBuffer(
            HStack(spacing: 1) { Text("A").hidden(); Text("B").hidden() }, context: ctx())
        #expect(grouped.lines.map { $0.stripped } == written.lines.map { $0.stripped })
        #expect(grouped.lines.count == 1, "hiding does not change the geometry, including the axis")
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
