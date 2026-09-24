#!/usr/bin/env python3
"""
Tests for `drive.py`, the Mode-B PTY driver.

    python3 Tools/Profiling/test_drive.py

The driven binary is a stub that reports what it was launched with, so these
need no build and no Instruments: they are about what `drive.py` hands the
app, not about the app.

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


if __name__ == "__main__":
    unittest.main()
