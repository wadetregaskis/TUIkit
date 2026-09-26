//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EnvironmentSnapshot.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Environment Snapshot

/// A snapshot of environment values that affect rendered output.
///
/// Used by `RenderLoop` to detect environment changes (theme, appearance)
/// between frames. When the snapshot differs from the previous frame, the
/// render cache is cleared so `EquatableView`-cached subtrees re-render
/// with the updated values.
///
/// Only tracks values that affect visual output — reference-type infrastructure
/// services (`FocusManager`, `ThemeManager`) are excluded.
///
/// Internal (not private) so tests can pin which values participate: a value
/// missing from here is a class of "changed but stale subtrees keep the old
/// look" bug, and it is invisible in headless single-render tests.
internal struct EnvironmentSnapshot: Equatable {
    /// The active palette, compared by value where it can be (`isSamePalette(as:)`).
    /// Its id was not enough: the Example's Theme page edits its palette in place
    /// under the preset's id, so an edit changed no field here and memoized
    /// subtrees kept drawing the colours from before it.
    let palette: ComparablePalette

    /// The active appearance identifier.
    let appearanceID: String

    /// What the `.automatic` toggle character set resolves to this frame. Under tmux this
    /// CHANGES mid-run when a different client attaches; without it in the
    /// snapshot, `EquatableView`/`ForEach`-memoized subtrees kept serving
    /// buffers with the OLD glyphs, so the screen showed a mix — rows the user
    /// touched re-rendered in the new style while untouched rows stayed in the
    /// old one (observed live: iTerm2 attached to a running app and the default
    /// toggles stayed ■/□ while the answer had flipped to emoji).
    let resolvedAutomaticToggleCharacterSet: ToggleCharacterSet

    /// The frame's locale, republished from the app language each frame. A
    /// language switch re-renders — but the memoized subtrees compare by
    /// VALUE, and the view values (localization keys) don't change with the
    /// language, so without this every `EquatableView`/`ForEach`-memoized row
    /// kept serving buffers in the OLD language: the same mixed-screen class
    /// as the toggle-glyph field above, in a different coat.
    let localeIdentifier: String

    /// The frame's scene phase, republished from the run loop each frame the way
    /// the locale is, and for the same reason: it changes between frames with no
    /// view value and no `@State` changing, so without it a memoized subtree that
    /// read `\.scenePhase` went on drawing the phase from before a suspend.
    let scenePhase: ScenePhase

    /// The terminal cell's height-to-width ratio, which the render loop reads
    /// from `TIOCGWINSZ` every frame and publishes at the root — before this
    /// snapshot is taken, which it was not. A change of cell moves it (a 7x16
    /// cell is 2.29, an 8x17 one 2.13), and nothing a memo keys on moves with
    /// it, so without it here a memoized row kept an ASCII picture sized, and a
    /// radial or angular ramp shaped, for the cell before the change, beside
    /// fresh rows drawn for the new one.
    let imageCellAspect: Double

    /// The terminal cell's size in pixels, published beside the aspect from the
    /// same `ioctl`, for the same reason: a picture transmitted to the
    /// terminal is resampled to it.
    let imageCellPixels: TerminalCellPixels

    /// Creates a snapshot from fully-built environment values.
    init(from environment: EnvironmentValues) {
        self.palette = ComparablePalette(environment.palette)
        self.appearanceID = environment.appearance.id
        self.resolvedAutomaticToggleCharacterSet = environment.resolvedAutomaticToggleCharacterSet
        self.localeIdentifier = environment.locale.identifier
        self.scenePhase = environment.scenePhase
        self.imageCellAspect = environment.imageCellAspect
        self.imageCellPixels = environment.imageCellPixels
    }
}
