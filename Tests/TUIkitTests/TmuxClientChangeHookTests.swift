//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TmuxClientChangeHookTests.swift
//
//  Pins the tmux hook registration that makes client-change detection PUSH
//  rather than poll, and the coalescer that keeps the resulting async probes
//  to at-most-one-in-flight — and, below, the theme-change hooks that ride the
//  same channel when a client switches between a light and a dark theme.
//
//  The hook behaviours these encode were measured on tmux 3.7b (2026-07-15):
//  client-attached / client-detached / client-session-changed all fire —
//  including for a SAME-SIZE attach (no SIGWINCH of its own) and for a client
//  killed with SIGKILL; a session-scoped hook shadows the user's entire global
//  array for that hook name, while two GLOBAL hooks at different indices
//  coexist; and `set-hook -gu 'name[i]'` removes only index i.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation  // pid_t
import Testing

@testable import TUIkit

@Suite("tmux client-change hooks")
struct TmuxClientChangeHookTests {
    @Test("Registration is global, PID-indexed, backgrounded, and self-cleaning")
    func hookRegistrationShape() {
        let arguments = TerminalHost.tmuxClientChangeHookArguments(pid: 12345)

        // One set-hook per hook, ';'-separated into a single tmux invocation
        // (one fork registers everything).
        #expect(arguments.filter { $0 == "set-hook" }.count == 3)
        #expect(arguments.filter { $0 == ";" }.count == 2)

        // GLOBAL, never session-scoped: a session-scoped hook shadows the
        // user's entire global array for that hook name (measured), silently
        // disabling their config while the app runs. Global hooks at distinct
        // indices coexist with theirs.
        #expect(arguments.filter { $0 == "-g" }.count == 3)
        #expect(!arguments.contains("-t"))

        // PID-indexed, so several TUIkit apps on one server can't collide.
        for hook in TerminalHost.tmuxClientChangeHooks {
            #expect(arguments.contains("\(hook)[12345]"), "\(hook) must be registered")
        }

        // Every hook command must be backgrounded (tmux must never block on
        // us), signal via SIGWINCH (default action IGNORE, so a recycled PID
        // is safe — SIGUSR1 would terminate an innocent process), and remove
        // itself when the kill fails because this app is gone.
        for command in arguments where command.hasPrefix("run-shell") {
            #expect(command.contains("run-shell -b"), "must not block tmux: \(command)")
            #expect(command.contains("kill -s WINCH 12345"), "must poke our SIGWINCH path: \(command)")
            #expect(command.contains("|| tmux set-hook -gu"), "must self-clean after a crash: \(command)")
        }
    }

    @Test("The hooks watched are exactly the client-change events")
    func hookNames() {
        // attach + detach + a client switching sessions into/away from ours:
        // the complete set of events that can change which terminals paint our
        // output. Resizes need no hook — a real resize sends SIGWINCH itself.
        #expect(
            TerminalHost.tmuxClientChangeHooks.sorted() == [
                "client-attached", "client-detached", "client-session-changed",
            ])
    }

    @Test("Unhooking removes exactly our indices, nothing of the user's")
    func unhookShape() {
        let arguments = TerminalHost.tmuxClientChangeUnhookArguments(pid: 12345)
        #expect(arguments.filter { $0 == "-gu" }.count == 3)
        for hook in TerminalHost.tmuxClientChangeHooks {
            #expect(arguments.contains("\(hook)[12345]"))
        }
        // -gu on an index removes that index alone (measured); asserting no
        // bare hook names guards against a refactor to whole-array removal,
        // which would delete the user's hooks too.
        for hook in TerminalHost.tmuxClientChangeHooks {
            #expect(!arguments.contains(hook), "must unset our index, not the whole \(hook) array")
        }
    }

    @Test("Install and remove are inert off tmux")
    func inertOffTmux() {
        // Off tmux there is nothing to hook; these must not fork.
        // (isTmux is env-derived and false in the test process — pinned so a
        // future refactor can't make the test silently vacuous.)
        guard !TerminalHost.isTmux else { return }
        #expect(TerminalHost.installTmuxClientChangeHooks() == false)
        TerminalHost.removeTmuxClientChangeHooks()  // must not trap or fork
    }
}

/// The hooks that fire when a tmux CLIENT changes its theme, which is the only
/// notice a pane gets that the colours it is drawn in have moved.
///
/// Measured on tmux 3.7c (2026-09-15, private socket, empty config):
/// `client-light-theme` and `client-dark-theme` are accepted as global indexed
/// hooks and show up in `show-hooks -g`; an unknown hook name is refused with
/// "invalid option" and a non-zero exit, **and the commands after it in the same
/// argv do not run** — with a bogus name first, the real hook that followed it in
/// one invocation was never set. That is why these are registered on their own.
@Suite("tmux client theme hooks")
struct TmuxThemeChangeHookTests {

    @Test("The theme hooks watched are exactly the two tmux fires on a theme change")
    func hookNames() {
        #expect(
            TerminalHost.tmuxThemeChangeHooks.sorted() == [
                "client-dark-theme", "client-light-theme",
            ])
    }

    @Test("Registration is global, PID-indexed, backgrounded, and self-cleaning")
    func hookRegistrationShape() {
        let arguments = TerminalHost.tmuxThemeChangeHookArguments(pid: 12345)

        #expect(arguments.filter { $0 == "set-hook" }.count == 2)
        #expect(arguments.filter { $0 == ";" }.count == 1)

        // Global at a PID index, for the reasons the client-change hooks give:
        // a session-scoped hook shadows the user's whole global array for that
        // name, and the index keeps several TUIkit apps out of each other's
        // slots.
        #expect(arguments.filter { $0 == "-g" }.count == 2)
        #expect(!arguments.contains("-t"))
        for hook in TerminalHost.tmuxThemeChangeHooks {
            #expect(arguments.contains("\(hook)[12345]"), "\(hook) must be registered")
        }

        // The same SIGWINCH channel the client-change hooks ride: the app's
        // resize path already throws the screen away and re-asks the terminal
        // for its colours, which is exactly what a theme change needs.
        for command in arguments where command.hasPrefix("run-shell") {
            #expect(command.contains("run-shell -b"), "must not block tmux: \(command)")
            #expect(command.contains("kill -s WINCH 12345"), "must poke our SIGWINCH path: \(command)")
            #expect(command.contains("|| tmux set-hook -gu"), "must self-clean after a crash: \(command)")
        }
    }

    /// The load-bearing part. A tmux too old for the theme hooks refuses the
    /// whole invocation, so sharing one with the client-change hooks would let
    /// it take those down too — measured above.
    @Test("The theme hooks and the client-change hooks are never in one invocation")
    func registeredSeparately() {
        let theme = TerminalHost.tmuxThemeChangeHookArguments(pid: 12345)
        let clients = TerminalHost.tmuxClientChangeHookArguments(pid: 12345)

        for hook in TerminalHost.tmuxClientChangeHooks {
            #expect(
                !theme.contains { $0.contains(hook) },
                "\(hook) rides in the theme invocation, which an old tmux refuses whole")
        }
        for hook in TerminalHost.tmuxThemeChangeHooks {
            #expect(
                !clients.contains { $0.contains(hook) },
                "\(hook) rides in the client-change invocation and would take it down")
        }
    }

    @Test("Unhooking removes exactly our indices, nothing of the user's")
    func unhookShape() {
        let arguments = TerminalHost.tmuxThemeChangeUnhookArguments(pid: 12345)
        #expect(arguments.filter { $0 == "-gu" }.count == 2)
        for hook in TerminalHost.tmuxThemeChangeHooks {
            #expect(arguments.contains("\(hook)[12345]"))
            #expect(!arguments.contains(hook), "must unset our index, not the whole \(hook) array")
        }
    }

    @Test("Install and remove are inert off tmux")
    func inertOffTmux() {
        guard !TerminalHost.isTmux else { return }
        #expect(TerminalHost.installTmuxThemeChangeHooks() == false)
        TerminalHost.removeTmuxThemeChangeHooks()  // must not trap or fork
    }

    /// What the app actually calls. Both halves go out, each as its own tmux
    /// invocation, and neither may fork off tmux.
    @Test("The pair the app installs covers both sets, and is inert off tmux")
    func combinedEntryPointIsInertOffTmux() {
        guard !TerminalHost.isTmux else { return }
        TerminalHost.installTmuxHooks()  // must not trap or fork
        TerminalHost.removeTmuxHooks()
    }
}
