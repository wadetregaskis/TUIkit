//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TerminalHost.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

/// Identity of the terminal emulator hosting the process, detected once from
/// the environment.
///
/// Some rendering choices are terminal-specific rather than
/// capability-negotiable: Terminal.app mis-advances the cursor over emoji
/// (see ``FrameDiffWriter``, which carries workarounds gated on this), and
/// conversely draws emoji-repertoire glyphs like ⬛︎ as single seamless
/// multi-cell glyphs where adjacent FULL BLOCK cells show seams (see
/// ``ToggleCharacterSet/automatic``).
enum TerminalHost {
    /// Whether the host terminal is macOS Terminal.app, detected once from
    /// the process environment. Compile-time `false` off macOS, where
    /// Terminal.app cannot run — so a spurious `TERM_PROGRAM=Apple_Terminal`
    /// exported on another platform is never mistaken for the real thing.
    static let isAppleTerminal: Bool = {
        #if os(macOS)
        return detectAppleTerminal(environment: ProcessInfo.processInfo.environment)
        #else
        return false
        #endif
    }()

    /// Whether the host terminal is iTerm2, detected once from the process
    /// environment.
    static let isITerm2: Bool =
        detectITerm2(environment: ProcessInfo.processInfo.environment)

    /// Whether the host terminal is Ghostty, detected once from the process
    /// environment.
    static let isGhostty: Bool =
        detectGhostty(environment: ProcessInfo.processInfo.environment)

    /// Whether the host terminal is Warp, detected once from the process
    /// environment.
    static let isWarp: Bool =
        detectWarp(environment: ProcessInfo.processInfo.environment)

    /// Whether TUIkit is running inside tmux, detected once from the process
    /// environment.
    ///
    /// tmux is a **compositor**, not a passthrough: it parses our output into
    /// its own cell grid using its own width tables and re-renders that grid to
    /// whichever client is attached. So the host that matters is tmux — the
    /// outer terminal's advance quirks apply to *tmux's* output, not ours — and
    /// this must be checked BEFORE the four native detectors would otherwise
    /// win. In practice they cannot: tmux overwrites `TERM_PROGRAM` with its own
    /// name rather than forwarding the outer terminal's (measured, 3.7b), so
    /// running under tmux inside iTerm2 reports `tmux`, not `iTerm.app`.
    static let isTmux: Bool =
        detectTmux(environment: ProcessInfo.processInfo.environment)

    /// Whether the host draws the emoji-repertoire chrome glyphs (⬛︎ / ⬜︎
    /// with the U+FE0E text-presentation selector) correctly: monochrome,
    /// theme-tintable, two cells, no row shear. Verified by eye on every
    /// host listed (Apple Terminal + iTerm2 2026-07-13; Ghostty + Warp
    /// 2026-07-14); terminals not on this allowlist get the universally-safe
    /// non-emoji glyphs instead — mis-measuring the selector shears the whole
    /// row (issue #9), so membership is earned by inspection, not assumed.
    ///
    /// Ghostty qualifies only because ``String/withGhosttyCursorCompensation()``
    /// fixes it up: Ghostty PAINTS ⬛︎ two cells but advances the cursor by
    /// one, so uncompensated the label collides with the glyph (`■On`). Warp
    /// advances these correctly with no help.
    static var supportsEmojiChrome: Bool { isAppleTerminal || isITerm2 || isGhostty || isWarp }

    /// `true` for macOS Terminal.app (`TERM_PROGRAM == "Apple_Terminal"`),
    /// wherever that variable is set in the process environment.
    ///
    /// Pure over the environment argument — like the other native detectors
    /// (``detectITerm2(environment:)`` and friends) — so tests exercise both
    /// answers deterministically regardless of which terminal, or platform,
    /// runs them. The real-host guarantee that Terminal.app cannot be running
    /// off macOS lives on ``isAppleTerminal``, which gates this to macOS; the
    /// raw check itself stays a plain environment predicate.
    static func detectAppleTerminal(environment: [String: String]) -> Bool {
        environment["TERM_PROGRAM"] == "Apple_Terminal"
    }

    /// `true` for iTerm2 (`TERM_PROGRAM == "iTerm.app"`), wherever iTerm2 sets
    /// that variable in the process environment — locally on macOS.
    ///
    /// NOT across an ssh hop: `TERM_PROGRAM` is not an `LC_*` variable, and
    /// OpenSSH forwards only `LANG` and `LC_*` by default (measured:
    /// `/etc/ssh/ssh_config.d/100-macos.conf` sends `LANG LC_*`), so a shell on
    /// the far side sees no `TERM_PROGRAM` and this returns false there. iTerm2's
    /// shell integration does forward `LC_TERMINAL=iTerm2` — which ssh's `LC_*`
    /// rule carries — but that is a different variable this does not consult; a
    /// remote process is treated as an unknown terminal, conservatively.
    static func detectITerm2(environment: [String: String]) -> Bool {
        environment["TERM_PROGRAM"] == "iTerm.app"
    }

    /// `true` for Ghostty (`TERM_PROGRAM == "ghostty"`), on any platform —
    /// Ghostty runs on macOS and Linux and sets the variable on both.
    ///
    /// Ghostty also ships its own terminfo and sets `TERM=xterm-ghostty`, but
    /// `TERM` is not the discriminator: it is routinely overridden to
    /// `xterm-256color` for compatibility with hosts lacking the entry, while
    /// `TERM_PROGRAM` survives.
    static func detectGhostty(environment: [String: String]) -> Bool {
        environment["TERM_PROGRAM"] == "ghostty"
    }

    /// `true` for Warp (`TERM_PROGRAM == "WarpTerminal"`), on any platform.
    ///
    /// Warp reports `TERM=xterm-256color`, so again only `TERM_PROGRAM`
    /// identifies it. (`WARP_TERMINAL_SESSION_UUID` and friends are also
    /// present, but `TERM_PROGRAM` is the stable, documented signal.)
    static func detectWarp(environment: [String: String]) -> Bool {
        environment["TERM_PROGRAM"] == "WarpTerminal"
    }

    /// `true` when running inside tmux, on any platform.
    ///
    /// `$TMUX` (the server socket path) is the primary signal: tmux always sets
    /// it for its panes and nothing else does, so it holds even on an ancient
    /// tmux. `TERM_PROGRAM == "tmux"` is the secondary signal — set since tmux
    /// 3.2 and the same variable the other hosts key off — and covers a pane
    /// whose `$TMUX` was scrubbed (a `env -u`, a `sudo`, some shell wrappers).
    /// Either alone is sufficient; both are checked because the cost of missing
    /// tmux is silently applying the wrong terminal's width model.
    ///
    /// `TERM` is deliberately NOT consulted: it is `tmux-256color` OR
    /// `screen-256color` depending on the user's `default-terminal`, and
    /// `screen*` is also what GNU screen sets — a different compositor with a
    /// different width table that this model does not describe.
    static func detectTmux(environment: [String: String]) -> Bool {
        if let socket = environment["TMUX"], !socket.isEmpty { return true }
        return environment["TERM_PROGRAM"] == "tmux"
    }

    // MARK: - tmux client identification

    /// One terminal attached to a tmux session — what tmux will tell us about
    /// it, and the handle that lets us find out the rest ourselves.
    struct TmuxClient: Equatable {
        /// The client's XTVERSION reply as `#{client_termtype}` reports it —
        /// "iTerm2 3.6.11", "ghostty 1.3.1", "Warp(v0.2026…)" — or `""` for a
        /// terminal that answered none (Terminal.app, and anything older than
        /// the escape).
        let termtype: String

        /// The `tmux attach` process, whose parent chain runs back through the
        /// login shell to the terminal application that owns the window — which
        /// is how a silent client is identified. `nil` if tmux did not report it.
        let pid: pid_t?
    }

    /// Whether the terminals currently attached to a tmux session all draw the
    /// emoji chrome glyphs correctly.
    ///
    /// Under tmux the *glyph repertoire* is still the outer terminal's — tmux
    /// composites a grid but the client's font paints it — so the emoji-chrome
    /// question is the one thing that genuinely depends on which client is
    /// attached. (Widths do not: tmux's grid is client-independent, measured.)
    ///
    /// **Every** attached client must be recognised, not just the active one: a
    /// tmux session can have several clients at once, each with its own font,
    /// painting the same bytes. Requiring unanimity costs the common
    /// single-client case nothing and keeps a stray unknown client from getting
    /// glyphs it cannot draw.
    ///
    /// - Parameter clients: one entry per attached client. `nil` means the
    ///   question could not be asked; empty means no clients are attached
    ///   (nothing to please).
    static func emojiChromeSupported(tmuxClients clients: [TmuxClient]?) -> Bool {
        guard let clients else { return false }
        return clientCapabilities(tmuxClients: clients).emojiChrome
    }

    /// The full answer for a client list: the verdict, plus whether it might
    /// improve on a short retry.
    ///
    /// The retry signal exists because of a measured race: the
    /// `client-attached` hook fires — and the app probes — BEFORE the new
    /// client's XTVERSION reply has arrived, so `#{client_termtype}` is still
    /// empty at that moment (measured: a hook logging `list-clients` at
    /// attach time saw `pid:` with an empty termtype for an iTerm2 that
    /// reported "iTerm2 3.6.11" moments later). A client that is silent AND
    /// unidentifiable by its process chain may therefore be a recognisable
    /// terminal whose reply is milliseconds away — worth re-asking briefly —
    /// or a genuinely unknown terminal, in which case the bounded retries burn
    /// out and the safe answer stands.
    static func clientCapabilities(tmuxClients clients: [TmuxClient]) -> ClientCapabilities {
        guard !clients.isEmpty else {
            // No clients: nothing to please. No emoji chrome (nobody has earned
            // it), but skin tones stay — tmux's own grid joins them correctly,
            // and an attach fires the hooks, which re-probe and fully redraw.
            return ClientCapabilities(
                emojiChrome: false, skinTonesSafe: true, mayImproveShortly: false)
        }
        var chrome = true
        var skinTones = true
        var mayImprove = false
        for client in clients {
            switch classifyClient(client) {
            case true:
                break
            case false:
                // Identified, and not on the allowlist: no retry will change it.
                chrome = false
            case nil:
                // Silent and unidentified — possibly an XTVERSION reply in
                // flight (the attach race above), possibly a genuine unknown.
                chrome = false
                mayImprove = true
            }
            // Skin tones: tmux re-emits the cluster VERBATIM (byte-captured, no
            // backspace trick), so the client's NATIVE advance applies while
            // tmux's grid believes 2 cells. Measured against exactly that,
            // 2026-07-16: Ghostty 2 ✓; iTerm2 2 (but paints the tone as a
            // separate swatch — the same appearance its native path strips
            // for); Apple Terminal 4 ✗ and Warp 4 ✗, shearing the row rightward
            // by 2 per cluster. So, exactly like every NATIVE path, only
            // Ghostty keeps the tones; a silent client strips until identified
            // (the shared retry covers it).
            if clientRendersSkinTones(client) != true {
                skinTones = false
            }
        }
        return ClientCapabilities(
            emojiChrome: chrome, skinTonesSafe: skinTones, mayImproveShortly: mayImprove)
    }

    /// Whether one client renders SMP-base skin-tone clusters (👍🏽) correctly
    /// when tmux re-emits them verbatim: `true` only for Ghostty — the same
    /// answer as the native paths, where Ghostty alone skips the skin-tone
    /// strip. `nil` for a client neither signal could name.
    static func clientRendersSkinTones(_ client: TmuxClient) -> Bool? {
        if !client.termtype.isEmpty {
            return client.termtype.lowercased().hasPrefix("ghostty")
        }
        guard let pid = client.pid,
            let executable = owningApplicationPath(ofTmuxClient: pid)
        else { return nil }
        return executable.contains("/Ghostty.app/Contents/MacOS/")
    }

    /// Identifies one attached client, by asking it and then — if it said
    /// nothing — by looking at what process owns it.
    ///
    /// Two signals, because neither covers the field alone:
    ///
    /// - **XTVERSION** (`termtype`) names any terminal that answers it, local or
    ///   across an ssh hop, but Terminal.app answers nothing at all (and every
    ///   terminal is silent in the first moments after attaching — the reply is
    ///   a round trip the `client-attached` hook does not wait for).
    /// - **The owning application** identifies a silent terminal, but only a
    ///   local one — over ssh the client's parent is `sshd`, not a terminal.
    ///
    /// Returns `true` for a client positively identified as chrome-capable,
    /// `false` for one positively identified as not (a termtype we don't
    /// recognise), and `nil` for one neither signal could name — silent, with
    /// no recognisable local application in its process chain. `nil` clients
    /// draw the safe glyphs, but distinguish themselves from `false` because
    /// their answer may improve within milliseconds (see
    /// ``clientCapabilities(tmuxClients:)``).
    static func classifyClient(_ client: TmuxClient) -> Bool? {
        if !client.termtype.isEmpty {
            return termtypeDrawsEmojiChrome(client.termtype)
        }
        guard let pid = client.pid,
            let executable = owningApplicationPath(ofTmuxClient: pid)
        else { return nil }
        return applicationDrawsEmojiChrome(executablePath: executable) ? true : nil
    }

    /// Classifies a client by its XTVERSION reply — against the THROUGH-TMUX
    /// bar, which is stricter than the native one.
    ///
    /// Natively, a terminal qualifies if it draws ⬛︎/⬜︎ correctly *with our
    /// compensation applied*. Through tmux no compensation can reach the
    /// client — a CUF we emit lands in tmux's grid and corrupts it — and tmux
    /// redraws a VS-15 cell to the client as `base BS BS base+VS15` (byte-
    /// captured, 3.7b). So membership here requires the client to advance that
    /// sequence by the 2 cells tmux believes it occupies, unaided. Measured
    /// (DSR, alternate screen, 2026-07-16):
    ///
    /// - Apple Terminal 455.1: 2 ✓, iTerm2 3.6.11: 2 ✓, Warp v0.2026.07: 2 ✓
    /// - **Ghostty 1.3.1: 1 ✗** — its VS-15 under-advance (the one quirk our
    ///   native CUF patches) nets the trick to 1, shifting everything after
    ///   the glyph left by one on every such row (and checkering the
    ///   scrollbar, one shifted row at a time). Hence Ghostty, alone, is
    ///   excluded HERE while remaining on the native allowlist.
    ///
    /// Prefix-matched and case-insensitive, so a version bump does not silently
    /// drop support. Terminal.app is deliberately absent: it never answers, so
    /// no termtype can name it — it is recognised by
    /// ``applicationDrawsEmojiChrome(executablePath:)`` instead.
    static func termtypeDrawsEmojiChrome(_ termtype: String) -> Bool {
        let lowered = termtype.lowercased()
        return lowered.hasPrefix("iterm2")
            || lowered.hasPrefix("warp")
    }

    /// Executable paths of the terminal applications verified to draw the emoji
    /// chrome — the same allowlist as ``supportsEmojiChrome``, spelled as
    /// bundles rather than as `TERM_PROGRAM` values.
    ///
    /// Matched as substrings, each anchored with a leading `/` so a bundle
    /// merely *ending* in one of these names ("/My Terminal.app/…") cannot
    /// match. Only Terminal.app names its executable, because the others'
    /// executable names are less predictable than their bundles (iTerm.app ships
    /// `iTerm2`, Warp.app ships `stable`); matching to the `MacOS/` directory is
    /// enough to identify the bundle and won't break when they rename a binary.
    /// Every terminal application the process walk can name — identification,
    /// not capability. Each capability then selects its own subset, because
    /// they genuinely differ per terminal (Ghostty: no chrome through tmux,
    /// but the only one that keeps skin tones).
    private static let recognisedTerminalExecutables = [
        "/Terminal.app/Contents/MacOS/Terminal",
        "/iTerm.app/Contents/MacOS/",
        // iTerm2's session-restoration daemon: with it enabled (the default),
        // a shell's parent chain ends at
        // ~/Library/Application Support/iTerm2/iTermServer-<version> — the app
        // bundle never appears in the chain at all (measured; this is how a
        // tmux client attached from iTerm2 walks). The daemon lives only in
        // iTerm2's own Application Support directory, so the fragment is as
        // unambiguous as the bundle paths.
        "/iTerm2/iTermServer-",
        "/Ghostty.app/Contents/MacOS/",
        "/Warp.app/Contents/MacOS/",
    ]

    /// The subset of ``recognisedTerminalExecutables`` whose owners draw the
    /// emoji chrome correctly THROUGH TMUX. Ghostty is recognised but absent:
    /// it under-advances tmux's re-emitted VS-15 cells (see
    /// `termtypeDrawsEmojiChrome`), so a client owned by Ghostty must not earn
    /// the chrome by ancestry either.
    private static let emojiChromeApplicationExecutables = [
        "/Terminal.app/Contents/MacOS/Terminal",
        "/iTerm.app/Contents/MacOS/",
        "/iTerm2/iTermServer-",
        "/Warp.app/Contents/MacOS/",
    ]

    /// Whether a terminal application, named by its executable path, is one of
    /// the four verified to draw the emoji chrome correctly.
    static func applicationDrawsEmojiChrome(executablePath: String) -> Bool {
        emojiChromeApplicationExecutables.contains { executablePath.contains($0) }
    }

    /// Walks up from a tmux client process to the terminal application that owns
    /// its window, and returns that application's executable path.
    ///
    /// A tmux client's ancestry is the window it was launched in — measured, for
    /// Terminal.app:
    ///
    /// ```
    ///   32465  /opt/homebrew/Cellar/tmux/3.7b/bin/tmux     ← #{client_pid}
    ///   32453  /bin/zsh
    ///   32452  /usr/bin/login
    ///     509  /System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal
    /// ```
    ///
    /// This is the client's chain, not ours: the tmux *server* is a daemon
    /// reparented to `launchd`, so our own ancestry says nothing about who is
    /// watching. Hence `#{client_pid}`.
    ///
    /// Costs no subprocess — `sysctl` for each parent link and `proc_pidpath`
    /// for each path, both plain syscalls — so it adds nothing measurable to the
    /// probe that already forked for tmux.
    ///
    /// Returns the first ancestor that is a recognised terminal application, or
    /// `nil` if the chain reaches `launchd` without one (an ssh session, a
    /// terminal we don't know, a client that already exited).
    ///
    /// macOS-only, and deliberately: this exists to identify Terminal.app, which
    /// is the only allowlisted terminal that answers no XTVERSION and doesn't
    /// exist off macOS. Ghostty answers on Linux, so there is nothing for the
    /// walk to add there and no `/proc` twin worth carrying.
    static func owningApplicationPath(ofTmuxClient pid: pid_t) -> String? {
        #if canImport(Darwin)
        var current: pid_t? = pid
        // launchd (pid 1) roots every chain; the bound is for a pid recycled into
        // a cycle mid-walk, which would otherwise spin forever.
        for _ in 0..<16 {
            guard let pid = current, pid > 1 else { return nil }
            if let path = executablePath(ofProcess: pid),
                recognisedTerminalExecutables.contains(where: { path.contains($0) })
            {
                return path
            }
            current = parentProcess(ofProcess: pid)
        }
        return nil
        #else
        return nil
        #endif
    }

    #if canImport(Darwin)
    /// The parent of a process, or `nil` if it has exited or is unreadable.
    private static func parentProcess(ofProcess pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let ok = mib.withUnsafeMutableBufferPointer {
            sysctl($0.baseAddress, u_int($0.count), &info, &size, nil, 0) == 0
        }
        // A dead pid succeeds with size 0 rather than failing — hence both checks.
        guard ok, size > 0 else { return nil }
        let parent = info.kp_eproc.e_ppid
        return parent > 0 ? parent : nil
    }

    /// The full executable path of a process, or `nil` if it has exited or is
    /// unreadable (another user's process, in particular).
    private static func executablePath(ofProcess pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: Int(4 * MAXPATHLEN))
        // Returns the path's length, excluding the terminating NUL.
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        // Failable rather than lossy: a path that isn't valid UTF-8 is one we
        // cannot match against the allowlist anyway, and saying so leaves the
        // client unidentified — the safe answer — instead of comparing against
        // a string peppered with U+FFFD.
        return String(bytes: buffer[..<Int(length)], encoding: .utf8)
    }
    #endif

    /// Asks tmux what each attached client is, or `nil` when it cannot be asked.
    ///
    /// There is no in-band way to learn this: tmux overwrites `TERM_PROGRAM`
    /// with its own name, and the leaked per-terminal variables
    /// (`LC_TERMINAL`, `GHOSTTY_*`, …) are frozen at the environment of the
    /// client that STARTED the server — measured to still name Apple Terminal
    /// after iTerm2 attaches to the same session. Only tmux itself knows, and
    /// only by being asked. Hence a subprocess.
    ///
    /// **Cost:** one `fork`/`exec` per call, so callers MUST cache. It is not
    /// safe to call per frame, let alone per view. `RenderLoop` calls it once
    /// at startup (via ``EmojiChromeRefresher``) and again — asynchronously,
    /// off the render path — only when a SIGWINCH says something changed: a
    /// real resize, or the synthetic one the client-change hooks send (see
    /// ``installTmuxClientChangeHooks()``). Steady state runs no probes.
    ///
    /// Fails closed: not under tmux, tmux missing from `PATH`, a non-zero exit
    /// or a hang all yield `nil`, which ``emojiChromeSupported(tmuxClients:)``
    /// reads as "unknown" and so as the safe non-emoji glyphs.
    ///
    /// The wait is BOUNDED. `list-clients` answers in a few milliseconds, but a
    /// tmux whose server is wedged — `SIGSTOP`, a stuck socket, a machine under
    /// load — could otherwise block the render loop forever on the unbounded
    /// `readDataToEndOfFile`/`waitUntilExit` this used to call. Past the deadline
    /// the child is killed and the probe fails closed.
    static func probeTmuxClients() -> [TmuxClient]? {
        guard isTmux else { return nil }
        // One line per attached client. The pid comes first because it is always
        // digits: the termtype takes the rest of the line, spaces and all.
        guard
            let output = runTmux(["list-clients", "-F", "#{client_pid} #{client_termtype}"])
        else { return nil }
        return parseTmuxClients(output)
    }

    /// Runs one tmux command with a bounded wait, returning its stdout, or `nil`
    /// on any failure (tmux missing, non-zero exit, or the deadline passing).
    ///
    /// The wait is BOUNDED: tmux answers in a few milliseconds, but a wedged
    /// server — `SIGSTOP`, a stuck socket — could otherwise block forever on the
    /// unbounded `readDataToEndOfFile`/`waitUntilExit` this replaces. Exit is
    /// polled against the deadline; reading is deferred until the child has
    /// exited, which cannot itself block because every command sent through here
    /// answers with at most a few lines, far under the pipe buffer.
    private static func runTmux(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["tmux"] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil  // no tmux on PATH, or exec refused
        }
        let deadline = DispatchTime.now() + .milliseconds(commandTimeoutMilliseconds)
        while process.isRunning {
            if DispatchTime.now() >= deadline {
                process.terminate()
                return nil
            }
            Thread.sleep(forTimeInterval: 0.002)
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    /// How long ``runTmux(_:)`` waits for tmux before giving up and failing
    /// closed. Two orders of magnitude above tmux's normal few-ms reply, so a
    /// loaded machine is not mistaken for a wedged one, yet short enough to be
    /// invisible on the rare occasions a command runs.
    private static let commandTimeoutMilliseconds = 250

    /// Parses `list-clients` output into one entry per attached client.
    ///
    /// Empty termtypes are kept — a client whose XTVERSION went unanswered
    /// (Terminal.app) is still a client, and now an identifiable one. Only the
    /// empty element the trailing newline leaves behind is dropped. Split out
    /// from the subprocess so the parsing is testable without one.
    static func parseTmuxClients(_ output: String) -> [TmuxClient] {
        // No output at all means no clients — distinct from one line that
        // happens to carry no termtype, which IS a client. Without this, `""`
        // would split to a single empty element and be miscounted as one.
        guard !output.isEmpty else { return [] }
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        let withoutTrailingNewlineArtefact = output.hasSuffix("\n") ? lines.dropLast() : lines[...]
        return withoutTrailingNewlineArtefact.map { line in
            let fields = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
            // A tmux too old to know `client_pid` substitutes nothing for it, so
            // the pid is absent rather than wrong: identification falls back to
            // the termtype alone, which is exactly the old behaviour.
            let pid = fields.first.flatMap { pid_t($0) }
            let termtype = fields.count > 1 ? String(fields[1]) : ""
            return TmuxClient(termtype: termtype, pid: pid)
        }
    }

    // MARK: - tmux client-change hooks (push, not poll)

    /// The tmux hooks that mean "the set of attached clients may have changed":
    /// a client attached, detached, or switched its session to (or away from)
    /// ours. All three fire on tmux 3.7b — measured, including for a same-size
    /// attach (which sends no SIGWINCH) and for a client killed with SIGKILL.
    static let tmuxClientChangeHooks = [
        "client-attached", "client-detached", "client-session-changed",
    ]

    /// The `set-hook` arguments that make tmux notify a process of client
    /// changes, as one flat tmux argv (`;`-separated commands). Pure, so the
    /// exact registration is testable without a tmux server.
    ///
    /// Shape, for each hook in ``tmuxClientChangeHooks``:
    ///
    /// ```
    /// set-hook -g 'client-attached[<pid>]' \
    ///     "run-shell -b \"kill -s WINCH <pid> || tmux set-hook -gu 'client-attached[<pid>]'\""
    /// ```
    ///
    /// Every part is load-bearing:
    ///
    /// - **Global (`-g`), never session-scoped.** Hooks are per-index inherited
    ///   options, and a session-scoped hook shadows the user's ENTIRE global
    ///   array for that hook — measured: with a session `client-attached[7391]`
    ///   set, the user's global `client-attached[0]` stopped firing. Two global
    ///   hooks at different indices coexist (also measured), so global is the
    ///   only scope that leaves the user's hooks running.
    /// - **Index = our PID**, so several TUIkit apps on one server each get
    ///   their own slot with no collisions, and unset only their own.
    /// - **`run-shell -b`**: background, so tmux never blocks on us.
    /// - **`kill -s WINCH`**, not a bespoke channel: the app already has a
    ///   complete SIGWINCH pipeline (async-signal-safe flag + self-pipe that
    ///   wakes the idle loop, full repaint), so a client change rides it with
    ///   zero new plumbing. And SIGWINCH's default action is IGNORE, so if this
    ///   app dies and its PID is recycled, a stale hook signalling the new
    ///   process is harmless — which is NOT true of e.g. SIGUSR1 (terminates).
    /// - **`|| tmux set-hook -gu …`**: self-cleaning. `kill` fails once the PID
    ///   is gone, and the hook removes itself on its first firing after this
    ///   app dies without running its own cleanup.
    static func tmuxClientChangeHookArguments(pid: pid_t) -> [String] {
        var arguments: [String] = []
        for hook in tmuxClientChangeHooks {
            if !arguments.isEmpty { arguments.append(";") }
            let slot = "\(hook)[\(pid)]"
            arguments += [
                "set-hook", "-g", slot,
                "run-shell -b \"kill -s WINCH \(pid) || tmux set-hook -gu '\(slot)'\"",
            ]
        }
        return arguments
    }

    /// The `set-hook -gu` arguments that remove exactly the hooks
    /// ``tmuxClientChangeHookArguments(pid:)`` registered — ours and only ours;
    /// unsetting one array index leaves the user's other indices untouched
    /// (measured). Pure, for the same testability.
    static func tmuxClientChangeUnhookArguments(pid: pid_t) -> [String] {
        var arguments: [String] = []
        for hook in tmuxClientChangeHooks {
            if !arguments.isEmpty { arguments.append(";") }
            arguments += ["set-hook", "-gu", "\(hook)[\(pid)]"]
        }
        return arguments
    }

    /// Registers the client-change hooks for this process, so tmux pushes a
    /// SIGWINCH whenever a client attaches, detaches, or changes session —
    /// including the same-size attach that sends no SIGWINCH of its own.
    ///
    /// This is what makes client-change detection PUSH rather than poll: with
    /// the hooks in place the app forks nothing in steady state, and re-probes
    /// only when tmux says something actually happened.
    ///
    /// Returns whether registration succeeded. Failure (a tmux too old for
    /// these hooks, a wedged server) is tolerated: the app then adapts only on
    /// real SIGWINCHes, exactly the behaviour before hooks existed.
    @discardableResult
    static func installTmuxClientChangeHooks() -> Bool {
        guard isTmux else { return false }
        let pid = ProcessInfo.processInfo.processIdentifier
        return runTmux(tmuxClientChangeHookArguments(pid: pid_t(pid))) != nil
    }

    /// Removes this process's client-change hooks; the graceful-shutdown half
    /// of ``installTmuxClientChangeHooks()``. Safe to call when nothing is
    /// registered. (A crash skips this — then the hooks' own `||` arm removes
    /// them on their next firing instead.)
    static func removeTmuxClientChangeHooks() {
        guard isTmux else { return }
        let pid = ProcessInfo.processInfo.processIdentifier
        _ = runTmux(tmuxClientChangeUnhookArguments(pid: pid_t(pid)))
    }
}
