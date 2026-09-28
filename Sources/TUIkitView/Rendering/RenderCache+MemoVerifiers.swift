//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderCache+MemoVerifiers.swift
//
//  The memo verifiers: `TUIKIT_VERIFY_MEASURE_MEMO` and
//  `TUIKIT_VERIFY_RENDER_MEMO`, which check every size and buffer a memo
//  serves against a fresh measure or render, and where what they find goes.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitCore
import TUIkitStyling

extension RenderCache {
    /// Whether every memo hit is checked against a fresh measurement.
    ///
    /// Off by default and never on in an app: it measures the subtree the memo
    /// just saved, so it costs more than the memo saves. It exists because the
    /// memo's claim — that a size taken under one vertical budget answers a
    /// query made under another — is a claim about every `sizeThatFits` beneath
    /// it, and the only direct check of it is to make both measurements and
    /// compare. Set by `TUIKIT_VERIFY_MEASURE_MEMO`, or assigned directly by a
    /// test; ``measureMemoMismatches`` collects what it finds.
    ///
    /// A pixel-level guard alone is not enough, which is the reason this exists
    /// as well as `MeasureMemoEquivalenceTests`: an unsound serve only changes
    /// the picture when the wrong size reaches a place that draws differently
    /// for it, so a corpus can miss a real one. This catches the serve itself.
    ///
    /// Where a served size disagrees, the layout uses the FRESH one, as
    /// ``verifiesRenderMemo`` draws its fresh render — see there for why that
    /// makes it a debugging aid and never a fix.
    @MainActor public static var verifiesMeasureMemo =
        ProcessInfo.processInfo.environment["TUIKIT_VERIFY_MEASURE_MEMO"] != nil

    /// What ``verifiesMeasureMemo`` found: one line per served size that a fresh
    /// measurement disagreed with. Capped, because a broken memo produces them
    /// by the thousand and the first few say everything.

    /// Where ``verifiesMeasureMemo`` writes what it finds, when the environment
    /// variable names a path rather than just switching the mode on.
    ///
    /// An app draws a screen; it has nowhere to print a diagnostic that would
    /// not corrupt the very frame under test. So a live run — the Example app
    /// walked through a PTY, which is the only place a real app's tree is
    /// measured — says where to put the report instead.
    @MainActor static let measureMemoMismatchLog: String? = {
        guard let value = ProcessInfo.processInfo.environment["TUIKIT_VERIFY_MEASURE_MEMO"],
            value.contains("/")
        else { return nil }
        return value
    }()

    /// Whether every BUFFER memo hit is checked against a fresh render.
    ///
    /// The twin of ``verifiesMeasureMemo``, and it exists because a served
    /// buffer can be wrong in a way nothing else notices. The memo's claim is
    /// that a subtree whose view value compares equal, at the same size, draws
    /// the same cells — and that claim quietly depends on everything ELSE the
    /// subtree read while drawing. An environment value applied through a
    /// modifier is compared (``noteAppliedEnvironment(_:identity:keyPath:depth:)``), but one **assigned
    /// directly** — `context.environment.foo = x`, which several containers do
    /// — is not, and the entry it invalidates is nobody's.
    ///
    /// That is not hypothetical: it is how a buffer painted over one
    /// `surfaceBackground` came to be served over another, blend and all, until
    /// the surface joined the key. The direct check is to render the subtree the
    /// memo just saved and compare the cells, which costs more than the memo
    /// saves and so is never on in an app.
    ///
    /// Set by `TUIKIT_VERIFY_RENDER_MEMO`, or assigned directly by a test.
    /// ``renderMemoMismatches`` collects what it finds.
    ///
    /// Where a served buffer disagrees, the FRESH render is drawn. That makes
    /// it a debugging aid for a view that fails to update: if it updates with
    /// the verifier on, the cache was serving it stale, and the report names
    /// the view and where it sits. It is not a way to make an app work. It
    /// re-renders everything the cache serves, costing more than the cache
    /// saves; every difference it draws, it also reports; and a view that
    /// still fails to update under it is not being served stale at all — its
    /// state is not reaching it (the Render Cycle article's "Checking What the
    /// Cache Serves" has the recipe).
    @MainActor public static var verifiesRenderMemo =
        ProcessInfo.processInfo.environment["TUIKIT_VERIFY_RENDER_MEMO"] != nil

    /// Where ``verifiesRenderMemo`` writes what it finds, when the environment
    /// variable names a path rather than just switching the mode on — an app has
    /// nowhere to print a diagnostic that would not corrupt the frame under test.
    @MainActor static let renderMemoMismatchLog: String? = {
        guard let value = ProcessInfo.processInfo.environment["TUIKIT_VERIFY_RENDER_MEMO"],
            value.contains("/")
        else { return nil }
        return value
    }()

    /// Records a served buffer that a fresh render did not reproduce.
    ///
    /// - Parameters:
    ///   - viewType: The memoized view's type, for the report.
    ///   - served: What the memo handed back.
    ///   - fresh: What rendering it again produced.
    ///   - identity: Where in the tree it sat.
    @MainActor public func noteRenderMemoMismatch(
        viewType: String, served: FrameBuffer, fresh: FrameBuffer, identity: String = ""
    ) {
        guard renderMemoMismatches.count < 20 else { return }
        let shared = min(served.lines.count, fresh.lines.count)
        let differing = (0..<shared).first { served.lines[$0] != fresh.lines[$0] }
        let firstDiff =
            differing.map {
                "line \($0): served \(served.lines[$0].debugDescription) "
                    + "but a fresh render says \(fresh.lines[$0].debugDescription)"
            }
            ?? "served \(served.lines.count) lines, a fresh render gives \(fresh.lines.count)"
        recordRenderMemoMismatch("\(viewType): \(firstDiff)" + (identity.isEmpty ? "" : " at \(identity)"))
    }

    /// Records a served entry whose replayed registrations a fresh render did
    /// not make: a different kind, order or count.
    ///
    /// Compared by kind because the recorded closures are opaque. What it
    /// catches is a key that compares equal over a subtree that registers
    /// differently, which a served buffer would silently get wrong.
    @MainActor package func noteRenderMemoEffectMismatch(
        viewType: String, served: [EffectJournal.Kind], fresh: [EffectJournal.Kind], identity: String = ""
    ) {
        guard renderMemoMismatches.count < 20 else { return }
        let names = { (kinds: [EffectJournal.Kind]) in kinds.map(\.name).joined(separator: ", ") }
        recordRenderMemoMismatch(
            "\(viewType): served registrations [\(names(served))] but a fresh render makes [\(names(fresh))]"
                + (identity.isEmpty ? "" : " at \(identity)"))
    }

    /// Appends one finding to ``renderMemoMismatches``, and to the log file
    /// when the environment variable names one.
    @MainActor private func recordRenderMemoMismatch(_ line: String) {
        renderMemoMismatches.append(line)
        if let path = Self.renderMemoMismatchLog, let data = (line + "\n").data(using: .utf8) {
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
    }

    /// Records a served size a fresh measurement did not agree with.
    @MainActor public func noteMeasureMemoMismatch(
        viewType: String, served: ViewSize, fresh: ViewSize, proposal: ProposedSize,
        availableWidth: Int, availableHeight: Int, identity: String = ""
    ) {
        guard measureMemoMismatches.count < 20 else { return }
        measureMemoMismatches.append(
            "\(viewType): served \(served.width)x\(served.height)"
                + "\(served.isNaturalSize ? " (natural)" : "")"
                + " but a fresh measure at proposal "
                + "(\(proposal.width.map(String.init) ?? "nil"), \(proposal.height.map(String.init) ?? "nil"))"
                + " in \(availableWidth)x\(availableHeight) says \(fresh.width)x\(fresh.height)"
                + (identity.isEmpty ? "" : " at \(identity)"))
        if let path = Self.measureMemoMismatchLog, let last = measureMemoMismatches.last,
            let data = (last + "\n").data(using: .utf8)
        {
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
    }
}
