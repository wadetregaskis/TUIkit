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
    ///
    /// ## Seeing across blank cells
    ///
    /// A run of SGR with nothing printed between is not the only thing a row
    /// wastes bytes on. The commoner shape is styling that changes for cells
    /// that cannot show the change: a label in colour, three spaces, another
    /// label in the same colour spends `ESC[39m` to stop being green over
    /// cells that are not green either way, then twelve bytes becoming green
    /// again. Measured over a divider drag at 140×42, `ESC[39m` was the single
    /// most common escape in the whole stream — **4,187 of 17,367, 20,935
    /// bytes** — and `ESC[38;5;22m`, the colour going straight back on, was the
    /// second at 2,646.
    ///
    /// So a state change whose only visible difference is on a glyph is HELD
    /// while the row prints spaces, and emitted at the first cell that can show
    /// it — by which time the row has often changed its mind and nothing needs
    /// emitting at all. What "can show it" means is
    /// ``SGRState/paintsBlankCellsIdentically(to:)``: the background, and the
    /// attributes that put ink on an empty cell.
    ///
    /// This is exact for the same reason the rest is: nothing observed the
    /// intermediate state. It is deliberately done HERE, at the row builder,
    /// rather than in the diff downstream — a row written whole never reaches
    /// the diff, and a full repaint is all such rows.
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

        /// Whether the styling still owed may be held over a blank cell.
        ///
        /// Only once the state is knowable at all (`sawReset`) and something has
        /// been emitted to compare against — before that the line's baseline is
        /// inherited and unknown, and an unknown state cannot be shown to be
        /// invisible.
        var canDeferAcross: Bool {
            guard sawReset, unresetRun.isEmpty, let emitted else { return false }
            return desired.paintsBlankCellsIdentically(to: emitted)
        }

        var index = startIndex
        while index < endIndex {
            if self[index] == "\u{1B}", let end = escapeEnd(from: index) {
                var sequence = String(self[index..<end])
                // The escape's final byte can FUSE with following zero-width
                // scalars (a combining mark, a variation selector) into one
                // Character, leaving a "sequence" that no longer ends in its
                // own terminator: it would take the barrier branch below,
                // never reach the model, and the state would diverge silently
                // — a later escape netting to what the model believes is on
                // the wire then reconciles to nothing, dropping a reset. Peel
                // the fused scalars back off: they are CONTENT, binding to
                // the previous glyph wherever they sit relative to styling.
                var fusedContent = ""
                if let last = sequence.last, last.unicodeScalars.count > 1,
                    let final = last.unicodeScalars.first?.value, String.isCSIFinalByte(final)
                {
                    let scalars = last.unicodeScalars
                    fusedContent = String(String.UnicodeScalarView(scalars.dropFirst()))
                    sequence = String(sequence.dropLast())
                        + String(String.UnicodeScalarView(scalars.prefix(1)))
                }
                defer {
                    if !fusedContent.isEmpty {
                        // A fused scalar that OCCUPIES cells — a lone
                        // Fitzpatrick modifier is a 2-cell swatch — is
                        // content, and must pass the same gate as any
                        // printable character, or it is painted in whatever
                        // state the previous fragment left and the escape it
                        // followed lands after it. A zero-width mark binds to
                        // the glyph before it whatever sits between, and
                        // stays where it was.
                        if fusedContent.strippedLength > 0 { reconcile() }
                        result += fusedContent
                    }
                }
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
            // A space shows its background and whatever draws ink on an empty
            // cell, and nothing else — so a change confined to the rest of the
            // state waits for a cell that can show it.
            if self[index] != " " || !canDeferAcross {
                reconcile()
            }
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
    /// when it is neither a complete CSI nor a string-terminated sequence.
    ///
    /// Not ``Swift/String/escapeSequenceEnd(from:)``, which is otherwise the
    /// walker for exactly this: that one classifies a final byte by the whole
    /// `Character`'s single scalar and so refuses to consume a terminator that
    /// has FUSED with a following combining mark, while this one must consume
    /// it — the caller peels the fused scalars back off as content, and a
    /// sequence stopped short of its own terminator would take the barrier
    /// branch and never reach the SGR model. See the peeling code above.
    private func escapeEnd(from start: Index) -> Index? {
        var index = self.index(after: start)
        guard index < endIndex else { return nil }
        // A string-terminated sequence — the OSC 8 hyperlink among them — runs
        // to its `BEL` or `ST`, with an arbitrary payload in between. Left
        // unrecognised it is not merely copied wrong: the payload's characters
        // reach the reconciler one at a time, so a pending `ESC[…m` gets
        // emitted INSIDE the URI, and both the styling and the link are lost.
        if let scalar = self[index].unicodeScalars.first, self[index].unicodeScalars.count == 1,
            String.isStringFamilyIntroducer(scalar.value)
        {
            index = self.index(after: index)
            while index < endIndex {
                let character = self[index]
                index = self.index(after: index)
                if character == "\u{07}" { return index }  // BEL terminates
                if character == "\u{1B}", index < endIndex, self[index] == "\\" {
                    return self.index(after: index)  // ESC \ — ST
                }
            }
            return index  // unterminated: the payload runs to the end
        }
        guard self[index] == "[" else { return nil }
        index = self.index(after: index)
        while index < endIndex {
            let character = self[index]
            index = self.index(after: index)
            // The FIRST scalar, not the Character: the terminator can fuse
            // with a following combining scalar into a cluster (`m` + U+0301
            // is one Character, "ḿ") whose letter-ness is an accident of the
            // mark. The caller peels the fused scalars back off the sequence.
            //
            // And the ECMA-48 final-byte test (0x40…0x7E), NOT "is a letter":
            // `ESC[1@` (ICH) ends at `@`, and a walker that runs on past it
            // to the next letter swallows the following escape — which, when
            // that one ends in `m`, turns `ESC[1@ ESC[0m` into one "SGR" and
            // merges it into a corrupt parameter list.
            if let value = character.unicodeScalars.first?.value, String.isCSIFinalByte(value) {
                return index
            }
        }
        return nil
    }
}
