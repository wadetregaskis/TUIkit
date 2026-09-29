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
import sys
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


class TestMachineLock(unittest.TestCase):
    # flock belongs to an open file, not to a process, so two opens in this
    # one process contend exactly as two runs would.
    def test_a_second_run_waits_for_the_first(self):
        import fcntl
        import io
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "lock")
            first = pt.machine_lock(path, out=io.StringIO())
            with open(path, "a+") as other:
                with self.assertRaises(BlockingIOError):
                    fcntl.flock(other, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with open(path) as fh:
                self.assertIn("pid %d" % os.getpid(), fh.read())
            first.close()
            second = pt.machine_lock(path, out=io.StringIO())
            self.assertIsNotNone(second)
            second.close()

    def test_a_waiting_run_names_the_holder(self):
        import io
        import threading
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "lock")
            first = pt.machine_lock(path, out=io.StringIO())
            said = io.StringIO()
            waiter = threading.Thread(target=lambda: pt.machine_lock(path, out=said).close())
            waiter.start()
            waiter.join(0.5)
            self.assertTrue(waiter.is_alive(), "the second run did not wait")
            first.close()
            waiter.join(5)
            self.assertFalse(waiter.is_alive())
            self.assertIn("waiting for pid %d" % os.getpid(), said.getvalue())


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


class TestSwiftCommand(unittest.TestCase):
    def test_default_is_the_swift_on_path(self):
        self.assertEqual(pt.swift_command({}), ["swift"])
        self.assertEqual(pt.swift_command({"SWIFT": ""}), ["swift"])

    def test_ci_spelling_of_a_swift_org_toolchain(self):
        # What the macOS lanes write to $GITHUB_ENV for a swift.org toolchain.
        self.assertEqual(
            pt.swift_command({"SWIFT": "xcrun --toolchain org.swift.640202609131a swift"}),
            ["xcrun", "--toolchain", "org.swift.640202609131a", "swift"])


class TestDarwinTestEnv(unittest.TestCase):
    """The layouts are real ones, transcribed from this machine: swiftly's
    swift.org toolchains, Xcode 26.3, and the Command Line Tools."""

    SWIFTORG = "/U/Library/Developer/Toolchains/swift-6.2.4-RELEASE.xctoolchain"
    XCODE_TC = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain"
    PLATFORM = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform"
    CLT = "/Library/Developer/CommandLineTools"

    def env(self, root, present, platform=None, environ=None):
        exists = lambda p: p in present
        return pt.darwin_test_env(root + "/usr/lib/swift", environ or {}, platform, exists)

    def test_swift_org_toolchain_under_the_command_line_tools_is_unchanged(self):
        # The local swiftly workflow: xcrun finds no platform, so the one
        # variable is the toolchain's testing directory — exactly what the
        # harness always set.
        lib = self.SWIFTORG + "/usr/lib/swift/macosx/testing"
        env, found = self.env(self.SWIFTORG, {lib})
        self.assertEqual(env, {"DYLD_LIBRARY_PATH": lib})
        self.assertEqual(found, [lib])

    def test_swift_org_toolchain_with_xcode_selected_loads_its_own_testing_first(self):
        # CI's swift.org lanes. The platform goes AFTER the toolchain's own
        # swift-testing, or Xcode's Testing.framework would shadow it.
        lib = self.SWIFTORG + "/usr/lib/swift/macosx/testing"
        env, found = self.env(self.SWIFTORG, {lib}, self.PLATFORM)
        dev = self.PLATFORM + "/Developer"
        self.assertEqual(env["DYLD_LIBRARY_PATH"], lib + ":" + dev + "/usr/lib")
        self.assertEqual(env["DYLD_FRAMEWORK_PATH"],
                         dev + "/Library/Frameworks:" + dev + "/Library/PrivateFrameworks")
        self.assertEqual(found, [lib])

    def test_xcode_finds_testing_in_the_platform(self):
        dev = self.PLATFORM + "/Developer"
        fw = dev + "/Library/Frameworks"
        env, found = self.env(self.XCODE_TC, {fw + "/Testing.framework"}, self.PLATFORM)
        self.assertEqual(env, {
            "DYLD_FRAMEWORK_PATH": fw + ":" + dev + "/Library/PrivateFrameworks",
            "DYLD_LIBRARY_PATH": dev + "/usr/lib"})
        self.assertEqual(found, [fw])

    def test_command_line_tools_use_their_frameworks_directory(self):
        fw = self.CLT + "/Library/Developer/Frameworks"
        env, found = self.env(self.CLT, {fw + "/Testing.framework"})
        self.assertEqual(env, {"DYLD_FRAMEWORK_PATH": fw,
                               "DYLD_LIBRARY_PATH": self.CLT + "/Library/Developer/usr/lib"})
        self.assertEqual(found, [fw])

    def test_the_frameworks_directory_wins_when_both_exist(self):
        # SwiftPM's `deriveSwiftTestingPath` returns the first it finds; it
        # never puts two copies of swift-testing on the search paths.
        fw = self.CLT + "/Library/Developer/Frameworks"
        lib = self.CLT + "/usr/lib/swift/macosx/testing"
        env, found = self.env(self.CLT, {fw + "/Testing.framework", lib})
        self.assertNotIn(lib, env["DYLD_LIBRARY_PATH"])
        self.assertEqual(found, [fw])

    def test_a_users_own_setting_comes_first(self):
        lib = self.SWIFTORG + "/usr/lib/swift/macosx/testing"
        env, _ = self.env(self.SWIFTORG, {lib}, environ={"DYLD_LIBRARY_PATH": "/mine"})
        self.assertEqual(env["DYLD_LIBRARY_PATH"], "/mine:" + lib)

    def test_nothing_found_is_reported_as_nothing(self):
        _, found = self.env(self.XCODE_TC, set())
        self.assertEqual(found, [])


class TestSdkPlatformPath(unittest.TestCase):
    class Out(object):
        def __init__(self, rc, stdout):
            self.returncode, self.stdout = rc, stdout

    def test_the_override_wins_without_asking_xcrun(self):
        def run(*a, **k):
            raise AssertionError("xcrun should not run")
        self.assertEqual(pt.sdk_platform_path({"SWIFTPM_PLATFORM_PATH_macosx": "/P"}, run), "/P")

    def test_xcrun_answer(self):
        run = lambda *a, **k: self.Out(0, "/X/MacOSX.platform\n")
        self.assertEqual(pt.sdk_platform_path({}, run), "/X/MacOSX.platform")

    def test_command_line_tools_have_no_platform(self):
        run = lambda *a, **k: self.Out(1, "")
        self.assertIsNone(pt.sdk_platform_path({}, run))

    def test_no_xcrun_at_all(self):
        def run(*a, **k):
            raise FileNotFoundError("/usr/bin/xcrun")
        self.assertIsNone(pt.sdk_platform_path({}, run))


class TestTestBinaries(unittest.TestCase):
    def touch(self, path, mode=0o755):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as fh:
            fh.write("")
        os.chmod(path, mode)

    def test_native_macos_is_one_bundle(self):
        with tempfile.TemporaryDirectory() as d:
            self.touch(os.path.join(d, "PkgPackageTests.xctest/Contents/MacOS/PkgPackageTests"))
            self.assertEqual(pt.test_binaries(d, True), {
                "PkgPackageTests":
                    os.path.join(d, "PkgPackageTests.xctest/Contents/MacOS/PkgPackageTests")})

    def test_swift_build_on_macos_is_one_bundle_per_test_target(self):
        with tempfile.TemporaryDirectory() as d:
            for n in ("ATests", "BTests"):
                self.touch(os.path.join(d, "%s.xctest/Contents/MacOS/%s" % (n, n)))
            self.touch(os.path.join(d, "A.o"))
            self.assertEqual(sorted(pt.test_binaries(d, True)), ["ATests", "BTests"])

    def test_native_linux_is_one_executable_file(self):
        with tempfile.TemporaryDirectory() as d:
            self.touch(os.path.join(d, "PkgPackageTests.xctest"))
            self.assertEqual(pt.test_binaries(d, False), {
                "PkgPackageTests": os.path.join(d, "PkgPackageTests.xctest")})

    def test_swift_build_on_linux_runs_the_launchers(self):
        with tempfile.TemporaryDirectory() as d:
            for n in ("ATests", "BTests"):
                self.touch(os.path.join(d, n + "-test-runner"))
                self.touch(os.path.join(d, n + ".so"))
            self.touch(os.path.join(d, "PkgPackageTests.xctest"))  # stale native build
            self.assertEqual(pt.test_binaries(d, False), {
                "ATests": os.path.join(d, "ATests-test-runner"),
                "BTests": os.path.join(d, "BTests-test-runner")})

    def test_no_binary_is_an_error_not_an_empty_run(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(SystemExit):
                pt.test_binaries(d, True)
            with self.assertRaises(SystemExit):
                pt.test_binaries(os.path.join(d, "absent"), False)


class TestCommandLine(unittest.TestCase):
    def test_macos_goes_through_the_helper_as_before(self):
        tc = pt.Toolchain("/tc/helper", {}, True, "")
        self.assertEqual(
            pt.test_cmd(tc, "/b/T", "^(?:A/)", xunit="/o.xml", events="/o.jsonl"),
            ["/tc/helper", "--test-bundle-path", "/b/T", "/b/T",
             "--testing-library", "swift-testing", "--filter", "^(?:A/)",
             "--xunit-output", "/o.xml",
             "--event-stream-output-path", "/o.jsonl", "--event-stream-version", "0"])

    def test_linux_runs_the_binary_with_the_library_flag_last(self):
        tc = pt.Toolchain(None, {}, False, "")
        self.assertEqual(
            pt.test_cmd(tc, "/b/T.xctest", "^(?:A/)", serial=True),
            ["/b/T.xctest", "--filter", "^(?:A/)", "--no-parallel",
             "--testing-library", "swift-testing"])
        self.assertEqual(pt.test_cmd(tc, "/b/T.xctest", None, extra=["--list-tests"]),
                         ["/b/T.xctest", "--list-tests", "--testing-library", "swift-testing"])


class TestPlan(unittest.TestCase):
    def test_one_binary_is_one_invocation_per_group(self):
        owner = {"M.A/a()": "P", "M.A/b()": "P", "M.B/c()": "P"}
        pats = [pt.group_pattern([("suite", "M.A")]), pt.group_pattern([("suite", "M.B")])]
        plan = pt.plan_invocations(pats, owner, {"P": "/p"})
        self.assertEqual([(i["tag"], i["selected"]) for i in plan], [("g0", 2), ("g1", 1)])

    def test_a_group_spanning_binaries_is_split_and_nothing_is_run_twice(self):
        owner = {"X.A/a()": "XTests", "X.A/b()": "XTests",
                 "Y.B/c()": "YTests", "Z.C/d()": "ZTests"}
        pats = [pt.group_pattern([("suite", "X.A"), ("suite", "Y.B")]),
                pt.group_pattern([("suite", "Z.C")])]
        bins = {"XTests": "/x", "YTests": "/y", "ZTests": "/z"}
        plan = pt.plan_invocations(pats, owner, bins)
        self.assertEqual([(i["tag"], i["group"], i["selected"]) for i in plan],
                         [("g0-XTests", 0, 2), ("g0-YTests", 0, 1), ("g1-ZTests", 1, 1)])
        self.assertEqual(sum(i["selected"] for i in plan), len(owner))


class TestRunProcesses(unittest.TestCase):
    """A slot's invocations run one after another; slots run at once."""

    def setUp(self):
        self._work = pt.WORK
        self._tmp = tempfile.TemporaryDirectory()
        pt.WORK = self._tmp.name

    def tearDown(self):
        pt.WORK = self._work
        self._tmp.cleanup()

    def stamp(self, tag, slot, code=0):
        prog = ("import time, sys; print(time.time()); sys.stdout.flush(); "
                "time.sleep(0.3); print(time.time()); sys.exit(%d)" % code)
        return {"tag": tag, "slot": slot, "cmd": [sys.executable, "-c", prog]}

    def times(self, r):
        with open(r["log"]) as fh:
            return [float(x) for x in fh.read().split()]

    def test_chained_in_a_slot_and_concurrent_across_slots(self):
        tc = pt.Toolchain(None, {}, False, "")
        invs = [self.stamp("a1", 0), self.stamp("a2", 0, code=3), self.stamp("b1", 1)]
        done, _ = pt.run_processes(invs, tc, lambda i: i["slot"])
        by = {r["tag"]: r for r in done}
        self.assertEqual(sorted(by), ["a1", "a2", "b1"])
        a1, a2, b1 = (self.times(by[t]) for t in ("a1", "a2", "b1"))
        self.assertGreaterEqual(a2[0], a1[1], "slot 0 ran its two invocations at once")
        self.assertLess(b1[0], a1[1], "slot 1 waited for slot 0")
        self.assertEqual((by["a1"]["rc"], by["a2"]["rc"]), (0, 3))


class TestFailureExcerpt(unittest.TestCase):
    # Linux, verbatim from CI job 109198918461 (Swift 6.4), less the timestamps.
    LINUX = "\n".join([
        '✔ Suite "Indeterminate configuration" passed after 30.502 seconds.',
        '✘ Test "Deciding the bar" recorded an issue at ScrollbarFirstRoundTests.swift:236:9: '
        'Expectation failed: hundredThousand == tenThousand',
        '↳ deciding the bar cost 37 lookups over 100,000 rows, 11 over 10,000',
        '  10000 rows — decided: 38 hits, 97 misses, 0 rows measured',
        '↳ hundredThousand == tenThousand → false',
        '↳   hundredThousand → 37',
        '✔ Test "A closed picker lets Tab propagate for focus navigation" passed after 36.471 seconds.',
        '✘ Test "Deciding the bar" failed after 424.937 seconds with 1 issue.',
    ])
    # macOS 6.2.4, from a probe package: SF Symbols in the private-use area.
    MACOS = "\n".join([
        "\U00100884  Test bad() recorded an issue at F.swift:3:40: Expectation failed: (a → 1) == (b → 2)",
        "\U00100135  why",
        "     second line",
        "\U00100883  Test known() recorded a known issue at F.swift:4:41: Expectation failed: Bool(false)",
        "\U00100884  Test bad() failed after 0.001 seconds with 1 issue.",
    ])

    def test_linux_issue_and_its_details(self):
        got = pt.failure_excerpt(self.LINUX)
        self.assertEqual(len(got), 5)
        self.assertIn("recorded an issue", got[0])
        self.assertTrue(got[-1].startswith("↳   hundredThousand"))

    def test_macos_issue_and_its_details_but_not_the_known_issue(self):
        got = pt.failure_excerpt(self.MACOS)
        self.assertEqual(got, self.MACOS.splitlines()[:3])

    def test_a_detail_that_starts_with_the_word_test_is_still_a_detail(self):
        text = "✘ Test t() recorded an issue at A.swift:1:1: x\n↳ Test value → 3\n✔ Test u() passed"
        self.assertEqual(len(pt.failure_excerpt(text)), 2)

    def test_a_passing_log_has_nothing_to_show(self):
        self.assertEqual(pt.failure_excerpt("✔ Test a() passed after 0.1 seconds.\n"), [])


class TestReportFailingLogs(unittest.TestCase):
    def proc(self, d, tag, text, rc, summary):
        log = os.path.join(d, tag + ".log")
        with open(log, "w") as fh:
            fh.write(text)
        return {"tag": tag, "binary": "B", "log": log, "rc": rc, "summary": summary}

    def test_only_failing_processes_are_shown_and_a_crash_shows_its_tail(self):
        import io
        from unittest import mock
        ok = {"passed": True}
        with tempfile.TemporaryDirectory() as d:
            procs = [self.proc(d, "g0", "✔ Test a() passed\n", 0, ok),
                     self.proc(d, "g1", TestFailureExcerpt.LINUX, 1, {"passed": False}),
                     self.proc(d, "g2", "line 1\nFatal error: boom\n", -11, None)]
            out = io.StringIO()
            with mock.patch.dict(os.environ, {"GITHUB_ACTIONS": "true"}):
                pt.report_failing_logs(procs, {"g1": {"M.S/t()"}}, True, out)
            text = out.getvalue()
        self.assertNotIn("── g0", text)
        self.assertIn("── g1 (B, exit 1) ──", text)
        self.assertIn("recorded an issue", text)
        self.assertIn("── g2 (B, killed by signal 11) ──", text)
        self.assertIn("Fatal error: boom", text)
        self.assertEqual(text.count("::group::"), 2)
        self.assertEqual(text.count("::endgroup::"), 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
