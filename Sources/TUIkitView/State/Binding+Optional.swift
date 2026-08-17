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
    /// Unwraps a binding to an optional, or returns `nil` if there is nothing
    /// in it — mirrors SwiftUI's `Binding(_:)`.
    ///
    /// This is the other answer to the question ``defaulted(to:)`` answers, and
    /// which one you want depends on what "absent" means to the *interface*
    /// rather than to the data:
    ///
    /// ```swift
    /// // Absent means "off": show the control, decide what nil draws as.
    /// Toggle(feature, isOn: $enabled[feature].defaulted(to: false))
    ///
    /// // Absent means "nothing to edit": show no control at all.
    /// if let name = Binding($profile.nickname) {
    ///     TextField("field.nickname", text: name)
    /// } else {
    ///     Button("button.addNickname") { profile.nickname = "" }
    /// }
    /// ```
    ///
    /// Being failable is the whole point: it moves the decision to a place
    /// where the view hierarchy can branch, so the absent case gets its own
    /// interface instead of a control editing a value that is not there.
    ///
    /// # It does not observe the source becoming nil
    ///
    /// Emptiness is checked **once**, when the binding is made. The returned
    /// binding writes straight through, and if the source is set to `nil`
    /// elsewhere a read falls back to the value that was present at
    /// construction rather than trapping. The `if let` is re-evaluated on the
    /// next frame — the tree is rebuilt every frame — so the branch corrects
    /// itself immediately; this only decides what happens in between, and
    /// returning the last known value is the answer that cannot crash. SwiftUI
    /// behaves the same way, for the same reason.
    ///
    /// - Parameter base: A binding to an optional value.
    public init?(_ base: Binding<Value?>) {
        guard let initial = base.wrappedValue else { return nil }
        self.init(
            get: { base.wrappedValue ?? initial },
            set: { base.wrappedValue = $0 })
    }

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
