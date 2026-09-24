//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusEffect.swift
//
//  Whether a focused control is allowed to LOOK focused. SwiftUI's
//  `focusEffectDisabled(_:)`, and the same contract: the view stays in the
//  focus ring — Tab still reaches it, it still takes keys — it simply stops
//  advertising that it has arrived.
//
//  Created by Wade Tregaskis
//  License: MIT

/// Environment key for the cascading focus-effect suppression (SwiftUI's
/// `\.focusEffectDisabled`).
///
/// `.focusEffectDisabled(true)` flips it for a whole subtree. It is
/// **additive** — a descendant cannot restore an indication an ancestor
/// suppressed — exactly as ``EnvironmentValues/isEnabled`` is, and for the
/// same reason: both modifiers speak for a subtree rather than for a node.
private struct FocusEffectDisabledKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether controls in this subtree suppress their focus indication.
    ///
    /// Read it through ``RenderContext/indicatesFocus(_:)`` rather than
    /// directly: every control has to combine it with its own focus state the
    /// same way, and one place to do that is one fewer place to forget.
    ///
    /// What is read here is the COMBINED answer — ``View/focusEffectDisabled(_:)``
    /// ORs into it rather than overwriting it — so a control never has to ask
    /// what any ancestor said.
    public var focusEffectDisabled: Bool {
        get { self[FocusEffectDisabledKey.self] }
        set { self[FocusEffectDisabledKey.self] = newValue }
    }
}

extension RenderContext {
    /// Whether a control that IS focused should draw itself as focused.
    ///
    /// The one question every control's styling asks, so that
    /// ``EnvironmentValues/focusEffectDisabled`` cannot be honoured by six
    /// controls and forgotten by two — the failure mode that kept this
    /// modifier off the list for months, because a control still shouting
    /// "focused!" while its neighbours had gone quiet reads as a bug in that
    /// control rather than as a modifier working.
    ///
    /// It answers `false` for one reason: the focus effect is disabled.
    ///
    /// NOT because the view does not appear active
    /// (``EnvironmentValues/appearsActive`` is `false`, as when the terminal
    /// window has lost focus). The focus has not gone anywhere then — it is
    /// parked on this control, and the keys reach it again the moment the
    /// window does — so the indication stays and holds still instead: the
    /// emphasis clock stops breathing (``EnvironmentValues/selectionEmphasis``),
    /// and a highlighted row takes the still tint of an unfocused selection.
    /// Hiding it read as the focus having been lost.
    ///
    /// **Behaviour is not an effect.** This gates appearance only. A control
    /// with its focus effect disabled still holds the focus, still takes the
    /// keys, and still moves the cursor — which is what makes the modifier
    /// usable at all, and what distinguishes it from `.disabled(true)`.
    ///
    /// What deliberately survives it: a **text cursor**. A caret is the
    /// insertion point, not decoration — it says where TYPING will go, which
    /// is a fact about the control rather than an announcement about focus —
    /// and SwiftUI keeps it under this modifier for the same reason.
    ///
    /// That is the whole of the exception, and the test is typing. A
    /// `DatePicker`'s active-field marker looks like a caret and is not one:
    /// nothing is typed there, and the field is active only because the
    /// control is focused, so the mark announces focus exactly as a `Button`'s
    /// bold does. It goes.
    public func indicatesFocus(_ isFocused: Bool) -> Bool {
        environment.indicatesFocus(isFocused)
    }
}

extension EnvironmentValues {
    /// The environment-only answer to `RenderContext.indicatesFocus(_:)`, and
    /// the one place the question is decided.
    ///
    /// A `RenderContext` adds nothing to it — only its environment is read — and
    /// a site that holds an environment but no context (a border's focus ●, a
    /// style's body) has to ask the same question the same way, which is why
    /// this is the primitive and the context method forwards to it: the shape of
    /// `SelectionIndicator.resolve(isFocused:environment:)`.
    ///
    /// `appearsActive` is deliberately NOT here: an inactive window keeps its
    /// focus indication, held still — see ``RenderContext/indicatesFocus(_:)``.
    func indicatesFocus(_ isFocused: Bool) -> Bool {
        isFocused && !focusEffectDisabled
    }
}

extension View {
    /// Suppresses the focus indication of controls in this subtree, without
    /// taking them out of the focus ring.
    ///
    /// ```swift
    /// TextField("Search", text: $query)
    ///     .focusEffectDisabled()
    /// ```
    ///
    /// Everything a control does to say "I am focused" goes: the pulse, the
    /// caps, the bold, the recoloured glyphs and arrows, the highlighted row,
    /// a scroll bar's breath, a colour grid's cursor mark, a `DatePicker`'s
    /// active-field mark, a focus section's ●, a split divider's or resize
    /// grip's breath. A text cursor stays, and animates
    /// as it always did.
    ///
    /// Be aware of what that costs. A terminal has no pointer to fall back on
    /// when the keyboard is the only way to navigate, so a subtree with its
    /// focus effects off can be genuinely impossible to navigate blind. That
    /// is the same trade SwiftUI's modifier makes, and it is the caller's to
    /// make — the modifier exists because sometimes the indication is the
    /// problem (a dashboard that should not breathe, a control whose own
    /// content already says where you are).
    ///
    /// It is **additive**: `true` anywhere above a control suppresses that
    /// control's indication, and a nested `.focusEffectDisabled(false)` does
    /// not put it back. SwiftUI says so outright — "the higher views in a view
    /// hierarchy can override the value you set on this view" — and works this
    /// very example, an inner `false` inside an outer `true` drawing nothing.
    /// It is also how the parallel ``View/disabled(_:)`` composes here, which
    /// is no coincidence: Apple's two modifiers carry the same sentence, and a
    /// modifier that speaks for a subtree cannot let one view in that subtree
    /// speak back.
    ///
    /// So `false` is the *absence* of a suppression rather than a suppression
    /// of one, and `.focusEffectDisabled(isQuiet)` on a leaf is the spelling
    /// that works: the flag decides whether this subtree adds its own, and
    /// whatever an ancestor decided stands either way.
    ///
    /// - Parameter disabled: `true` (the default) suppresses the indication for
    ///   this subtree; `false` adds no suppression of its own, and does not
    ///   lift one an ancestor added.
    public func focusEffectDisabled(_ disabled: Bool = true) -> some View {
        // `transformEnvironment`, not `environment`: the value is derived from
        // what is inherited (OR), which is what makes the modifier additive.
        // The closure is a pure function of the inherited value, as that helper
        // requires — it runs on the measure walk and the render walk alike.
        transformEnvironment(\.focusEffectDisabled) { $0 = $0 || disabled }
    }
}
