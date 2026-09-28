//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ObservationCensus.swift
//
//  How many observation registrations are alive, and who armed them.
//
//  A `withObservationTracking` scope that read something arms one
//  registration, and the registration lives until a property it read is
//  written — then its `onChange` runs, on the writer's thread, and it is
//  gone — or until every object it read from has been deinitialized, which
//  frees it without running anything — or until the observation lease it
//  was armed under retires, which cancels it (`ObservationLeases`). Without
//  that last, a body evaluated on every frame that reads a property nobody
//  writes adds a registration every frame for as long as the model lives,
//  each holding its closure and what it captured, and the first write,
//  whenever it comes, runs all of them. The census is how that is counted:
//  what each change to what TUIkit observes, or to when it stops observing,
//  adds or frees.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// Counts the observation registrations TUIkit arms, the ones that fire, the
/// ones cancelled and the ones freed without firing, by the kind of reader that
/// armed them; what is left is how many are alive.
///
/// Off unless a harness or a test installs one on a cache
/// (`RenderCache.observationCensus`). Counted exactly:
/// - A scope arms a registration only when it read something, and that is
///   exactly when `withObservationTracking` evaluates its `onChange`
///   argument — an autoclosure — which is where `arm(_:)` is called. So a
///   body that reads nothing observable costs no count and no lookup of this
///   object.
/// - A registration fires when a property it read is written: its closure
///   runs, and calls ``Registration/fire()``.
/// - A registration is CANCELLED when its lease retires: its sentinel is
///   written, its closure runs, finds the sentinel retired and calls
///   ``Registration/cancel()`` instead (see `ObservationLease`).
/// - A registration is freed WITHOUT firing when every object it read from is
///   deinitialized: the objects' registrars drop it, and nothing runs. So the
///   closure holds its ``Registration``, whose deinit counts it as dropped
///   unless it fired or was cancelled. Without that, a reader of a model that
///   has gone would be counted alive for good.
///
/// Each registration is counted once, whichever of those comes first: a
/// retirement racing a write on another thread can run its closure twice.
///
/// Package, not public: a harness in this package (`Stress --census`) and the
/// tests are what read it.
///
/// Thread-safe: a registration fires on the thread of the write that fires
/// it, and is freed on whichever thread lets the last object it read go;
/// neither need be the main actor.
package final class ObservationCensus: Sendable {
    /// Who armed a registration.
    package enum Kind: Int, CaseIterable, Sendable, CustomStringConvertible {
        /// A view's `body`, evaluated to draw it.
        case bodyRender
        /// A view's `body`, evaluated while measuring.
        case bodyMeasure
        /// A style's `makeBody`, evaluated where a control draws it.
        case styleRender
        /// A style's `makeBody`, evaluated where a control measures it.
        case styleMeasure
        /// A control's `Binding`, read to draw it.
        case bindingRender
        /// A control's `Binding`, read while measuring.
        case bindingMeasure

        package var description: String {
            switch self {
            case .bodyRender: "body-render"
            case .bodyMeasure: "body-measure"
            case .styleRender: "style-render"
            case .styleMeasure: "style-measure"
            case .bindingRender: "binding-render"
            case .bindingMeasure: "binding-measure"
            }
        }
    }

    /// Registrations armed, fired and dropped so far, by kind.
    package struct Counts: Equatable, Sendable {
        /// Armed, indexed by the kind's raw value.
        package private(set) var armed = [Int](repeating: 0, count: Kind.allCases.count)
        /// Fired, indexed by the kind's raw value.
        package private(set) var fired = [Int](repeating: 0, count: Kind.allCases.count)
        /// Freed without firing, because every object the registration read
        /// from was deinitialized; indexed by the kind's raw value.
        package private(set) var dropped = [Int](repeating: 0, count: Kind.allCases.count)
        /// Cancelled by a retiring lease; indexed by the kind's raw value.
        package private(set) var cancelled = [Int](repeating: 0, count: Kind.allCases.count)
        /// Armed without a sentinel although leases were on — the first scope
        /// of a reader type not yet known to read, which is how it becomes
        /// known — so no lease can cancel it; indexed by the kind's raw value.
        /// A subset of `armed`, not a fate: it still fires, is dropped, or is
        /// alive.
        package private(set) var unleased = [Int](repeating: 0, count: Kind.allCases.count)

        /// How many `kind` has armed.
        package func armed(_ kind: Kind) -> Int { armed[kind.rawValue] }
        /// How many of `kind`'s have fired.
        package func fired(_ kind: Kind) -> Int { fired[kind.rawValue] }
        /// How many of `kind`'s were freed without firing.
        package func dropped(_ kind: Kind) -> Int { dropped[kind.rawValue] }
        /// How many of `kind`'s a retiring lease cancelled.
        package func cancelled(_ kind: Kind) -> Int { cancelled[kind.rawValue] }
        /// How many of `kind`'s were armed without a sentinel although leases
        /// were on.
        package func unleased(_ kind: Kind) -> Int { unleased[kind.rawValue] }
        /// How many of `kind`'s are alive: armed, and neither fired, cancelled
        /// nor dropped.
        package func live(_ kind: Kind) -> Int {
            armed[kind.rawValue] - fired[kind.rawValue] - cancelled[kind.rawValue] - dropped[kind.rawValue]
        }
        /// How many are alive, of every kind.
        package var live: Int { Kind.allCases.reduce(0) { $0 + live($1) } }

        fileprivate mutating func arm(_ kind: Kind, unleased isUnleased: Bool) {
            armed[kind.rawValue] += 1
            if isUnleased { unleased[kind.rawValue] += 1 }
        }
        fileprivate mutating func fire(_ kind: Kind) { fired[kind.rawValue] += 1 }
        fileprivate mutating func cancel(_ kind: Kind) { cancelled[kind.rawValue] += 1 }
        fileprivate mutating func drop(_ kind: Kind) { dropped[kind.rawValue] += 1 }
    }

    /// One armed registration, held by its `onChange` closure — and so freed
    /// exactly when the registration is: counted as fired when the closure
    /// runs for a write, as cancelled when it runs for its lease's retirement,
    /// and as dropped when it is freed without having run.
    ///
    /// `@unchecked Sendable`: its one mutable field is read and written only
    /// under the census's lock.
    package final class Registration: @unchecked Sendable {
        private let census: ObservationCensus
        private let kind: Kind
        /// Whether it has been counted as fired or cancelled. Under the
        /// census's lock.
        private var hasFired = false

        fileprivate init(census: ObservationCensus, kind: Kind) {
            self.census = census
            self.kind = kind
        }

        /// Counts it as fired, once: two writes on two threads can both run
        /// the closure before either cancels it. Call first thing in the
        /// registration's `onChange`.
        package func fire() {
            census.counts.withLock { counts in
                guard !hasFired else { return }
                hasFired = true
                counts.fire(kind)
            }
        }

        /// Counts it as cancelled, once — unless a write fired it first. Call
        /// first thing in the registration's `onChange` when its sentinel is
        /// retired.
        package func cancel() {
            census.counts.withLock { counts in
                guard !hasFired else { return }
                hasFired = true
                counts.cancel(kind)
            }
        }

        deinit {
            census.counts.withLock { counts in
                if !hasFired { counts.drop(kind) }
            }
        }
    }

    private let counts = Lock(initialState: Counts())

    /// Creates an empty census.
    package init() {}

    /// What has been counted so far.
    package var snapshot: Counts { counts.withLock { $0 } }

    /// Counts a registration `kind` armed, and returns what its `onChange`
    /// closure must hold. Call where the scope's `onChange` is evaluated,
    /// which is only when the scope read something.
    ///
    /// - Parameter unleased: Whether it was armed without a sentinel although
    ///   leases were on, so that no lease can cancel it.
    package func arm(_ kind: Kind, unleased: Bool = false) -> Registration {
        counts.withLock { $0.arm(kind, unleased: unleased) }
        return Registration(census: self, kind: kind)
    }
}
