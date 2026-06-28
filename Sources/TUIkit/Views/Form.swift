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
/// - ``FormStyle/columns`` (and ``FormStyle/automatic``, the default) — the
///   classic macOS layout: field labels right-aligned to a shared pillar, controls
///   left-aligned in the column after it, push buttons right-aligned, section
///   headers bold and right-aligned to the pillar, sections separated by a blank
///   line.
/// - ``FormStyle/grouped`` — each ``Section`` drawn as a bordered group.
///
/// Row kinds follow macOS conventions:
///
/// - **Field rows** — `LabeledContent("Name") { TextField(…) }` (also `Picker`,
///   `Slider`, `Stepper`, value rows): a right-aligned field label, then the control.
/// - **Checkboxes / radios** — a `Toggle("Wi-Fi", isOn:)` or `RadioButtonGroup`
///   used directly (with its own label) sits in the control column, box first,
///   and the **whole control (box, gap, and label) is clickable** — so don't wrap
///   it in `LabeledContent` unless you want a separate field label to its left.
/// - **Buttons** — a `Button` is right-aligned (macOS places confirmation buttons
///   on the right).
///
/// ```swift
/// Form {
///     Section("Profile") {
///         LabeledContent("Name") { TextField("", text: $name) }
///     }
///     Section("Notifications") {
///         Toggle("Push", isOn: $push)          // box-first, fully clickable
///         Button("Sign Out", role: .destructive) {}   // right-aligned
///     }
/// }
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

/// One form row, by kind — each laid out per macOS form conventions.
enum _FormRow {
    /// A field: right-aligned pillar label + a control/value left-aligned after it.
    case field(label: AnyView, content: AnyView)
    /// A self-labelled control (checkbox/radio): box-first, in the control column,
    /// with its own (clickable) label.
    case control(AnyView)
    /// A push button: right-aligned to the form's content width.
    case button(AnyView)
    /// Anything else: a full-width row.
    case plain(AnyView)
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

// MARK: - Row-kind markers

/// A self-labelled control that a ``Form`` places in the control column with its
/// own clickable label (a checkbox/radio), rather than pulling a label to the
/// pillar. Conformed by ``Toggle`` and ``RadioButtonGroup``.
protocol FormControlRow {}

/// A control a ``Form`` right-aligns (a push button). Conformed by ``Button``.
protocol FormButtonRow {}

extension Toggle: FormControlRow {}
extension RadioButtonGroup: FormControlRow {}
extension Button: FormButtonRow {}

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
/// ``FormContentExtractor``; otherwise a control row (checkbox/radio), a button
/// row, or a plain full-width row depending on its kind.
@MainActor
func formElements(from view: some View) -> [_FormElement] {
    if let extractor = view as? FormContentExtractor {
        return extractor.extractFormElements()
    }
    if view is FormControlRow {
        return [.row(.control(AnyView(view)))]
    }
    if view is FormButtonRow {
        return [.row(.button(AnyView(view)))]
    }
    return [.row(.plain(AnyView(view)))]
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
        [.row(.field(label: AnyView(label), content: AnyView(content)))]
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

// MARK: - Row view builder

/// Where the control column begins: one cell past the label pillar (the ~6pt
/// label/control gap), or column 0 when there are no field labels.
private func controlIndent(pillar: Int) -> Int { pillar == 0 ? 0 : pillar + 1 }

/// Builds one row's view. Buttons are framed to `contentWidth` so they
/// right-align to the form's content edge; checkbox/radio controls are indented
/// to the control column; fields put a right-aligned label in the pillar.
@MainActor @ViewBuilder
private func formRowView(_ row: _FormRow, pillar: Int, contentWidth: Int) -> some View {
    switch row {
    case .field(let label, let content):
        HStack(spacing: 1) {
            label.frame(width: pillar, alignment: .trailing)
            content
        }
    case .control(let view):
        view.padding(.leading, controlIndent(pillar: pillar))
    case .button(let view):
        // Right-align to the content edge in columns; natural width when
        // contentWidth is 0 (grouped passes 0 — right-alignment is a columns rule).
        if contentWidth > 0 {
            view.frame(width: contentWidth, alignment: .trailing)
        } else {
            view
        }
    case .plain(let view):
        view
    }
}

/// A bold section header right-aligned to the pillar (left-aligned when there are
/// no field labels). There is no direct AppKit analogue for a header in a columns
/// form, so it is aligned with the field labels.
@MainActor @ViewBuilder
private func sectionHeaderView(_ header: AnyView, pillar: Int) -> some View {
    if pillar > 0 {
        header.bold().frame(width: pillar, alignment: .trailing)
    } else {
        header.bold()
    }
}

/// Columns layout for one element: rows pillar-aligned; a section renders a
/// leading blank line (except the first), its bold right-aligned header, its
/// rows, then its footer — all to one pillar.
@MainActor @ViewBuilder
private func columnsElementView(
    _ element: _FormElement, pillar: Int, contentWidth: Int, isFirst: Bool
) -> some View {
    switch element {
    case .row(let row):
        formRowView(row, pillar: pillar, contentWidth: contentWidth)
    case .section(let section):
        VStack(alignment: .leading, spacing: 0) {
            if !isFirst { Text("") }  // blank line between sections
            if let header = section.header { sectionHeaderView(header, pillar: pillar) }
            ForEach(0..<section.rows.count) { index in
                formRowView(section.rows[index], pillar: pillar, contentWidth: contentWidth)
            }
            if let footer = section.footer { footer }
        }
    }
}

/// Grouped layout for one element: a section is a content-sized bordered box (its
/// title bold above it); a bare row renders as-is. Buttons aren't right-aligned
/// here — that is a columns rule — so `contentWidth` is 0.
@MainActor @ViewBuilder
private func groupedElementView(_ element: _FormElement, pillar: Int) -> some View {
    switch element {
    case .row(let row):
        formRowView(row, pillar: pillar, contentWidth: 0)
    case .section(let section):
        VStack(alignment: .leading, spacing: 0) {
            if let header = section.header { header.bold() }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<section.rows.count) { index in
                    formRowView(section.rows[index], pillar: pillar, contentWidth: 0)
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
        let contentWidth = grouped ? 0 : contentWidth(of: elements, pillar: pillar, context: context)

        let composed = VStack(alignment: .leading, spacing: grouped ? 1 : 0) {
            ForEach(0..<elements.count) { index in
                if grouped {
                    groupedElementView(elements[index], pillar: pillar)
                } else {
                    columnsElementView(
                        elements[index], pillar: pillar, contentWidth: contentWidth,
                        isFirst: index == 0)
                }
            }
        }
        return TUIkit.renderToBuffer(composed, context: context)
    }

    /// The shared pillar: the widest field label across every row (sections
    /// included), so all field labels right-align to one column.
    private func pillarWidth(of elements: [_FormElement], context: RenderContext) -> Int {
        formRows(of: elements)
            .compactMap { row -> Int? in
                guard case .field(let label, _) = row else { return nil }
                return measureChild(
                    label, proposal: ProposedSize(width: nil, height: nil), context: context
                ).width
            }
            .max() ?? 0
    }

    /// The form's content width: the widest non-button row (buttons are sized to
    /// this so they right-align to the content edge in columns).
    private func contentWidth(of elements: [_FormElement], pillar: Int, context: RenderContext) -> Int {
        formRows(of: elements)
            .compactMap { row -> Int? in
                if case .button = row { return nil }
                return measureChild(
                    formRowView(row, pillar: pillar, contentWidth: 0),
                    proposal: ProposedSize(width: nil, height: nil), context: context
                ).width
            }
            .max() ?? 0
    }
}
