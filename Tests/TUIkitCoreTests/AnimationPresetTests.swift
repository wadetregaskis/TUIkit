//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimationPresetTests.swift
//
//  The three spring presets are the constants the API-parity map leans on
//  (`.snappy` is why SwiftUI's `interactiveSpring` is not ported) and the
//  article sells as "the usual three points on that scale" — and nothing
//  asserted them: transposing 0.15 and 0.3, or dropping a default duration,
//  changed no test's outcome.
//
//  `description` was in the same position, and being unexecuted it had drifted
//  from its own doc comment: named eases printed as `timingCurve(0.42, …)` and
//  springs as `spring(omega:zeta:settles:)`, a spelling no factory accepts.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitCore

@Suite("Animation presets")
struct AnimationPresetTests {

    @Test("Each preset is its documented spring")
    func presetsAreTheirSprings() {
        #expect(Animation.smooth == .spring(duration: 0.5, bounce: 0))
        #expect(Animation.snappy == .spring(duration: 0.5, bounce: 0.15))
        #expect(Animation.bouncy == .spring(duration: 0.5, bounce: 0.3))
        // The bare `spring` is the no-bounce one at the same pace, so it and
        // `smooth` are the same animation — which is the intent, not a bug.
        #expect(Animation.spring == .spring(duration: 0.5, bounce: 0))
        #expect(Animation.spring == Animation.smooth)
    }

    @Test("extraBounce adds to the preset's own bounce, and the pace is settable")
    func extraBounceAdds() {
        // Exact, not approximate: the preset and the factory run the identical
        // arithmetic, and 0.15 + 0.1 and 0.3 + 0.1 are both exact in binary.
        #expect(Animation.smooth(extraBounce: 0.1) == .spring(duration: 0.5, bounce: 0.1))
        #expect(Animation.snappy(extraBounce: 0.1) == .spring(duration: 0.5, bounce: 0.25))
        #expect(Animation.bouncy(extraBounce: 0.1) == .spring(duration: 0.5, bounce: 0.4))
        #expect(Animation.snappy(duration: 0.2) == .spring(duration: 0.2, bounce: 0.15))
        #expect(Animation.bouncy(duration: 0.2) == .spring(duration: 0.2, bounce: 0.3))
        #expect(Animation.smooth(duration: 0.2) == .spring(duration: 0.2, bounce: 0))
    }

    @Test("The presets really are ordered by springiness")
    func presetsAreOrdered() {
        // The claim the article makes. A bouncier spring is less damped, so it
        // overshoots: its value passes 1 somewhere in the first pass.
        func overshoots(_ animation: Animation) -> Bool {
            (0...200).contains { animation.fraction(at: Double($0) / 200 * 2) > 1.0001 }
        }
        #expect(!overshoots(.smooth))
        #expect(overshoots(.snappy))
        #expect(overshoots(.bouncy))
    }
}

@Suite("Animation description")
struct AnimationDescriptionTests {

    @Test("The doc comment's own example is what the code produces")
    func documentedExample() {
        #expect(
            Animation.easeInOut(duration: 0.3).repeatCount(3, autoreverses: true).description
                == "easeInOut(duration: 0.3).repeatCount(3, autoreverses: true)")
    }

    @Test("Each named ease prints as the factory that makes it")
    func namedCurves() {
        #expect(Animation.linear(duration: 0.2).description == "linear(duration: 0.2)")
        #expect(Animation.easeIn(duration: 0.2).description == "easeIn(duration: 0.2)")
        #expect(Animation.easeOut(duration: 0.2).description == "easeOut(duration: 0.2)")
        #expect(Animation.easeInOut(duration: 0.2).description == "easeInOut(duration: 0.2)")
        #expect(Animation.default.description == "easeInOut(duration: 0.35)")
        // An arbitrary Bézier has no name, so it keeps the general spelling.
        #expect(
            Animation.timingCurve(0.1, 0.2, 0.3, 0.4, duration: 0.5).description
                == "timingCurve(0.1, 0.2, 0.3, 0.4, duration: 0.5)")
        // And one written out longhand that HAPPENS to be a named ease prints
        // as that ease: it is the same animation, so the name is not a guess.
        #expect(
            Animation.timingCurve(0.42, 0, 0.58, 1, duration: 0.2).description
                == "easeInOut(duration: 0.2)")
    }

    @Test("A spring prints the arguments that would rebuild it")
    func springs() {
        // Not `spring(omega:zeta:settles:)`, which is what it printed while
        // nothing ran it — no factory takes those.
        #expect(Animation.smooth.description == "spring(duration: 0.5, bounce: 0.0)")
        #expect(Animation.snappy.description == "spring(duration: 0.5, bounce: 0.15)")
        #expect(Animation.bouncy.description == "spring(duration: 0.5, bounce: 0.3)")
        #expect(
            Animation.spring(duration: 0.25, bounce: -0.5).description
                == "spring(duration: 0.25, bounce: -0.5)")
    }

    @Test("Delay, speed and repeat are appended in modifier order")
    func modifierSuffixes() {
        #expect(
            Animation.linear(duration: 1).delay(0.5).description
                == "linear(duration: 1.0).delay(0.5)")
        #expect(
            Animation.linear(duration: 1).speed(2).description
                == "linear(duration: 1.0).speed(2.0)")
        #expect(
            Animation.linear(duration: 1).repeatForever(autoreverses: false).description
                == "linear(duration: 1.0).repeatForever(autoreverses: false)")
        #expect(
            Animation.linear(duration: 1).delay(0.5).speed(2).repeatCount(3).description
                == "linear(duration: 1.0).delay(0.5).speed(2.0).repeatCount(3, autoreverses: true)")
        // A single non-reversing pass is the default, so it adds nothing.
        #expect(Animation.linear(duration: 1).description == "linear(duration: 1.0)")
    }
}
