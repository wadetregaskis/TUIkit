#!/usr/bin/env python3
"""
Tests for `drive.py`, the Mode-B PTY driver.

    python3 Tools/Profiling/test_drive.py

The driven binary is a stub that reports what it was launched with, so these
need no build and no Instruments: they are about what `drive.py` hands the
app, not about the app. The exception is `TestTourStaysOnItsRoute`, which is
about where the `tour`'s keys land in the real Example, drives a built one
(`.build/debug/Example`, or `$DRIVE_TEST_BINARY`), and is skipped without it.

What they guard is where the app's persisted state goes. `record.sh` — the
profiling flow CLAUDE.md sends everyone through — runs `drive.py`, and a
TUIkit app writes its `@AppStorage` wherever `TUIKIT_CONFIG_DIR` says, or,
with it unset on macOS, into the user's real preferences domain
(`~/Library/Preferences/Example.plist`; UserDefaults ignores a `$HOME`
override, so nothing short of the variable isolates it). The driver passed
its own environment straight through, so a profiling run read and wrote the
developer's own settings — and what it wrote was page shortcuts typed into
the Sliders page's track editor, which is how a Fill of `■];q];-=s.m1`
reached the owner's screen.
"""

import base64
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
_DRIVE = os.path.join(_HERE, "drive.py")

# The stand-in app. It records the configuration directory it was given —
# and whether that directory existed — then writes a setting into it the way
# `JSONFileStorage` would, and runs until the driver's closing `q`, so the run
# ends the way a real one does rather than by the driver killing it.
_STUB = """\
import json, os, sys, tty
config = os.environ.get("TUIKIT_CONFIG_DIR", "")
with open(os.environ["DRIVE_TEST_REPORT"], "w") as report:
    json.dump({"config": config, "existed": bool(config) and os.path.isdir(config)}, report)
if config:
    os.makedirs(os.path.join(config, "Example"), exist_ok=True)
    with open(os.path.join(config, "Example", "settings.json"), "w") as settings:
        settings.write("{}")
tty.setraw(0)
while True:
    data = os.read(0, 4096)
    if not data or b"q" in data:
        break
"""


class TestConfigIsolation(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.mkdtemp(prefix="test-drive-")
        self.addCleanup(shutil.rmtree, self.scratch, ignore_errors=True)
        self.stub = os.path.join(self.scratch, "Example")
        with open(self.stub, "w") as handle:
            handle.write(f"#!{sys.executable}\n{_STUB}")
        os.chmod(self.stub, os.stat(self.stub).st_mode | stat.S_IXUSR)

    def drive(self, name, config_dir=None):
        """One `drive.py` run of the stub; returns what the stub reported."""
        report = os.path.join(self.scratch, f"{name}.json")
        env = {key: value for key, value in os.environ.items() if key != "TUIKIT_CONFIG_DIR"}
        env["DRIVE_TEST_REPORT"] = report
        if config_dir is not None:
            env["TUIKIT_CONFIG_DIR"] = config_dir
        # `list` is the shortest scenario that types anything: ~2 s.
        subprocess.run(
            [sys.executable, _DRIVE, self.stub, "--scenario", "list", "--settle", "0.1", "--quiet"],
            env=env, check=True, timeout=60)
        with open(report) as handle:
            return json.load(handle)

    def test_a_run_gets_a_fresh_config_directory_of_its_own(self):
        first = self.drive("first")
        self.assertNotEqual(
            first["config"], "",
            "the app was launched with no TUIKIT_CONFIG_DIR, so on macOS it read and wrote "
            "the developer's real preferences")
        self.assertTrue(first["existed"], "the directory the app was given did not exist")
        self.assertFalse(
            os.path.exists(first["config"]),
            "the run's configuration directory outlived the run")
        # Fresh each time: what one scenario typed into a field must not be
        # what the next one profiles.
        second = self.drive("second")
        self.assertNotEqual(second["config"], "")
        self.assertNotEqual(first["config"], second["config"])

    def test_a_directory_the_caller_chose_is_used_and_kept(self):
        chosen = os.path.join(self.scratch, "chosen")
        os.makedirs(chosen)
        reported = self.drive("chosen", config_dir=chosen)
        self.assertEqual(reported["config"], chosen)
        self.assertTrue(
            os.path.exists(os.path.join(chosen, "Example", "settings.json")),
            "a directory the caller named is the caller's to delete")


_REPO = os.path.dirname(os.path.dirname(_HERE))
_EXAMPLE = os.environ.get("DRIVE_TEST_BINARY", os.path.join(_REPO, ".build", "debug", "Example"))


# Local only. Its margins — 150 ms between the two Escapes and before `q` — were
# measured on a developer's machine, and a slow shared runner can merge an ESC
# with the key after it (Alt+q), failing the run with nothing wrong. A flaky gate
# costs more than this check buys there; the stub test above is the CI half.
@unittest.skipIf(os.environ.get("CI"), "local only: its key timing margins were measured on a developer's machine")
@unittest.skipUnless(os.access(_EXAMPLE, os.X_OK), f"needs a built Example ({_EXAMPLE})")
class TestTourStaysOnItsRoute(unittest.TestCase):
    """The real Example, because the question is what its pages do with the keys.

    The `tour` jumps to a page by its menu shortcut, scrolls with the arrows
    and presses Escape to go back to the menu for the next one. On the
    Sliders page the arrows walk the focus into the track editor's Fill combo
    field, where Down opens its suggestions — so that page's Escape closed the
    menu instead of leaving the page, and every key after it (the Steppers and
    Split View shortcuts, then the closing `q`) was typed into the field. The
    two last pages were never profiled, the app never quit, and the text was
    saved as the field's value.
    """

    def test_the_tour_types_nothing_and_ends_by_quitting(self):
        scratch = tempfile.mkdtemp(prefix="test-drive-tour-")
        self.addCleanup(shutil.rmtree, scratch, ignore_errors=True)
        # Named explicitly, not left to the driver: this must be isolated
        # whichever `drive.py` it runs against.
        env = dict(os.environ, TUIKIT_CONFIG_DIR=scratch)
        # A long settle: in a PTY that answers none of its startup queries, a
        # debug Example takes ~1.5 s to start reading keys, and everything
        # sent before then is parsed as one batch — a different question.
        result = subprocess.run(
            [sys.executable, _DRIVE, _EXAMPLE, "--scenario", "tour", "--settle", "2.5", "--quiet"],
            env=env, timeout=120, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        # The tour only navigates and scrolls, so it has no business saving
        # anything; what a stray keystroke saves is the evidence it went
        # somewhere other than where the script meant.
        settings_file = os.path.join(scratch, "Example", "settings.json")
        saved = {}
        if os.path.exists(settings_file):
            with open(settings_file) as handle:
                saved = json.load(handle)
        decoded = {key: base64.b64decode(value).decode() for key, value in saved.items()}
        self.assertEqual(decoded, {}, "the tour's keys changed the app's saved settings")


if __name__ == "__main__":
    unittest.main()
