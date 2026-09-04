//  🖥️ TUIkit — Terminal UI Kit for Swift
//  IntClampingDoubleTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUIkitStyling

@Suite("Int(clamping: Double)")
struct IntClampingDoubleTests {

    @Test(
        "Ordinary values truncate toward zero, exactly as Int(_:) does",
        arguments: [(3.7, 3), (-3.7, -3), (0.0, 0), (255.4999, 255), (-0.9, 0), (1e15, 1_000_000_000_000_000)])
    func ordinary(pair: (Double, Int)) {
        #expect(Int(clamping: pair.0) == pair.1)
        #expect(Int(clamping: pair.0) == Int(pair.0), "agrees with the trapping conversion where that one is defined")
    }

    @Test("The values Int(_:) traps on land on a bound, and NaN on zero")
    func extremes() {
        #expect(Int(clamping: .infinity) == .max)
        #expect(Int(clamping: -.infinity) == .min)
        #expect(Int(clamping: 1e300) == .max)
        #expect(Int(clamping: -1e300) == .min)
        #expect(Int(clamping: .nan) == 0)
        #expect(Int(clamping: -.nan) == 0)
    }

    @Test("The boundary is exact: 2^63 is past the largest Int, the Double below it is not")
    func boundary() {
        // `Double(Int.max)` rounds up to 2^63, which `Int(_:)` refuses.
        #expect(Int(clamping: Double(Int.max)) == .max)
        #expect(Int(clamping: Double(Int.min)) == .min)
        // 2^63 - 1024 is the largest Double below 2^63 and converts exactly.
        #expect(Int(clamping: 9_223_372_036_854_774_784) == 9_223_372_036_854_774_784)
        #expect(Int(clamping: -9_223_372_036_854_774_784) == -9_223_372_036_854_774_784)
    }
}
