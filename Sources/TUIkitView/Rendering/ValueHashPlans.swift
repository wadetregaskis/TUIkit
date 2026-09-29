//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ValueHashPlans.swift
//
//  The value-hash plans a render cache has built, found by type on every
//  measured view, and what runs them.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// Every ``ValueHashPlan`` one render cache has built, keyed by type.
///
/// Looked up once per measured view, so it is shaped for that: open addressing
/// on the metadata address, linear probing, a power-of-two table kept at most a
/// quarter full, and inserts only. A plan is allocated on its own and never
/// moves, so a pointer to one stays good while the table grows under a build.
/// Built on first sight of a type and kept for the life of the cache: a plan is
/// a fact about the type, the same in every pass and for every value.
///
/// Owned by ``RenderCache`` — a table per cache rather than one per process,
/// so nothing here is shared state. A cache's first frame builds the plans for
/// the types it meets, a few microseconds each.
///
/// The table's state is reached through a pointer the class holds as a
/// constant, so a lookup is loads from memory nothing else aliases — not
/// accesses to a class's stored variables, which Swift checks for exclusivity
/// at run time.
///
/// Nothing here is isolated to the main actor, though every caller is on it:
/// the plans are only ever run from inside a measure, synchronously. That is
/// not a nicety. A `@MainActor` function's closures are isolated too, and
/// Swift 6 checks the executor on entry to one handed to the standard
/// library's `withUnsafeBytes` or `_openExistential` (SE-0423) — and a hash
/// that runs steps passes several: measured with the plans wired in, the
/// check's leaves were more than half of `viewValueHash`'s inclusive time on
/// `fanout`. The one thing that needs the main actor, the stack guard's
/// floor, is read at the entry (``armStackCheck()``).
package final class ValueHashPlans {
    private struct Slot {
        /// The metadata address of the planned type; 0 for an empty slot.
        var key: UInt
        var plan: UnsafeMutablePointer<ValueHashPlan>?
    }

    private struct Table {
        var slots: UnsafeMutablePointer<Slot>
        /// Capacity − 1.
        var mask: Int
        /// 64 − log2(capacity): what a Fibonacci hash is shifted right by.
        var shift: UInt64
        var count: Int
    }

    /// What running a plan keeps between one entry and the steps below it.
    private struct Running {
        /// The stack address below which a step gives up rather than open
        /// another existential: ``StackGuard``'s floor for the thread the
        /// last entry ran on, set by ``armStackCheck()``. 0 until then —
        /// no check — which only a test calling the steps directly sees.
        var stackFloor: UInt = 0
    }

    private let table: UnsafeMutablePointer<Table>
    private let running: UnsafeMutablePointer<Running>
    private let builder: ValueHashPlanBuilder

    /// A table to start with: enough for the few hundred types a large app's
    /// frames measure before it first grows.
    private static let initialCapacity = 256

    /// An empty table, which opens an existential of a static type it has an
    /// `opener` for directly — see ``ValueHashOpener``.
    package convenience init(openers: [ValueHashOpener] = []) {
        self.init(builder: ValueHashPlanBuilder(openers: openers))
    }

    init(builder: ValueHashPlanBuilder) {
        self.builder = builder
        table = .allocate(capacity: 1)
        table.initialize(to: Self.emptyTable(capacity: Self.initialCapacity))
        running = .allocate(capacity: 1)
        running.initialize(to: Running())
    }

    deinit {
        let current = table.pointee
        for index in 0...current.mask {
            guard let plan = current.slots[index].plan else { continue }
            UnsafeMutableBufferPointer(mutating: plan.pointee.runs).deallocate()
            // A step can hold an opener's closure, so the steps are torn down,
            // not just freed: `copied(_:)` initialised them, retaining it.
            let steps = UnsafeMutableBufferPointer(mutating: plan.pointee.steps)
            _ = steps.deinitialize()
            steps.deallocate()
            plan.deinitialize(count: 1)
            plan.deallocate()
        }
        current.slots.deallocate()
        table.deinitialize(count: 1)
        table.deallocate()
        running.deinitialize(count: 1)
        running.deallocate()
    }

    /// How many types have a plan — what a test counts.
    package var count: Int { table.pointee.count }

    /// `type`'s plan, built the first time it is asked for.
    @inline(__always)
    package func plan(for type: Any.Type) -> UnsafePointer<ValueHashPlan> {
        let key = UInt(bitPattern: ObjectIdentifier(type))
        let current = table.pointee
        var index = Int(truncatingIfNeeded: (UInt64(key) &* 0x9E37_79B9_7F4A_7C15) &>> current.shift)
        while true {
            let slot = current.slots[index]
            if slot.key == key { return UnsafePointer(slot.plan.unsafelyUnwrapped) }
            if slot.key == 0 { return insertPlan(for: type, key: key) }
            index = (index &+ 1) & current.mask
        }
    }

    /// Builds `type`'s plan and files it. Out of line: once per type per cache.
    @inline(never)
    private func insertPlan(for type: Any.Type, key: UInt) -> UnsafePointer<ValueHashPlan> {
        if (table.pointee.count + 1) * 4 > table.pointee.mask + 1 { grow() }
        let plan = UnsafeMutablePointer<ValueHashPlan>.allocate(capacity: 1)
        plan.initialize(to: Self.plan(for: type, from: builder.items(for: type)))
        let current = table.pointee
        var index = Int(truncatingIfNeeded: (UInt64(key) &* 0x9E37_79B9_7F4A_7C15) &>> current.shift)
        while current.slots[index].key != 0 { index = (index &+ 1) & current.mask }
        current.slots[index] = Slot(key: key, plan: plan)
        table.pointee.count += 1
        return UnsafePointer(plan)
    }

    /// Doubles the table and refiles every plan in it.
    private func grow() {
        let old = table.pointee
        var grown = Self.emptyTable(capacity: (old.mask + 1) * 2)
        for index in 0...old.mask where old.slots[index].key != 0 {
            let slot = old.slots[index]
            var target = Int(truncatingIfNeeded: (UInt64(slot.key) &* 0x9E37_79B9_7F4A_7C15) &>> grown.shift)
            while grown.slots[target].key != 0 { target = (target &+ 1) & grown.mask }
            grown.slots[target] = slot
        }
        grown.count = old.count
        old.slots.deallocate()
        table.pointee = grown
    }

    private static func emptyTable(capacity: Int) -> Table {
        let slots = UnsafeMutablePointer<Slot>.allocate(capacity: capacity)
        slots.initialize(repeating: Slot(key: 0, plan: nil), count: capacity)
        return Table(
            slots: slots, mask: capacity - 1, shift: UInt64(64 - capacity.trailingZeroBitCount), count: 0)
    }

    /// A plan from the builder's parts: adjacent runs merged, the shape
    /// decided, both lists copied to storage of their own.
    private static func plan(
        for type: Any.Type, from built: Result<[ValueHashPlanBuilder.Item], ValueHashPlanBuilder.Bypass>
    ) -> ValueHashPlan {
        let size = ValueHashPlanBuilder.layout(of: type).size
        var runs: [ValueHashPlan.Run] = []
        var steps: [ValueHashPlan.Step] = []
        var shape = ValueHashPlan.Shape.bypass
        var bypassReason: String?
        switch built {
        case .failure(let bypass):
            bypassReason = bypass.reason
        case .success(let items):
            for item in items {
                switch item {
                case .bytes(let offset, let count, _) where count > 0:
                    if let last = runs.last, last.offset + last.count == offset {
                        runs[runs.count - 1] = .init(offset: last.offset, count: last.count + count)
                    } else {
                        runs.append(.init(offset: offset, count: count))
                    }
                case .bytes:
                    break
                case .step(let step):
                    steps.append(step)
                }
            }
            if !steps.isEmpty {
                shape = .steps
            } else if size == 0 || runs == [.init(offset: 0, count: size)] {
                shape = .dense
            } else {
                shape = .runs
            }
        }
        return ValueHashPlan(
            shape: shape, size: size, runs: copied(runs), steps: copied(steps), bypassReason: bypassReason)
    }

    private static func copied<Element>(_ elements: [Element]) -> UnsafeBufferPointer<Element> {
        let storage = UnsafeMutableBufferPointer<Element>.allocate(capacity: elements.count)
        _ = storage.initialize(from: elements)
        return UnsafeBufferPointer(storage)
    }
}

// MARK: - Running a plan

extension ValueHashPlans {
    /// The value hash of the value of type `V` at `value`, by its plan, or
    /// `nil` when its type bypasses.
    ///
    /// On the main actor for the stack guard alone, and with no closure of
    /// its own, so nothing here checks the executor (see the type).
    @MainActor
    package func valueHash<V>(at value: UnsafePointer<V>) -> Int? {
        let plan = plan(for: V.self)
        if plan.pointee.shape == .dense {
            return hashOfRawBytes(UnsafeRawBufferPointer(start: value, count: MemoryLayout<V>.size))
        }
        armStackCheck()
        return hashByPlan(UnsafeRawPointer(value), plan)
    }

    /// Readies the check ``mixOpened(_:into:plans:)`` makes before it opens
    /// an existential, for the thread this runs on: every entry that runs a
    /// plan with steps calls this first, on the main actor, where the stack
    /// guard's state lives.
    ///
    /// The steps below compare the stack pointer with the floor read here,
    /// off the main actor — sound because an entry and every step under it
    /// run synchronously, on one thread, the one this found the floor of.
    /// `UInt.max` when there is no headroom even here, so every opening
    /// gives up; 0 when the guard is off, so none does — its answers exactly.
    @MainActor @inline(__always)
    func armStackCheck() {
        running.pointee.stackFloor = StackGuard.uncountedFloor()
    }

    /// Whether a step may open another existential: the stack pointer is
    /// above the floor the entry armed. See ``armStackCheck()``.
    @inline(__always)
    var hasStackHeadroom: Bool {
        StackGuard.currentStackPointer() > running.pointee.stackFloor
    }

    /// The hash of a value whose plan is not dense: its runs, then its steps,
    /// seeded and finalised as the dense hash is. Out of line, off the dense
    /// path. The caller has armed the stack check.
    @inline(never)
    func hashByPlan(_ base: UnsafeRawPointer, _ plan: UnsafePointer<ValueHashPlan>) -> Int? {
        var hash = hashFoldSeed
        guard mix(at: base, plan: plan, into: &hash) else { return nil }
        return finalizeHashWord(hash)
    }

    /// Mixes the value of `type` at `base` into `hash`, by `type`'s plan;
    /// `false` when it bypasses.
    func mix(at base: UnsafeRawPointer, type: Any.Type, into hash: inout UInt64) -> Bool {
        mix(at: base, plan: plan(for: type), into: &hash)
    }

    /// For an enum's ``_ValueHashing`` conformance: mixes the case it
    /// switched to, then that case's payload by the payload's plan.
    ///
    /// `caseIndex` is the case's own number, distinct for every case of the
    /// type, so two cases never mix the same words whatever their payloads;
    /// pass `()` for a case without one.
    package func mixCase<Payload>(_ caseIndex: Int, _ payload: Payload, into hash: inout UInt64) -> Bool {
        hash = mixHashWord(hash, UInt64(bitPattern: Int64(caseIndex)))
        return mixValue(payload, into: &hash)
    }

    /// Mixes `value` into `hash` by its type's plan — for a step that has
    /// opened or switched its way to a payload of its own, in a local.
    package func mixValue<Value>(_ value: Value, into hash: inout UInt64) -> Bool {
        let plan = plan(for: Value.self)
        guard plan.pointee.size > 0 else { return true }
        return withUnsafeBytes(of: value) { bytes in
            mix(at: bytes.baseAddress.unsafelyUnwrapped, plan: plan, into: &hash)
        }
    }

    private func mix(at base: UnsafeRawPointer, plan: UnsafePointer<ValueHashPlan>, into hash: inout UInt64) -> Bool {
        switch plan.pointee.shape {
        case .dense:
            mixDefinedRun(base, from: 0, count: plan.pointee.size, into: &hash)
            return true
        case .bypass:
            return false
        case .runs, .steps:
            for run in plan.pointee.runs {
                mixDefinedRun(base, from: run.offset, count: run.count, into: &hash)
            }
            for step in plan.pointee.steps {
                let at = base + step.offset
                switch step.action {
                case .typed(let type):
                    guard type._mixValueHash(at: at, into: &hash, plans: self) else { return false }
                case .existential(let field):
                    guard field.mix(at: at, into: &hash, plans: self) else { return false }
                }
            }
            return true
        }
    }
}

/// Mixes the `count` bytes at `base + start` into `hash`, loading no byte
/// outside them.
///
/// Every byte is covered, so equal bytes mix equal words and different bytes
/// different ones for a given `count`: whole words, the last of them
/// overlapping the one before when the run is not a whole number of words;
/// under a word, two overlapping halves (or quarters, or the one byte).
@inline(__always)
func mixDefinedRun(_ base: UnsafeRawPointer, from start: Int, count: Int, into hash: inout UInt64) {
    let end = start + count
    if count >= 8 {
        var offset = start
        while offset + 8 <= end {
            hash = mixHashWord(hash, base.loadUnaligned(fromByteOffset: offset, as: UInt64.self))
            offset += 8
        }
        if offset < end {
            hash = mixHashWord(hash, base.loadUnaligned(fromByteOffset: end - 8, as: UInt64.self))
        }
    } else if count >= 4 {
        let low = base.loadUnaligned(fromByteOffset: start, as: UInt32.self)
        let high = base.loadUnaligned(fromByteOffset: end - 4, as: UInt32.self)
        hash = mixHashWord(hash, UInt64(low) | UInt64(high) &<< 32)
    } else if count >= 2 {
        let low = base.loadUnaligned(fromByteOffset: start, as: UInt16.self)
        let high = base.loadUnaligned(fromByteOffset: end - 2, as: UInt16.self)
        hash = mixHashWord(hash, UInt64(low) | UInt64(high) &<< 16)
    } else if count == 1 {
        hash = mixHashWord(hash, UInt64(base.load(fromByteOffset: start, as: UInt8.self)))
    }
}
