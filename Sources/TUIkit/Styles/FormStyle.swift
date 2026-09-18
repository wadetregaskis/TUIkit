//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FormStyle.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - FormStyle

/// The appearance and layout of a ``Form``.
///
/// Set it with the ``View/formStyle(_:)`` modifier:
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
///
/// ## Styles and the render cache
///
/// ``TUIkit/View/formStyle(_:)`` puts the style into the environment, and the
/// render cache keeps memoized subtrees honest by comparing each injected value
/// with the one applied there last frame. A value it cannot compare may have
/// changed under a buffer it is about to serve with nothing able to notice, so
/// every memo below one declines to cache at all — not the form alone, but
/// everything under the modifier, which for a form is usually a whole settings
/// panel.
///
/// All three built-in styles are therefore `Equatable`. None of them holds
/// anything, and they are pure markers: ``Form`` reads the style's TYPE and
/// nothing else, picking the grouped layout for ``GroupedFormStyle`` and the
/// columns layout for the other two. So `==` within a type is vacuously true and
/// two instances of one really do lay out the same form. Between types it is the
/// downcast in the comparison that answers, and a swap from grouped to columns
/// takes away the border the sections were drawn in.
///
/// The comparison is blunter than the presentation, and deliberately so.
/// ``AutomaticFormStyle`` and ``ColumnsFormStyle`` lay out identically —
/// `automatic` resolves to columns here — but a swap between them still compares
/// unequal and clears. That costs a redraw the frame did not need; the error runs
/// toward invalidating, never toward serving a stale buffer.
///
/// A custom style need not conform. One that is not `Equatable` simply turns
/// memoization off below itself, which costs render time rather than
/// correctness.
///
/// - Note: SwiftUI's form styles declare no such conformance, and this is one of
///   the places a terminal renderer has to differ. SwiftUI diffs the view graph
///   the compiler builds for it and never has to ask whether an environment
///   value changed; TUIkit re-runs `body` and compares values, so here the
///   question must be answerable.
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
///
/// `Equatable` for the reason given under ``FormStyle``: a memo below a value the
/// render cache cannot compare declines to cache.
public struct AutomaticFormStyle: FormStyle, Equatable {
    /// Creates an automatic form style.
    public init() {}
}

/// A form style that aligns labels in a right-justified column against a shared
/// pillar of whitespace, with controls left-aligned after it — the classic macOS
/// "Settings" look.
///
/// `Equatable` on the same terms as ``AutomaticFormStyle``. Laying out identically
/// to it does not make it compare equal to it — see ``FormStyle``.
public struct ColumnsFormStyle: FormStyle, Equatable {
    /// Creates a columns form style.
    public init() {}
}

/// A form style that draws each ``Section`` as a bordered group with its title —
/// the grouped (iOS-style) layout.
///
/// `Equatable` on the same terms as ``AutomaticFormStyle``, and this is the half
/// that earns the cross-type comparison: replacing it with either of the others
/// takes the section borders away.
public struct GroupedFormStyle: FormStyle, Equatable {
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
    /// ``View/formStyle(_:)`` modifier. Default: ``AutomaticFormStyle``
    /// (columns).
    ///
    /// The built-in styles are `Equatable` so that a memo below one can still
    /// store — see ``FormStyle`` for why the render cache has to ask.
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
