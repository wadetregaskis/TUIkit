//  🖥️ TUIKit — Terminal UI Kit for Swift
//  LayoutPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// Layout system demo page.
///
/// Shows various layout options including:
/// - VStack (vertical stacking)
/// - HStack (horizontal stacking)
/// - Spacer (flexible space)
/// - Padding and frame modifiers
struct LayoutPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            DemoSection("VStack (Vertical)") {
                VStack(spacing: 0) {
                    Text("Item 1")
                    Text("Item 2")
                    Text("Item 3")
                }
                .border(color: .brightBlack)
            }

            DemoSection("HStack (Horizontal)") {
                HStack(spacing: 2) {
                    Text("Left")
                    Text("Center")
                    Text("Right")
                }
                .border()
            }

            DemoSection("Spacer") {
                HStack {
                    Text("Start")
                    Spacer()
                    Text("End")
                }
                .border()
            }

            DemoSection("Padding & Frame") {
                HStack(spacing: 2) {
                    VStack {
                        Text(".padding()").dim()
                        Text("Padded")
                            .frame(width: 25, alignment: .center)
                            .padding(EdgeInsets(all: 1))
                            .border()  // Uses appearance default
                    }
                    VStack {
                        Text(".frame()").dim()
                        Text("Framed")
                            .frame(width: 15, alignment: .center)
                            .border()  // Uses appearance default
                    }
                }
            }

            DemoSection("ViewThatFits (Adaptive)") {
                // A single row when there is room; the same items stacked
                // vertically when the terminal is too narrow for the row.
                ViewThatFits {
                    HStack(spacing: 2) {
                        Text("[ Profile ]")
                        Text("[ Settings ]")
                        Text("[ Sign Out ]")
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text("[ Profile ]")
                        Text("[ Settings ]")
                        Text("[ Sign Out ]")
                    }
                }
                .border(color: .brightBlack)
            }

            DemoSection("ZStack (Layering)") {
                // Children stack back-to-front; alignment positions them within
                // the union of their sizes. Here a label is centred over a band.
                ZStack(alignment: .center) {
                    Text(String(repeating: "▒", count: 28)).foregroundStyle(.palette.accent)
                    Text(" on top ").bold().inverted()
                }
                .border(color: .brightBlack)
            }

            DemoSection("Divider") {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Above")
                    Divider()
                    Text("Between")
                    Divider(character: "═")
                    Text("Below")
                }
                .border(color: .brightBlack)
            }

            Spacer()
        }
        .scrollableDemoPage()
        .appHeader {
            DemoAppHeader("Layout System Demo")
        }
    }
}
