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

private struct FocusEffectDisabledKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether controls in this subtree suppress their focus indication.
    ///
    /// Read it through ``RenderContext/indicatesFocus(_:)`` rather than
    /// directly: every control has to combine it with its own focus state the
    /// same way, and one place to do that is one fewer place to forget.
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
    /// It answers `false` for two reasons: the focus effect is disabled, or
    /// the view does not appear active (``EnvironmentValues/appearsActive``
    /// is `false`, as when the scene is not `.active`). A macOS window stops
    /// drawing its focus ring when another window takes input, and so does a
    /// TUIkit view.
    ///
    /// **Behaviour is not an effect.** This gates appearance only. A control
    /// with its focus effect disabled, or in a view that does not appear
    /// active, still holds the focus, still takes the keys, and still moves
    /// the cursor — which is what makes the modifier usable at all, and what
    /// distinguishes it from `.disabled(true)`.
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
    /// `appearsActive` is here, rather than folded into `focusEffectDisabled`
    /// at the root, so that anything reading `focusEffectDisabled` still reads
    /// what the app set.
    func indicatesFocus(_ isFocused: Bool) -> Bool {
        isFocused && !focusEffectDisabled && appearsActive
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
    /// - Parameter disabled: `true` (the default) suppresses the indication;
    ///   `false` restores it for this subtree, which is how a nested control
    ///   opts back in.
    public func focusEffectDisabled(_ disabled: Bool = true) -> some View {
        environment(\.focusEffectDisabled, disabled)
    }
}
