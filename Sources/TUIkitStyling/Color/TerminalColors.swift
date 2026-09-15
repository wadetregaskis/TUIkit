//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalColors.swift
//
//  What the terminal has said about its own colours, for rendering to read.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Terminal Colors

/// What the host terminal reported about its own colours: its default
/// foreground (OSC 10), its default background (OSC 11), its sixteen ANSI slots
/// (OSC 4), and whether it prefers a dark theme.
///
/// Every field is optional, and `nil` means the terminal did not say. Nothing
/// is guessed here. A colour the terminal did not report is unknown, and
/// whatever reads this decides what unknown means for it.
///
/// ## Reading and setting
///
/// Published the way `TerminalWidthTraits` is: a process-wide value, a
/// task-local pin over it, and a `generation` counter that moves only when
/// the process value really changes. Use `withCurrent(_:operation:)` for a
/// scoped pin, because a plain global mutate-and-restore bleeds across Swift
/// Testing's parallel runner.
///
/// TUIkit's startup exchange assigns `current` once, before an app draws its
/// first frame, when the terminal, or `COLORFGBG`, says anything about its
/// colours. Nothing assigns it again later yet. A process that runs no app,
/// and one whose terminal says nothing, keep `unknown`.
package struct TerminalColors: Sendable, Hashable {

    /// A reported colour, eight bits per channel.
    package struct RGB: Sendable, Hashable {
        /// The red channel.
        package var red: UInt8
        /// The green channel.
        package var green: UInt8
        /// The blue channel.
        package var blue: UInt8

        package init(red: UInt8, green: UInt8, blue: UInt8) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    /// All sixteen ANSI slots, 0 to 15, as the terminal reported them.
    ///
    /// All or nothing: a partial table cannot say what the slots it lacks
    /// paint, so `TerminalColors.slots` is either a whole `Slots` or `nil`.
    ///
    /// Stored as a 16-tuple so the count is part of the type, with no array to
    /// check or allocate. It is NOT an `InlineArray<16, RGB>`, which would say
    /// the same thing more plainly: that type needs the macOS 26 runtime, and
    /// it has no `Equatable` conformance to build this one's on.
    package struct Slots: Sendable, Hashable {
        /// How many slots there are.
        package static let count = 16

        // The one tuple wider than six on purpose: sixteen slots ARE the
        // type, and the alternatives are an array whose count must be
        // checked, or channels packed into integers.
        // swiftlint:disable:next large_tuple
        private typealias Storage = (
            RGB, RGB, RGB, RGB, RGB, RGB, RGB, RGB,
            RGB, RGB, RGB, RGB, RGB, RGB, RGB, RGB
        )

        private var storage: Storage

        /// Sixteen slots, all `colour`.
        package init(repeating colour: RGB) {
            storage = (
                colour, colour, colour, colour, colour, colour, colour, colour,
                colour, colour, colour, colour, colour, colour, colour, colour
            )
        }

        /// The slots in order, or `nil` unless there are exactly sixteen.
        package init?(_ colours: some Collection<RGB>) {
            guard colours.count == Self.count, let first = colours.first else { return nil }
            self.init(repeating: first)
            for (index, colour) in colours.enumerated() {
                self[index] = colour
            }
        }

        /// Slot `index`, 0 to 15.
        ///
        /// Read and written through the tuple's bytes. That is sound because a
        /// homogeneous tuple is laid out contiguously, one element stride apart,
        /// and `RGB` is three `UInt8`s with no padding.
        package subscript(index: Int) -> RGB {
            get {
                precondition((0..<Self.count).contains(index), "slot \(index) is not 0 to 15")
                return withUnsafeBytes(of: storage) { bytes in
                    bytes.load(fromByteOffset: index * MemoryLayout<RGB>.stride, as: RGB.self)
                }
            }
            set {
                precondition((0..<Self.count).contains(index), "slot \(index) is not 0 to 15")
                withUnsafeMutableBytes(of: &storage) { bytes in
                    bytes.storeBytes(
                        of: newValue, toByteOffset: index * MemoryLayout<RGB>.stride, as: RGB.self)
                }
            }
        }

        // Written out because a tuple is neither Equatable nor Hashable, so
        // neither conformance can be synthesised. Both walk all sixteen slots.
        package static func == (lhs: Self, rhs: Self) -> Bool {
            (0..<count).allSatisfy { lhs[$0] == rhs[$0] }
        }

        package func hash(into hasher: inout Hasher) {
            for index in 0..<Self.count {
                hasher.combine(self[index])
            }
        }
    }

    /// The default foreground (OSC 10), or `nil` if the terminal did not say.
    package var foreground: RGB?

    /// The default background (OSC 11), or `nil` if the terminal did not say.
    package var background: RGB?

    /// The sixteen ANSI slots (OSC 4), or `nil` unless all sixteen were
    /// reported.
    package var slots: Slots?

    /// Whether the terminal prefers a dark theme, or `nil` if nothing said.
    ///
    /// A hint, not a colour: it can come from something other than OSC 11,
    /// so it is recorded separately from `background`.
    package var prefersDark: Bool?

    package init(
        foreground: RGB? = nil,
        background: RGB? = nil,
        slots: Slots? = nil,
        prefersDark: Bool? = nil
    ) {
        self.foreground = foreground
        self.background = background
        self.slots = slots
        self.prefersDark = prefersDark
    }

    /// A terminal that has said nothing about its colours.
    package static let unknown = Self()
}

// MARK: - The process-wide value

extension TerminalColors {

    /// The process-wide colours, before any task-local pin.
    ///
    /// `nonisolated(unsafe)` for the reason `TerminalWidthTraits` gives: it is
    /// assigned from the thread that renders, outside a frame, and read from
    /// the render path.
    nonisolated(unsafe) private static var processCurrent: Self = .unknown

    /// A task-scoped pin, bound by `withCurrent(_:operation:)`.
    ///
    /// Task-local rather than a plain global because Swift Testing runs suites
    /// in parallel, and a global mutate-and-restore would bleed one test's
    /// terminal into another's rendering.
    @TaskLocal private static var taskCurrent: Self?

    /// Bumped every time the process-wide colours change.
    ///
    /// Something computed from these colours and kept is wrong once they
    /// change. This counter is for such a cache to compare, dropping itself
    /// when it moves, as the width caches do with
    /// `TerminalWidthTraits.generation`. The render cache clears when it moves,
    /// and the pulse ramp, quantised ramp and chrome track memos key on it.
    ///
    /// Only the process value bumps it. A task-local pin is scoped to work that
    /// opts into it, and the render path is not that work.
    nonisolated(unsafe) package private(set) static var generation: Int = 0

    /// The colours in force. Assign to set them process-wide, or use
    /// `withCurrent(_:operation:)` for a scoped pin.
    ///
    /// Assigning the value already in force changes nothing, so it does not
    /// bump `generation`.
    package static var current: Self {
        get { taskCurrent ?? processCurrent }
        set {
            guard newValue != processCurrent else { return }
            processCurrent = newValue
            generation &+= 1
        }
    }

    /// Runs `operation` with `colours` in force on this task only.
    package static func withCurrent<R>(
        _ colours: Self, operation: () throws -> R
    ) rethrows -> R {
        try $taskCurrent.withValue(colours, operation: operation)
    }
}
