//  🖥️ TUIKit — Terminal UI Kit for Swift
//  Bindable.swift
//
//  Created by LAYERED.work
//  License: MIT

import Observation

/// A property wrapper that creates bindings to the mutable properties of an
/// observable object.
///
/// Use `@Bindable` when you have an `@Observable` reference you already own —
/// from `@Environment(Model.self)`, a passed-in value, or a `@State` object —
/// and you want to hand a `Binding` to one of its properties to a control:
///
/// ```swift
/// @Observable final class Settings { var name = ""; var enabled = false }
///
/// struct SettingsView: View {
///     @Bindable var settings: Settings   // not a source of truth — a wrapper
///
///     var body: some View {
///         VStack {
///             TextField("Name", text: $settings.name)
///             Toggle("Enabled", isOn: $settings.enabled)
///         }
///     }
/// }
/// ```
///
/// Unlike `@State`, `@Bindable` is **not** a source of truth: it holds no
/// storage of its own and takes no part in render-identity binding. It simply
/// wraps a reference the developer already owns, and `$settings.field` derives a
/// `Binding` that reads and writes straight through that reference. Mutations
/// made through such a binding trigger a re-render via the same observation
/// tracking any other `@Observable` write does — no explicit invalidation.
///
/// Mirrors SwiftUI's `Bindable`.
@propertyWrapper
@dynamicMemberLookup
public struct Bindable<Value> {
    /// The observable object this wrapper projects bindings into.
    public var wrappedValue: Value

    /// The bindable wrapper itself (accessed via the `$` projection).
    public var projectedValue: Bindable<Value> {
        self
    }

    /// Re-wraps an existing bindable projection.
    ///
    /// Mirrors SwiftUI's `Bindable(projectedValue:)`; used by generic code and
    /// macros that re-wrap a `$value` projection.
    public init(projectedValue: Bindable<Value>) {
        self = projectedValue
    }

    /// Derives a `Binding` to a mutable property of the wrapped object.
    ///
    /// This is what makes `$model.field` yield a `Binding`: the derived binding
    /// reads and writes the addressed member directly through the object
    /// reference (no whole-value copy-back — the object is a class). The
    /// `ReferenceWritableKeyPath` requirement means this subscript only applies
    /// when `Value` is a reference type, matching SwiftUI.
    public subscript<Subject>(
        dynamicMember keyPath: ReferenceWritableKeyPath<Value, Subject>
    ) -> Binding<Subject> {
        let object = wrappedValue
        return Binding<Subject>(
            get: { object[keyPath: keyPath] },
            set: { object[keyPath: keyPath] = $0 }
        )
    }
}

extension Bindable where Value: AnyObject, Value: Observable {
    /// Wraps an observable object (the `@Bindable var settings = …` form).
    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }

    /// Wraps an observable object (the `Bindable(settings)` form).
    public init(_ wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }
}
