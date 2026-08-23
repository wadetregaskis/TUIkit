//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LabelsVisibility.swift
//
//  Whether the controls in a subtree draw their OWN labels.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

/// Environment key for ``View/labelsVisibility(_:)`` and ``View/labelsHidden()``.
private struct LabelsVisibilityKey: EnvironmentKey {
    static let defaultValue: Visibility = .automatic
}

extension EnvironmentValues {
    /// Whether the controls in this subtree draw the labels they were given.
    ///
    /// Read by every control that draws a label of its OWN — the text a
    /// `Toggle`, `Picker`, `Slider`, `Stepper`, `DatePicker`, `ColorPicker`,
    /// `ProgressView`, `Gauge` or `LabeledContent` puts beside itself. It is
    /// not a general "hide text" switch: a `Text` in a stack next to a control
    /// is content, and stays.
    public var labelsVisibility: Visibility {
        get { self[LabelsVisibilityKey.self] }
        set { self[LabelsVisibilityKey.self] = newValue }
    }

    /// Whether a control should withhold its own label right now.
    ///
    /// The one place the tri-state is collapsed, so that every control asks the
    /// same question and `.automatic` cannot come to mean different things in
    /// different controls. `.automatic` is SwiftUI's deferral to "the policies
    /// of the component", and every control here has the same policy: show it.
    var controlLabelsAreHidden: Bool { labelsVisibility == .hidden }
}

extension View {
    /// Hides the labels of the controls in this view.
    ///
    /// A control's label is the text it draws BESIDE itself — a `Toggle`'s
    /// caption, the word in front of a `Slider`. Hiding it leaves the control,
    /// and takes the label's cells with it: the row closes up rather than
    /// keeping a blank gap where the words were.
    ///
    /// The case for it is a layout that labels the controls itself — a `Form`
    /// or a `Grid` whose first column is the captions — where each control
    /// repeating its own label would say everything twice:
    ///
    /// ```swift
    /// Grid {
    ///     GridRow {
    ///         Text("Volume")
    ///         Slider(value: $volume) { Text("Volume") }.labelsHidden()
    ///     }
    /// }
    /// ```
    ///
    /// SwiftUI keeps the hidden label for accessibility, which is why it is
    /// still worth writing one; a terminal has no separate accessibility tree,
    /// so here the label is simply not drawn. Give one anyway — the same source
    /// then reads correctly on both.
    ///
    /// It does NOT reach ordinary content: a `Text` sitting beside a control is
    /// content, not the control's label, and stays.
    ///
    /// - Returns: A view whose controls draw no labels.
    public func labelsHidden() -> some View {
        labelsVisibility(.hidden)
    }

    /// Sets whether the controls in this view draw their own labels.
    ///
    /// The general form of ``labelsHidden()``, and the one that can turn labels
    /// back ON inside a subtree that hid them.
    ///
    /// - Parameter visibility: `.hidden` withholds every control's label;
    ///   `.visible` and `.automatic` both draw it, a terminal control having no
    ///   second policy for `.automatic` to defer to.
    /// - Returns: A view whose controls draw labels as stated.
    public func labelsVisibility(_ visibility: Visibility) -> some View {
        environment(\.labelsVisibility, visibility)
    }
}
