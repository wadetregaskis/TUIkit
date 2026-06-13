//  🖥️ TUIKit — Terminal UI Kit for Swift
//  TextStylesPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// Text styles demo page.
///
/// Shows various text styling options including:
/// - Basic styles (bold, italic, underline, etc.)
/// - Combined styles
/// - Special effects (blink, inverted)
struct TextStylesPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            DemoSection("Basic Styles") {
                Text("Normal text - no styling applied")
                Text("Bold text").bold()
                Text("Italic text").italic()
                Text("Underlined text").underline()
                Text("Strikethrough text").strikethrough()
                Text("Dimmed text").dim()
            }

            DemoSection("Combined Styles") {
                Text("Bold + Italic").bold().italic()
                Text("Bold + Underline").bold().underline()
                Text("Bold + Color").bold().foregroundStyle(.palette.accent)
                Text("Italic + Dim").italic().dim()
                Text("All combined").bold().italic().underline().foregroundStyle(.palette.accent)
            }

            DemoSection("Special Effects") {
                Text("Blinking text (if terminal supports)").blink()
                Text("Inverted colors").inverted()
            }

            DemoSection("Truncation & Line Limits") {
                VStack(alignment: .leading, spacing: 1) {
                    let long = "A long line that will not fit inside a 30-column frame"
                    // Single-line truncation, cut at different ends (note the ellipsis).
                    // `lineLimit`/`truncationMode` are Text modifiers, so they come
                    // before `.frame` (which returns `some View`).
                    Text(long).lineLimit(1).truncationMode(.tail).frame(width: 30)
                    Text(long).lineLimit(1).truncationMode(.head).frame(width: 30)
                    Text(long).lineLimit(1).truncationMode(.middle).frame(width: 30)
                    // Multi-line wrap clamped to two lines.
                    Text(
                        "This paragraph wraps across several lines, but .lineLimit(2) "
                            + "clamps it to the first two and drops the rest of the text."
                    )
                    .lineLimit(2)
                    .frame(width: 46)
                }
            }

            Spacer()
        }
        .appHeader {
            DemoAppHeader("Text Styles Demo")
        }
    }
}
