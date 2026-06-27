//  🖥️ TUIKit — Terminal UI Kit for Swift
//  FormStyle.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - FormStyle

/// The appearance and layout of a ``Form``.
///
/// Set it with the ``SwiftUICore/View/formStyle(_:)`` modifier:
///
/// ```swift
/// Form {
///     LabeledContent("Name") { TextField("", text: $name) }
///     Toggle("Notifications", isOn: $notify)
/// }
/// .formStyle(.grouped)
/// ```
///
/// ## Built-in styles
///
/// | Style | Description |
/// |-------|-------------|
/// | ``automatic`` | Platform default — **columns** in TUIkit, the classic macOS form. |
/// | ``columns`` | Labels right-aligned to a shared pillar, controls left-aligned after it. |
/// | ``grouped`` | Each ``Section`` drawn as a bordered group with its title. |
///
/// ## Custom styles
///
/// Conform to `FormStyle` and implement ``makeBody(configuration:)``, laying out
/// `configuration.content` however you like.
public protocol FormStyle: Sendable {
    /// A view representing the form's body.
    associatedtype Body: View = EmptyView

    /// Creates a view that represents the body of a form.
    ///
    /// - Parameter configuration: The form's content.
    @MainActor @ViewBuilder
    func makeBody(configuration: Configuration) -> Body

    /// The properties of a form.
    typealias Configuration = FormStyleConfiguration
}

extension FormStyle {
    /// Default body for the built-in marker styles, which ``Form`` lays out
    /// directly (it needs the form's concrete content type to extract its
    /// label/control rows, which the type-erased configuration can't provide).
    /// A custom style overrides this.
    @MainActor public func makeBody(configuration: Configuration) -> EmptyView {
        EmptyView()
    }

    /// Renders this style's body for `configuration` into a frame buffer. Opens
    /// the `any FormStyle` existential so ``makeBody(configuration:)`` can return
    /// its concrete ``Body``. Used only for custom styles.
    @MainActor
    func makeBuffer(configuration: Configuration, context: RenderContext) -> FrameBuffer {
        renderToBuffer(makeBody(configuration: configuration), context: context)
    }
}

/// The properties of a form, passed to a ``FormStyle``.
///
/// You don't create this — TUIkit builds one per ``Form`` and hands it to the
/// active style's ``FormStyle/makeBody(configuration:)``. Mirrors SwiftUI's
/// `FormStyleConfiguration`.
public struct FormStyleConfiguration {
    /// The form's content, type-erased.
    public let content: AnyView
}

// MARK: - Built-in Form Styles

/// The default form style: **columns** in TUIkit (the classic macOS form layout),
/// matching how `automatic` resolves on macOS.
public struct AutomaticFormStyle: FormStyle {
    /// Creates an automatic form style.
    public init() {}
}

/// A form style that aligns labels in a right-justified column against a shared
/// pillar of whitespace, with controls left-aligned after it — the classic macOS
/// "Settings" look.
public struct ColumnsFormStyle: FormStyle {
    /// Creates a columns form style.
    public init() {}
}

/// A form style that draws each ``Section`` as a bordered group with its title —
/// the grouped (iOS-style) layout.
public struct GroupedFormStyle: FormStyle {
    /// Creates a grouped form style.
    public init() {}
}

// MARK: - FormStyle Static Accessors

extension FormStyle where Self == AutomaticFormStyle {
    /// The default form style — **columns** in TUIkit (macOS convention).
    public static var automatic: AutomaticFormStyle { AutomaticFormStyle() }
}

extension FormStyle where Self == ColumnsFormStyle {
    /// A form style with labels right-aligned to a shared pillar (macOS form).
    public static var columns: ColumnsFormStyle { ColumnsFormStyle() }
}

extension FormStyle where Self == GroupedFormStyle {
    /// A form style that draws each section as a bordered group.
    public static var grouped: GroupedFormStyle { GroupedFormStyle() }
}

// MARK: - Environment

/// Environment key for the form style.
private struct FormStyleKey: EnvironmentKey {
    static let defaultValue: any FormStyle = AutomaticFormStyle()
}

extension EnvironmentValues {
    /// The form style for this environment.
    ///
    /// Controls how ``Form`` views render. Set via the
    /// ``SwiftUICore/View/formStyle(_:)`` modifier. Default: ``AutomaticFormStyle``
    /// (columns).
    public var formStyle: any FormStyle {
        get { self[FormStyleKey.self] }
        set { self[FormStyleKey.self] = newValue }
    }
}

// MARK: - Form Style Modifier

extension View {
    /// Sets the style for forms within this view.
    ///
    /// ```swift
    /// Form { … }
    ///     .formStyle(.grouped)
    /// ```
    ///
    /// - Parameter style: The form style to apply.
    /// - Returns: A view whose forms use the specified style.
    public func formStyle<S: FormStyle>(_ style: S) -> some View {
        environment(\.formStyle, style)
    }
}
