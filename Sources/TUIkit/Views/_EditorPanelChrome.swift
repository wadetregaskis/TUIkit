//  🖥️ TUIkit — Terminal UI Kit for Swift
//  _EditorPanelChrome.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// The chrome every live-editing panel shares: a ``Dialog``, a Cancel / Done
/// footer, and **revert on anything but Done**.
///
/// Four panels — ``ColorPickerPanel``, ``GradientEditorPanel``,
/// ``ToneCurveEditorPanel``, ``ChannelCurveEditorPanel`` — wrote all of this out
/// themselves, and they had to agree on every part of it: the same dialog
/// arguments, the same two localized buttons in the same order at the same
/// spacing, the same `Session` reference box, and the same pair of lifecycle
/// hooks. Four copies of a rule is four places for it to drift, and the rule
/// here is a *semantic* one — "Cancel means the edit never happened" — which a
/// reader cannot check by looking at one panel.
///
/// These panels edit LIVE: every drag writes straight through the caller's
/// binding, so the caller's own view updates as you drag. That is the feature,
/// and it is also why Cancel needs an undo rather than just declining to write.
///
/// The undo hangs off `onDisappear` rather than off the Cancel button, because
/// Cancel is not the only way out: `Esc`, the modal's own dismissal, and the
/// presenting page going away all have to mean the same thing. Only Done says
/// otherwise, and it says so by setting a flag first.
struct _EditorPanelChrome<Value, Content: View>: View {
    /// The dialog's title.
    let title: String

    /// The value being edited live. Restored to what it held on appear unless
    /// Done was pressed.
    let edited: Binding<Value>

    /// The presenting `.modal`'s binding; Cancel and Done both clear it.
    let isPresented: Binding<Bool>

    /// The panel's own content, drawn inside the dialog above the footer.
    let content: Content

    /// What Done does before dismissing, beyond keeping the edit. Set by
    /// ``onDone(_:)``.
    private var doneAction: () -> Void = {}

    init(
        title: String,
        edited: Binding<Value>,
        isPresented: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.edited = edited
        self.isPresented = isPresented
        self.content = content()
    }

    /// Extra work Done does before dismissing, beyond keeping the edit.
    ///
    /// Only ``GradientEditorPanel`` needs it, to record the applied gradient in
    /// its recents — which must happen on Done and only on Done, so it belongs
    /// here beside the flag rather than in the panel's own lifecycle.
    ///
    /// A modifier rather than an init parameter so the content stays the trailing
    /// closure, which is the only shape that reads like a view.
    func onDone(_ action: @escaping () -> Void) -> Self {
        var copy = self
        copy.doneAction = action
        return copy
    }

    /// Per-presentation bookkeeping for Cancel semantics. A REFERENCE type: the
    /// dismissal callback must read the values as they are when it fires, not as
    /// they were when the closure's frame was rendered (a value capture would
    /// miss Done setting `applied` in the same action that dismisses).
    @State private var session = Session()

    private final class Session {
        var original: Value?
        var applied = false
    }

    var body: some View {
        Dialog(title: title, titleColor: .palette.accent, footerAlignment: .center) {
            content
                .onAppear { session.original = edited.wrappedValue }
                .onDisappear {
                    // ANY dismissal that isn't Done — Cancel, Esc, the page
                    // going away — restores what the dialog opened with. Live
                    // edits already wrote through the binding; this is the undo.
                    if !session.applied, let original = session.original {
                        edited.wrappedValue = original
                    }
                }
        } footer: {
            // No leading Spacer: a Spacer is width-flexible, which would make the
            // dialog claim the full available width instead of sizing to its
            // content. The footer sizes to the buttons; the dialog to its body.
            HStack(spacing: 2) {
                Button(LocalizationService.shared.string(for: LocalizationKey.Button.cancel)) {
                    isPresented.wrappedValue = false
                }
                Button(LocalizationService.shared.string(for: LocalizationKey.Button.done)) {
                    session.applied = true
                    doneAction()
                    isPresented.wrappedValue = false
                }
                .buttonStyle(.primary)
            }
        }
    }
}
