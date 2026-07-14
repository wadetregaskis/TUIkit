//  🖥️ TUIKit — Terminal UI Kit for Swift
//  AlertRenderTests.swift
//
//  Buffer-level rendering tests for Alert.
//  License: MIT

import Testing

@testable import TUIkit

@MainActor
@Suite("Alert rendering")
struct AlertRenderTests {

    // MARK: - Helpers

    /// Alert buttons emit hit-test regions, so the context needs a focus
    /// manager and the full TUIContext services for a faithful render.
    private func makeContext(width: Int = 80, height: Int = 16) -> RenderContext {
        makeRenderContext(width: width, height: height)
    }

    private func lines(_ buffer: FrameBuffer) -> [String] {
        buffer.lines.map { $0.stripped }
    }

    // Default appearance is rounded.
    private let tl = "╭", tr = "╮", bl = "╰", br = "╯", lt = "├", rt = "┤", v = "│"

    private func isAllBorder(_ row: String, corners: (String, String)) -> Bool {
        row.hasPrefix(corners.0) && row.hasSuffix(corners.1)
    }

    // MARK: - Basic alert (no actions)

    @Test("A simple alert renders the title in the top border and the message in the body")
    func simpleAlert() {
        let alert = Alert(title: "Warning", message: "Are you sure?")
        let result = lines(renderToBuffer(alert, context: makeContext()))

        #expect(result.count == 5, "top + blank + message + blank + bottom")
        #expect(result.first?.contains("Warning") == true, "Title sits in the top border")
        #expect(isAllBorder(result[0], corners: (tl, tr)), "Top border corners present")
        #expect(result.contains(where: { $0.contains("Are you sure?") }), "Message in body")
        #expect(isAllBorder(result.last!, corners: (bl, br)), "Bottom border corners present")
        // No footer divider when there are no actions.
        #expect(!result.contains(where: { $0.hasPrefix(lt) }), "No footer separator without actions")
    }

    @Test("Every line of a bordered alert has the same visible width")
    func uniformWidth() {
        let alert = Alert(title: "Notice", message: "Operation complete!")
        let result = lines(renderToBuffer(alert, context: makeContext()))
        let widths = Set(result.map { $0.strippedLength })
        #expect(widths.count == 1, "All alert rows must be the same visible width: \(result.map { $0.strippedLength })")
    }

    @Test("Body rows are bounded by side borders")
    func sideBordersPresent() {
        let alert = Alert(title: "Notice", message: "Hello")
        let result = lines(renderToBuffer(alert, context: makeContext()))
        for row in result.dropFirst().dropLast() {
            #expect(row.hasPrefix(v) && row.hasSuffix(v), "Body row '\(row)' must be wrapped by side borders")
        }
    }

    // MARK: - Alert with actions

    @Test("An alert with actions renders a footer separator and the buttons")
    func alertWithActions() {
        let alert = Alert(title: "Confirm", message: "Delete this item?") {
            Button("Cancel", role: .cancel) {}
            Button("Delete") {}
        }
        let result = lines(renderToBuffer(alert, context: makeContext()))

        #expect(result.first?.contains("Confirm") == true)
        #expect(result.contains(where: { $0.contains("Delete this item?") }))
        // Footer separator (T-junction divider) appears before the buttons.
        #expect(result.contains(where: { $0.hasPrefix(lt) && $0.hasSuffix(rt) }), "Footer separator present")
        // Both button labels rendered on one footer row.
        #expect(result.contains(where: { $0.contains("Cancel") && $0.contains("Delete") }), "Both buttons on the footer row")
        #expect(isAllBorder(result.last!, corners: (bl, br)))
    }

    @Test("A cancel-role button is ordered to the left of other buttons")
    func cancelButtonSortsLeft() {
        // Declared Delete-first, Cancel-second; cancel must still render left.
        let alert = Alert(title: "Q", message: "M") {
            Button("Delete") {}
            Button("Cancel", role: .cancel) {}
        }
        let result = lines(renderToBuffer(alert, context: makeContext()))
        let footer = result.first(where: { $0.contains("Cancel") && $0.contains("Delete") })
        #expect(footer != nil, "Footer row with both buttons exists")
        if let footer {
            let cancelPos = footer.range(of: "Cancel")!.lowerBound
            let deletePos = footer.range(of: "Delete")!.lowerBound
            #expect(cancelPos < deletePos, "Cancel must sort to the left of Delete")
        }
    }

    @Test("showFooterSeparator:false omits the divider but keeps the buttons")
    func noFooterSeparator() {
        let alert = Alert(title: "Confirm", message: "Body", showFooterSeparator: false) {
            Button("OK") {}
        }
        let result = lines(renderToBuffer(alert, context: makeContext()))

        #expect(!result.contains(where: { $0.hasPrefix(lt) }), "No divider when showFooterSeparator is false")
        #expect(result.contains(where: { $0.contains("OK") }), "Button still rendered")
        #expect(isAllBorder(result.last!, corners: (bl, br)))
    }

    // MARK: - Width / sizing

    @Test("An alert sizes to its content when it is narrower than the available width")
    func sizesToContent() {
        let alert = Alert(title: "Hi", message: "Short")
        let buffer = renderToBuffer(alert, context: makeContext(width: 80))
        #expect(buffer.width < 80, "Alert shrinks to fit its content rather than filling the screen")
        #expect(buffer.width >= "Short".count, "But is at least wide enough for the message")
    }

    @Test("An alert is capped at its maximum width even with long content")
    func cappedAtMaxWidth() {
        let longMessage = String(repeating: "x", count: 200)
        let alert = Alert(title: "Long", message: longMessage)
        let buffer = renderToBuffer(alert, context: makeContext(width: 200))
        #expect(buffer.width <= 60, "Alert width is capped at 60; got \(buffer.width)")
    }

    @Test("A message too wide for the alert wraps across multiple body lines")
    func messageWraps() {
        let message = "This message is long enough that it must wrap across several lines when the alert width is constrained."
        let alert = Alert(title: "Notice", message: message).frame(width: 30)
        let result = lines(renderToBuffer(alert, context: makeContext(width: 80)))

        // The message must NOT appear intact on any single line (it was wrapped).
        #expect(!result.contains(where: { $0.contains(message) }), "Long message must wrap, not overflow")
        // Several body rows carry message fragments.
        let messageRows = result.filter { $0.contains("message") || $0.contains("wrap") || $0.contains("lines") }
        #expect(messageRows.count >= 2, "Wrapped message should span multiple rows")
        // Borders remain continuous and uniform width.
        let widths = Set(result.map { $0.strippedLength })
        #expect(widths.count == 1, "Wrapped alert keeps uniform width: \(widths)")
    }

    @Test("A long title is truncated to fit the top border without breaking corners")
    func longTitleTruncates() {
        let alert = Alert(title: "A Really Quite Long Alert Title That Exceeds", message: "Hi")
            .frame(width: 20)
        let result = lines(renderToBuffer(alert, context: makeContext(width: 80)))

        #expect(isAllBorder(result[0], corners: (tl, tr)), "Top border still closes with its corner despite a long title")
        let widths = Set(result.map { $0.strippedLength })
        #expect(widths.count == 1, "All rows uniform width even with a truncated title")
        // The full title cannot have fit.
        #expect(!result[0].contains("That Exceeds"), "Overflowing title text is truncated away")
    }

    // MARK: - Preset styles

    @Test("Preset alerts render their default titles")
    func presetTitles() {
        let warning = lines(renderToBuffer(Alert.warning(message: "w"), context: makeContext()))
        #expect(warning.first?.contains("Warning") == true)

        let error = lines(renderToBuffer(Alert.error(message: "e"), context: makeContext()))
        #expect(error.first?.contains("Error") == true)

        let info = lines(renderToBuffer(Alert.info(message: "i"), context: makeContext()))
        #expect(info.first?.contains("Info") == true)

        let success = lines(renderToBuffer(Alert.success(message: "s"), context: makeContext()))
        #expect(success.first?.contains("Success") == true)
    }

    @Test("A preset alert with actions keeps both the preset title and the buttons")
    func presetWithActions() {
        // The action-taking preset returns `Alert<A>` where `A` is inferred from
        // the closure; the base specialization is arbitrary (here EmptyView).
        let alert = Alert<EmptyView>.error(title: "Failed", message: "Try again?") {
            Button("Retry") {}
            Button("Cancel", role: .cancel) {}
        }
        let result = lines(renderToBuffer(alert, context: makeContext()))
        #expect(result.first?.contains("Failed") == true)
        #expect(result.contains(where: { $0.contains("Retry") && $0.contains("Cancel") }))
    }
}
