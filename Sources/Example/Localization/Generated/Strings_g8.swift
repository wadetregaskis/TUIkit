//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Strings_g8.swift
//
//  Created by LAYERED.work
//  License: MIT
//
//  Translation fragment for the SwiftUI-compatibility (§4a) demo additions:
//  Text(_:format:), \.locale, .focusable, .searchable, and EditMode/EditButton.
//  English is the source of truth; every other language mirrors the same key
//  set. (This fragment was English-only when the §4a demos landed, which left
//  every other language silently falling back to English for 31 strings.)

// swiftlint:disable line_length

extension ExampleStrings {
    static let g8: [String: [String: String]] = [
        "en": [
            // Text(_:format:) + \.locale (Text Styles page)
            "page.textStyles.section.format": "Formatted Values · Text(_:format:)",
            "page.textStyles.formatExplain": "Text(value, format:) renders a value through a Foundation FormatStyle (percent, number, currency).",
            "page.textStyles.section.locale": "Locale · \\.locale",
            "page.textStyles.localeExplain": "The same number, re-formatted by overriding .environment(\\.locale, …) — note the grouping separators.",

            // .focusable (Focus & Input page)
            "page.focus.focusableSection": "Focusable views · .focusable()",
            "page.focus.focusableExplain": "Any view becomes a Tab stop with .focusable(); @FocusState then binds to it via .focused(). Tab to the item below — it shows (focused) while it holds focus.",
            "page.focus.focusableUnfocused": "Focusable",
            "page.focus.focusableFocused": "Focusable (focused)",

            // .searchable (Lists page)
            "page.list.searchableSection": "Searchable",
            "page.list.searchableExplain": "A .searchable field filters the list (filtering is app-driven).",
            "page.list.searchableEmpty": "No matches",

            // (The Lists page's .onMove / .onDelete section moved to group 3,
            // alongside the other `page.list.*` keys — and is translated there.)

            // @Bindable + .id (State Persistence page)
            "page.state.bindableSection": "@Bindable · bindings into an @Observable",
            "page.state.bindableDescription": "@Bindable derives a Binding into a mutable property of an @Observable object you already own.",
            "page.state.bindableName": "Name",
            "page.state.bindableSubscribed": "Subscribed",
            "page.state.bindableLive": "Live model",
            "page.state.idSection": ".id() · identity reset",
            "page.state.idDescription": "Changing a view's .id() gives it a fresh identity, so its own @State resets. Increment the counter, then press Reset.",
            "page.state.idCount": "Count",
            "page.state.idHint": "← its own @State",
            "page.state.idReset": "Reset (bump .id)",

            // confirmationDialog (Overlays page)
            "page.overlays.confirm.section": "confirmationDialog",
            "page.overlays.confirm.explain": "An action sheet: vertically-stacked buttons, the cancel role sorted last, Escape to dismiss.",
            "page.overlays.confirm.trigger": "Delete item…",
            "page.overlays.confirm.result": "Choice",
            "page.overlays.confirm.title": "Delete this item?",
            "page.overlays.confirm.message": "This action cannot be undone.",
            "page.overlays.confirm.delete": "Delete",
            "page.overlays.confirm.cancel": "Cancel",
            "page.overlays.confirm.deleted": "deleted",
            "page.overlays.confirm.cancelled": "cancelled",
        ],
        // MARK: - German
        "de": [
            // Text(_:format:) + \.locale (Text Styles page)
            "page.textStyles.section.format": "Formatierte Werte · Text(_:format:)",
            "page.textStyles.formatExplain": "Text(value, format:) stellt einen Wert über einen Foundation-FormatStyle dar (Prozent, Zahl, Währung).",
            "page.textStyles.section.locale": "Gebietsschema · \\.locale",
            "page.textStyles.localeExplain": "Dieselbe Zahl, neu formatiert durch Überschreiben von .environment(\\.locale, …) — beachte die Tausendertrennzeichen.",

            // .focusable (Focus & Input page)
            "page.focus.focusableSection": "Fokussierbare Views · .focusable()",
            "page.focus.focusableExplain": "Mit .focusable() wird jede View zur Tab-Station; @FocusState bindet sich per .focused() daran. Tabbe zum Element unten — es zeigt (fokussiert), solange es den Fokus hält.",
            "page.focus.focusableUnfocused": "Fokussierbar",
            "page.focus.focusableFocused": "Fokussierbar (fokussiert)",

            // .searchable (Lists page)
            "page.list.searchableSection": "Durchsuchbar",
            "page.list.searchableExplain": "Ein .searchable-Feld filtert die Liste (das Filtern übernimmt die App).",
            "page.list.searchableEmpty": "Keine Treffer",

            // (The Lists page's .onMove / .onDelete section moved to group 3,
            // alongside the other `page.list.*` keys — and is translated there.)

            // @Bindable + .id (State Persistence page)
            "page.state.bindableSection": "@Bindable · Bindings in ein @Observable",
            "page.state.bindableDescription": "@Bindable leitet ein Binding auf eine veränderbare Eigenschaft eines @Observable-Objekts ab, das dir bereits gehört.",
            "page.state.bindableName": "Name",
            "page.state.bindableSubscribed": "Abonniert",
            "page.state.bindableLive": "Live-Modell",
            "page.state.idSection": ".id() · Identität zurücksetzen",
            "page.state.idDescription": "Ändert man die .id() einer View, bekommt sie eine neue Identität und ihr eigener @State wird zurückgesetzt. Zähle hoch und drücke dann Zurücksetzen.",
            "page.state.idCount": "Zähler",
            "page.state.idHint": "← ihr eigener @State",
            "page.state.idReset": "Zurücksetzen (.id erhöhen)",

            // confirmationDialog (Overlays page)
            "page.overlays.confirm.section": "confirmationDialog",
            "page.overlays.confirm.explain": "Ein Aktionsblatt: vertikal gestapelte Schaltflächen, die Abbrechen-Rolle zuletzt einsortiert, Escape zum Schließen.",
            "page.overlays.confirm.trigger": "Element löschen…",
            "page.overlays.confirm.result": "Auswahl",
            "page.overlays.confirm.title": "Dieses Element löschen?",
            "page.overlays.confirm.message": "Diese Aktion kann nicht rückgängig gemacht werden.",
            "page.overlays.confirm.delete": "Löschen",
            "page.overlays.confirm.cancel": "Abbrechen",
            "page.overlays.confirm.deleted": "gelöscht",
            "page.overlays.confirm.cancelled": "abgebrochen",
        ],
        // MARK: - French
        "fr": [
            // Text(_:format:) + \.locale (Text Styles page)
            "page.textStyles.section.format": "Valeurs formatées · Text(_:format:)",
            "page.textStyles.formatExplain": "Text(value, format:) affiche une valeur via un FormatStyle de Foundation (pourcentage, nombre, devise).",
            "page.textStyles.section.locale": "Locale · \\.locale",
            "page.textStyles.localeExplain": "Le même nombre, reformaté en surchargeant .environment(\\.locale, …) — notez les séparateurs de milliers.",

            // .focusable (Focus & Input page)
            "page.focus.focusableSection": "Vues focalisables · .focusable()",
            "page.focus.focusableExplain": "Toute vue devient un arrêt de tabulation avec .focusable() ; @FocusState s'y lie ensuite via .focused(). Tabulez jusqu'à l'élément ci-dessous — il affiche (focalisé) tant qu'il détient le focus.",
            "page.focus.focusableUnfocused": "Focalisable",
            "page.focus.focusableFocused": "Focalisable (focalisé)",

            // .searchable (Lists page)
            "page.list.searchableSection": "Recherchable",
            "page.list.searchableExplain": "Un champ .searchable filtre la liste (le filtrage est piloté par l'application).",
            "page.list.searchableEmpty": "Aucun résultat",

            // (The Lists page's .onMove / .onDelete section moved to group 3,
            // alongside the other `page.list.*` keys — and is translated there.)

            // @Bindable + .id (State Persistence page)
            "page.state.bindableSection": "@Bindable · liaisons vers un @Observable",
            "page.state.bindableDescription": "@Bindable dérive un Binding vers une propriété modifiable d'un objet @Observable que vous possédez déjà.",
            "page.state.bindableName": "Nom",
            "page.state.bindableSubscribed": "Abonné",
            "page.state.bindableLive": "Modèle en direct",
            "page.state.idSection": ".id() · réinitialisation d'identité",
            "page.state.idDescription": "Changer le .id() d'une vue lui donne une nouvelle identité, donc son propre @State est réinitialisé. Incrémentez le compteur, puis appuyez sur Réinitialiser.",
            "page.state.idCount": "Compteur",
            "page.state.idHint": "← son propre @State",
            "page.state.idReset": "Réinitialiser (incrémenter .id)",

            // confirmationDialog (Overlays page)
            "page.overlays.confirm.section": "confirmationDialog",
            "page.overlays.confirm.explain": "Une feuille d'actions : boutons empilés verticalement, le rôle d'annulation trié en dernier, Échap pour fermer.",
            "page.overlays.confirm.trigger": "Supprimer l'élément…",
            "page.overlays.confirm.result": "Choix",
            "page.overlays.confirm.title": "Supprimer cet élément ?",
            "page.overlays.confirm.message": "Cette action est irréversible.",
            "page.overlays.confirm.delete": "Supprimer",
            "page.overlays.confirm.cancel": "Annuler",
            "page.overlays.confirm.deleted": "supprimé",
            "page.overlays.confirm.cancelled": "annulé",
        ],
        // MARK: - Italian
        "it": [
            // Text(_:format:) + \.locale (Text Styles page)
            "page.textStyles.section.format": "Valori formattati · Text(_:format:)",
            "page.textStyles.formatExplain": "Text(value, format:) mostra un valore tramite un FormatStyle di Foundation (percentuale, numero, valuta).",
            "page.textStyles.section.locale": "Locale · \\.locale",
            "page.textStyles.localeExplain": "Lo stesso numero, riformattato sovrascrivendo .environment(\\.locale, …) — nota i separatori delle migliaia.",

            // .focusable (Focus & Input page)
            "page.focus.focusableSection": "Viste focalizzabili · .focusable()",
            "page.focus.focusableExplain": "Con .focusable() qualsiasi vista diventa una tappa del Tab; @FocusState vi si lega poi tramite .focused(). Tabula fino all'elemento sotto — mostra (con focus) finché lo mantiene.",
            "page.focus.focusableUnfocused": "Focalizzabile",
            "page.focus.focusableFocused": "Focalizzabile (con focus)",

            // .searchable (Lists page)
            "page.list.searchableSection": "Ricercabile",
            "page.list.searchableExplain": "Un campo .searchable filtra l'elenco (il filtro è gestito dall'app).",
            "page.list.searchableEmpty": "Nessun risultato",

            // (The Lists page's .onMove / .onDelete section moved to group 3,
            // alongside the other `page.list.*` keys — and is translated there.)

            // @Bindable + .id (State Persistence page)
            "page.state.bindableSection": "@Bindable · binding in un @Observable",
            "page.state.bindableDescription": "@Bindable ricava un Binding verso una proprietà modificabile di un oggetto @Observable che già possiedi.",
            "page.state.bindableName": "Nome",
            "page.state.bindableSubscribed": "Iscritto",
            "page.state.bindableLive": "Modello dal vivo",
            "page.state.idSection": ".id() · ripristino dell'identità",
            "page.state.idDescription": "Cambiare l'.id() di una vista le dà una nuova identità, quindi il suo @State si azzera. Incrementa il contatore, poi premi Ripristina.",
            "page.state.idCount": "Conteggio",
            "page.state.idHint": "← il suo @State",
            "page.state.idReset": "Ripristina (incrementa .id)",

            // confirmationDialog (Overlays page)
            "page.overlays.confirm.section": "confirmationDialog",
            "page.overlays.confirm.explain": "Un foglio d'azione: pulsanti impilati verticalmente, il ruolo di annullamento ordinato per ultimo, Esc per chiudere.",
            "page.overlays.confirm.trigger": "Elimina elemento…",
            "page.overlays.confirm.result": "Scelta",
            "page.overlays.confirm.title": "Eliminare questo elemento?",
            "page.overlays.confirm.message": "Questa azione non può essere annullata.",
            "page.overlays.confirm.delete": "Elimina",
            "page.overlays.confirm.cancel": "Annulla",
            "page.overlays.confirm.deleted": "eliminato",
            "page.overlays.confirm.cancelled": "annullato",
        ],
        // MARK: - Spanish
        "es": [
            // Text(_:format:) + \.locale (Text Styles page)
            "page.textStyles.section.format": "Valores formateados · Text(_:format:)",
            "page.textStyles.formatExplain": "Text(value, format:) muestra un valor a través de un FormatStyle de Foundation (porcentaje, número, moneda).",
            "page.textStyles.section.locale": "Configuración regional · \\.locale",
            "page.textStyles.localeExplain": "El mismo número, reformateado al sobrescribir .environment(\\.locale, …); fíjate en los separadores de miles.",

            // .focusable (Focus & Input page)
            "page.focus.focusableSection": "Vistas enfocables · .focusable()",
            "page.focus.focusableExplain": "Con .focusable() cualquier vista pasa a ser una parada del tabulador; @FocusState se enlaza a ella mediante .focused(). Tabula hasta el elemento de abajo: muestra (con foco) mientras lo mantiene.",
            "page.focus.focusableUnfocused": "Enfocable",
            "page.focus.focusableFocused": "Enfocable (con foco)",

            // .searchable (Lists page)
            "page.list.searchableSection": "Buscable",
            "page.list.searchableExplain": "Un campo .searchable filtra la lista (el filtrado lo hace la app).",
            "page.list.searchableEmpty": "Sin coincidencias",

            // (The Lists page's .onMove / .onDelete section moved to group 3,
            // alongside the other `page.list.*` keys — and is translated there.)

            // @Bindable + .id (State Persistence page)
            "page.state.bindableSection": "@Bindable · enlaces a un @Observable",
            "page.state.bindableDescription": "@Bindable deriva un Binding a una propiedad mutable de un objeto @Observable que ya posees.",
            "page.state.bindableName": "Nombre",
            "page.state.bindableSubscribed": "Suscrito",
            "page.state.bindableLive": "Modelo en vivo",
            "page.state.idSection": ".id() · reinicio de identidad",
            "page.state.idDescription": "Cambiar el .id() de una vista le da una identidad nueva, así que su propio @State se reinicia. Incrementa el contador y luego pulsa Restablecer.",
            "page.state.idCount": "Contador",
            "page.state.idHint": "← su propio @State",
            "page.state.idReset": "Restablecer (subir .id)",

            // confirmationDialog (Overlays page)
            "page.overlays.confirm.section": "confirmationDialog",
            "page.overlays.confirm.explain": "Una hoja de acciones: botones apilados verticalmente, el rol de cancelar ordenado al final, Escape para cerrar.",
            "page.overlays.confirm.trigger": "Eliminar elemento…",
            "page.overlays.confirm.result": "Elección",
            "page.overlays.confirm.title": "¿Eliminar este elemento?",
            "page.overlays.confirm.message": "Esta acción no se puede deshacer.",
            "page.overlays.confirm.delete": "Eliminar",
            "page.overlays.confirm.cancel": "Cancelar",
            "page.overlays.confirm.deleted": "eliminado",
            "page.overlays.confirm.cancelled": "cancelado",
        ],
        // MARK: - Chinese (Simplified)
        "zh": [
            // Text(_:format:) + \.locale (Text Styles page)
            "page.textStyles.section.format": "格式化数值 · Text(_:format:)",
            "page.textStyles.formatExplain": "Text(value, format:) 通过 Foundation 的 FormatStyle 渲染数值（百分比、数字、货币）。",
            "page.textStyles.section.locale": "区域设置 · \\.locale",
            "page.textStyles.localeExplain": "同一个数字，通过覆盖 .environment(\\.locale, …) 重新格式化——注意千位分隔符。",

            // .focusable (Focus & Input page)
            "page.focus.focusableSection": "可聚焦视图 · .focusable()",
            "page.focus.focusableExplain": "用 .focusable() 可让任何视图成为 Tab 停靠点；@FocusState 再通过 .focused() 与之绑定。用 Tab 移到下方条目——持有焦点时它会显示（已聚焦）。",
            "page.focus.focusableUnfocused": "可聚焦",
            "page.focus.focusableFocused": "可聚焦（已聚焦）",

            // .searchable (Lists page)
            "page.list.searchableSection": "可搜索",
            "page.list.searchableExplain": ".searchable 字段用于筛选列表（筛选逻辑由应用实现）。",
            "page.list.searchableEmpty": "无匹配项",

            // (The Lists page's .onMove / .onDelete section moved to group 3,
            // alongside the other `page.list.*` keys — and is translated there.)

            // @Bindable + .id (State Persistence page)
            "page.state.bindableSection": "@Bindable · 绑定到 @Observable",
            "page.state.bindableDescription": "@Bindable 会为你已持有的 @Observable 对象的可变属性派生出一个 Binding。",
            "page.state.bindableName": "名称",
            "page.state.bindableSubscribed": "已订阅",
            "page.state.bindableLive": "实时模型",
            "page.state.idSection": ".id() · 标识重置",
            "page.state.idDescription": "修改视图的 .id() 会赋予它新的标识，因此它自己的 @State 会重置。先增加计数，再按重置。",
            "page.state.idCount": "计数",
            "page.state.idHint": "← 它自己的 @State",
            "page.state.idReset": "重置（递增 .id）",

            // confirmationDialog (Overlays page)
            "page.overlays.confirm.section": "confirmationDialog",
            "page.overlays.confirm.explain": "操作表：按钮纵向排列，取消角色排在最后，按 Esc 关闭。",
            "page.overlays.confirm.trigger": "删除项目…",
            "page.overlays.confirm.result": "选择",
            "page.overlays.confirm.title": "要删除此项吗？",
            "page.overlays.confirm.message": "此操作无法撤销。",
            "page.overlays.confirm.delete": "删除",
            "page.overlays.confirm.cancel": "取消",
            "page.overlays.confirm.deleted": "已删除",
            "page.overlays.confirm.cancelled": "已取消",
        ],
        // MARK: - Japanese
        "ja": [
            // Text(_:format:) + \.locale (Text Styles page)
            "page.textStyles.section.format": "書式付きの値 · Text(_:format:)",
            "page.textStyles.formatExplain": "Text(value, format:) は Foundation の FormatStyle を通して値を表示します（パーセント・数値・通貨）。",
            "page.textStyles.section.locale": "ロケール · \\.locale",
            "page.textStyles.localeExplain": "同じ数値を .environment(\\.locale, …) の上書きで再フォーマットしたもの — 桁区切りに注目してください。",

            // .focusable (Focus & Input page)
            "page.focus.focusableSection": "フォーカス可能なビュー · .focusable()",
            "page.focus.focusableExplain": ".focusable() を付ければどんなビューも Tab の停止点になり、@FocusState が .focused() で結び付きます。Tab で下の項目へ移動すると、フォーカスを持つ間は（フォーカス中）と表示されます。",
            "page.focus.focusableUnfocused": "フォーカス可能",
            "page.focus.focusableFocused": "フォーカス可能（フォーカス中）",

            // .searchable (Lists page)
            "page.list.searchableSection": "検索可能",
            "page.list.searchableExplain": ".searchable フィールドがリストを絞り込みます（絞り込み処理はアプリ側で行います）。",
            "page.list.searchableEmpty": "該当なし",

            // (The Lists page's .onMove / .onDelete section moved to group 3,
            // alongside the other `page.list.*` keys — and is translated there.)

            // @Bindable + .id (State Persistence page)
            "page.state.bindableSection": "@Bindable · @Observable への束縛",
            "page.state.bindableDescription": "@Bindable は、すでに保持している @Observable オブジェクトの可変プロパティへの Binding を導きます。",
            "page.state.bindableName": "名前",
            "page.state.bindableSubscribed": "購読中",
            "page.state.bindableLive": "ライブモデル",
            "page.state.idSection": ".id() · アイデンティティのリセット",
            "page.state.idDescription": "ビューの .id() を変えると新しいアイデンティティになり、そのビュー自身の @State はリセットされます。カウンターを増やしてからリセットを押してください。",
            "page.state.idCount": "カウント",
            "page.state.idHint": "← このビュー自身の @State",
            "page.state.idReset": "リセット（.id を進める）",

            // confirmationDialog (Overlays page)
            "page.overlays.confirm.section": "confirmationDialog",
            "page.overlays.confirm.explain": "アクションシート: ボタンを縦に並べ、キャンセルの役割を最後に置き、Escape で閉じます。",
            "page.overlays.confirm.trigger": "項目を削除…",
            "page.overlays.confirm.result": "選択",
            "page.overlays.confirm.title": "この項目を削除しますか？",
            "page.overlays.confirm.message": "この操作は取り消せません。",
            "page.overlays.confirm.delete": "削除",
            "page.overlays.confirm.cancel": "キャンセル",
            "page.overlays.confirm.deleted": "削除しました",
            "page.overlays.confirm.cancelled": "キャンセルしました",
        ],
    ]
}

// swiftlint:enable line_length
