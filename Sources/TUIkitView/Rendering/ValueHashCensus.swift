//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ValueHashCensus.swift
//
//  What the value hash did, by the shape of each plan it ran — compiled in
//  only with `-DTUIKIT_VALUE_HASH_CENSUS`, so an ordinary build pays nothing.
//
//  Created by Wade Tregaskis
//  License: MIT

#if TUIKIT_VALUE_HASH_CENSUS
/// The value hash's lookups by the shape of the plan that answered them, and
/// the types behind anything but the dense shape.
///
/// For deciding where a plan is worth making cheaper: a type that bypasses
/// loses its memo hits, and one with steps pays for typed Swift on every
/// lookup, so the types that do either, weighted by how often they are
/// hashed, are the list of what to reorder, re-represent or opt in. Build
/// with `swift build -Xswiftc -DTUIKIT_VALUE_HASH_CENSUS`; `Stress --bench`
/// prints it.
package struct ValueHashCensus {
    /// Lookups answered by a dense plan: the word loop over the whole value.
    package var dense = 0
    /// Lookups answered by runs over the defined bytes.
    package var runs = 0
    /// Lookups whose plan has typed steps, and that were hashed.
    package var steps = 0
    /// Lookups that bypassed: by a plan that bypasses, or by a step that
    /// found a part it cannot hash (an optional's payload that bypasses).
    package var bypass = 0
    /// Each type hashed through steps, and how often.
    package var stepTypes: [String: Int] = [:]
    /// Each type that bypassed, with why, and how often.
    package var bypassTypes: [String: Int] = [:]
    /// Each existential's static type opened by a dynamic cast — no opener of
    /// its own, so its payload's type was found by boxing it in an `Any` —
    /// and how often. The list of what an opener would make cheap.
    package var castOpenedTypes: [String: Int] = [:]
    /// Why the step that gave up on the value being hashed gave up: the
    /// innermost part's plan's reason, which names that part's own type (an
    /// optional's payload, an existential's content), or the stack running
    /// low. Set where it gave up, read and cleared by
    /// ``note(_:plan:hashed:)``, so a lookup that bypasses through a step
    /// names what stopped it and not only the view being hashed.
    var stepBypass: String?

    /// Records why a step gave up, unless a part inside it already has.
    mutating func noteStepBypass(_ reason: @autoclosure () -> String) {
        if stepBypass == nil { stepBypass = reason() }
    }

    /// Counts one existential of static type `type` opened by a dynamic cast.
    mutating func noteCastOpen(_ type: Any.Type) {
        castOpenedTypes["\(type)", default: 0] += 1
    }

    /// Counts one lookup of `type` by `plan`, which answered `hashed`.
    mutating func note(_ type: Any.Type, plan: UnsafePointer<ValueHashPlan>, hashed: Bool) {
        defer { stepBypass = nil }
        guard hashed else {
            bypass += 1
            let why = plan.pointee.bypassReason ?? "a step found a part it cannot hash: \(stepBypass ?? "?")"
            bypassTypes["\(type) — \(why)", default: 0] += 1
            return
        }
        switch plan.pointee.shape {
        case .dense: dense += 1
        case .runs: runs += 1
        case .steps:
            steps += 1
            stepTypes["\(type)", default: 0] += 1
        case .bypass: bypass += 1
        }
    }

    /// The counts, and the `limit` most frequent types of each list, one per
    /// line.
    package func report(limit: Int = 12) -> [String] {
        var lines = ["value hash: \(dense) dense, \(runs) runs, \(steps) steps, \(bypass) bypass"]
        for (title, types) in [
            ("steps", stepTypes), ("bypass", bypassTypes), ("existentials opened by a cast", castOpenedTypes),
        ] where !types.isEmpty {
            lines.append("  \(title):")
            for (type, count) in types.sorted(by: { $0.value > $1.value }).prefix(limit) {
                lines.append("    \(count)  \(type)")
            }
        }
        return lines
    }
}
#endif
