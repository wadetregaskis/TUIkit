//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Form.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Form

/// A container that lays out labelled controls in a consistent, aligned form.
///
/// Mirrors SwiftUI's `Form`. Choose the layout with ``SwiftUICore/View/formStyle(_:)``:
///
/// - ``FormStyle/columns`` (and ``FormStyle/automatic``, the default) — labels
///   right-aligned to a shared pillar of whitespace, controls left-aligned after
///   it. This is the classic macOS form / Settings layout.
/// - ``FormStyle/grouped`` — each ``Section`` drawn as a bordered group.
///
/// Rows are usually ``LabeledContent`` (a label + a control/value); a row that
/// isn't labelled spans the full width. Group rows with ``Section``.
///
/// ```swift
/// Form {
///     Section("Profile") {
///         LabeledContent("Name") { TextField("", text: $name) }
///         LabeledContent("Email") { TextField("", text: $email) }
///     }
///     Section("Preferences") {
///         LabeledContent("Notifications") { Toggle("", isOn: $notify) }
///     }
/// }
/// .formStyle(.grouped)
/// ```
public struct Form<Content: View>: View {
    let content: Content

    /// Creates a form with the given content.
    ///
    /// - Parameter content: A view builder producing the form's rows/sections.
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        _FormLayout(content: content)
    }
}

// MARK: - Form Row Model

/// One form row: a label paired with content, or — when `label` is `nil` — a
/// full-width row.
struct _FormRow {
    var label: AnyView?
    var content: AnyView
}

/// A grouped run of rows with an optional header/footer (from a ``Section``).
struct _FormSection {
    var header: AnyView?
    var footer: AnyView?
    var rows: [_FormRow]
}

/// A top-level form element: a bare row or a section of rows.
enum _FormElement {
    case row(_FormRow)
    case section(_FormSection)
}

// MARK: - Form Content Extraction

/// Views that can contribute rows/sections to a ``Form``.
///
/// Mirrors the ``ButtonProvider`` pattern ``Alert`` uses: the form walks its
/// content tree through this protocol to recover the label/control structure it
/// needs for pillar alignment (a generic `Form<Content>` can't otherwise see
/// inside its opaque content).
@MainActor
protocol FormContentExtractor {
    func extractFormElements() -> [_FormElement]
}

/// Extracts the form elements of `view`: its own contribution if it is a
/// ``FormContentExtractor``, otherwise a single full-width row.
@MainActor
func formElements(from view: some View) -> [_FormElement] {
    if let extractor = view as? FormContentExtractor {
        return extractor.extractFormElements()
    }
    return [.row(_FormRow(label: nil, content: AnyView(view)))]
}

/// Flattens elements to their rows (a section contributes its rows).
private func formRows(of elements: [_FormElement]) -> [_FormRow] {
    elements.flatMap { element -> [_FormRow] in
        switch element {
        case .row(let row): return [row]
        case .section(let section): return section.rows
        }
    }
}

extension LabeledContent: FormContentExtractor {
    func extractFormElements() -> [_FormElement] {
        [.row(_FormRow(label: AnyView(label), content: AnyView(content)))]
    }
}

extension Section: FormContentExtractor {
    func extractFormElements() -> [_FormElement] {
        [.section(_FormSection(
            header: (header is EmptyView) ? nil : AnyView(header),
            footer: (footer is EmptyView) ? nil : AnyView(footer),
            rows: formRows(of: formElements(from: content))))]
    }
}

extension TupleView: FormContentExtractor {
    func extractFormElements() -> [_FormElement] {
        var elements: [_FormElement] = []
        func collect<T: View>(_ view: T) {
            elements.append(contentsOf: formElements(from: view))
        }
        repeat collect(each children)
        return elements
    }
}

extension ForEach: FormContentExtractor {
    func extractFormElements() -> [_FormElement] {
        data.flatMap { element in formElements(from: content(element)) }
    }
}

extension EmptyView: FormContentExtractor {
    func extractFormElements() -> [_FormElement] { [] }
}

// MARK: - Row / element view builders

/// A pillar-aligned row: the label right-aligned in a `pillar`-wide column, the
/// content left-aligned after a one-cell gap. An unlabelled row is full-width.
@MainActor @ViewBuilder
private func formRowView(_ row: _FormRow, pillar: Int) -> some View {
    if let label = row.label {
        HStack(spacing: 1) {
            label.frame(width: pillar, alignment: .trailing)
            row.content
        }
    } else {
        row.content
    }
}

/// Columns layout for one element: rows pillar-aligned; a section renders its
/// (optional) header, its rows, then its (optional) footer, all to one pillar.
@MainActor @ViewBuilder
private func columnsElementView(_ element: _FormElement, pillar: Int) -> some View {
    switch element {
    case .row(let row):
        formRowView(row, pillar: pillar)
    case .section(let section):
        VStack(alignment: .leading, spacing: 0) {
            if let header = section.header { header }
            ForEach(0..<section.rows.count) { index in
                formRowView(section.rows[index], pillar: pillar)
            }
            if let footer = section.footer { footer }
        }
    }
}

/// Grouped layout for one element: a section is a bordered box (header above it);
/// a bare row is rendered as-is.
@MainActor @ViewBuilder
private func groupedElementView(_ element: _FormElement, pillar: Int) -> some View {
    switch element {
    case .row(let row):
        formRowView(row, pillar: pillar)
    case .section(let section):
        VStack(alignment: .leading, spacing: 0) {
            if let header = section.header { header }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<section.rows.count) { index in
                    formRowView(section.rows[index], pillar: pillar)
                }
            }
            .padding(.horizontal, 1)
            .border()
            if let footer = section.footer { footer }
        }
    }
}

// MARK: - Internal Core View

/// Renders a ``Form`` per the active ``FormStyle``. Built-in styles
/// (columns/grouped/automatic) are laid out here directly — they need the form's
/// concrete content type to extract its rows, which the type-erased
/// ``FormStyleConfiguration`` can't carry — while a custom style is dispatched
/// through its ``FormStyle/makeBody(configuration:)``.
private struct _FormLayout<Content: View>: View, Renderable, Layoutable {
    let content: Content

    var body: Never {
        fatalError("_FormLayout renders via Renderable")
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureFixedByRendering(self, proposal: proposal, context: context)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let style = context.environment.formStyle
        let grouped: Bool
        if style is GroupedFormStyle {
            grouped = true
        } else if style is ColumnsFormStyle || style is AutomaticFormStyle {
            grouped = false
        } else {
            // Custom style: hand it the (type-erased) content to render itself.
            return style.makeBuffer(
                configuration: FormStyleConfiguration(content: AnyView(content)), context: context)
        }

        let elements = formElements(from: content)
        let pillar = pillarWidth(of: elements, context: context)

        let composed = VStack(alignment: .leading, spacing: grouped ? 1 : 0) {
            ForEach(0..<elements.count) { index in
                if grouped {
                    groupedElementView(elements[index], pillar: pillar)
                } else {
                    columnsElementView(elements[index], pillar: pillar)
                }
            }
        }
        return TUIkit.renderToBuffer(composed, context: context)
    }

    /// The shared pillar: the widest label across every row (sections included),
    /// so all labels right-align to one column.
    private func pillarWidth(of elements: [_FormElement], context: RenderContext) -> Int {
        formRows(of: elements)
            .compactMap { row -> Int? in
                guard let label = row.label else { return nil }
                return measureChild(
                    label, proposal: ProposedSize(width: nil, height: nil), context: context
                ).width
            }
            .max() ?? 0
    }
}
