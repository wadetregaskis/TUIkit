//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ComplexScriptWidthTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore

// MARK: - Two width rules, one set of scalars

/// The complex-script corpus rows, with **both** of the framework's width rules
/// written down side by side for every one of them.
///
/// ## Why both numbers are pinned rather than compared
///
/// ``Swift/Character/terminalWidth`` answers a multi-scalar cluster with a flat
/// **2** as soon as any scalar past the first adds width. ``Unicode/Scalar/
/// loneTerminalWidth`` — the same file's per-scalar rule, and what the run
/// scanners use for every cluster they can prove standalone — prices each
/// scalar and sums. For all 78 rows the corpus held before 2026-09-04 the two
/// coincide, because an emoji sequence has exactly two advancing scalars and
/// 1 + 1 = 2.
///
/// Unicode 15.1's GB9c broke the coincidence, and Swift 6.2 implements it: a
/// Devanagari conjunct is ONE `Character` however many consonants it stacks, so
/// स्त्र reaches the cluster rule with three advancing scalars and is answered 2
/// where the per-scalar rule says 3. The framework therefore holds two answers
/// for the same text, and which one a caller gets depends only on whether the
/// standard library fused it — nothing about the terminal.
///
/// **No host has been measured on any of this**, so this suite does not pick a
/// winner. It records what each rule claims today, asserts they agree where
/// they agree, and wraps the disagreements in `withKnownIssue` — which fails if
/// the divergence silently disappears just as loudly as a new one fails
/// ``rulesAgreeExceptWhereRecorded``. Either direction of a quiet change is a
/// test failure; only a measurement licenses an intentional one.
///
/// - Note: The direction of the error is not the same for every disagreement,
///   which is exactly why "make one rule call the other" is not the fix. For a
///   three-consonant conjunct the cluster rule's 2 is the suspect number (a
///   wcwidth-per-codepoint host advances 3). For decomposed Hangul the cluster
///   rule's 2 is almost certainly right — 한 is two cells however it is spelled
///   — and the per-scalar rule's 3 and 4 are the suspect ones, because it
///   prices the conjoining V and T jamo at 1 each where `wcwidth` gives
///   U+1160…U+11FF zero.
@Suite("Complex script widths")
struct ComplexScriptWidthTests {

    /// One corpus row and the two answers.
    ///
    /// `cluster` and `perScalar` are transcribed, not computed from each other:
    /// a table that derived one from the other could not record a disagreement,
    /// which is the whole point of it. `advancing` is how many of the cluster's
    /// scalars price above zero — the quantity the cluster rule ignores.
    struct Row: Sendable, CustomStringConvertible {
        let id: String
        let cluster: Int
        let perScalar: Int
        let advancing: Int

        var description: String { id }
        /// Whether the two rules answer the same number for this row.
        var rulesAgree: Bool { cluster == perScalar }
    }

    /// Every row added to the corpus on 2026-09-04.
    ///
    /// ``tableCoversEveryComplexScriptRow`` fails if a row is added to one of
    /// these classes and not to this table, so the list cannot silently rot.
    static let rows: [Row] = [
        Row(id: "fullwidth_latin_a", cluster: 2, perScalar: 2, advancing: 1),
        Row(id: "combining_stack", cluster: 1, perScalar: 1, advancing: 1),

        // GB9c fuses these. The first, and the Bengali and Telugu rows, have
        // exactly two advancing scalars and so land on the cluster rule's 2 by
        // coincidence — which is why nothing caught the other three.
        Row(id: "conjunct_deva_ksha", cluster: 2, perScalar: 2, advancing: 2),
        Row(id: "conjunct_deva_stra", cluster: 2, perScalar: 3, advancing: 3),
        Row(id: "conjunct_deva_shtra", cluster: 2, perScalar: 3, advancing: 3),
        Row(id: "conjunct_deva_stri", cluster: 2, perScalar: 4, advancing: 4),
        Row(id: "conjunct_bengali_ksha", cluster: 2, perScalar: 2, advancing: 2),
        Row(id: "conjunct_telugu_ksha", cluster: 2, perScalar: 2, advancing: 2),

        // The half-forms GB9c does not fuse: virama is `Mn`, so the cluster is
        // its base and both rules say 1.
        Row(id: "virama_tamil_sa", cluster: 1, perScalar: 1, advancing: 1),
        Row(id: "virama_kannada_ka", cluster: 1, perScalar: 1, advancing: 1),
        Row(id: "virama_khmer_ka", cluster: 1, perScalar: 1, advancing: 1),

        Row(id: "matra_deva_i", cluster: 2, perScalar: 2, advancing: 2),
        Row(id: "matra_deva_o", cluster: 2, perScalar: 2, advancing: 2),
        Row(id: "matra_deva_au", cluster: 2, perScalar: 2, advancing: 2),
        Row(id: "matra_deva_i_anusvara", cluster: 2, perScalar: 2, advancing: 2),
        Row(id: "matra_tamil_aa", cluster: 2, perScalar: 2, advancing: 2),
        Row(id: "matra_khmer_aa", cluster: 2, perScalar: 2, advancing: 2),

        Row(id: "nukta_deva_qa", cluster: 1, perScalar: 1, advancing: 1),
        Row(id: "nukta_deva_rra", cluster: 1, perScalar: 1, advancing: 1),

        Row(id: "chillu_malayalam_atomic", cluster: 1, perScalar: 1, advancing: 1),
        Row(id: "chillu_malayalam_zwj", cluster: 1, perScalar: 1, advancing: 1),

        Row(id: "thai_tone", cluster: 1, perScalar: 1, advancing: 1),
        Row(id: "thai_vowel_tone", cluster: 1, perScalar: 1, advancing: 1),
        // Sara am is a SPACING vowel, so it is width-adding where the tone
        // marks above are not — 2 from both rules, unlike its neighbours.
        Row(id: "thai_sara_am", cluster: 2, perScalar: 2, advancing: 2),
        Row(id: "lao_vowel_tone", cluster: 1, perScalar: 1, advancing: 1),

        Row(id: "tibetan_subjoined", cluster: 1, perScalar: 1, advancing: 1),
        Row(id: "tibetan_subjoined_vowel", cluster: 1, perScalar: 1, advancing: 1),

        Row(id: "arabic_lam_alef", cluster: 1, perScalar: 1, advancing: 1),
        Row(id: "arabic_harakat", cluster: 1, perScalar: 1, advancing: 1),
        Row(id: "arabic_shadda_harakat", cluster: 1, perScalar: 1, advancing: 1),

        Row(id: "hebrew_hiriq", cluster: 1, perScalar: 1, advancing: 1),
        Row(id: "hebrew_dagesh_qamats", cluster: 1, perScalar: 1, advancing: 1),

        // The other disagreement, and it points the OTHER way: the L jamo is
        // East-Asian Wide so the per-scalar rule starts at 2 and then charges
        // for the V and T jamo, which `wcwidth` gives zero.
        Row(id: "hangul_jamo_lvt", cluster: 2, perScalar: 4, advancing: 3),
        Row(id: "hangul_jamo_lv", cluster: 2, perScalar: 3, advancing: 2),

        Row(id: "latin_zwj", cluster: 1, perScalar: 1, advancing: 1),
        Row(id: "latin_zwnj", cluster: 1, perScalar: 1, advancing: 1),
        Row(id: "bidi_lrm", cluster: 0, perScalar: 0, advancing: 0),
        Row(id: "bidi_rlm", cluster: 0, perScalar: 0, advancing: 0),
    ]

    /// The corpus classes ``rows`` is the table for.
    static let classes: Set<String> = [
        "indic_conjunct", "virama_final", "spacing_vowel_sign", "nukta", "chillu",
        "thai_lao", "tibetan_stack", "arabic", "hebrew_points", "hangul_jamo",
        "format_control",
    ]

    /// The two rows added to classes that already existed.
    static let additionsToExistingClasses: Set<String> = ["fullwidth_latin_a", "combining_stack"]

    private static let corpus: [String: TerminalWidthCorpus.Entry] =
        Dictionary(uniqueKeysWithValues: TerminalWidthCorpus.all.map { ($0.id, $0) })

    private static func entry(for row: Row) throws -> TerminalWidthCorpus.Entry {
        try #require(corpus[row.id], "\(row.id) is not in the corpus")
    }

    // MARK: - The premise

    /// The fact everything else rests on. If Swift stopped fusing a conjunct,
    /// `स्त्र` would be three `Character`s of one cell each, the cluster rule
    /// would never see it, and there would be nothing here to disagree about —
    /// so this is checked rather than assumed. (It is also what makes
    /// ``TerminalWidthCorpus/Entry/character`` safe: that initialiser traps on
    /// anything but exactly one cluster.)
    @Test("Every complex-script row is exactly one grapheme cluster", arguments: rows)
    func rowIsOneCluster(row: Row) throws {
        let entry = try Self.entry(for: row)
        #expect(
            entry.text.count == 1,
            "\(row.id) (\(entry.codepoints)) segments into \(entry.text.count) clusters")
    }

    // MARK: - What each rule claims today

    /// Traits are pinned to ``TerminalWidthTraits/composing`` throughout: the
    /// widening arms only fire for clusters carrying a joiner or a Fitzpatrick
    /// modifier, but pinning makes these numbers independent of whatever host
    /// the tests happen to run under.
    @Test("The cluster rule claims what is recorded here", arguments: rows)
    func clusterRuleClaim(row: Row) throws {
        let entry = try Self.entry(for: row)
        TerminalWidthTraits.withTraits(.composing) {
            #expect(
                entry.character.terminalWidth == row.cluster,
                """
                \(row.id) (\(entry.codepoints)): the cluster rule now says \
                \(entry.character.terminalWidth), recorded \(row.cluster)
                """)
        }
    }

    @Test("The per-scalar rule sums to what is recorded here", arguments: rows)
    func perScalarRuleSum(row: Row) throws {
        let entry = try Self.entry(for: row)
        TerminalWidthTraits.withTraits(.composing) {
            let sum = entry.text.unicodeScalars.reduce(0) { $0 + $1.loneTerminalWidth }
            let advancing = entry.text.unicodeScalars.count { $0.loneTerminalWidth > 0 }
            #expect(
                sum == row.perScalar,
                """
                \(row.id) (\(entry.codepoints)): the per-scalar rule now sums to \(sum), \
                recorded \(row.perScalar)
                """)
            #expect(
                advancing == row.advancing,
                "\(row.id): \(advancing) scalars advance, recorded \(row.advancing)")
        }
    }

    // MARK: - Where they disagree

    /// The assertion the finding is about, run for every row and expected to
    /// fail for exactly the five recorded in ``rows``.
    ///
    /// A `withKnownIssue` fails when the issue does NOT occur, so this is a
    /// two-way pin: a sixth divergence fails here, and any of the five quietly
    /// resolving fails here too. Neither may happen without a measurement,
    /// because 2 and 3 (and 2 and 4) cannot both be right and nothing has yet
    /// asked a terminal which is.
    @Test("The cluster rule and the per-scalar rule agree, except where recorded",
          arguments: rows)
    func rulesAgreeExceptWhereRecorded(row: Row) throws {
        let entry = try Self.entry(for: row)
        TerminalWidthTraits.withTraits(.composing) {
            withKnownIssue(
                """
                \(row.id) (\(entry.codepoints)): the cluster rule says \(row.cluster), \
                the per-scalar rule \(row.perScalar). Settle it by measuring the row — \
                `advance_probe.py` for the internal column, `landing_probe.py` + \
                `landing_analyze.py` for the paint — on each host in \
                Documentation/Terminal-compatibility.md, and only then change a rule.
                """,
                isIntermittent: false
            ) {
                #expect(entry.character.terminalWidth == row.perScalar)
            } when: {
                !row.rulesAgree
            }
        }
    }

    // MARK: - The rows are known to be unmeasured

    /// Until a landing record measures a row, its absence must be recorded
    /// rather than invisible — otherwise "no terminal has been asked" reads
    /// exactly like "every model passes", which is the failure mode
    /// ``TerminalLedgerConformanceTests/awaitingLandingMeasurement`` exists to
    /// prevent. This is the other end of that: a row this suite reasons about
    /// is either measured somewhere or listed there.
    @Test("Every complex-script row is measured, or recorded as awaiting measurement",
          arguments: rows)
    func rowIsMeasuredOrRecordedAsAwaiting(row: Row) {
        let measured = TerminalLedgerConformanceTests.ledgers.contains {
            $0.measurements[row.id] != nil
        }
        #expect(
            measured
                || TerminalLedgerConformanceTests.awaitingLandingMeasurement.contains(row.id),
            "\(row.id): no host has measured it and it is not recorded as awaiting measurement")
    }

    // MARK: - The table cannot rot

    @Test("Every corpus row in a complex-script class is in this table")
    func tableCoversEveryComplexScriptRow() {
        let tabled = Set(Self.rows.map(\.id))
        for entry in TerminalWidthCorpus.all
        where Self.classes.contains(entry.category) || Self.additionsToExistingClasses.contains(entry.id) {
            #expect(tabled.contains(entry.id), "\(entry.id) is in the corpus but not in this table")
        }
        for id in tabled where Self.corpus[id] == nil {
            Issue.record("\(id) is in this table but no longer in the corpus")
        }
    }

    // MARK: - The clusters that are NOT one cluster

    /// The conjuncts GB9c leaves alone, and the lam-alef a keyboard produces.
    ///
    /// These read as one unit to anyone who reads the script and are two
    /// `Character`s to Swift, which is why the corpus holds their halves
    /// instead: GB9c's `InCB=Linker` property is defined for six scripts, and
    /// Tamil, Kannada and Khmer are not among them. Pinned because the whole
    /// shape of a width bug in this text depends on which it is — a shear once
    /// per conjunct, or once per half.
    @Test("A conjunct outside GB9c's linker set is two clusters, not one",
          arguments: [
            ("tamil_ksha", "\u{B95}\u{BCD}\u{BB7}", 2, 2),
            ("tamil_shri", "\u{BB8}\u{BCD}\u{BB0}\u{BC0}", 2, 2),
            ("kannada_ksha", "\u{C95}\u{CCD}\u{CB7}", 2, 2),
            ("khmer_kaka", "\u{1780}\u{17D2}\u{1780}", 2, 2),
            ("arabic_lam_alef_spelled", "\u{644}\u{627}", 2, 2),
          ])
    func outsideTheLinkerSet(name: String, text: String, clusters: Int, width: Int) {
        TerminalWidthTraits.withTraits(.composing) {
            #expect(text.count == clusters, "\(name): \(text.count) clusters")
            #expect(text.strippedLength == width, "\(name): \(text.strippedLength) cells")
        }
    }

    // MARK: - What it costs a whole word

    /// The divergence at the scale it is actually seen: `राष्ट्र` is two clusters
    /// — `रा` (base + matra, both rules 2) and `ष्ट्र` (three consonants, cluster
    /// rule 2, per-scalar 3) — so the word claims four cells while its scalars
    /// price five.
    ///
    /// Whichever number is right, every column after this word on a row is
    /// placed by the claim, so a wrong claim shears the rest of the row by one
    /// cell per such cluster and clips a truncation one cell late.
    @Test("A word of two conjunct clusters carries the divergence")
    func wordCarriesTheDivergence() {
        let word = "\u{930}\u{93E}\u{937}\u{94D}\u{91F}\u{94D}\u{930}"  // राष्ट्र
        TerminalWidthTraits.withTraits(.composing) {
            #expect(word.count == 2)
            let perScalar = word.unicodeScalars.reduce(0) { $0 + $1.loneTerminalWidth }
            #expect(perScalar == 5)
            withKnownIssue(
                """
                राष्ट्र claims 4 cells (रा 2 + ष्ट्र 2) against a per-scalar 5. Measure \
                `conjunct_deva_shtra` before changing either number.
                """,
                isIntermittent: false
            ) {
                #expect(word.strippedLength == perScalar)
            }
            #expect(word.strippedLength == 4, "the claim the layout uses today")
        }
    }
}
