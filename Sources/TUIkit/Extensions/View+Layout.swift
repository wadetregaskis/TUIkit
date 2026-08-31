//  🖥️ TUIkit — Terminal UI Kit for Swift
//  View+Layout.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Border

extension View {
    /// Adds a border around this view.
    ///
    /// Content is inset by 1 character on each side so text doesn't touch
    /// the border characters. The total width overhead is 4 characters
    /// (2 for borders + 2 for inner padding).
    ///
    /// Internally this creates a `ContainerView` without title or footer,
    /// ensuring consistent padding and rendering across all bordered views.
    ///
    /// # Example
    ///
    /// ```swift
    /// Text("Hello")
    ///     .border()               // the appearance's style, the palette's colour
    ///
    /// Text("Warning")
    ///     .border(.red)           // SwiftUI's spelling, and it means the same
    ///
    /// Text("Rounded")
    ///     .border(.cyan, style: .rounded)
    ///
    /// Text("Emphatic")
    ///     .border(.yellow, style: .doubleLine, width: 2)
    /// ```
    ///
    /// The colour comes first and unlabelled because that is where SwiftUI puts
    /// it: `border(_ content: some ShapeStyle, width: CGFloat = 1)`. A terminal
    /// border has something SwiftUI's has not — the box-drawing characters it
    /// is made of — so `style:` is added rather than substituted, and the two
    /// spellings agree on everything they share.
    ///
    /// - Parameters:
    ///   - colour: The border colour.
    ///   - style: The box-drawing characters (default: the appearance's).
    ///   - width: How many concentric rings to draw, in CELLS — a terminal has
    ///     no fractional stroke, so a thicker border is literally a border
    ///     around a border. `0` draws none; values above 1 nest.
    /// - Returns: A view with a border.
    public func border(
        _ colour: Color,
        style: BorderStyle? = nil,
        width: Int = 1
    ) -> some View {
        bordered(style: style, colour: AnimatedColor(colour), width: width)
    }

    /// A border whose colour breathes, blinks, or otherwise moves.
    ///
    /// The cheap way to show that your own view holds the focus. The border is
    /// drawn here, so it is this modifier — not the caller — that knows which
    /// cells to animate, and it leaves ``AnimatedCellRun``s for them. Nothing
    /// re-renders per tick.
    ///
    /// ```swift
    /// Text("Right-click me")
    ///     .border(emphasis.animatedColor(
    ///         isFocused, dim: palette.border, bright: palette.accent))
    /// ```
    ///
    /// A still ``AnimatedColor`` (an unfocused element, or a
    /// `.selectionIndicatorStyle(.none)`) simply draws its one colour and
    /// leaves nothing behind, so the call site need not branch.
    ///
    /// - Parameters:
    ///   - colour: The border colour, as every frame of its cycle.
    ///   - style: The box-drawing characters (default: the appearance's).
    ///   - width: Concentric rings, in cells. Every ring animates.
    /// - Returns: A view with a border that moves.
    public func border(
        _ colour: AnimatedColor,
        style: BorderStyle? = nil,
        width: Int = 1
    ) -> some View {
        bordered(style: style, colour: colour, width: width)
    }

    /// A border in the palette's own colour — the terminal-native spelling,
    /// where the theme decides and the call site does not have to.
    ///
    /// SwiftUI has no equivalent because it has no palette: there, a border
    /// with no colour is `border(.foreground)`. Here it is what nearly every
    /// call wants, so it stays available rather than forcing a colour that a
    /// theme change would then have to fight.
    ///
    /// - Parameters:
    ///   - style: The box-drawing characters (default: the appearance's).
    ///   - width: Concentric rings, in cells.
    /// - Returns: A view with a border.
    public func border(
        style: BorderStyle? = nil,
        width: Int = 1
    ) -> some View {
        bordered(style: style, colour: nil, width: width)
    }

    /// The one implementation both spellings funnel through, and the one the
    /// framework's own chrome calls when its colour is already an `Optional`
    /// (a menu or popover whose caller may or may not have named one).
    ///
    /// `width` nests rather than thickens: each ring is another
    /// `ContainerView` around the last, which is exactly what a two-cell
    /// border looks like on a grid that has no half-cells.
    @ViewBuilder
    func bordered(style: BorderStyle?, colour: AnimatedColor?, width: Int) -> some View {
        if width <= 0 {
            self
        } else {
            (1..<max(1, width)).reduce(
                AnyView(ring(style: style, colour: colour))
            ) { inner, _ in
                AnyView(inner.ring(style: style, colour: colour))
            }
        }
    }

    /// One border, drawn as the titleless container it has always been.
    private func ring(style: BorderStyle?, colour: AnimatedColor?) -> some View {
        ContainerView(
            style: ContainerStyle(
                showHeaderSeparator: false,
                showFooterSeparator: false,
                borderStyle: style,
                borderColor: colour
            )
        ) {
            self
        }
    }
}

// MARK: - Dimmed

extension View {
    /// Applies a dimming effect to the view content.
    ///
    /// This reduces the visual intensity of the content using the ANSI dim
    /// escape code — a purely visual change.
    ///
    /// Dimmed content is **inert**: what looks recessive is recessive. It is
    /// not a Tab stop, its `onKeyPress` and `.keyboardShortcut` do not fire, it
    /// publishes no status-bar items, and it is not clickable. Its `@State` and
    /// scroll position survive, so undimming brings it back as it was.
    ///
    /// > Important: inert is still not the same as **modal**. This dims and
    /// > deadens the content it is applied to and nothing else: it does not
    /// > centre a dialog on the screen, capture focus into a section of its
    /// > own, publish ESC to dismiss, or stop a sibling elsewhere in the tree
    /// > from being reached. Present a ``Dialog`` or an ``Alert`` through
    /// > ``SwiftUICore/View/modal(isPresented:onDismiss:content:)`` or
    /// > ``SwiftUICore/View/alert(_:isPresented:actions:message:)``, which do
    /// > all of that; `.dimmed()` is for content you want recessive in place.
    ///
    /// It also **drops** anything the content floated: a presentation, a
    /// `Picker` drop-down or a context menu inside a `.dimmed()` subtree is
    /// discarded, by construction — a backdrop is meant to be flat and inert.
    ///
    /// # Example
    ///
    /// ```swift
    /// VStack {
    ///     Text("This content will be dimmed")
    ///     Text("All text is affected")
    /// }
    /// .dimmed()
    /// ```
    ///
    /// - Returns: A view with the dimming effect applied.
    public func dimmed() -> some View {
        DimmedModifier(content: self)
    }
}

// MARK: - Background

extension View {
    /// Adds a background color to this view.
    ///
    /// # Example
    ///
    /// ```swift
    /// Text("Warning!")
    ///     .foregroundStyle(.black)
    ///     .background(.yellow)
    ///
    /// VStack {
    ///     Text("Header")
    /// }
    /// .background(.blue)
    /// ```
    ///
    /// - Parameter color: The background color.
    /// - Returns: A view with the background color applied.
    public func background<S: ShapeStyle>(_ style: S) -> some View {
        modifier(BackgroundModifier(style: style))
    }

    /// The colour spelling, so `.background(.red)` and
    /// `.background(.palette.surface)` keep inferring what they always did —
    /// the same `@_disfavoredOverload` pair `foregroundStyle` uses, and that
    /// Apple ships for `tint`.
    @_disfavoredOverload
    public func background(_ color: Color) -> some View {
        modifier(BackgroundModifier(style: color))
    }
}

// MARK: - Frame

extension View {
    /// Sets an explicit frame size for this view.
    ///
    /// The content is aligned within the frame according to the specified alignment.
    ///
    /// # Example
    ///
    /// ```swift
    /// Text("Hello")
    ///     .frame(width: 20, alignment: .center)
    /// ```
    ///
    /// - Parameters:
    ///   - width: The desired width in characters (nil preserves intrinsic width).
    ///   - height: The desired height in lines (nil preserves intrinsic height).
    ///   - alignment: The alignment within the frame (default: .topLeading).
    ///     This **intentionally** differs from SwiftUI's `.center`: a terminal
    ///     reads from the top-left, and a fixed `.frame(width:)` is overwhelmingly
    ///     used to make a left-aligned, fixed-width column (labels, channel
    ///     sliders, table cells), not to centre content in slack space. Centring
    ///     by default would surprise TUI authors and silently shift such columns.
    ///     Pass an explicit `alignment:` when you do want centring.
    /// - Returns: A view constrained to the specified frame.
    public func frame(
        width: Int? = nil,
        height: Int? = nil,
        alignment: Alignment = .topLeading
    ) -> some View {
        FlexibleFrameView(
            content: self,
            minWidth: width,
            idealWidth: width,
            maxWidth: width.map { .fixed($0) },
            minHeight: height,
            idealHeight: height,
            maxHeight: height.map { .fixed($0) },
            alignment: alignment
        )
    }

    /// Sets flexible frame constraints for this view.
    ///
    /// Use `.infinity` for maxWidth/maxHeight to expand to fill available space.
    ///
    /// # Examples
    ///
    /// ```swift
    /// // Expand to full width
    /// Text("Hello")
    ///     .frame(maxWidth: .infinity)
    ///
    /// // Expand to full size
    /// Color.blue
    ///     .frame(maxWidth: .infinity, maxHeight: .infinity)
    ///
    /// // Minimum size with expansion
    /// Text("Button")
    ///     .frame(minWidth: 10, maxWidth: .infinity)
    /// ```
    ///
    /// - Parameters:
    ///   - minWidth: Minimum width in characters.
    ///   - idealWidth: Preferred width (used when no max is set).
    ///   - maxWidth: Maximum width, or `.infinity` to fill available space.
    ///   - minHeight: Minimum height in lines.
    ///   - idealHeight: Preferred height (used when no max is set).
    ///   - maxHeight: Maximum height, or `.infinity` to fill available space.
    ///   - alignment: The alignment within the frame (default: .center).
    /// - Returns: A view with flexible frame constraints.
    public func frame(
        minWidth: Int? = nil,
        idealWidth: Int? = nil,
        maxWidth: FrameDimension? = nil,
        minHeight: Int? = nil,
        idealHeight: Int? = nil,
        maxHeight: FrameDimension? = nil,
        alignment: Alignment = .center
    ) -> some View {
        FlexibleFrameView(
            content: self,
            minWidth: minWidth,
            idealWidth: idealWidth,
            maxWidth: maxWidth,
            minHeight: minHeight,
            idealHeight: idealHeight,
            maxHeight: maxHeight,
            alignment: alignment
        )
    }
}

// MARK: - Overlay

extension View {
    /// Layers the specified view on top of this view.
    ///
    /// The overlay is positioned according to the specified alignment
    /// within the bounds of the base view.
    ///
    /// # Example
    ///
    /// ```swift
    /// Text("Background content here")
    ///     .overlay(alignment: .center) {
    ///         Text("Centered overlay")
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - alignment: The alignment of the overlay (default: .center).
    ///   - content: The overlay content.
    /// - Returns: A view with the overlay applied.
    public func overlay<Overlay: View>(
        alignment: Alignment = .center,
        @ViewBuilder content: () -> Overlay
    ) -> some View {
        OverlayModifier(base: self, overlay: content(), alignment: alignment)
    }
}

// MARK: - Padding

extension View {
    /// Adds padding on all sides.
    ///
    /// In a terminal context, 1 unit of padding means:
    /// - **Vertical (top/bottom):** 1 line
    /// - **Horizontal (leading/trailing):** 1 character
    ///
    /// ```swift
    /// Text("Hello")
    ///     .padding(2)   // 2 lines top/bottom, 2 chars left/right
    /// ```
    ///
    /// - Parameter length: The padding amount on all sides.
    /// - Returns: A padded view.
    public func padding(_ length: Int) -> some View {
        modifier(PaddingModifier(insets: EdgeInsets(all: length)))
    }

    /// Adds padding on specific edges.
    ///
    /// In a terminal context, 1 unit of padding means:
    /// - **Vertical (top/bottom):** 1 line
    /// - **Horizontal (leading/trailing):** 1 character
    ///
    /// When called without arguments, `.padding()` adds 1 unit on all sides.
    ///
    /// ```swift
    /// Text("Hello")
    ///     .padding()                // 1 unit on all sides
    ///     .padding(.horizontal, 4)  // 4 chars left and right
    ///     .padding(.vertical, 2)    // 2 lines top and bottom
    /// ```
    ///
    /// - Parameters:
    ///   - edges: The edges to pad (default: `.all`).
    ///   - length: The padding amount (default: 1).
    /// - Returns: A padded view.
    public func padding(_ edges: Edge.Set = .all, _ length: Int = 1) -> some View {
        let insets = EdgeInsets(
            top: edges.contains(.top) ? length : 0,
            leading: edges.contains(.leading) ? length : 0,
            bottom: edges.contains(.bottom) ? length : 0,
            trailing: edges.contains(.trailing) ? length : 0
        )
        return modifier(PaddingModifier(insets: insets))
    }

    /// Adds padding with explicit edge insets.
    ///
    /// ```swift
    /// Text("Hello")
    ///     .padding(EdgeInsets(top: 1, leading: 4, bottom: 1, trailing: 4))
    /// ```
    ///
    /// - Parameter insets: The edge insets.
    /// - Returns: A padded view.
    public func padding(_ insets: EdgeInsets) -> some View {
        modifier(PaddingModifier(insets: insets))
    }
}
