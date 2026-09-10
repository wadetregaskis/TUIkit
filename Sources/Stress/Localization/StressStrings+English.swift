//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StressStrings+English.swift
//
//  Created by LAYERED.work
//  License: MIT
//
//  English — the source of truth. Every other language falls back to this
//  table (then to the key) for any key it omits.
//
//  Per-language translation tables for the Stress harness. English is the
//  source of truth; other languages fall back to English (then the key) for any
//  key they omit.
//
//  Scope: the interactive shell's own UI plus each scenario's title / blurb /
//  `stresses` summary / rendered heading. Headings that show a live count keep
//  the number via `{0}` / `{1}` placeholders (see `Lf(_:_:)`); only the static
//  phrasing is translated. The `--bench` / `--selfcheck` stdout diagnostics, the
//  `--scenario` id strings, the synthetic sample data, and the table column
//  headers are intentionally NOT here — they stay English.

// swiftlint:disable line_length

extension StressStrings {
    static let en: [String: String] = [
        // MARK: shell
        "stress.shell.menu.title": "TUIkit — Stress Test",
        "stress.shell.label.scale": "scale",
        "stress.shell.label.seed": "seed",
        "stress.shell.label.autopilot": "autopilot",
        "stress.shell.autopilot.on": "on",
        "stress.shell.autopilot.off": "off",
        "stress.shell.autopilot.frame": "frame",
        "stress.shell.menu.help": "↑/↓ select · enter open · +/− scale · a autopilot · esc quit",
        "stress.shell.footer.hint": "esc back · +/− scale · a autopilot",

        // MARK: megalist
        "stress.scenario.megalist.title": "Mega List",
        "stress.scenario.megalist.blurb": "Windowed List of N rows; content hashed per index (no backing array).",
        "stress.scenario.megalist.stresses": "List/ForEach windowing · row-id resolution · lazy row content · per-row memo",
        "stress.scenario.megalist.heading": "Mega List — {0} rows",

        // MARK: table
        "stress.scenario.table.title": "Wide Table",
        "stress.scenario.table.blurb": "N rows × 8 columns; per-cell strings synthesised from the row hash.",
        "stress.scenario.table.stresses": "Table column-width computation · row windowing · per-cell value closures",
        "stress.scenario.table.heading": "Wide Table — {0} rows × 8 columns",

        // MARK: table-multiline
        "stress.scenario.table-multiline.title": "Multi-line Table",
        "stress.scenario.table-multiline.blurb": "N rows × 4 columns; a Details column wraps to ≤3 lines, so rows vary in height.",
        "stress.scenario.table-multiline.stresses": "Multi-line cell wrapping · lazy row sizing (window + suffix only) · variable-height windowing",
        "stress.scenario.table-multiline.heading": "Multi-line Table — {0} rows, Details wraps to ≤3 lines",

        // MARK: tables-scroll
        "stress.scenario.tables-scroll.title": "Tables in a ScrollView",
        "stress.scenario.tables-scroll.blurb": "N tables stacked in a ScrollView; each materialises its rows and computes its own column widths.",
        "stress.scenario.tables-scroll.stresses": "Multiple Table instances · per-table column-width computation · ScrollView windowing over the combined buffer",
        "stress.scenario.tables-scroll.heading": "Tables in a ScrollView — {0} tables × {1} rows",

        // MARK: tables-vstack
        "stress.scenario.tables-vstack.title": "Tables in a VStack",
        "stress.scenario.tables-vstack.blurb": "N tables stacked directly in a VStack (no scroll); the stack measures and lays out every table.",
        "stress.scenario.tables-vstack.stresses": "Multiple Table instances · per-table column-width computation · VStack measure/layout over many children",
        "stress.scenario.tables-vstack.heading": "Tables in a VStack — {0} tables × {1} rows",
        "stress.scenario.tables.tableLabel": "Table {0}",

        // MARK: deep
        "stress.scenario.deep.title": "Deep Recursion",
        "stress.scenario.deep.blurb": "One view nested in itself to depth D (bordered/padded at each level).",
        "stress.scenario.deep.stresses": "ViewIdentity chain depth · measure recursion · context propagation",
        "stress.scenario.deep.heading": "Deep Recursion — depth {0}",
        "stress.scenario.deep.leaf": "leaf @ {0}: {1}",
        "stress.scenario.deep.level": "level {0}",

        // MARK: fanout
        "stress.scenario.fanout.title": "Wide Fanout",
        "stress.scenario.fanout.blurb": "One non-lazy VStack with N direct children (every child measured each frame).",
        "stress.scenario.fanout.stresses": "container measure over all children · space distribution · O(n) layout",
        "stress.scenario.fanout.heading": "Wide Fanout — {0} siblings in one VStack",

        // MARK: modifiers
        "stress.scenario.modifiers.title": "Modifier Chains",
        "stress.scenario.modifiers.blurb": "N rows, each wrapped in a long modifier chain.",
        "stress.scenario.modifiers.stresses": "ModifiedView/environment-modifier layering · per-node measure overhead",
        "stress.scenario.modifiers.heading": "Modifier Chains — {0} deeply-modified rows",

        // MARK: preferences
        "stress.scenario.preferences.title": "Preference Rows",
        "stress.scenario.preferences.blurb": "N rows, each publishing a preference to one collector.",
        "stress.scenario.preferences.stresses": "preference side-effect declaration · value-memo defeat · per-row re-measure",
        "stress.scenario.preferences.heading": "{0} rows · {1} published",

        // MARK: customlayout
        "stress.scenario.customlayout.title": "Custom Layout",
        "stress.scenario.customlayout.blurb": "N subviews arranged by a Layout conformance behind AnyLayout.",
        "stress.scenario.customlayout.stresses": "Layout protocol call pattern · repeated subview measurement · AnyLayout erasure",
        "stress.scenario.customlayout.heading": "{0} chips in a custom Layout",

        // MARK: textwall
        "stress.scenario.textwall.title": "Text Wall",
        "stress.scenario.textwall.blurb": "N long wrapping paragraphs of synthesised prose.",
        "stress.scenario.textwall.stresses": "text width measurement · word wrapping · glyph throughput",
        "stress.scenario.textwall.heading": "Text Wall — {0} wrapping paragraphs",

        // MARK: anyview
        "stress.scenario.anyview.title": "AnyView Storm",
        "stress.scenario.anyview.blurb": "N heterogeneous rows, each erased through AnyView.",
        "stress.scenario.anyview.stresses": "type-erasure fallback · render-to-measure path · lost concrete dispatch",
        "stress.scenario.anyview.heading": "AnyView Storm — {0} type-erased rows",

        // MARK: dashboard
        "stress.scenario.dashboard.title": "Dashboard",
        "stress.scenario.dashboard.blurb": "A grid of N metric Panels (bars + progress) — dense container layout.",
        "stress.scenario.dashboard.stresses": "Panel/Card container measure · flexible-width row sharing · mixed leaves",
        "stress.scenario.dashboard.heading": "Dashboard — {0} metric panels",
        "stress.scenario.framedcolumns.title": "Framed Columns",
        "stress.scenario.framedcolumns.blurb": "Fixed-frame columns of interactive rows (List, Toggle Cards, a log Panel).",
        "stress.scenario.framedcolumns.stresses": "non-infinity .frame measure · frames-in-stacks-in-frames cascade · uncacheable interactive rows",
        "stress.scenario.framedcolumns.heading": "Framed columns — {0} toggle rows per card",

        // MARK: churn
        "stress.scenario.churn.title": "Churn Update",
        "stress.scenario.churn.blurb": "N rows whose content changes every frame (tick-driven) — no memo hits.",
        "stress.scenario.churn.stresses": "full re-render per frame · cache invalidation · measure with no memo",
        "stress.scenario.animating.title": "Animating",
        "stress.scenario.animating.blurb": "N rows interpolating at once, none of them cacheable.",
        "stress.scenario.animating.stresses": "animation store lookups · uncacheable subtrees · colour resolution per frame",
        "stress.scenario.animating.heading": "Animating — {0} rows, all mid-flight",
        "stress.scenario.translucent.title": "Translucent",
        "stress.scenario.translucent.blurb": "A large faded panel over a destination that redraws every frame.",
        "stress.scenario.translucent.stresses": "cell decomposition of both sides · per-cell region lookup · SGR re-emission",
        "stress.scenario.translucent.heading": "Translucent — {0} rows, each faded over a changing band",
        "stress.scenario.gradients.title": "Gradients",
        "stress.scenario.gradients.blurb": "A subtree ramp down a long list, per-leaf ramps, four geometries, ramped fills.",
        "stress.scenario.gradients.stresses": "ramp quantisation · per-cell geometry · origin propagation · re-ink on move · SGR runs",
        "stress.scenario.gradients.heading": "Gradients — {0} rows under one ramp, plus per-leaf and geometry bands",
        "stress.scenario.alpharamp.title": "Alpha ramps",
        "stress.scenario.alpharamp.blurb": "Translucent gradients in all four alpha shapes, as ink and as fills.",
        "stress.scenario.alpharamp.stresses": "claim derivation per cell · region carriage through composites · opacity resolution",
        "stress.scenario.alpharamp.heading": "Alpha ramps — {0} rows of translucent gradient in every alpha shape",
        "stress.scenario.churn.heading": "Churn Update — frame {0}, {1} rows invalidated/frame",
        "stress.scenario.scrollfollow.title": "Scroll Follow",
        "stress.scenario.scrollfollow.blurb": "Bottom-anchored ScrollView over N variable-height rows; a row appends every tick.",
        "stress.scenario.scrollfollow.stresses": "windowed band render · anchor advance · tail estimate · O(window) at any N",
        "stress.scenario.scrollfollow.heading": "Scroll Follow — {0} rows, bottom-anchored (a row appends every frame)",

        // MARK: kitchensink
        "stress.scenario.menus.title": "Menu Bar",
        "stress.scenario.menus.blurb": "Inline menus of shortcut-bearing rows, beside every built-in button style.",
        "stress.scenario.menus.stresses": "ButtonStyle body measure · menu hug-width pass · shortcut hint column · per-row @Environment resolution",
        "stress.scenario.menus.heading": "Menu bar — {0} menus of {1} rows",
        "stress.scenario.kitchensink.title": "Kitchen Sink",
        "stress.scenario.kitchensink.blurb": "Split view: big list sidebar + dense panel-grid detail, together.",
        "stress.scenario.kitchensink.stresses": "split-view layout + list windowing + container grid simultaneously",
        "stress.scenario.kitchensink.heading.items": "Items ({0})",
        "stress.scenario.kitchensink.heading.metrics": "Metrics",
    ]
}

// swiftlint:enable line_length
