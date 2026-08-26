//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Appearance.swift
//
//  Created by LAYERED.work
//  License: MIT
//  Appearance defines the visual style of controls (border style, etc.),
//  while Theme defines the colors. Together they create a complete look.
//

// MARK: - Appearance

/// Defines the visual appearance of UI controls.
///
/// `Appearance` controls the structural styling of UI elements like border styles,
/// while `Theme` controls the colors. Together they create a complete visual design.
///
/// # Usage
///
/// Set appearance at the app level:
///
/// ```swift
/// @main
/// struct MyApp: App {
///     var body: some Scene {
///         WindowGroup {
///             ContentView()
///         }
///         .appearance(.rounded)
///         .theme(.amber)
///     }
/// }
/// ```
///
/// Or override locally:
///
/// ```swift
/// Panel("Bold Section") {
///     content()
/// }
/// .appearance(.heavy)
/// ```
///
/// Access in `renderToBuffer(context:)`:
///
/// ```swift
/// let appearance = context.environment.appearance
/// let style = appearance.borderStyle
/// ```
public struct Appearance: Cyclable, Hashable {
    /// Unique identifier for the appearance (conforms to ``Cyclable``).
    public var id: String { rawId.rawValue }

    /// The type-safe identifier.
    public let rawId: ID

    /// The border style used for all controls.
    public let borderStyle: BorderStyle

    /// Creates a custom appearance.
    ///
    /// - Parameters:
    ///   - id: The unique identifier.
    ///   - borderStyle: The border style to use for controls.
    public init(id: ID, borderStyle: BorderStyle) {
        self.rawId = id
        self.borderStyle = borderStyle
    }

    /// Human-readable name derived from ID (conforms to ``Cyclable``).
    public var name: String {
        rawId.rawValue.capitalized
    }

    /// Equatable conformance based on the type-safe ID.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.rawId == rhs.rawId && lhs.borderStyle == rhs.borderStyle
    }

    /// Hashes exactly what ``==`` compares. Hand-written because the custom
    /// `==` above suppresses synthesis; `id` and `name` are derived from
    /// `rawId`, so they add nothing.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawId)
        hasher.combine(borderStyle)
    }
}

// MARK: - Appearance ID

extension Appearance {
    /// Type-safe identifier for appearances.
    ///
    /// IDs match `BorderStyle` names for consistency.
    ///
    /// ```swift
    /// // Predefined (matching BorderStyle names)
    /// Appearance.ID.line
    /// Appearance.ID.rounded
    /// Appearance.ID.doubleLine
    ///
    /// // Custom
    /// extension Appearance.ID {
    ///     static let myCustom = ID(rawValue: "my-custom")
    /// }
    /// ```
    public struct ID: RawRepresentable, Hashable, Sendable {
        /// The string identifier for this appearance.
        public let rawValue: String

        /// Creates an appearance ID from a raw string value.
        ///
        /// - Parameter rawValue: The string identifier.
        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        /// Single line borders (┌─┐).
        public static let line = Self(rawValue: "line")

        /// Rounded corners (╭─╮).
        public static let rounded = Self(rawValue: "rounded")

        /// Double-line borders (╔═╗).
        public static let doubleLine = Self(rawValue: "doubleLine")

        /// Heavy/bold borders (┏━┓).
        public static let heavy = Self(rawValue: "heavy")

        /// A solid band of full blocks (███), in the border colour.
        public static let block = Self(rawValue: "block")

        /// A blank one-cell inset, in whatever is behind it.
        public static let blank = Self(rawValue: "blank")
    }
}

// MARK: - Predefined Appearances

extension Appearance {
    /// Single line borders.
    ///
    /// Uses `BorderStyle.line` with standard box-drawing characters.
    public static let line = Appearance(id: .line, borderStyle: .line)

    /// Rounded corners (default).
    ///
    /// Uses `BorderStyle.rounded` with curved corner characters.
    public static let rounded = Appearance(id: .rounded, borderStyle: .rounded)

    /// Double-line borders.
    ///
    /// Uses `BorderStyle.doubleLine` for a more prominent look.
    public static let doubleLine = Appearance(id: .doubleLine, borderStyle: .doubleLine)

    /// Heavy/bold borders.
    ///
    /// Uses `BorderStyle.heavy` for bold, prominent borders.
    public static let heavy = Appearance(id: .heavy, borderStyle: .heavy)

    /// A solid band of full blocks, drawn in the border colour.
    ///
    /// The heaviest a border gets: a band of colour around the content rather
    /// than a line drawn near it.
    public static let block = Appearance(id: .block, borderStyle: .block)

    /// A blank one-cell inset, showing whatever is behind it.
    ///
    /// The other half of the pair, and the quietest border there is: the same
    /// geometry as every other appearance — the content still sits one cell in
    /// from where it would otherwise — with nothing drawn to mark it. Useful
    /// where the chrome should give the content room without framing it.
    public static let blank = Appearance(id: .blank, borderStyle: .none)

    /// The default appearance (rounded).
    public static let `default`: Appearance = .rounded
}

// MARK: - Appearance Registry

/// Registry of available appearances for cycling.
public struct AppearanceRegistry {
    /// All available appearances in cycling order.
    ///
    /// Order: rounded (default) → line → doubleLine → heavy → block → blank
    ///
    /// Roughly by weight, so cycling with the appearance key walks from the
    /// usual to the extremes rather than jumping between them.
    public static let all: [Appearance] = [
        .rounded,
        .line,
        .doubleLine,
        .heavy,
        .block,
        .blank,
    ]

    /// Finds an appearance by ID.
    ///
    /// - Parameter id: The appearance ID to find.
    /// - Returns: The appearance, or nil if not found.
    public static func appearance(withId id: Appearance.ID) -> Appearance? {
        all.first { $0.rawId == id }
    }
}
