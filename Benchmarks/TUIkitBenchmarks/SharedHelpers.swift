//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SharedHelpers.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// 80×24 — the historical "default terminal" shape; what most
/// of the smaller widget benchmarks render into.
@MainActor
func standardContext() -> RenderContext {
    RenderContext(
        availableWidth: 80,
        availableHeight: 24,
        tuiContext: TUIContext()
    )
}

/// 80×80 — for long-list / long-table benchmarks where 24
/// rows wouldn't even contain the visible window, let alone
/// the chrome around it.
@MainActor
func tallContext() -> RenderContext {
    RenderContext(
        availableWidth: 80,
        availableHeight: 80,
        tuiContext: TUIContext()
    )
}

/// 120×40 — for whole-page benchmarks where pages assume
/// terminal-window-sized dimensions.
@MainActor
func pageContext() -> RenderContext {
    RenderContext(
        availableWidth: 120,
        availableHeight: 40,
        tuiContext: TUIContext()
    )
}
