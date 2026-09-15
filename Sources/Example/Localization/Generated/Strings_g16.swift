//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Strings_g16.swift
//
//  Created by Wade Tregaskis
//  License: MIT
//
//  Translation fragment for the ProgressView page's indeterminate catalogue
//  controls: the speed its bars run at and the width they are drawn at. Its own
//  fragment rather than an addition to `Strings_g5`, which holds the page's
//  other strings and is past the 600-line limit.
//
//  The speed labels say what the Spinners page's say, under this page's own
//  keys, so that neither page's wording is tied to the other's. Numbers that are
//  API values (`1 ± 0.05`, `0.5`) keep Swift's spelling in every language.
//  English is the source of truth; every other language carries the same key
//  set.

extension ExampleStrings {
    static let g16: [String: [String: String]] = [
        "en": [
            "page.progressView.indeterminateSpeed": "Speed",
            "page.progressView.speedAutomatic": "Automatic (1 ± 0.05)",
            "page.progressView.speedHalf": "Half (0.5)",
            "page.progressView.speedStandard": "Standard (1, exact)",
            "page.progressView.speedDouble": "Double (2)",
            "page.progressView.indeterminateWidth": "Width",
        ],

        "de": [
            "page.progressView.indeterminateSpeed": "Geschwindigkeit",
            "page.progressView.speedAutomatic": "Automatisch (1 ± 0.05)",
            "page.progressView.speedHalf": "Halb (0.5)",
            "page.progressView.speedStandard": "Standard (1, exakt)",
            "page.progressView.speedDouble": "Doppelt (2)",
            "page.progressView.indeterminateWidth": "Breite",
        ],

        "fr": [
            "page.progressView.indeterminateSpeed": "Vitesse",
            "page.progressView.speedAutomatic": "Automatique (1 ± 0.05)",
            "page.progressView.speedHalf": "Moitié (0.5)",
            "page.progressView.speedStandard": "Standard (1, exacte)",
            "page.progressView.speedDouble": "Double (2)",
            "page.progressView.indeterminateWidth": "Largeur",
        ],

        "it": [
            "page.progressView.indeterminateSpeed": "Velocità",
            "page.progressView.speedAutomatic": "Automatica (1 ± 0.05)",
            "page.progressView.speedHalf": "Metà (0.5)",
            "page.progressView.speedStandard": "Standard (1, esatta)",
            "page.progressView.speedDouble": "Doppia (2)",
            "page.progressView.indeterminateWidth": "Larghezza",
        ],

        "es": [
            "page.progressView.indeterminateSpeed": "Velocidad",
            "page.progressView.speedAutomatic": "Automática (1 ± 0.05)",
            "page.progressView.speedHalf": "Mitad (0.5)",
            "page.progressView.speedStandard": "Estándar (1, exacta)",
            "page.progressView.speedDouble": "Doble (2)",
            "page.progressView.indeterminateWidth": "Anchura",
        ],

        "zh": [
            "page.progressView.indeterminateSpeed": "速度",
            "page.progressView.speedAutomatic": "自动（1 ± 0.05）",
            "page.progressView.speedHalf": "半速（0.5）",
            "page.progressView.speedStandard": "标准（1，精确）",
            "page.progressView.speedDouble": "双倍（2）",
            "page.progressView.indeterminateWidth": "宽度",
        ],

        "ja": [
            "page.progressView.indeterminateSpeed": "速度",
            "page.progressView.speedAutomatic": "自動（1 ± 0.05）",
            "page.progressView.speedHalf": "半分（0.5）",
            "page.progressView.speedStandard": "標準（1、正確）",
            "page.progressView.speedDouble": "倍速（2）",
            "page.progressView.indeterminateWidth": "幅",
        ],
    ]
}
