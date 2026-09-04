//  🖥️ TUIkit — Terminal UI Kit for Swift
//  STBLengthGuardTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import Testing

@testable import TUIkitImage

/// `stbi_load_from_memory` takes a C `int` length, and the conversion feeding
/// it used to be `Int32(data.count)` — the trapping one — so a payload over
/// 2 GiB aborted the process where the `NSImage` arm merely throws.
///
/// Tested through the length conversion rather than a real decode: a trap is
/// not catchable, so an `#expect(throws:)` around `loadImage(from:)` would take
/// the whole run down instead of failing, and the alternative (a child-process
/// exit test buffering 2 GiB) only ever runs on the non-Apple lanes.
@Suite("stb_image length guard")
struct STBLengthGuardTests {

    @Test("A byte count stb_image can express converts unchanged")
    func inRangeByteCountConverts() throws {
        #expect(try PlatformImageLoader.stbLength(forByteCount: 0) == 0)
        #expect(try PlatformImageLoader.stbLength(forByteCount: 1024) == 1024)
        #expect(try PlatformImageLoader.stbLength(forByteCount: Int(Int32.max)) == Int32.max)
    }

    @Test("A payload larger than stb_image's length parameter is rejected, not trapped")
    func oversizedByteCountThrows() {
        #expect(throws: ImageLoadError.self) {
            try PlatformImageLoader.stbLength(forByteCount: Int(Int32.max) + 1)
        }
    }
}
