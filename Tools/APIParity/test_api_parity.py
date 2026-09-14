"""Tests for the pure comparison half of `api_parity.py`.

    cd Tools/APIParity && python3 -m unittest
    python3 -m unittest discover -s Tools/APIParity     # from the repository root

These need no SDK and no build: every function exercised here takes the
symbol dictionaries `load_symbols` would have produced (key -> kind), so each
case spells out exactly the vocabulary it is about.
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import api_parity  # noqa: E402  (the path has to be set up first)


def symbols(*keys):
    """A symbol dictionary shaped like `load_symbols`' result."""
    return {key: "func" for key in keys}


class LabelDeviationTests(unittest.TestCase):

    def test_a_swiftui_declaration_is_never_a_misspelling_of_another(self):
        # `toolbar(removing:)` is exact SwiftUI API. That TUIkit lacks
        # `toolbar(content:)` does not make the one it has a misspelling.
        swiftui = symbols("View.toolbar(content:)", "View.toolbar(removing:)")
        tuikit = symbols("View.toolbar(removing:)")
        self.assertEqual(api_parity.label_deviations(swiftui, tuikit), {})

    def test_a_genuine_misspelling_is_still_flagged(self):
        swiftui = symbols("View.onHover(perform:)")
        tuikit = symbols("View.onHover(action:)")
        self.assertEqual(
            api_parity.label_deviations(swiftui, tuikit),
            {"View.onHover(perform:)": ["View.onHover(action:)"]})

    def test_only_the_misspelt_candidates_are_kept(self):
        # Two TUIkit overloads with the same name and arity: one is SwiftUI's
        # own `toolbar(removing:)`, the other is TUIkit's own spelling.
        swiftui = symbols("View.toolbar(content:)", "View.toolbar(removing:)")
        tuikit = symbols("View.toolbar(removing:)", "View.toolbar(items:)")
        self.assertEqual(
            api_parity.label_deviations(swiftui, tuikit),
            {"View.toolbar(content:)": ["View.toolbar(items:)"]})

    def test_a_different_arity_is_not_a_misspelling(self):
        # A missing overload with more or fewer arguments is an absence, not a
        # misspelling of the overload that exists.
        swiftui = symbols("Button.init(_:image:action:)", "View.alert(_:isPresented:)")
        tuikit = symbols("Button.init(_:action:)", "View.alert(_:isPresented:actions:message:)")
        self.assertEqual(api_parity.label_deviations(swiftui, tuikit), {})

    def test_a_symbol_tuikit_has_is_not_a_deviation(self):
        swiftui = symbols("View.padding(_:)", "View.padding(_:_:)")
        tuikit = symbols("View.padding(_:)", "View.padding(_:_:)")
        self.assertEqual(api_parity.label_deviations(swiftui, tuikit), {})


if __name__ == "__main__":
    unittest.main()
