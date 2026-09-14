//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SplitViewPage.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

// MARK: - Demo Data

/// A mail folder for the sidebar.
private struct Folder: Identifiable {
    let id: String
    let name: String
    let icon: String
    let unreadCount: Int

    static let samples: [Self] = [
        Self(id: "inbox", name: L("page.splitView.folderInbox"), icon: "[>]", unreadCount: 12),
        Self(id: "starred", name: L("page.splitView.folderStarred"), icon: "[*]", unreadCount: 3),
        Self(id: "sent", name: L("page.splitView.folderSent"), icon: "[^]", unreadCount: 0),
        Self(id: "drafts", name: L("page.splitView.folderDrafts"), icon: "[~]", unreadCount: 2),
        Self(id: "archive", name: L("page.splitView.folderArchive"), icon: "[=]", unreadCount: 0),
        Self(id: "trash", name: L("page.splitView.folderTrash"), icon: "[x]", unreadCount: 0),
    ]
}

/// A mail message for the content list.
private struct Message: Identifiable {
    let id: String
    let from: String
    let subject: String
    let body: String
    let date: String
    let isRead: Bool

    static func samples(for folder: String) -> [Self] {
        switch folder {
        case "inbox":
            return [
                Self(
                    id: "1",
                    from: "Alice",
                    subject: "Meeting Tomorrow",
                    body: "Hi,\n\nJust wanted to confirm our meeting tomorrow at 2pm.\n\nBest,\nAlice",
                    date: "10:30",
                    isRead: false
                ),
                Self(
                    id: "2",
                    from: "Bob",
                    subject: "Code Review",
                    body: "Hey,\n\nI've reviewed your PR and left some comments.\n\nLooks good overall!",
                    date: "09:15",
                    isRead: false
                ),
                Self(
                    id: "3",
                    from: "Carol",
                    subject: "Project Update",
                    body: "Team,\n\nHere's the latest status on the project.\n\nWe're on track for launch.",
                    date: "Yesterday",
                    isRead: true
                ),
                Self(
                    id: "4",
                    from: "David",
                    subject: "Quick Question",
                    body: "Hi,\n\nDo you have a moment to discuss the API design?\n\nThanks!",
                    date: "Yesterday",
                    isRead: true
                ),
                Self(
                    id: "5",
                    from: "Eve",
                    subject: "New Feature Idea",
                    body: "Hello,\n\nI was thinking we could add dark mode support.\n\nThoughts?",
                    date: "Monday",
                    isRead: true
                ),
            ]
        case "starred":
            return [
                Self(
                    id: "s1",
                    from: "Frank",
                    subject: "Important: Deadline",
                    body: "Reminder:\n\nThe deadline is next Friday.\n\nPlease submit your work.",
                    date: "Tuesday",
                    isRead: true
                ),
                Self(
                    id: "s2",
                    from: "Grace",
                    subject: "Contract Review",
                    body: "Hi,\n\nPlease review the attached contract.\n\nLet me know if you have questions.",
                    date: "Last week",
                    isRead: true
                ),
            ]
        case "drafts":
            return [
                Self(
                    id: "d1",
                    from: "Me",
                    subject: "Re: Meeting",
                    body: "Thanks for the invite.\n\nI'll be there at 2pm.\n\nSee you then!",
                    date: "Draft",
                    isRead: true
                )
            ]
        default:
            return []
        }
    }
}

// MARK: - SplitView Page

/// NavigationSplitView demo page.
///
/// Shows a three-column mail client layout with interactive Lists:
/// - Sidebar: Folder list (Tab to focus)
/// - Content: Message list for selected folder
/// - Detail: Full message content
struct SplitViewPage: View {
    @State private var selectedFolder: String? = "inbox"
    @State private var selectedMessage: String? = "1"
    @State private var visibility: NavigationSplitViewVisibility = .all
    @State private var styleName: String = "balanced"
    @State private var resizable: Bool = true
    /// Bumped by the Reset button to release any manually-resized column widths
    /// back to the style / size-to-fit defaults (`.navigationSplitViewColumnWidthReset`).
    @State private var widthResetToken: Int = 0

    var body: some View {
        // `.leading`, not the default centre: the control row is narrower than the
        // split view below it, and centred it drifted right as the terminal grew —
        // 33 columns of empty left margin at 140 cols, which reads as a bug. The
        // split view itself fills the width either way.
        VStack(alignment: .leading, spacing: 0) {
            controls
            styledSplitView
        }
        .appHeader {
            DemoAppHeader("menu.item.splitView")
        }
    }

    /// The three knobs, ABOVE the split view and horizontal wherever they fit.
    ///
    /// Horizontal because the split view is the thing worth looking at: side by
    /// side these cost it as many rows as the tallest one, stacked they cost nine.
    /// Each radio group stays vertical INSIDE itself — a row of radio buttons
    /// reads as a sentence rather than as a choice.
    ///
    /// `ViewThatFits(in: .horizontal)` rather than one fixed arrangement, because
    /// one row does not fit 80 columns in most languages: measured, the divider
    /// pair is clipped there in German, French, Italian, Spanish and Japanese,
    /// where the style group's own widest option ("Ajustar al contenido (desde la
    /// izquierda)") is half the terminal on its own. The fallback drops the pair
    /// to its own row, which is four rows for the groups plus one — exactly the
    /// height this page had before the visibility group existed, so the new
    /// control costs nothing even at the narrow end.
    @ViewBuilder private var controls: some View {
        ViewThatFits(in: .horizontal) {
            // Preferred: all three side by side. The divider pair stacks here so
            // this candidate fits at more widths; it is one row tall either way,
            // against the groups' four.
            HStack(alignment: .top, spacing: 3) {
                stylePicker
                visibilityPicker
                VStack(alignment: .leading, spacing: 0) { dividerControls }
            }
            // Fallback: the two groups side by side, the divider pair beneath.
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 3) {
                    stylePicker
                    visibilityPicker
                }
                HStack(spacing: 2) { dividerControls }
            }
        }
        .padding(.horizontal, 1)
    }

    /// Switch the split style live. The first three divide the width by fixed
    /// shares, and differ only in how big the leading columns' shares are:
    /// `.balanced` gives them the largest, so the detail shrinks to make room;
    /// `.prominentDetail` the smallest, so the detail is widest; `.automatic`
    /// sits between the two. None of them hides or overlays a column: which
    /// columns show is the visibility group's job. Size to fit fits each column
    /// to its content instead.
    private var stylePicker: some View {
        Picker("page.splitView.style", selection: $styleName) {
            Text("page.splitView.styleAutomatic").tag("automatic")
            Text("page.splitView.styleBalanced").tag("balanced")
            Text("page.splitView.styleProminentDetail").tag("prominentDetail")
            Text("page.splitView.styleSizeToFit").tag("sizeToFit")
        }
        .pickerStyle(.radioGroup)
    }

    /// Which leading columns are showing — the `columnVisibility` binding. The
    /// split view writes it back when the user hides a column with the ◀ on its
    /// leftmost divider or brings one back with the ▶ edge column, and this group
    /// follows. Otherwise it shows what was picked, not what was drawn: Auto stays
    /// selected while all three columns show, because the split view draws
    /// `.automatic` as `.all`.
    ///
    /// Tagged with the visibility values themselves rather than with strings, as
    /// the style picker above has to be: `NavigationSplitViewVisibility` is
    /// `Hashable`, and `NavigationSplitViewStyle` is not.
    private var visibilityPicker: some View {
        Picker("page.splitView.visibility", selection: $visibility) {
            Text("page.splitView.visibilityAll")
                .tag(NavigationSplitViewVisibility.all)
            Text("page.splitView.visibilityDouble")
                .tag(NavigationSplitViewVisibility.doubleColumn)
            Text("page.splitView.visibilityDetail")
                .tag(NavigationSplitViewVisibility.detailOnly)
            Text("page.splitView.visibilityAuto")
                .tag(NavigationSplitViewVisibility.automatic)
        }
        .pickerStyle(.radioGroup)
    }

    /// Divider resizing is a configurable option — including under size-to-fit,
    /// where the columns fit their content until you drag or arrow-resize one,
    /// which pins it. Reset releases every pin so the columns re-flow to the
    /// automatic widths.
    ///
    /// Two views rather than a container, so each candidate layout above can put
    /// them in the stack that suits it.
    @ViewBuilder private var dividerControls: some View {
        Toggle("page.splitView.resizable", isOn: $resizable)
        Button("page.splitView.resetWidths") { widthResetToken += 1 }
            .disabled(!resizable)
    }

    /// The shared three-column split view with the currently-selected
    /// ``NavigationSplitViewStyle`` applied.
    @ViewBuilder private var styledSplitView: some View {
        styledSplitViewCore
            .navigationSplitViewResizable(resizable)
            .navigationSplitViewColumnWidthReset(widthResetToken)
    }

    @ViewBuilder private var styledSplitViewCore: some View {
        switch styleName {
        case "automatic":
            splitView.navigationSplitViewStyle(.automatic)
        case "prominentDetail":
            splitView.navigationSplitViewStyle(.prominentDetail)
        case "sizeToFit":
            splitView.navigationSplitViewStyle(.sizeToFitFromLeft)
        default:
            splitView.navigationSplitViewStyle(.balanced)
        }
    }

    private var splitView: some View {
        NavigationSplitView(columnVisibility: $visibility) {
            // Sidebar: Folder list
            List("page.splitView.folders", selection: $selectedFolder) {
                ForEach(Folder.samples) { folder in
                    HStack(spacing: 1) {
                        Text(folder.icon)
                        Text(folder.name)
                    }
                    .badge(folder.unreadCount)
                }
            }
        } content: {
            // Content: Message list
            messageListContent
        } detail: {
            // Detail: Message content
            detailColumn
        }
    }
}

// MARK: - Column Views

extension SplitViewPage {
    @ViewBuilder
    fileprivate var messageListContent: some View {
        let messages = Message.samples(for: selectedFolder ?? "inbox")
        if messages.isEmpty {
            // Centred on BOTH axes by its own content. A column of spacers used to paint
            // the whole offered width, which centred this line by accident; it now hugs
            // its widest child, as it always measured, and a split view places a
            // narrower column at its leading edge.
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text("page.splitView.noMessages").dim()
                    Spacer()
                }
                Spacer()
            }
        } else {
            List(folderTitle, selection: $selectedMessage) {
                ForEach(messages) { message in
                    HStack(spacing: 1) {
                        if message.isRead {
                            Text(" ")
                        } else {
                            Text("*").foregroundStyle(.palette.accent)
                        }
                        if message.isRead {
                            Text(message.from)
                        } else {
                            Text(message.from).bold()
                        }
                        Text("-").dim()
                        Text(message.subject)
                    }
                }
            }
        }
    }

    fileprivate var detailColumn: some View {
        // Top-aligned: subject, then From/Date on adjacent lines, one blank
        // line, the body, and ALL the unused space at the bottom. (A
        // `Spacer(minLength:)` would be wrong for the gaps — a Spacer
        // EXPANDS, minLength is only its floor, so every one added here
        // would take an equal share of the leftover space and scatter the
        // message down the column.)
        VStack(alignment: .leading, spacing: 0) {
            if let message = currentMessage {
                // Header
                Text(message.subject)
                    .bold()
                    .foregroundStyle(.palette.accent)
                    .padding(.bottom, 1)
                HStack(spacing: 1) {
                    Text("page.splitView.from").foregroundStyle(.palette.foregroundSecondary)
                    Text(message.from)
                }
                HStack(spacing: 1) {
                    Text("page.splitView.date").foregroundStyle(.palette.foregroundSecondary)
                    Text(message.date)
                }

                // Message body
                Text(message.body)
                    .padding(.top, 1)
                Spacer()
            } else {
                Spacer()
                HStack {
                    Spacer()
                    Text("page.splitView.selectMessage").dim()
                    Spacer()
                }
                Spacer()
            }
        }
        .padding(.horizontal, 1)
    }
}

// MARK: - Private Helpers

extension SplitViewPage {
    fileprivate var folderTitle: String {
        Folder.samples.first { $0.id == selectedFolder }?.name ?? L("page.splitView.messages")
    }

    fileprivate var currentMessage: Message? {
        guard let messageId = selectedMessage else { return nil }
        return Message.samples(for: selectedFolder ?? "inbox").first { $0.id == messageId }
    }
}
