//  🖥️ TUIkit — Terminal UI Kit for Swift
//  String+SGRCollapsing.swift
//
//  Created by Wade Tregaskis
//  License: MIT

extension String {
    /// Merges every run of back-to-back SGR escapes into one.
    ///
    /// ## Why
    ///
    /// A rendered row is assembled from styled fragments, and each fragment
    /// ends by resetting. `FrameDiffWriter` then re-establishes the row's
    /// background after every reset, because a row must keep its own background
    /// across one. The result is a row whose bytes are mostly punctuation:
    /// measured on one frame of a `NavigationSplitView` divider drag at 120×40
    /// — a full repaint, which is what a column resize is — **32,394 bytes, of
    /// which 19,974 were SGR escapes**. 2,565 escapes for 4,800 cells: a colour
    /// change every 1.9 cells, 984 of them a bare `ESC[0m` immediately followed
    /// by the background it had just cleared.
    ///
    /// That is why dragging a divider looked like one or two frames a second.
    /// The app was not slow — writes to the terminal block, so it renders
    /// exactly as fast as the terminal can absorb, and it was handing the
    /// terminal three times the bytes the frame needed.
    ///
    /// ## What it does, and why it is exact
    ///
    /// SGR is a pure state update, so a run of them with **no character printed
    /// in between** is indistinguishable from a single escape carrying the same
    /// parameters in the same order. Nothing observed the intermediate states.
    /// Two cases, both exact:
    ///
    /// - **A run containing a reset.** Everything before the last `0` is
    ///   discarded by that reset, and everything after it is netted by
    ///   ``SGRState`` — whose whole contract is "the shortest sequence that puts
    ///   a freshly-reset terminal into this state", which is precisely the
    ///   situation after a reset. The line's FIRST reset is emitted as `ESC[0m`
    ///   plus that, because the state it resets from is the unknown baseline.
    ///   Every state after it is emitted as a DELTA from the state this function
    ///   last put the terminal in — see ``SGRState/rendered(changingFrom:)``. An
    ///   absolute would be correct too; it would also spend twelve bytes saying
    ///   "black background" to a terminal whose background is already black.
    /// - **A run without one.** The prior state is unknown, so nothing may be
    ///   netted; the parameters are concatenated into one escape instead. Fewer
    ///   bytes of framing, identical meaning.
    ///
    /// A non-SGR escape (a cursor move, an erase) ends a run, because reordering
    /// styling across one would change what it applies to. An unparseable code
    /// is carried through verbatim by ``SGRState``, which is the same call that
    /// type already makes: unknown means "not safe to reason about".
    public func collapsingAdjacentSGR() -> String {
        guard containsAnySGR else { return self }

        var result = ""
        result.reserveCapacity(count)
        // Before the line's first reset the incoming state is UNKNOWN, so
        // nothing may be netted and nothing may be skipped — an added reset
        // would clear styling the original deliberately inherited, and a
        // skipped escape would fail to apply to it. Runs are merged by plain
        // concatenation there, which is exact whatever the baseline was.
        //
        // After a reset the state is absolute, which is what makes the rest
        // possible: `SGRState.parameters` is by contract what a freshly-reset
        // terminal needs, and two identical absolute states are
        // indistinguishable, so the second need not be sent.
        var sawReset = false
        var desired = SGRState()
        var emitted: SGRState?
        var unresetRun: [String] = []
        var pending = false

        func flushUnresetRun() {
            defer { unresetRun.removeAll(keepingCapacity: true) }
            guard !unresetRun.isEmpty else { return }
            let parameters = unresetRun.joined(separator: ";")
            result += "\u{1B}[" + parameters + "m"
        }

        func reconcile() {
            flushUnresetRun()
            guard pending else { return }
            pending = false
            // With something already emitted, the terminal's state is not merely
            // knowable but KNOWN — we put it there — so say only what changed.
            // Without, it is unknown (nothing has been netted yet, only the
            // line's inherited baseline), and only a reset-prefixed absolute is
            // safe. See ``SGRState/rendered(changingFrom:)``.
            if let emitted {
                result += desired.rendered(changingFrom: emitted)
            } else {
                result += desired.isDefault ? "\u{1B}[0m" : "\u{1B}[0;" + desired.parameters + "m"
            }
            emitted = desired
        }

        var index = startIndex
        while index < endIndex {
            if self[index] == "\u{1B}", let end = escapeEnd(from: index) {
                let sequence = String(self[index..<end])
                if sequence.hasSuffix("m") {
                    if sawReset {
                        desired.apply(sequence)
                        pending = true
                    } else if sequence.isSGRReset {
                        // From here on the state is knowable.
                        flushUnresetRun()
                        sawReset = true
                        desired = SGRState()
                        emitted = nil
                        pending = true
                    } else {
                        unresetRun.append(sequence.sgrParameters ?? "")
                    }
                } else {
                    // An erase paints with the background in force, and a
                    // cursor move must not be crossed by styling: both are
                    // barriers, so settle before letting one past.
                    reconcile()
                    result += sequence
                }
                index = end
                continue
            }
            reconcile()
            result.append(self[index])
            index = self.index(after: index)
        }
        // The trailing reset is load-bearing — it is what stops a row's styling
        // leaking into whatever is drawn next — so the line always ends
        // reconciled, printable characters or not.
        reconcile()
        return result
    }

    /// Whether the string carries any SGR at all — a plain line has nothing to
    /// reconcile, and bailing costs one scan and saves an allocation.
    private var containsAnySGR: Bool { utf8.contains(0x1B) }

    /// Whether this escape is a reset — `ESC[0m`, `ESC[m`, or any parameter
    /// list whose codes are all zero.
    fileprivate var isSGRReset: Bool {
        guard let parameters = sgrParameters else { return false }
        if parameters.isEmpty { return true }
        return parameters.split(separator: ";", omittingEmptySubsequences: false)
            .allSatisfy { $0.isEmpty || Int($0) == 0 }
    }

    /// This SGR escape's parameter list, without the `ESC[` and the `m`.
    fileprivate var sgrParameters: String? {
        guard hasPrefix("\u{1B}["), hasSuffix("m") else { return nil }
        return String(dropFirst(2).dropLast())
    }

    /// The index just past the escape sequence starting at `start`, or `nil`
    /// when it is not a complete CSI sequence.
    private func escapeEnd(from start: Index) -> Index? {
        var index = self.index(after: start)
        guard index < endIndex, self[index] == "[" else { return nil }
        index = self.index(after: index)
        while index < endIndex {
            let character = self[index]
            index = self.index(after: index)
            if character.isLetter { return index }
        }
        return nil
    }
}
