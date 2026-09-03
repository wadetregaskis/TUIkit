//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DemoSection.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// A section with a styled title and content.
///
/// Used to group related demo content with a yellow underlined title.
///
/// # Example
///
/// ```swift
/// DemoSection("page.buttons.section.styles") {
///     Text("Feature 1")
///     Text("Feature 2")
/// }
/// ```
///
/// The title follows the framework's rule: a string **literal** is a
/// `LocalizedStringKey` and is looked up, a computed `String` is displayed as
/// given. An app's own components have to spell out the pair themselves — this
/// one is the reference for the rest of the demo components.
struct DemoSection<Content: View>: View {
    let title: String
    let content: Content

    /// Creates a section with a localized title.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the section title.
    ///   - content: The section's content.
    init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.init(titleKey.localized, content: content)
    }

    /// Creates a section titled as written.
    ///
    /// Generic over `StringProtocol` rather than taking a concrete `String`,
    /// which is what keeps a *literal* binding to the key overload above — see
    /// ``LocalizedStringKey``. A literal already binds correctly here as it
    /// stands, because the `@ViewBuilder` argument is generic over `Content` and
    /// that is enough to tip the ranking; the point of spelling it this way is
    /// that the title no longer depends on the shape of its neighbours to be
    /// looked up.
    ///
    /// - Parameters:
    ///   - title: The section title.
    ///   - content: The section's content.
    @_disfavoredOverload
    init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {
        self.title = String(title)
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .bold()
                .underline()
                .foregroundStyle(.palette.accent)
                // Render the title as a themeable section header so it picks up the
                // app-wide `.chrome(.sectionHeader)` styling — e.g. the Theme page's
                // "UPPERCASE section headers" toggle drives its textCase. The local
                // `dim = false` overrides the chrome role's default dimming (which is
                // for plain section headers), keeping these bold-underline-accent
                // headers crisp; only textCase is inherited from the cascade.
                .environment(\.chromeRole, .sectionHeader)
                .style(.chrome(.sectionHeader)) { $0.dim = false }
            content
        }
    }
}
