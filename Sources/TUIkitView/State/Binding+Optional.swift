//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Binding+Optional.swift
//
//  Handing a `Binding` to an optional to a control that wants a non-optional
//  one. Dictionary entries arrive in exactly that shape: `$settings[key]` is a
//  `Binding<Value?>`, because a key that isn't there has no value.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Optional bindings

extension Binding {
    /// Substitutes a value for `nil`, producing a binding a control can take.
    ///
    /// A `Binding<Value?>` is what you get for anything that might be absent —
    /// most often an entry in a dictionary:
    ///
    /// ```swift
    /// @State private var enabled: [String: Bool] = [:]
    ///
    /// var body: some View {
    ///     ForEach(features, id: \.self) { feature in
    ///         Toggle(feature, isOn: $enabled[feature].defaulted(to: false))
    ///     }
    /// }
    /// ```
    ///
    /// ``Toggle`` wants a `Binding<Bool>` — it has to draw a checkbox one way
    /// or the other, and "absent" is not a third way to draw it. This decides
    /// which way absent means, once, at the call site where the answer is
    /// known, and hands on a binding of the type the control asked for.
    ///
    /// # Writing creates the entry
    ///
    /// The returned binding writes straight through, so the first change to a
    /// row **inserts** it — including a change back to the fallback. Toggle a
    /// feature on and off again and the dictionary holds `[feature: false]`,
    /// not `[:]`. For "which of these are selected" that is usually right, and
    /// it is why this does not try to be clever and remove the key: a binding
    /// whose setter sometimes deletes the thing it is bound to is a surprise,
    /// and a `Set` is the better model for a collection that should only hold
    /// what was chosen.
    ///
    /// # Why the fallback is a value, not an autoclosure
    ///
    /// `Dictionary.subscript(_:default:)` takes an `@autoclosure`, evaluated
    /// only on a miss. This takes a plain value, evaluated once when the
    /// binding is made. A binding is read every frame, by every render pass
    /// that touches the control, so an expression re-evaluated per read would
    /// be re-evaluated a great many times for a value that cannot change the
    /// outcome. (It is also the reason `$dictionary[key, default: false]` does
    /// not compile in the first place — an autoclosure argument cannot form
    /// the key path a dynamic-member subscript needs. That is equally true of
    /// SwiftUI; see `Documentation/SwiftUI-compatibility.md`.)
    ///
    /// # TUIkit-only
    ///
    /// SwiftUI has no equivalent, so code using this will not port unchanged.
    /// The portable spelling is the longhand it saves:
    ///
    /// ```swift
    /// Binding(get: { enabled[feature] ?? false },
    ///         set: { enabled[feature] = $0 })
    /// ```
    ///
    /// - Parameter fallback: The value the binding reads when the wrapped
    ///   value is `nil`. Captured once, not re-evaluated per read.
    /// - Returns: A binding to the same storage, never `nil`.
    public func defaulted<T>(to fallback: T) -> Binding<T> where Value == T? {
        Binding<T>(
            get: { self.wrappedValue ?? fallback },
            // Writes through unconditionally, so a dictionary entry that was
            // absent is created here — see the note above on why that is the
            // deliberate behaviour and not an oversight.
            set: { self.wrappedValue = $0 })
    }
}
