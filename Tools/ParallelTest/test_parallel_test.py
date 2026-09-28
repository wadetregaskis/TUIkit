#!/usr/bin/env python3
"""
Unit tests for the parallel test harness's pure functions.

    python3 Tools/ParallelTest/test_parallel_test.py

The harness's value is entirely in refusing to report a green run it cannot
prove, so the cases that matter here are the ones where a partition LOOKS fine
and is not: a suite name that is a prefix of another, a parameterised test that
is a prefix of another, a regex metacharacter in an ID, and the summary line a
FAILING run writes (whose different wording made an earlier analysis read 13
known issues out of runs that had 21).
"""

import importlib.util
import os
import tempfile
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
_SPEC = importlib.util.spec_from_file_location(
    "parallel_test", os.path.join(_HERE, "parallel_test.py"))
pt = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(pt)


class TestIdentifiers(unittest.TestCase):
    def test_suite_of(self):
        self.assertEqual(pt.suite_of("Mod.SuiteTests/testThing()"), "Mod.SuiteTests")
        self.assertEqual(pt.suite_of("Mod.Outer.Inner/t()"), "Mod.Outer.Inner")

    def test_strip_source_location(self):
        self.assertEqual(
            pt.strip_source_location("M.S/projectedValue()/Bindable.swift:41:6"),
            "M.S/projectedValue()")
        # Already stripped, or an ID that merely mentions .swift, is untouched.
        self.assertEqual(pt.strip_source_location("M.S/t()"), "M.S/t()")

    def test_escape_leaves_colon_and_slash_literal(self):
        # Swift's Regex rejects unknown escapes, and Python's own re.escape
        # would emit backslashes for characters Swift does not expect.
        self.assertEqual(pt.escape_regex("M.S/foo(_:)"), r"M\.S\/foo\(_:\)")


class TestPatterns(unittest.TestCase):
    def sel(self, pattern, ids):
        import re
        rx = re.compile(pattern)
        return {i for i in ids if rx.search(i)}

    def test_suite_pattern_does_not_take_a_longer_sibling(self):
        ids = {"M.MenuTests/a()", "M.MenuTestsExtra/b()", "M.MenuTests/c()"}
        got = self.sel(pt.pattern_for_suite("M.MenuTests"), ids)
        self.assertEqual(got, {"M.MenuTests/a()", "M.MenuTests/c()"})

    def test_test_pattern_does_not_take_a_longer_sibling(self):
        ids = {"M.S/foo()", "M.S/fooBar()", "M.S/foo(_:)", "M.S/foo(_:_:)"}
        self.assertEqual(self.sel(pt.pattern_for_test("M.S/foo()"), ids),
                         {"M.S/foo()"})
        self.assertEqual(self.sel(pt.pattern_for_test("M.S/foo(_:)"), ids),
                         {"M.S/foo(_:)"})

    def test_test_pattern_matches_the_source_located_spelling(self):
        # The runtime may present an ID with its declaration site appended.
        ids = {"M.S/foo()/S.swift:10:3"}
        self.assertEqual(self.sel(pt.pattern_for_test("M.S/foo()"), ids), ids)

    def test_group_pattern_is_the_union_of_its_keys(self):
        ids = {"M.A/x()", "M.A/y()", "M.B/z()", "M.C/w()"}
        pat = pt.group_pattern([("suite", "M.A"), ("test", "M.C/w()")])
        self.assertEqual(self.sel(pat, ids), {"M.A/x()", "M.A/y()", "M.C/w()"})


class TestSelection(unittest.TestCase):
    IDS = ["M.A/a()", "M.A/b()", "M.B/c()"]

    def test_no_filter_keeps_everything(self):
        self.assertEqual(select_all := pt.select_ids(self.IDS, None), self.IDS)
        self.assertEqual(pt.select_ids(self.IDS, ""), select_all)

    def test_a_filter_narrows_the_enumeration(self):
        # The helper's own --list-tests ignores --filter and returns the whole
        # suite, so a filtered run MUST be narrowed here or it runs everything.
        self.assertEqual(pt.select_ids(self.IDS, r"^M\.A/"), ["M.A/a()", "M.A/b()"])

    def test_a_filter_matching_nothing_selects_nothing(self):
        self.assertEqual(pt.select_ids(self.IDS, "NoSuchSuite"), [])


class TestProof(unittest.TestCase):
    IDS = ["M.A/a%d()" % i for i in range(5)] + \
          ["M.B/b%d()" % i for i in range(3)] + ["M.BB/c()"]

    def test_exact_partition_is_accepted(self):
        pats = [pt.group_pattern([("suite", "M.A")]),
                pt.group_pattern([("suite", "M.B"), ("suite", "M.BB")])]
        proof = pt.prove(pats, self.IDS)
        self.assertTrue(proof["exact"])
        self.assertEqual(proof["counts"], [5, 4])
        self.assertEqual(proof["union"], 9)

    def test_a_missing_suite_is_caught(self):
        proof = pt.prove([pt.group_pattern([("suite", "M.A")])], self.IDS)
        self.assertFalse(proof["exact"])
        self.assertEqual(len(proof["missing"]), 4)

    def test_an_overlap_is_caught(self):
        # 'M.B' as a bare prefix would also swallow M.BB — the failure mode the
        # anchored '/' terminator exists to prevent. Simulate it directly.
        proof = pt.prove(["^M\\.B", pt.group_pattern([("suite", "M.BB")])], self.IDS)
        self.assertFalse(proof["exact"])
        self.assertEqual(proof["dupes"], ["M.BB/c()"])


class TestPacking(unittest.TestCase):
    def test_lpt_balances_and_keeps_everything(self):
        items = [(("suite", "S%d" % i), float(i)) for i in range(1, 9)]
        bins, loads = pt.lpt(items, 3)
        self.assertEqual(sum(len(b) for b in bins), 8)
        self.assertAlmostEqual(sum(loads), 36.0)
        self.assertLess(max(loads) - min(loads), 8.0)

    def test_a_heavy_suite_is_split_by_test(self):
        ids = ["M.Heavy/h%d()" % i for i in range(4)] + \
              ["M.Light/l%d()" % i for i in range(4)]
        weights = {t: (10.0 if "Heavy" in t else 0.1) for t in ids}
        items, split, total = pt.build_items(ids, weights, 4)
        self.assertEqual(split, ["M.Heavy"])
        self.assertIn((("test", "M.Heavy/h0()"), 10.0), items)
        self.assertIn((("suite", "M.Light"), 0.4), items)
        self.assertAlmostEqual(total, 40.4)

    def test_a_light_suite_stays_whole(self):
        ids = ["M.A/a%d()" % i for i in range(3)]
        weights = {t: 1.0 for t in ids}
        items, split, _ = pt.build_items(ids, weights, 1)
        self.assertEqual(split, [])
        self.assertEqual(items, [(("suite", "M.A"), 3.0)])

    def test_partition_of_a_realistic_shape_is_provably_exact(self):
        ids = ["M.S%02d/t%02d()" % (s, t) for s in range(20) for t in range(5)]
        ids += ["M.S00/t%02d(_:)" % t for t in range(3)]  # parameterised siblings
        weights = {t: (5.0 if t.startswith("M.S00/") else 0.01) for t in ids}
        items, _, _ = pt.build_items(ids, weights, 4)
        bins, _ = pt.lpt(items, 4)
        proof = pt.prove([pt.group_pattern(b) for b in bins], ids)
        self.assertTrue(proof["exact"], proof["missing"][:3] + proof["dupes"][:3])
        self.assertEqual(sum(proof["counts"]), len(ids))


class TestSummaryParsing(unittest.TestCase):
    def test_passing_run_with_known_issues(self):
        got = pt.parse_summary_text(
            "Test run with 7573 tests in 1081 suites passed after "
            "51.647 seconds with 21 known issues.")
        self.assertEqual((got["tests"], got["suites"], got["known"], got["passed"]),
                         (7573, 1081, 21, True))

    def test_failing_run_rewords_the_known_issue_clause(self):
        got = pt.parse_summary_text(
            "Test run with 7573 tests in 1081 suites failed after "
            "55.050 seconds with 22 issues (including 21 known issues).")
        self.assertEqual(got["known"], 21)
        self.assertFalse(got["passed"])

    def test_no_known_issues_at_all(self):
        got = pt.parse_summary_text(
            "Test run with 51 tests in 11 suites passed after 0.004 seconds.")
        self.assertEqual(got["known"], 0)
        self.assertTrue(got["passed"])

    def test_singular_wording(self):
        got = pt.parse_summary_text(
            "Test run with 1 test in 1 suite passed after 0.1 seconds "
            "with 1 known issue.")
        self.assertEqual((got["tests"], got["suites"], got["known"]), (1, 1, 1))

    def test_the_last_line_wins(self):
        # A per-test line mentioning a known issue must not be read as the total.
        text = ('Test "x" recorded a known issue.\n'
                "Test run with 10 tests in 2 suites passed after 1.0 seconds "
                "with 5 known issues.\n")
        self.assertEqual(pt.parse_summary_text(text)["known"], 5)

    def test_no_summary_at_all(self):
        self.assertIsNone(pt.parse_summary_text("error: database is locked\n"))

    # The clause after "seconds" comes from a three-way switch on (any error,
    # any warning, any known issue). These eight are the literal output of a
    # probe package run against the toolchains — 6.2.4 for the four without a
    # warning, 6.3.3 for the four with one (6.2.4 has no Issue.Severity) — not
    # transcribed from upstream source. Five of the eight did not parse before.
    SHAPES = [
        ("passed", "", 0),
        ("passed", " with 3 known issues", 3),
        ("passed", " with 2 warnings", 0),
        ("passed", " with 2 warnings and 3 known issues", 3),
        ("failed", " with 1 issue", 0),
        ("failed", " with 5 issues (including 3 known issues)", 3),
        ("failed", " with 5 issues (including 3 warnings)", 0),
        ("failed", " with 9 issues (including 3 warnings and 4 known issues)", 4),
    ]

    def test_every_clause_shape_parses(self):
        for verdict, clause, known in self.SHAPES:
            # The \U0010105b prefix is the status glyph a real harness log
            # carries, kept so the match stays unanchored.
            line = ("\U0010105b Test run with 3 tests in 0 suites %s after "
                    "0.001 seconds%s." % (verdict, clause))
            got = pt.parse_summary_text(line)
            self.assertIsNotNone(got, "did not parse: %r" % clause)
            self.assertEqual(
                (got["tests"], got["suites"], got["passed"], got["known"]),
                (3, 0, verdict == "passed", known), "clause %r" % clause)

    def test_singular_clause_wordings_parse(self):
        # Every count in SHAPES is plural; the singular spellings differ.
        for clause, known in ((" with 1 known issue", 1),
                              (" with 1 warning", 0),
                              (" with 1 warning and 1 known issue", 1),
                              (" with 1 issue", 0),
                              (" with 2 issues (including 1 known issue)", 1),
                              (" with 2 issues (including 1 warning)", 0),
                              (" with 3 issues (including 1 warning and 1 known issue)", 1)):
            got = pt.parse_summary_text(
                "Test run with 1 test in 1 suite failed after 0.1 seconds%s." % clause)
            self.assertIsNotNone(got, "did not parse: %r" % clause)
            self.assertEqual(got["known"], known, "clause %r" % clause)

    def test_a_failing_group_is_not_mistaken_for_a_dead_one(self):
        # The regression this pins: a group that fails with no known issues of
        # its own. Reported as "produced no summary line" — indistinguishable
        # from a hung or build-lock-starved process — on exactly the group
        # holding the real failure.
        got = pt.parse_summary_text(
            "Test run with 631 tests in 90 suites failed after 12.5 seconds "
            "with 1 issue.")
        self.assertIsNotNone(got)
        self.assertEqual((got["tests"], got["passed"], got["known"]),
                         (631, False, 0))

    def test_a_dead_group_still_reads_as_dead(self):
        # The permissive clause must not turn absence of a summary into one.
        # A parse here would cost the gate its only sight of a process that
        # died having run nothing (trap 1) — worse than the bug above.
        for text in ("",
                     "error: database is locked\n",
                     "\U0010105b Test run started.\n",
                     # per-test lines only: same verbs and clauses, no total
                     "Test knownIssues() passed after 0.001 seconds with 1 known issue.\n"
                     "Test errorIssues() failed after 0.001 seconds with 2 issues.\n",
                     # killed mid-line, before the seconds and before the period
                     "Test run with 100 tests in 10 suites failed after 1.2 seco",
                     "Test run with 100 tests in 10 suites failed after 1.2 seconds "
                     "with 1 issue"):
            self.assertIsNone(pt.parse_summary_text(text), repr(text))

    def test_an_unrecognised_clause_costs_the_count_not_the_line(self):
        # If upstream ever rewords the clause, the line must still parse (so a
        # failing group is not reported as dead); the known count silently
        # reads 0, and --expect-known-issues is the cross-check for that.
        got = pt.parse_summary_text(
            "Test run with 7591 tests in 1082 suites failed after 51.6 seconds "
            "with 4 problems (21 of them anticipated).")
        self.assertIsNotNone(got)
        self.assertEqual((got["tests"], got["passed"], got["known"]),
                         (7591, False, 0))


class TestXunit(unittest.TestCase):
    XML = """<?xml version="1.0" encoding="UTF-8"?>
<testsuites><testsuite name="TestResults" tests="3">
 <testcase classname="M.A" name="ok()" time="1.0" />
 <testcase classname="M.A" name="bad()" time="1.0"><failure message="nope"/></testcase>
 <testcase classname="M.B" name="err()" time="1.0"><error message="boom"/></testcase>
</testsuite></testsuites>"""

    def test_ids_and_failures(self):
        with tempfile.NamedTemporaryFile("w", suffix=".xml", delete=False) as fh:
            fh.write(self.XML)
            path = fh.name
        try:
            ids, failed, n = pt.parse_xunit(path)
            self.assertEqual(n, 3)
            self.assertEqual(ids, {"M.A/ok()", "M.A/bad()", "M.B/err()"})
            self.assertEqual(failed, {"M.A/bad()", "M.B/err()"})
        finally:
            os.unlink(path)

    def test_an_ansi_escape_in_a_failure_message_is_still_readable(self):
        # A failing expectation in this package quotes ANSI escapes, so the
        # message carries a raw 0x1b — illegal in XML 1.0. The xunit of a
        # FAILING run is therefore malformed, and that is the one file the
        # reconciliation gate cannot do without.
        xml = ('<?xml version="1.0" encoding="UTF-8"?>\n<testsuites><testsuite>'
               '<testcase classname="M.A" name="esc()">'
               '<failure message="got \x1b[48;2;25;27;36m" /></testcase>'
               '<testcase classname="M.A" name="fine()" /></testsuite></testsuites>')
        with tempfile.NamedTemporaryFile("w", suffix=".xml", delete=False,
                                         encoding="utf-8") as fh:
            fh.write(xml)
            path = fh.name
        try:
            ids, failed, n = pt.parse_xunit(path)
            self.assertEqual(n, 2)
            self.assertEqual(ids, {"M.A/esc()", "M.A/fine()"})
            self.assertEqual(failed, {"M.A/esc()"})
        finally:
            os.unlink(path)

    def test_unsalvageable_xml_raises_rather_than_reporting_nothing(self):
        with tempfile.NamedTemporaryFile("w", suffix=".xml", delete=False) as fh:
            fh.write("<testsuites><testcase classname=")
            path = fh.name
        try:
            with self.assertRaises(pt.XunitError):
                pt.parse_xunit(path)
        finally:
            os.unlink(path)

    def test_a_missing_file_is_empty_not_an_error(self):
        # A process killed before writing must read as "ran nothing", so the
        # union check fails loudly instead of the parse throwing.
        ids, failed, n = pt.parse_xunit("/nonexistent/none.xml")
        self.assertEqual((ids, failed, n), (set(), set(), 0))


class TestEventStream(unittest.TestCase):
    STREAM = "\n".join([
        '{"kind":"test","payload":{"id":"M.A","kind":"suite"},"version":0}',
        '{"kind":"event","payload":{"kind":"testStarted","testID":"M.A",'
        '"instant":{"absolute":100.0}},"version":0}',
        '{"kind":"event","payload":{"kind":"testStarted",'
        '"testID":"M.A/t()/A.swift:1:1","instant":{"absolute":100.5}},"version":0}',
        '{"kind":"event","payload":{"kind":"testEnded",'
        '"testID":"M.A/t()/A.swift:1:1","instant":{"absolute":102.0}},"version":0}',
        '{"kind":"event","payload":{"kind":"testEnded","testID":"M.A",'
        '"instant":{"absolute":103.0}},"version":0}',
        "",
    ])

    def test_durations_join_to_list_ids_and_exclude_suites(self):
        with tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False) as fh:
            fh.write(self.STREAM)
            path = fh.name
        try:
            d = pt.durations_from_event_stream(path)
            self.assertEqual(list(d), ["M.A/t()"])
            self.assertAlmostEqual(d["M.A/t()"], 1.5)
        finally:
            os.unlink(path)

    def test_peak_concurrency(self):
        # The guard that tells a serial calibration from a contended one.
        with tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False) as fh:
            fh.write(self.STREAM)
            path = fh.name
        try:
            self.assertEqual(pt.peak_concurrency(path), 1)
        finally:
            os.unlink(path)


class TestWeights(unittest.TestCase):
    def test_unknown_tests_get_the_median(self):
        weights = {"M.A/a()": 1.0, "M.A/b()": 3.0, "M.A/c()": 5.0}
        filled, unweighted = pt.fill_weights(
            ["M.A/a()", "M.A/b()", "M.A/c()", "M.NEW/d()"], weights)
        self.assertEqual(unweighted, 1)
        self.assertEqual(filled["M.NEW/d()"], 3.0)

    def test_no_cache_means_equal_weights(self):
        filled, unweighted = pt.fill_weights(["M.A/a()", "M.B/b()"], {})
        self.assertEqual(unweighted, 2)
        self.assertEqual(set(filled.values()), {1.0})

    def test_the_pieces_of_a_split_test_share_its_recorded_work(self):
        # One 40 s test split into four: the cache knows only the old name.
        weights = {"M.Slow/all(_:)": 40.0, "M.A/a()": 1.0, "M.A/b()": 1.0}
        ids = ["M.A/a()", "M.A/b()"] + ["M.Slow/piece%d()" % i for i in range(4)]
        filled, unweighted = pt.fill_weights(ids, weights)
        self.assertEqual(unweighted, 4)
        self.assertEqual([filled["M.Slow/piece%d()" % i] for i in range(4)], [10.0] * 4)
        # And the partition deals them out instead of stacking them.
        items, _, _ = pt.build_items(ids, filled, 4)
        bins, _ = pt.lpt(items, 4)
        per_bin = [sum(1 for kind, key in b if kind == "test" and key.startswith("M.Slow/")) for b in bins]
        self.assertEqual(sorted(per_bin), [1, 1, 1, 1])

    def test_lost_work_never_prices_a_piece_below_the_median(self):
        weights = {"M.A/a()": 2.0, "M.A/b()": 2.0, "M.A/c()": 2.0, "M.S/old()": 0.5}
        filled, _ = pt.fill_weights(["M.A/a()", "M.A/b()", "M.A/c()", "M.S/n1()", "M.S/n2()"], weights)
        self.assertEqual(filled["M.S/n1()"], 2.0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
