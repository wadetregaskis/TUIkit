//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Angle.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

import TUIkitCore

/// A geometric angle, in degrees or radians.
///
/// A terminal draws on a grid of whole cells and has no rotation to speak of,
/// so this is not here to turn anything: it is here because *colour* is
/// angular. A hue is a position on a wheel, and ``View/hueRotation(_:)`` moves
/// it — which is a real effect on a character grid, unlike the geometric
/// rotations SwiftUI uses this type for.
public struct Angle: Sendable, Equatable, Hashable, Comparable, Codable {
    /// The angle in radians.
    public var radians: Double

    /// The angle in degrees.
    public var degrees: Double {
        get { radians * 180 / .pi }
        set { radians = newValue * .pi / 180 }
    }

    /// A zero angle.
    public static let zero = Self(radians: 0)

    /// Creates a zero angle.
    public init() {
        self.radians = 0
    }

    /// Creates an angle from radians.
    public init(radians: Double) {
        self.radians = radians
    }

    /// Creates an angle from degrees.
    public init(degrees: Double) {
        self.radians = degrees * .pi / 180
    }

    /// An angle of `radians` radians.
    public static func radians(_ radians: Double) -> Self {
        Self(radians: radians)
    }

    /// An angle of `degrees` degrees.
    public static func degrees(_ degrees: Double) -> Self {
        Self(degrees: degrees)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.radians < rhs.radians
    }

    /// `Codable` over the RADIANS, the one stored property.
    ///
    /// SwiftUI's `Angle` is `Codable` too, so source that persists one
    /// compiles; the encoded shape is not an interchange format either way —
    /// each framework encodes what it stores — so this is the synthesized
    /// conformance under a name, spelled out only to say which of the two
    /// properties is the stored one.
    private enum CodingKeys: String, CodingKey {
        case radians
    }
}

extension Angle: Animatable {
    /// An angle is one continuous number, so this is a rename.
    public var animatableData: Double {
        get { radians }
        set { radians = newValue }
    }
}
