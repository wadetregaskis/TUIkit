//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Int+ClampingDouble.swift
//
//  Created by Wade Tregaskis
//  License: MIT

extension Int {
    /// `Int(value)` that cannot trap.
    ///
    /// This is NOT `Int(_: Double)`, which traps — in release builds too — on
    /// NaN, on either infinity, and on any magnitude past `Int`'s range; nor
    /// `Int(exactly:)`, which answers `nil` for anything fractional. It is the
    /// floating-point twin of the integer `Int(clamping:)`: a magnitude past
    /// either bound lands ON that bound, NaN — which has no order and so no
    /// nearer bound — lands on zero, and everything else truncates toward zero
    /// exactly as `Int(_:)` does.
    ///
    /// Round first when rounding is wanted: `Int(clamping: x.rounded())`. The
    /// hand-written shape this replaces, `Int(min(hi, max(lo, x)))`, is only
    /// safe once `x` is known finite — `max(lo, .nan)` is `lo` in Swift, but
    /// `Int(.infinity)` still traps — and every site that spelled it out had to
    /// remember the `isFinite` guard as well. Several did not; a zoom factor, a
    /// cell aspect and a tone-curve point each reached a trap this way.
    ///
    /// - Parameter value: Any `Double`, including the ones `Int(_:)` refuses.
    public init(clamping value: Double) {
        if value.isNaN {
            self = 0
        } else if value >= Double(Self.max) {
            // `Double(Int.max)` rounds UP to 2^63, one past the largest `Int`,
            // so `>=` is exactly the set `Int(_:)` rejects on this side.
            self = .max
        } else if value <= Double(Self.min) {
            self = .min
        } else {
            self = Int(value)
        }
    }
}
