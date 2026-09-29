//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EnvironmentValueHashTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIkitCore
@testable import TUIkitView

@Observable
private final class Model {
    var count = 0
}

private struct FlagKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    fileprivate var testFlag: Bool {
        get { self[FlagKey.self] }
        set { self[FlagKey.self] = newValue }
    }
}

private struct ReadsEnvironment: View {
    @Environment(\.testFlag) var flag
    @Environment(Model.self) var model
    let label: Int
    var body: some View { EmptyView() }
}

/// `@Environment` kept its lookup as a generic enum — a key path or an
/// observable type — and the per-pass memos' value hash cannot read a generic
/// enum (its inactive payload is not reliably written), so every view holding
/// one bypassed both memos. It is two one-pointer optionals now, which the
/// hash reads as words, at the size that keeps it inside an existential's
/// inline buffer.
@MainActor
@Suite("An @Environment property is read by the value hash as plain words")
struct EnvironmentValueHashTests {
    @Test("The wrapper plans dense, and still fits an existential's three words")
    func wrapperIsDense() {
        let plans = ValueHashPlans()
        #expect(plans.plan(for: Environment<Bool>.self).pointee.shape == .dense)
        #expect(plans.plan(for: Environment<Model>.self).pointee.shape == .dense)
        #expect(MemoryLayout<Environment<Bool>>.size == 3 * MemoryLayout<Int>.size)
        #expect(plans.plan(for: ReadsEnvironment.self).pointee.shape == .dense)
    }

    @Test("Both lookups still read what they read")
    func lookupsStillWork() {
        let model = Model()
        model.count = 7
        var environment = EnvironmentValues()
        environment.testFlag = false
        environment[observable: Model.self] = model
        let view = ReadsEnvironment(label: 1)
        let (flag, count) = StateRegistration.withHydration(environment: environment) {
            (view.flag, view.model.count)
        }
        #expect(flag == false)
        #expect(count == 7)
    }
}
