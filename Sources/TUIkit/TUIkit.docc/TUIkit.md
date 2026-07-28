# ``TUIkit``

A declarative, SwiftUI-like framework for building Terminal User Interfaces in Swift.

@Metadata {
    @DisplayName("TUIkit")
    @PageImage(purpose: icon, source: "tuikit-logo", alt: "TUIkit Logo")
    @PageImage(purpose: card, source: "tuikit-logo", alt: "TUIkit Logo")
}

## Overview

TUIkit lets you build terminal applications using a familiar, declarative syntax inspired by SwiftUI. No ncurses, no system terminal libraries: rendering is pure Swift. (Image decoding bundles `stb_image` as an in-tree C target; there are no external system C dependencies.)

```swift
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            VStack {
                Text("Hello, TUIkit!")
                    .bold()
                    .foregroundStyle(.cyan)
                Button("Press me") {
                    // handle action
                }
            }
        }
    }
}
```

### Key Features

- **Declarative syntax**: Build UIs with `VStack`, `HStack`, `Text`, `Button`, and more
- **SwiftUI-like API**: `@State`, `@ViewBuilder`, environment values, modifiers
- **Theming system**: 16 built-in palettes (6 phosphor presets + 10 terminal profiles) with full RGB color support
- **Focus management**: Keyboard-driven navigation between interactive elements
- **Status bar**: Configurable shortcut bar with context stack
- **No terminal libraries**: Rendering is pure Swift, with no ncurses or system terminal C libraries
- **Cross-platform**: macOS and Linux

## Topics

> Note: `import TUIkit` re-exports `TUIkitCore`, `TUIkitStyling`, `TUIkitView`
> and `TUIkitImage`, so everything below is one import away. The reference
> pages, though, follow the module a symbol is *declared* in: the entries here
> for core types — `View`, `Color`, `Binding`, `State`, `EnvironmentValues`,
> `FrameBuffer`, `Palette` and their neighbours — resolve only in a
> documentation build that covers those targets too. Building this catalog
> alone leaves them as plain text.

### Essentials

- <doc:GettingStarted>
- <doc:Architecture>
- <doc:AppLifecycle>
- <doc:RenderCycle>

### Guides

- <doc:StateManagement>
- <doc:ThemingGuide>
- <doc:FocusSystem>
- <doc:StatusBarGuide>
- <doc:AppearanceAndColors>
- <doc:Preferences>
- <doc:CustomViews>
- <doc:KeyboardShortcuts>
- <doc:MouseAndGestures>
- <doc:Presentation>
- <doc:PaletteReference>
- <doc:ListAndTable>
- <doc:LayoutSystem>
- <doc:Localization>

### App Structure

- ``App``
- ``Scene``
- ``WindowGroup``
- ``renderOnce(content:)``

### Views

- ``View``
- ``Text``
- ``Image``
- ``ImageSource``
- ``Label``
- ``EmptyView``
- ``AnyView``
- ``Spinner``
- ``Divider``
- ``ContentUnavailableView``

### Interactive Controls

- ``Button``
- ``ButtonRole``
- ``ButtonRow``
- ``TextField``
- ``SecureField``
- ``TextEditor``
- ``Toggle``
- ``Slider``
- ``Stepper``
- ``RadioButtonGroup``
- ``Picker``
- ``RadioButtonItem``
- ``DatePicker``
- ``ColorPicker``
- ``Menu``
- ``Link``
- ``ProgressView``
- ``Gauge``
- ``EditButton``
- ``EditMode``

### Layout

- ``VStack``
- ``HStack``
- ``ZStack``
- ``LazyVStack``
- ``LazyHStack``
- ``Spacer``
- ``Section``
- ``ForEach``
- ``Group``
- ``ViewThatFits``
- ``HorizontalAlignment``
- ``VerticalAlignment``
- ``Alignment``
- ``ProposedSize``
- ``ViewSize``

### Containers

- ``Card``
- ``Panel``
- ``Alert``
- ``Dialog``
- ``NavigationSplitView``
- ``TabView``
- ``Tab``
- ``ScrollView``
- ``Form``
- ``LabeledContent``

### Data Collections

- ``List``
- ``Table``
- ``TableColumn``
- ``ColumnWidth``
- ``SelectionMode``
- ``RowReorderFeedback``

### Scrolling

- ``ScrollViewReader``
- ``ScrollViewProxy``
- ``ScrollAnchor``
- ``ScrollFollowMargin``
- ``ScrollGranularity``
- ``ScrollOverscroll``
- ``ScrollbarVisibility``
- ``ScrollbarArrows``
- ``ScrollbarEdges``
- ``ScrollbarClickBehavior``
- ``ScrollbarRepeat``

### Focus

- ``FocusState``
- ``FocusInteractions``
- ``DefaultFocusEvaluationPriority``
- ``SelectionEmphasis``
- ``SelectionIndicatorStyle``

### Keyboard

- ``KeyboardShortcut``
- ``KeyEquivalent``
- ``EventModifiers``
- ``CommandKeyBinding``
- ``SubmitLabel``
- ``SubmitTriggers``

### Mouse & Drag and Drop

- ``MouseSupport``
- ``MouseFeature``
- ``DragGestureEvent``
- ``DragPreviewAnchor``
- ``DropInfo``

### Search

- ``SearchFieldPlacement``
- ``SearchFieldIconPlacement``

### State Management

- ``State``
- ``Binding``

### Environment

- ``EnvironmentKey``
- ``EnvironmentValues``
- ``DismissAction``

### Preference System

- ``PreferenceKey``
- ``PreferenceValues``

### Theming

- ``Palette``
- ``SystemPalette``
- ``TerminalProfilePalette``
- ``PaletteRegistry``
- ``Color``
- ``TextStyle``

### Appearance

- ``Appearance``
- ``BorderStyle``
- ``ContentMode``
- ``EdgeInsets``
- ``Edge``

### Styles

- ``ButtonStyle``
- ``ButtonStyleConfiguration``
- ``DefaultButtonStyle``
- ``PrimaryButtonStyle``
- ``DestructiveButtonStyle``
- ``SuccessButtonStyle``
- ``PlainButtonStyle``
- ``ToggleStyle``
- ``DefaultToggleStyle``
- ``CheckboxToggleStyle``
- ``SwitchToggleStyle``
- ``ToggleCharacterSet``
- ``MenuStyle``
- ``MenuStyleConfiguration``
- ``DefaultMenuStyle``
- ``InlineMenuStyle``
- ``GaugeStyle``
- ``FormStyle``
- ``FormStyleConfiguration``
- ``TrackStyle``
- ``TrackConfiguration``
- ``IndeterminateStyle``
- ``ListStyle``
- ``PlainListStyle``
- ``InsetGroupedListStyle``
- ``SpinnerStyle``
- ``TextCursorStyle``
- ``TextContentType``
- ``NavigationSplitViewStyle``
- ``TabViewStyle``
- ``PickerStyle``
- ``AutomaticPickerStyle``
- ``MenuPickerStyle``
- ``InlinePickerStyle``
- ``RadioGroupPickerStyle``

### View Composition

- ``ViewBuilder``
- ``ViewModifier``
- ``ModifiedView``
- ``EquatableView``

### Focus System

- ``FocusReference``
- ``Focusable``

### Status Bar

- ``StatusBar``
- ``StatusBarState``
- ``StatusBarItem``
- ``StatusBarItemProtocol``
- ``StatusBarStyle``
- ``StatusBarAlignment``
- ``Shortcut``

### Input Handling

- ``KeyEvent``
- ``Key``
- ``QuitBehavior``

### Rendering

- ``FrameBuffer``
- ``RenderContext``
- ``OverlayLayer``
- ``OverlayLevel``

### Persistence

- ``AppStorage``
- ``StorageBackend``
