//  🖥️ TUIKit — Terminal UI Kit for Swift
//  SharedHelpers.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkit

/// 80×24 — the historical "default terminal" shape; what most
/// of the smaller widget benchmarks render into.
func standardContext() -> RenderContext {
    RenderContext(availableWidth: 80, availableHeight: 24)
}

/// 80×80 — for long-list / long-table benchmarks where 24
/// rows wouldn't even contain the visible window, let alone
/// the chrome around it.
func tallContext() -> RenderContext {
    RenderContext(availableWidth: 80, availableHeight: 80)
}

/// 120×40 — for whole-page benchmarks where pages assume
/// terminal-window-sized dimensions.
func pageContext() -> RenderContext {
    RenderContext(availableWidth: 120, availableHeight: 40)
}
