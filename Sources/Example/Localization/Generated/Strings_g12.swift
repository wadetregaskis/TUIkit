// swiftlint:disable line_length
//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Strings_g12.swift
//
//  Created by Wade Tregaskis
//  License: MIT
//
//  Translation fragment (group 12): the multi-line editor's own key legend —
//  readline's bindings, which are written on nothing and so have to be written
//  down. Its own fragment because group 7 had reached the file-length limit.
//  English is the source of truth; other languages fall back to English (then
//  the key) for anything they omit. Merged into the shared lookup alongside the
//  other fragments.

extension ExampleStrings {
    static let g12: [String: [String: String]] = [
        "en": [
            "page.list.selectable": "Selection enabled",
            "page.textInput.editorKeysSection": "Editor shortcuts (readline)",
            "page.textInput.editorKeys.motion": "[^B] [^F] Back / forward a character · [^P] [^N] Previous / next line · [^V] Page down",
            "page.textInput.editorKeys.lineEnds": "[^A] [^E] Start / end of line · [^T] Transpose · [^O] Open a line below",
            "page.textInput.editorKeys.words": "[Opt-B] [Opt-F] Back / forward a word · [Opt-Bksp] [Opt-Del] Delete a word · [Opt-Tab] A literal tab",
            "page.textInput.editorKeys.kill": "[^K] Kill to end of line · [^Y] Yank it back · [^D] Delete forward",
            "page.textInput.editorKeys.selectAll": "[Opt-^A] Select all",
        ],
        "de": [
            "page.list.selectable": "Auswahl aktiviert",
            "page.textInput.editorKeysSection": "Editor-Kürzel (readline)",
            "page.textInput.editorKeys.motion": "[^B] [^F] Ein Zeichen zurück / vor · [^P] [^N] Vorige / nächste Zeile · [^V] Eine Seite runter",
            "page.textInput.editorKeys.lineEnds": "[^A] [^E] Zeilenanfang / -ende · [^T] Zeichen tauschen · [^O] Zeile darunter öffnen",
            "page.textInput.editorKeys.words": "[Opt-B] [Opt-F] Ein Wort zurück / vor · [Opt-Rück] [Opt-Entf] Wort löschen · [Opt-Tab] Echter Tabulator",
            "page.textInput.editorKeys.kill": "[^K] Bis Zeilenende löschen · [^Y] Wieder einfügen · [^D] Vorwärts löschen",
            "page.textInput.editorKeys.selectAll": "[Opt-^A] Alles auswählen",
        ],
        "fr": [
            "page.list.selectable": "Sélection activée",
            "page.textInput.editorKeysSection": "Raccourcis de l'éditeur (readline)",
            "page.textInput.editorKeys.motion": "[^B] [^F] Caractère précédent / suivant · [^P] [^N] Ligne précédente / suivante · [^V] Page suivante",
            "page.textInput.editorKeys.lineEnds": "[^A] [^E] Début / fin de ligne · [^T] Transposer · [^O] Ouvrir une ligne dessous",
            "page.textInput.editorKeys.words": "[Opt-B] [Opt-F] Mot précédent / suivant · [Opt-Ret.arr.] [Opt-Suppr] Supprimer un mot · [Opt-Tab] Tabulation littérale",
            "page.textInput.editorKeys.kill": "[^K] Supprimer jusqu'à la fin · [^Y] Recoller · [^D] Supprimer en avant",
            "page.textInput.editorKeys.selectAll": "[Opt-^A] Tout sélectionner",
        ],
        "it": [
            "page.list.selectable": "Selezione attiva",
            "page.textInput.editorKeysSection": "Scorciatoie dell'editor (readline)",
            "page.textInput.editorKeys.motion": "[^B] [^F] Un carattere indietro / avanti · [^P] [^N] Riga precedente / successiva · [^V] Pagina giù",
            "page.textInput.editorKeys.lineEnds": "[^A] [^E] Inizio / fine riga · [^T] Scambia caratteri · [^O] Apri una riga sotto",
            "page.textInput.editorKeys.words": "[Opt-B] [Opt-F] Una parola indietro / avanti · [Opt-Backsp] [Opt-Canc] Elimina una parola · [Opt-Tab] Tabulazione vera",
            "page.textInput.editorKeys.kill": "[^K] Elimina fino a fine riga · [^Y] Reincolla · [^D] Elimina in avanti",
            "page.textInput.editorKeys.selectAll": "[Opt-^A] Seleziona tutto",
        ],
        "es": [
            "page.list.selectable": "Selección activada",
            "page.textInput.editorKeysSection": "Atajos del editor (readline)",
            "page.textInput.editorKeys.motion": "[^B] [^F] Un carácter atrás / adelante · [^P] [^N] Línea anterior / siguiente · [^V] Página abajo",
            "page.textInput.editorKeys.lineEnds": "[^A] [^E] Inicio / fin de línea · [^T] Transponer · [^O] Abrir una línea debajo",
            "page.textInput.editorKeys.words": "[Opt-B] [Opt-F] Una palabra atrás / adelante · [Opt-Retroc] [Opt-Supr] Borrar una palabra · [Opt-Tab] Tabulador literal",
            "page.textInput.editorKeys.kill": "[^K] Borrar hasta el final · [^Y] Volver a pegar · [^D] Borrar hacia delante",
            "page.textInput.editorKeys.selectAll": "[Opt-^A] Seleccionar todo",
        ],
        "zh": [
            "page.list.selectable": "启用选择",
            "page.textInput.editorKeysSection": "编辑器快捷键（readline）",
            "page.textInput.editorKeys.motion": "[^B] [^F] 前后移动一个字符 · [^P] [^N] 上一行 / 下一行 · [^V] 向下翻页",
            "page.textInput.editorKeys.lineEnds": "[^A] [^E] 行首 / 行尾 · [^T] 交换字符 · [^O] 在下方新开一行",
            "page.textInput.editorKeys.words": "[Opt-B] [Opt-F] 前后移动一个词 · [Opt-退格] [Opt-Del] 删除一个词 · [Opt-Tab] 输入真正的制表符",
            "page.textInput.editorKeys.kill": "[^K] 删到行尾 · [^Y] 粘回来 · [^D] 向后删除",
            "page.textInput.editorKeys.selectAll": "[Opt-^A] 全选",
        ],
        "ja": [
            "page.list.selectable": "選択を有効にする",
            "page.textInput.editorKeysSection": "エディタのショートカット（readline）",
            "page.textInput.editorKeys.motion": "[^B] [^F] 一文字戻る／進む · [^P] [^N] 前の行／次の行 · [^V] 一画面下へ",
            "page.textInput.editorKeys.lineEnds": "[^A] [^E] 行頭／行末 · [^T] 文字を入れ替え · [^O] 下に行を開く",
            "page.textInput.editorKeys.words": "[Opt-B] [Opt-F] 一語戻る／進む · [Opt-BS] [Opt-Del] 一語削除 · [Opt-Tab] 本物のタブ",
            "page.textInput.editorKeys.kill": "[^K] 行末まで削除 · [^Y] 貼り戻す · [^D] 前方削除",
            "page.textInput.editorKeys.selectAll": "[Opt-^A] すべて選択",
        ],
    ]
}
// swiftlint:enable line_length
