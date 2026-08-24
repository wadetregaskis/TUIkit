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
    /// **Behaviour is not an effect.** This gates appearance only. A control
    /// with its focus effect disabled still holds the focus, still takes the
    /// keys, and still moves the cursor — which is what makes the modifier
    /// usable at all, and what distinguishes it from `.disabled(true)`.
    ///
    /// What deliberately survives it: a **text cursor**. A caret is the
    /// insertion point, not decoration — it says where typing will go, which
    /// is a fact about the control rather than an announcement about focus —
    /// and SwiftUI keeps it under this modifier for the same reason. The same
    /// argument keeps a `DatePicker`'s active-field marker, which is that
    /// control's caret: it says which field the arrows will change.
    public func indicatesFocus(_ isFocused: Bool) -> Bool {
        isFocused && !environment.focusEffectDisabled
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
    /// caps, the bold, the recoloured glyphs and arrows, the highlighted row.
    /// A text cursor stays, and animates as it always did.
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
