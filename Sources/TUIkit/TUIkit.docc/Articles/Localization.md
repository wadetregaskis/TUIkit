# Localization

Build multilingual terminal applications with TUIkit's comprehensive internationalization system.

## Overview

TUIkit provides built-in support for 7 languages: English, German, French, Italian, Spanish, Simplified Chinese, and Japanese. All framework strings use a type-safe, dot-notation based localization system with persistent language preferences and automatic fallback chains.

### Key Features

- **Type-safe keys**: Compile-time verified `LocalizationKey` enums with IDE autocomplete
- **7 languages built-in**: EN, DE, FR, IT, ES, ZH, JA with complete translations
- **Persistent storage**: Language preference saved and restored per-app, in the platform config directory (macOS Application Support, Linux XDG config)
- **Fallback chain**: Current language → English → key itself for graceful degradation
- **Thread-safe**: Safe language switching from any thread at runtime
- **JSON-based**: Easy to extend with new strings and languages

## Quick Start

### Display Localized Strings

Use `LocalizedString` to show localized text:

```swift
import TUIkit

VStack {
    LocalizedString(LocalizationKey.Button.ok)
    LocalizedString(LocalizationKey.Error.notFound)
    LocalizedString(LocalizationKey.Dialog.confirm)
}
```

Or use the `Text(localized:)` convenience initializer:

```swift
Text(localized: LocalizationKey.Button.save)
```

### A String Literal Is Already a Key

Every control that takes a title also takes a ``LocalizedStringKey``, and a
string **literal** binds there — so the plainest spelling is already localized:

```swift
Text("button.save")       // looked up
Text(fileName)            // NOT looked up — a computed String is content
Text(verbatim: "literal") // opted out explicitly
```

This is SwiftUI's rule, and nothing about it is magic: ``Text`` has one
initializer taking a `LocalizedStringKey` and another generic over
`StringProtocol`, and the generic one is marked `@_disfavoredOverload` so a
literal picks the key. A `String` you computed cannot become a key, so a file
path or a person's name is never looked up by accident.

Nothing breaks if a key is missing. Lookup falls back to English and then to
the key itself, so an app that registers no translations displays exactly the
literals it wrote.

#### It is not only `Text`

The same pair exists wherever a control takes display text, which is what makes
the rule worth knowing rather than a `Text` curiosity:

```swift
Button("button.save") { save() }
Toggle("settings.notifications", isOn: $on)
TextField("field.name", text: $name)
Section("section.advanced") { … }
Label("menu.favourites", systemImage: "star")
List("list.inbox", selection: $id) { … }
Table(files, selection: $id) { TableColumn("column.size", value: \.size) }
```

…and on the modifiers that carry text: ``TUIkit/View/navigationTitle(_:)``,
``TUIkit/View/alert(_:isPresented:actions:)``,
``TUIkit/View/confirmationDialog(_:isPresented:titleVisibility:actions:)``,
`searchable(prompt:)`, `badge(_:)` and `listEmptyPlaceholder(_:)`.

The TUI-specific chrome follows the same rule — a terminal app's dialogs, cards
and status bar are display text like any other:

```swift
Dialog(title: "dialog.settings") { … }
Alert(title: "alert.unsaved.title", message: "alert.unsaved.body")
Card(title: "card.summary") { … }
StatusBarItem(shortcut: "q", label: "status.quit") { quit() }
notifications.post("notice.saved")
```

An ``Alert``'s **message** is a key too, unlike a value: it is prose the reader
has to understand. Both of its slots must be literals or neither is looked up,
since a computed `String` in either one selects the plain-`String` overload.

Only **display text** is a key. A value the control is *showing you* is not:
`LabeledContent("row.size", value: fileSize)` looks up the label and prints the
size, an SF Symbol name is a symbol name, and a `Table`'s cells come from the
data. Nor is a **glyph**: a ``StatusBarItem``'s `shortcut` — `"q"`, `"⎋"`,
`"⌃q"` — is the key you press, the same in every language, and the item derives
its identity from it. If it would be wrong to translate it, it is not a key.

> Tip: You never have to use this. `Button(myLocalizedString)` — a computed
> `String` — is the disfavoured overload and is displayed exactly as given,
> which is why an app that resolves its own strings keeps working unchanged.

Interpolation builds one key for every value, with `%@` where each value went:

```swift
Text("Moved \(count) rows to \(destination)")
// key: "Moved %@ rows to %@"
```

Register that key once and every value reuses it. A translation may reorder
the values with `%2$@`, since word order differs between languages, and values
are converted eagerly — `\(value, format: .percent)` works. A key with **no**
interpolations is never scanned for placeholders, so `Text("100% done")` says
100% done.

### Switch Language at Runtime

```swift
LocalizationService.shared.setLanguage(.german)
// UI automatically re-renders with German strings
```

### Supported Languages

- `.english` - English
- `.german` - Deutsch
- `.french` - Français
- `.italian` - Italiano
- `.spanish` - Español
- `.simplifiedChinese` - 简体中文
- `.japanese` - 日本語

## Type-Safe Keys

All localized strings are available as `LocalizationKey` enums organized by category. This provides compile-time safety, IDE autocomplete, and refactoring support.

### Key Categories

#### Button Keys

21 button strings including: ok, cancel, yes, no, save, delete, close, apply, reset, submit, search, clear, add, remove, edit, done, next, previous, back, forward, refresh

```swift
LocalizationKey.Button.ok
LocalizationKey.Button.cancel
LocalizationKey.Button.save
```

#### Label Keys

17 label strings including: search, name, description, value, status, error, warning, info, loading, empty, none, page, item, items, total, from, to

```swift
LocalizationKey.Label.name
LocalizationKey.Label.description
LocalizationKey.Label.status
```

#### Error Keys

11 error strings including: invalidInput, requiredField, notFound, accessDenied, networkError, unknown, invalidFormat, operationFailed, timeout, fileNotFound, permissionDenied

```swift
LocalizationKey.Error.invalidInput
LocalizationKey.Error.notFound
LocalizationKey.Error.timeout
```

#### Placeholder Keys

6 placeholder strings: search, enterText, enterValue, selectOption, enterName, chooseFile

```swift
LocalizationKey.Placeholder.search
LocalizationKey.Placeholder.enterText
LocalizationKey.Placeholder.selectOption
```

#### Menu Keys

8 menu strings: file, edit, view, help, new, open, save, exit

```swift
LocalizationKey.Menu.file
LocalizationKey.Menu.edit
LocalizationKey.Menu.help
```

#### Dialog Keys

7 dialog strings: confirm, deleteConfirmation, unsavedChanges, overwriteConfirmation, exitConfirmation, success, error

```swift
LocalizationKey.Dialog.confirm
LocalizationKey.Dialog.deleteConfirmation
LocalizationKey.Dialog.unsavedChanges
```

#### Validation Keys

4 validation strings: emailInvalid, passwordTooShort, usernameTaken, fieldRequired

```swift
LocalizationKey.Validation.emailInvalid
LocalizationKey.Validation.passwordTooShort
LocalizationKey.Validation.usernameTaken
```

#### Status Bar Keys

3 status bar strings for the built-in system items: quit, appearance, theme

```swift
LocalizationKey.StatusBar.quit
LocalizationKey.StatusBar.appearance
LocalizationKey.StatusBar.theme
```

## Using Localized Strings

### LocalizedString View

Display a localized string as a View component:

```swift
struct MyView: View {
    var body: some View {
        VStack {
            LocalizedString(LocalizationKey.Button.save)
            LocalizedString(LocalizationKey.Error.invalidInput)
            LocalizedString(LocalizationKey.Validation.emailInvalid)
        }
    }
}
```

### Text View with Localization

Use the `Text(localized:)` initializer:

```swift
struct MyControl: View {
    var body: some View {
        VStack {
            Text(localized: LocalizationKey.Menu.file)
            Text(localized: LocalizationKey.Placeholder.search)
        }
    }
}
```

### Direct Service Access

For advanced use cases, access the service directly:

```swift
let service = LocalizationService.shared
let text = service.string(for: LocalizationKey.Button.ok)
```

## Language Switching

### Get Current Language

```swift
let current = LocalizationService.shared.currentLanguage
print(current.displayName)  // "English", "Deutsch", etc.
```

### Change Language

```swift
LocalizationService.shared.setLanguage(.german)
```

### Language Persistence

Language preferences are automatically saved per-app, in the
platform-idiomatic configuration directory:
- **macOS**: `~/Library/Application Support/<App>/language`
- **Linux**: `$XDG_CONFIG_HOME/<App>/language` (else `~/.config/<App>/language`)

`<App>` is the executable's (sanitized) process name, so each app keeps its own
preference. The saved preference is restored when the app restarts; with no
saved preference the system locale is used, falling back to English.

### Fallback Behavior

String resolution uses a fallback chain:

1. Try to find the key in the active language
2. If not found, fall back to English
3. If still not found, return the key itself as-is

This ensures the UI always has something to display, even with incomplete translations.

## Direct Access

`LocalizationService` is a shared service:

```swift
struct MyView: View {
    var body: some View {
        Text(LocalizationService.shared.string(for: LocalizationKey.Button.ok))
    }
}
```

Applications can also register their own translations, which win over the
framework's for matching keys:

```swift
LocalizationService.shared.register(translations: [
    "en": ["greeting.hello": "Hello"],
    "de": ["greeting.hello": "Hallo"],
])
```

## Adding New Keys

To add new localized strings to the framework:

### 1. Update LocalizationKey Enum

Edit `Sources/TUIkit/Localization/LocalizationKeys.swift`:

```swift
public enum LocalizationKey {
    public enum Button: String {
        // ... existing cases
        case myNewButton = "button.my_new_button"
    }
}
```

Then add convenient extensions:

```swift
extension LocalizedString {
    public init(_ key: LocalizationKey.Button) {
        self.init(key.rawValue)
    }
}

extension Text {
    public init(localized key: LocalizationKey.Button) {
        self.init(localized: key.rawValue)
    }
}

extension LocalizationService {
    public func string(for key: LocalizationKey.Button) -> String {
        string(for: key.rawValue)
    }
}
```

### 2. Add to All Translation Files

Add the same key to all 7 translation JSON files:

**en.json**:
```json
{
  "button.my_new_button": "My New Button",
  ...
}
```

**de.json**:
```json
{
  "button.my_new_button": "Mein neuer Button",
  ...
}
```

Similar for `fr.json`, `it.json`, `es.json`, `zh.json`, `ja.json`.

### 3. Update Tests

Add tests in `Tests/TUIkitTests/LocalizationKeyConsistencyTests.swift`:

```swift
@Test("All button keys exist in translations")
func allButtonKeysExist() {
    let keys = [
        LocalizationKey.Button.ok,
        LocalizationKey.Button.myNewButton,
        // ... all other button keys
    ]

    for key in keys {
        #expect(englishTranslations[key.rawValue] != nil)
    }
}
```

### 4. Run Consistency Tests

Verify all keys exist in translation files:

```bash
swift test --filter LocalizationKeyConsistencyTests
```

## Adding New Languages

To add support for a new language:

### 1. Update Language Enum

Edit `Sources/TUIkit/Localization/LocalizationService.swift`:

```swift
public enum Language: String, Codable {
    case english = "en"
    case german = "de"
    case french = "fr"
    case italian = "it"
    case spanish = "es"
    case portuguese = "pt"  // NEW

    public var displayName: String {
        switch self {
        case .english: "English"
        case .german: "Deutsch"
        case .french: "Français"
        case .italian: "Italiano"
        case .spanish: "Español"
        case .portuguese: "Português"  // NEW
        }
    }
}
```

### 2. Create Translation File

Create `Sources/TUIkit/Localization/translations/pt.json` with **all** keys from other language files:

```json
{
  "button.ok": "OK",
  "button.cancel": "Cancelar",
  ...
  // Must include ALL keys (use en.json as reference)
}
```

### 3. Test the New Language

```swift
let service = LocalizationService()
service.setLanguage(.portuguese)
let ok = service.string(for: LocalizationKey.Button.ok)
```

### 4. Run Consistency Tests

```bash
swift test --filter LocalizationKeyConsistencyTests
```

## Design Principles

### Dot-Notation Keys

Keys use `category.key_name` format:

```
button.ok
error.not_found
validation.email_invalid
```

This organizes related strings, makes them easy to find, and matches JSON structure.

### Enum Categories

Each JSON prefix becomes an enum category:
- All `button.*` keys → `LocalizationKey.Button`
- All `error.*` keys → `LocalizationKey.Error`
- All `validation.*` keys → `LocalizationKey.Validation`

This provides type safety, IDE autocomplete, and compile-time verification.

### Thread Safety

``LocalizationService`` uses `NSLock` for thread-safe access:

```swift
// Safe to call from any thread
DispatchQueue.global().async {
    LocalizationService.shared.setLanguage(.german)
}
```

### Performance Caching

Translations are cached per language after first load:

```swift
let text1 = service.string(for: LocalizationKey.Button.ok)  // Loads and caches
let text2 = service.string(for: LocalizationKey.Button.ok)  // Uses cache
```

## JSON File Format

### Structure

```json
{
  "category.key": "English text",
  "category.another_key": "More text",
  ...
}
```

### Rules

1. **Flat structure**: No nested objects (all keys are top-level)
2. **Dot-separated keys**: `"button.ok"`, not nested objects
3. **UTF-8 encoding**: Required for non-Latin characters
4. **Valid JSON**: No trailing commas, proper escaping

### Example

```json
{
  "button.ok": "OK",
  "button.cancel": "Cancel",
  "error.not_found": "Not found",
  "error.unicode_test": "Unicode: café, Ñoño, 日本語",
  "placeholder.enter_name": "Enter name..."
}
```

## Best Practices

1. **Always use type-safe keys**: Use `LocalizationKey` enums instead of raw strings
2. **Keep keys organized**: Group related strings by category
3. **Use descriptive names**: Short, clear key names
4. **Run consistency tests**: Always verify after adding keys
5. **Test all languages**: Check translations look correct in each language
6. **Handle missing strings**: Rely on the fallback chain for incomplete translations

## Testing

TUIkit includes comprehensive localization tests:

### LocalizationServiceTests
Core functionality tests covering:
- Bundle loading for all languages
- String resolution with dot-notation
- Fallback behavior
- Language switching
- Persistence to disk
- Thread safety

### LocalizationKeyConsistencyTests
Validation tests ensuring:
- Every enum key exists in all translation files
- No extraneous keys in translation files
- Expected total key count

Run after any localization changes:

```bash
swift test --filter LocalizationKeyConsistencyTests
```

## Troubleshooting

### String Not Appearing

- Verify the key exists in `LocalizationKey` enum
- Check the key is in all translation JSON files
- Run consistency tests to verify

### Wrong Language Showing

- Verify language was set: `LocalizationService.shared.currentLanguage`
- Confirm language is supported (en, de, fr, it, es, zh, ja)
- Check translation file exists for that language

### JSON Syntax Errors

If translation files won't load:
- Validate JSON syntax
- Check for missing commas or quotes
- Ensure UTF-8 encoding
- No trailing commas in objects

## See Also

- <doc:GettingStarted>
- <doc:AppLifecycle>
- <doc:Architecture>
