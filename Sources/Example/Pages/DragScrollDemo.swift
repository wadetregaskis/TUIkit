//  🖥️ TUIKit — Terminal UI Kit for Swift
//  DragScrollDemo.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// Demonstrates drag auto-scroll (a scrollable that scrolls when a drag hovers
/// near its edge): the folder list holds far more rows than fit, so dragging
/// the tag toward its top or bottom edge scrolls it to bring an off-screen
/// folder into view — the drop target below the fold stays reachable.
struct DragScrollDemoSection: View {
    /// The (marker) value the tag carries while dragged.
    private struct FilingTag: Equatable {}

    private struct Folder: Identifiable {
        let id: Int
        let name: String
    }

    @State private var filed: String?

    private var folders: [Folder] {
        (1...24).map { Folder(id: $0, name: "\(L("page.mouse.dragScrollFolder")) \($0)") }
    }

    var body: some View {
        DemoSection(L("page.mouse.dragScroll")) {
            VStack(alignment: .leading, spacing: 1) {
                Text(L("page.mouse.dragScrollHint"))
                    .foregroundStyle(.palette.foregroundSecondary)
                HStack(alignment: .top, spacing: 3) {
                    Text(L("page.mouse.dragScrollTag"))
                        .padding(EdgeInsets(horizontal: 1, vertical: 0))
                        .border(color: .palette.accent)
                        .draggable(FilingTag())
                    // 24 folders in six visible lines: it overflows, so a drag
                    // toward the edge auto-scrolls it to reveal the rest.
                    List {
                        ForEach(folders) { folder in
                            HStack(spacing: 1) {
                                Text("📁 \(folder.name)")
                                if filed == folder.name {
                                    Spacer()
                                    Text("●").foregroundStyle(.palette.accent)
                                }
                            }
                            .dropDestination(for: FilingTag.self) { _, _ in
                                filed = folder.name
                                return true
                            }
                        }
                    }
                    .frame(width: 24, height: 6)
                    .border(color: .palette.border)
                }
                if let filed {
                    Text("\(L("page.mouse.dragScrollFiled")) \(filed)")
                        .foregroundStyle(.palette.accent)
                }
            }
        }
    }
}
