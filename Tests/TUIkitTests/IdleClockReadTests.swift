//  🖥️ TUIKit — Terminal UI Kit for Swift
//  IdleClockReadTests.swift
//
//  The render loop is demand-driven: an animation clock keeps ticking only
//  while a frame tells it that something consumed the phase. `pulsePhase` is
//  a VOLATILE read — asking for it IS that signal.
//
//  So a control that reads the phase it isn't going to use keeps the clock
//  alive single-handedly, and the whole page re-renders ten times a second,
//  forever, drawing an identical frame. One ungated read on one control is
//  enough to do it to every page that control appears on. That is what a
//  Stepper did to the Example's Forms page.
//
//  Nothing about it is visible: the screen is correct, the diff emits nothing,
//  and the only symptom is CPU. These tests make it a failing assertion
//  instead — for every control that pulses, unfocused, in one place.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

@MainActor
@Suite("Idle controls must not read the animation clock")
struct IdleClockReadTests {

    /// Renders `view` with a volatile-read tracker installed and reports how
    /// many times it consulted a clock.
    ///
    /// - Parameter focused: when `false` a sentinel claims the focus first, so
    ///   the control under test renders in its resting state.
    private func clockReads(of view: some View, focused: Bool) -> Int {
        let tracker = VolatileReadTracker()
        let context = makeRenderContext(width: 40, height: 10) { environment, _ in
            environment.volatileReadTracker = tracker
        }
        if !focused {
            context.environment.focusManager!.register(IdleSentinel())
        }
        _ = renderToBuffer(view, context: context)
        return tracker.reads
    }

    /// Every control that breathes, rendered at rest. The list is the point:
    /// a new pulsing control belongs here the day it is written.
    ///
    /// `Stepper` is not just an example — it is the one that was wrong. It read
    /// `pulsePhase` unconditionally and used it only when focused, so any page
    /// with a stepper anywhere on it rendered ~10 times a second forever.
    @Test("An unfocused control consults no clock")
    func idleControlIsSilent() {
        let resting: [(String, AnyView)] = [
            ("Stepper", AnyView(Stepper("Count", value: .constant(3), in: 0...10))),
            ("Toggle", AnyView(Toggle("On", isOn: .constant(true)))),
            ("Slider", AnyView(Slider(value: .constant(0.5), in: 0...1))),
            ("TextField", AnyView(TextField("Name", text: .constant("Ada")))),
            ("SecureField", AnyView(SecureField("Password", text: .constant("x")))),
            ("Button", AnyView(Button("Save") {})),
            (
                "DatePicker",
                AnyView(DatePicker("When", selection: .constant(Date(timeIntervalSince1970: 0))))
            ),
        ]
        for (name, view) in resting {
            #expect(
                clockReads(of: view, focused: false) == 0,
                "\(name) keeps the animation clock alive while unfocused")
        }
    }

    @Test("A control that is disabled consults no clock either")
    func disabledControlIsSilent() {
        // Disabled controls never register for focus, but they still render,
        // and a read gated on the wrong condition still fires.
        #expect(clockReads(of: Stepper("Count", value: .constant(3), in: 0...10).disabled(), focused: true) == 0)
        #expect(clockReads(of: Button("Save") {}.disabled(), focused: true) == 0)
    }

    @Test("A page of resting controls is completely quiet")
    func restingPageIsSilent() {
        // The real shape of the bug: it is not one control costing a little, it
        // is one control costing the WHOLE PAGE a re-render every tick.
        let form = VStack {
            Text("Settings")
            Stepper("Devices", value: .constant(2), in: 0...10)
            Toggle("Notifications", isOn: .constant(true))
            Slider(value: .constant(0.3), in: 0...1)
        }
        #expect(clockReads(of: form, focused: false) == 0)
    }

    @Test("A focused control still animates — via a run, a read, or both")
    func focusedControlStillAnimates() {
        // The complement, so "consults no clock" is never satisfied by a
        // control that simply stopped animating. A converted producer reads
        // nothing but leaves a run; an unconverted one reads. Either counts;
        // neither-nor is the failure.
        for (name, view) in [
            ("Stepper", AnyView(Stepper("Count", value: .constant(3), in: 0...10))),
            ("Button", AnyView(Button("Save") {})),
            ("TextField", AnyView(TextField("Name", text: .constant("Ada")))),
        ] {
            let tracker = VolatileReadTracker()
            let context = makeRenderContext(width: 40, height: 10) { environment, _ in
                environment.volatileReadTracker = tracker
            }
            let buffer = renderToBuffer(view, context: context)
            let animates = tracker.reads > 0 || buffer.animatedCells.contains(where: \.isAnimating)
            #expect(animates, "\(name) does not animate when focused")
        }
    }
}

/// Claims auto-focus so the control under test renders at rest.
private final class IdleSentinel: Focusable {
    let focusID = "idle-clock-read-sentinel"
    func handleKeyEvent(_ event: KeyEvent) -> Bool { false }
}
