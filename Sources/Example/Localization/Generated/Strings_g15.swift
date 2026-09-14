//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Strings_g15.swift
//
//  Created by Wade Tregaskis
//  License: MIT
//
//  Translation fragment for the Spinners page's Speed section: the catalogue's
//  speed, per-style frame durations in 1/60 s ticks, and the readouts under the
//  page. Its own fragment rather than an addition to `Strings_g3`, which holds
//  the page's other strings and is past the 600-line limit.
//
//  Numbers that are API values (`1 ± 0.05`, `0.5`) keep Swift's spelling in
//  every language, as the tolerance picker beside them does. English is the
//  source of truth; every other language carries the same key set.

// swiftlint:disable line_length

extension ExampleStrings {
    static let g15: [String: [String: String]] = [
        "en": [
            "page.spinners.speedSection": "Speed",
            "page.spinners.speedHint": "Automatic is what an app gets when it sets no speed: the standard rate, free to move ±0.05 onto a whole number of 1/60 s ticks divisible by 2 or 3, which at the standard durations moves nothing. An override shows one style's frames for a whole number of ticks, exactly. Each row shows its frame duration, and the foot of the page lists them all.",
            "page.spinners.speed": "Speed",
            "page.spinners.speedAutomatic": "Automatic (1 ± 0.05)",
            "page.spinners.speedHalf": "Half (0.5)",
            "page.spinners.speedStandard": "Standard (1, exact)",
            "page.spinners.speedDouble": "Double (2)",
            "page.spinners.speedCustom": "Custom",
            "page.spinners.rate": "Rate",
            "page.spinners.tolerance": "Tolerance",
            "page.spinners.overrideStyle": "Override for",
            "page.spinners.frameTicks": "Frame",
            "page.spinners.frameInherit": "follows the speed",
            "page.spinners.clearOverrides": "Clear overrides",
            "page.spinners.durations": "Frame durations in ms:",
            "page.spinners.instantsModel %@": "≈ %@ distinct instants a second at which a spinner here changes frame (a model)",
        ],

        "de": [
            "page.spinners.speedSection": "Geschwindigkeit",
            "page.spinners.speedHint": "Automatisch bekommt eine App, die keine Geschwindigkeit festlegt: die Standardrate, die sich um ±0.05 auf eine durch 2 oder 3 teilbare ganze Zahl von 1/60-s-Takten verschieben darf, was bei den Standarddauern nichts verschiebt. Eine Überschreibung zeigt die Bilder eines Stils exakt für eine ganze Zahl von Takten. Jede Zeile zeigt ihre Bilddauer, und unten auf der Seite stehen alle.",
            "page.spinners.speed": "Geschwindigkeit",
            "page.spinners.speedAutomatic": "Automatisch (1 ± 0.05)",
            "page.spinners.speedHalf": "Halb (0.5)",
            "page.spinners.speedStandard": "Standard (1, exakt)",
            "page.spinners.speedDouble": "Doppelt (2)",
            "page.spinners.speedCustom": "Eigene",
            "page.spinners.rate": "Faktor",
            "page.spinners.tolerance": "Toleranz",
            "page.spinners.overrideStyle": "Überschreiben für",
            "page.spinners.frameTicks": "Bild",
            "page.spinners.frameInherit": "folgt der Geschwindigkeit",
            "page.spinners.clearOverrides": "Überschreibungen löschen",
            "page.spinners.durations": "Bilddauern in ms:",
            "page.spinners.instantsModel %@": "≈ %@ verschiedene Zeitpunkte je Sekunde, an denen ein Spinner hier das Bild wechselt (ein Modell)",
        ],

        "fr": [
            "page.spinners.speedSection": "Vitesse",
            "page.spinners.speedHint": "Automatique est ce qu'obtient une application qui ne fixe aucune vitesse : la vitesse standard, libre de bouger de ±0.05 pour tomber sur un nombre entier de tics de 1/60 s divisible par 2 ou 3, ce qui ne déplace aucune des durées standard. Une surcharge montre les images d'un style pendant un nombre entier de tics, exactement. Chaque ligne affiche sa durée d'image, et le bas de la page les liste toutes.",
            "page.spinners.speed": "Vitesse",
            "page.spinners.speedAutomatic": "Automatique (1 ± 0.05)",
            "page.spinners.speedHalf": "Moitié (0.5)",
            "page.spinners.speedStandard": "Standard (1, exacte)",
            "page.spinners.speedDouble": "Double (2)",
            "page.spinners.speedCustom": "Personnalisée",
            "page.spinners.rate": "Facteur",
            "page.spinners.tolerance": "Tolérance",
            "page.spinners.overrideStyle": "Surcharger pour",
            "page.spinners.frameTicks": "Image",
            "page.spinners.frameInherit": "suit la vitesse",
            "page.spinners.clearOverrides": "Effacer les surcharges",
            "page.spinners.durations": "Durées d'image en ms :",
            "page.spinners.instantsModel %@": "≈ %@ instants distincts par seconde où un spinner ici change d'image (un modèle)",
        ],

        "it": [
            "page.spinners.speedSection": "Velocità",
            "page.spinners.speedHint": "Automatica è ciò che ottiene un'app che non imposta alcuna velocità: la velocità standard, libera di spostarsi di ±0.05 su un numero intero di tick da 1/60 s divisibile per 2 o 3, il che non sposta nessuna delle durate standard. Una sostituzione mostra i fotogrammi di uno stile per un numero intero di tick, esattamente. Ogni riga mostra la durata del suo fotogramma, e in fondo alla pagina sono elencate tutte.",
            "page.spinners.speed": "Velocità",
            "page.spinners.speedAutomatic": "Automatica (1 ± 0.05)",
            "page.spinners.speedHalf": "Metà (0.5)",
            "page.spinners.speedStandard": "Standard (1, esatta)",
            "page.spinners.speedDouble": "Doppia (2)",
            "page.spinners.speedCustom": "Personalizzata",
            "page.spinners.rate": "Fattore",
            "page.spinners.tolerance": "Tolleranza",
            "page.spinners.overrideStyle": "Sostituisci per",
            "page.spinners.frameTicks": "Fotogramma",
            "page.spinners.frameInherit": "segue la velocità",
            "page.spinners.clearOverrides": "Cancella sostituzioni",
            "page.spinners.durations": "Durate dei fotogrammi in ms:",
            "page.spinners.instantsModel %@": "≈ %@ istanti distinti al secondo in cui uno spinner qui cambia fotogramma (un modello)",
        ],

        "es": [
            "page.spinners.speedSection": "Velocidad",
            "page.spinners.speedHint": "Automática es lo que obtiene una app que no fija ninguna velocidad: la velocidad estándar, libre de moverse ±0.05 hasta un número entero de ticks de 1/60 s divisible por 2 o 3, lo que no mueve ninguna de las duraciones estándar. Una anulación muestra los fotogramas de un estilo durante un número entero de ticks, exactamente. Cada fila muestra la duración de su fotograma, y al pie de la página aparecen todas.",
            "page.spinners.speed": "Velocidad",
            "page.spinners.speedAutomatic": "Automática (1 ± 0.05)",
            "page.spinners.speedHalf": "Mitad (0.5)",
            "page.spinners.speedStandard": "Estándar (1, exacta)",
            "page.spinners.speedDouble": "Doble (2)",
            "page.spinners.speedCustom": "Personalizada",
            "page.spinners.rate": "Factor",
            "page.spinners.tolerance": "Tolerancia",
            "page.spinners.overrideStyle": "Anular para",
            "page.spinners.frameTicks": "Fotograma",
            "page.spinners.frameInherit": "sigue la velocidad",
            "page.spinners.clearOverrides": "Borrar anulaciones",
            "page.spinners.durations": "Duraciones de fotograma en ms:",
            "page.spinners.instantsModel %@": "≈ %@ instantes distintos por segundo en que un spinner de aquí cambia de fotograma (un modelo)",
        ],

        "zh": [
            "page.spinners.speedSection": "速度",
            "page.spinners.speedHint": "“自动”是应用未设置速度时得到的速度：标准速率，可偏移 ±0.05 以落在能被 2 或 3 整除的整数个 1/60 s 节拍上，在标准时长下这不会改变任何时长。覆盖让某一样式的每帧精确显示整数个节拍。每行显示其帧时长，页面底部列出全部时长。",
            "page.spinners.speed": "速度",
            "page.spinners.speedAutomatic": "自动（1 ± 0.05）",
            "page.spinners.speedHalf": "半速（0.5）",
            "page.spinners.speedStandard": "标准（1，精确）",
            "page.spinners.speedDouble": "双倍（2）",
            "page.spinners.speedCustom": "自定义",
            "page.spinners.rate": "速率",
            "page.spinners.tolerance": "容差",
            "page.spinners.overrideStyle": "覆盖样式",
            "page.spinners.frameTicks": "每帧",
            "page.spinners.frameInherit": "跟随速度",
            "page.spinners.clearOverrides": "清除覆盖",
            "page.spinners.durations": "帧时长（ms）：",
            "page.spinners.instantsModel %@": "≈ 每秒有 %@ 个不同时刻，此处某个加载指示器换帧（模型）",
        ],

        "ja": [
            "page.spinners.speedSection": "速度",
            "page.spinners.speedHint": "「自動」は、アプリが速度を指定しないときの速度です。標準の速度で、2 または 3 で割り切れる整数個の 1/60 s ティックに揃うよう ±0.05 までずれることがありますが、標準の時間ではどれも変わりません。上書きすると、そのスタイルの各フレームを整数ティックぴったり表示します。各行にフレーム時間を表示し、ページの下にすべてを並べます。",
            "page.spinners.speed": "速度",
            "page.spinners.speedAutomatic": "自動（1 ± 0.05）",
            "page.spinners.speedHalf": "半分（0.5）",
            "page.spinners.speedStandard": "標準（1、正確）",
            "page.spinners.speedDouble": "倍速（2）",
            "page.spinners.speedCustom": "カスタム",
            "page.spinners.rate": "倍率",
            "page.spinners.tolerance": "許容誤差",
            "page.spinners.overrideStyle": "上書きするスタイル",
            "page.spinners.frameTicks": "1 フレーム",
            "page.spinners.frameInherit": "速度に従う",
            "page.spinners.clearOverrides": "上書きをクリア",
            "page.spinners.durations": "フレーム時間（ms）：",
            "page.spinners.instantsModel %@": "≈ 毎秒 %@ 回、ここのいずれかのスピナーがフレームを切り替える時刻（モデル）",
        ],
    ]
}

// swiftlint:enable line_length
