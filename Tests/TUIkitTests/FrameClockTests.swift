//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FrameClockTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// `render(frameNowNanos:)` once defaulted its absolute clock reading to 0,
/// so the frames that took the default anchored drag flights and the
/// auto-scroll timer at process-uptime zero.
@Suite("Frame clock")
struct FrameClockTests {

    @Test("The default frame stamp is the monotonic clock, not zero")
    func defaultIsNow() {
        let first = FrameClock.nowNanos
        #expect(first > 0)
        let second = FrameClock.nowNanos
        #expect(second >= first, "monotonic")
    }
}
