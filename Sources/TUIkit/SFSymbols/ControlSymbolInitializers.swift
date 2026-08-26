//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ControlSymbolInitializers.swift
//
//  `Button("Save", systemImage: "square.and.arrow.down") { … }`, and the same
//  shorthand on Toggle, Picker and ContentUnavailableView.
//
//  Each of these builds the ``Label`` the long spelling would have built, so
//  they inherit its behaviour whole — including the part that matters here:
//  when the symbol cannot be drawn (a non-Apple platform, a terminal font
//  without the SF Symbols glyphs, an unknown name) the label renders JUST ITS
//  TITLE, with no icon column and no stray gap. See ``SFSymbol/canRender(named:)``.
//
//  That degradation is why these belong in the framework at all. A modifier
//  that accepts a request the medium cannot meet and drops it is a stub, and
//  TUIkit deletes those so the call fails to compile
//  (Documentation/SwiftUI-compatibility.md). This is the other case: the
//  request is met where the terminal can meet it, and where it cannot the
//  fallback is the same view the developer would have written by hand. Nothing
//  is silently lost — an icon that was never renderable is not a dropped
//  request, it is a glyph the font does not have.
//
//  The `image:` spellings of these same initializers are NOT here, and that is
//  deliberate: they name an asset-catalogue `ImageResource`, which is a build
//  product a terminal app does not have. They are recorded in
//  Tools/APIParity/parity-map.json.
//
//  Created by Wade Tregaskis
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Button

extension Button {
    /// Creates a button with an SF Symbol beside a localized title.
    ///
    /// A string **literal** binds here, so the title is a lookup key — see
    /// ``LocalizedStringKey``. The `systemImage` is a symbol name rather than
    /// display text, so it is never a key.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the button's label.
    ///   - systemImage: The SF Symbol name, e.g. `"square.and.arrow.down"`.
    ///   - action: The action to perform when pressed.
    public init(
        _ titleKey: LocalizedStringKey,
        systemImage: String,
        action: @escaping () -> Void
    ) {
        self.init(titleKey.localized, systemImage: systemImage, action: action)
    }

    /// Creates a button with an SF Symbol beside a title shown as written.
    ///
    /// - Parameters:
    ///   - title: The button's label text.
    ///   - systemImage: The SF Symbol name, e.g. `"square.and.arrow.down"`.
    ///   - action: The action to perform when pressed.
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ title: S,
        systemImage: String,
        action: @escaping () -> Void
    ) {
        self.init(title, systemImage: systemImage, role: nil, action: action)
    }

    /// Creates a button with a role and an SF Symbol beside a localized title.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the button's label.
    ///   - systemImage: The SF Symbol name, e.g. `"trash"`.
    ///   - role: An optional semantic role describing the button.
    ///   - action: The action to perform when pressed.
    public init(
        _ titleKey: LocalizedStringKey,
        systemImage: String,
        role: ButtonRole?,
        action: @escaping () -> Void
    ) {
        self.init(titleKey.localized, systemImage: systemImage, role: role, action: action)
    }

    /// Creates a button with a role and an SF Symbol beside a title shown as
    /// written.
    ///
    /// - Parameters:
    ///   - title: The button's label text.
    ///   - systemImage: The SF Symbol name, e.g. `"trash"`.
    ///   - role: An optional semantic role describing the button.
    ///   - action: The action to perform when pressed.
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ title: S,
        systemImage: String,
        role: ButtonRole?,
        action: @escaping () -> Void
    ) {
        // The composed-label path, not the string one: `Button` is not generic
        // over its label (see the type's own note on why), so an icon can only
        // reach it as a view. A style that reads `configuration.labelView`
        // first — every built-in one does — renders this exactly as it renders
        // any other `Button(action:label:)`.
        self.init(role: role, action: action) {
            Label(title, systemImage: systemImage)
        }
    }
}

// MARK: - Toggle

extension Toggle where Label == TUIkit.Label<Text, _SymbolIcon> {
    /// Creates a toggle with an SF Symbol beside a localized label.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the toggle's label.
    ///   - systemImage: The SF Symbol name, e.g. `"wifi"`.
    ///   - isOn: A binding to the toggle's boolean state.
    public init(
        _ titleKey: LocalizedStringKey,
        systemImage: String,
        isOn: Binding<Bool>
    ) {
        self.init(titleKey.localized, systemImage: systemImage, isOn: isOn)
    }

    /// Creates a toggle with an SF Symbol beside a label shown as written.
    ///
    /// - Parameters:
    ///   - title: The toggle's label text.
    ///   - systemImage: The SF Symbol name, e.g. `"wifi"`.
    ///   - isOn: A binding to the toggle's boolean state.
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ title: S,
        systemImage: String,
        isOn: Binding<Bool>
    ) {
        self.init(isOn: isOn) {
            TUIkit.Label(title, systemImage: systemImage)
        }
    }
}

// MARK: - Picker

extension Picker where Label == TUIkit.Label<Text, _SymbolIcon> {
    /// Creates a picker with an SF Symbol beside a localized label.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the picker's label.
    ///   - systemImage: The SF Symbol name, e.g. `"paintpalette"`.
    ///   - selection: A binding to the selected value.
    ///   - content: A view builder of options, each carrying a ``View/tag(_:)``.
    public init(
        _ titleKey: LocalizedStringKey,
        systemImage: String,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            titleKey.localized, systemImage: systemImage,
            selection: selection, content: content)
    }

    /// Creates a picker with an SF Symbol beside a label shown as written.
    ///
    /// - Parameters:
    ///   - title: The picker's label text.
    ///   - systemImage: The SF Symbol name, e.g. `"paintpalette"`.
    ///   - selection: A binding to the selected value.
    ///   - content: A view builder of options, each carrying a ``View/tag(_:)``.
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ title: S,
        systemImage: String,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) {
        self.init(selection: selection, content: content) {
            TUIkit.Label(title, systemImage: systemImage)
        }
    }
}

// MARK: - ContentUnavailableView

extension ContentUnavailableView
where Label == TUIkit.Label<Text, _SymbolIcon>, Description == Text?, Actions == EmptyView {
    /// Creates an empty-state view with an SF Symbol beside a localized title.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the title text.
    ///   - systemImage: The SF Symbol name, e.g. `"tray"`.
    ///   - description: An optional sentence below the title. It is a ``Text``
    ///     rather than a key because that is SwiftUI's shape here, and `Text`'s
    ///     own literal initializer already treats a literal as a key.
    public init(
        _ titleKey: LocalizedStringKey,
        systemImage: String,
        description: Text? = nil
    ) {
        self.init(titleKey.localized, systemImage: systemImage, description: description)
    }

    /// Creates an empty-state view with an SF Symbol beside a title shown as
    /// written.
    ///
    /// - Parameters:
    ///   - title: The title text.
    ///   - systemImage: The SF Symbol name, e.g. `"tray"`.
    ///   - description: An optional sentence below the title.
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ title: S,
        systemImage: String,
        description: Text? = nil
    ) {
        self.init(
            label: { TUIkit.Label(title, systemImage: systemImage) },
            description: { description },
            actions: { EmptyView() })
    }
}
