//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Strings_g14.swift
//
//  Created by Wade Tregaskis
//  License: MIT
//
//  Translation fragment for the Buttons & Links page's terminal-hyperlink note
//  — what this host does with the OSC 8 escape a `Link` carries, and why the
//  answer differs between hosts. Its own fragment rather than an addition to
//  `Strings_g7`, which was at the 600-line limit. English is the source of
//  truth; every other language carries the same key set.

// swiftlint:disable line_length

extension ExampleStrings {
    static let g14: [String: [String: String]] = [
        "en": [
            "page.buttons.links.osc8": "A link also carries an OSC 8 escape, telling the terminal where the label points — so the URL can be shown on hover and copied, even though it appears nowhere on screen.",
            "page.buttons.links.terminal": "Terminal",
            "page.buttons.links.osc8Status": "OSC 8",
            "page.buttons.links.honoured": "sent",
            "page.buttons.links.notHonoured": "not sent",
            "page.buttons.links.unidentified": "unidentified",
            "page.buttons.links.noteITerm2": "iTerm2 stores the destination — hover a link to see it. ⌘-click arrives at the app rather than the link, so shift-click is what to try instead (untested — no probe can click).",
            "page.buttons.links.noteGhostty": "Ghostty stores the destination in its cell model and can preview it on hover.",
            "page.buttons.links.noteTmux": "tmux stores the link but forwards it only to clients it credits with the hyperlinks feature. If yours shows nothing: set -ga terminal-features '*:hyperlinks'",
            "page.buttons.links.noteAppleTerminal": "Apple Terminal has no hyperlink support at all: it swallows the escape and keeps nothing, so TUIkit does not send one.",
            "page.buttons.links.noteWarp": "Warp handles links only outside the alternate screen — the only buffer a TUIkit app ever draws into — so the escape would be stored nowhere and is not sent.",
            "page.buttons.links.noteUnidentified": "This terminal was not identified, so links are off: an unmeasured host gets the answer that cannot hurt. Set TUIKIT_HYPERLINKS=1 if yours does support them.",
            "page.buttons.links.suppressed": "That last link suppresses the escape with .terminalHyperlinks(false) — what an app opening its own URL scheme wants, since a terminal that opens a link does so over the top of OpenURLAction.",
        ],

        "de": [
            "page.buttons.links.osc8": "Ein Link trägt außerdem eine OSC-8-Sequenz, die dem Terminal mitteilt, wohin die Beschriftung zeigt — so lässt sich die URL beim Überfahren anzeigen und kopieren, obwohl sie nirgends auf dem Bildschirm steht.",
            "page.buttons.links.terminal": "Terminal",
            "page.buttons.links.osc8Status": "OSC 8",
            "page.buttons.links.honoured": "gesendet",
            "page.buttons.links.notHonoured": "nicht gesendet",
            "page.buttons.links.unidentified": "nicht erkannt",
            "page.buttons.links.noteITerm2": "iTerm2 speichert das Ziel — Maus über einen Link bewegen, um es zu sehen. ⌘-Klick erreicht die App statt des Links; stattdessen Umschalt-Klick versuchen (ungetestet — kein Prüfprogramm kann klicken).",
            "page.buttons.links.noteGhostty": "Ghostty speichert das Ziel in seinem Zellenmodell und kann es beim Überfahren anzeigen.",
            "page.buttons.links.noteTmux": "tmux speichert den Link, leitet ihn aber nur an Clients weiter, denen es die Funktion hyperlinks zutraut. Wenn nichts erscheint: set -ga terminal-features '*:hyperlinks'",
            "page.buttons.links.noteAppleTerminal": "Apple Terminal unterstützt Hyperlinks überhaupt nicht: Es verschluckt die Sequenz und behält nichts, deshalb sendet TUIkit keine.",
            "page.buttons.links.noteWarp": "Warp verarbeitet Links nur außerhalb des alternativen Bildschirms — dem einzigen Puffer, in den eine TUIkit-App zeichnet — die Sequenz würde also nirgends gespeichert und wird nicht gesendet.",
            "page.buttons.links.noteUnidentified": "Dieses Terminal wurde nicht erkannt, daher sind Links aus: Ein nicht vermessener Host bekommt die Antwort, die nicht schaden kann. TUIKIT_HYPERLINKS=1 setzen, falls Ihres sie unterstützt.",
            "page.buttons.links.suppressed": "Der letzte Link unterdrückt die Sequenz mit .terminalHyperlinks(false) — passend für eine App mit eigenem URL-Schema, denn ein Terminal, das einen Link öffnet, tut das über OpenURLAction hinweg.",
        ],

        "fr": [
            "page.buttons.links.osc8": "Un lien porte aussi une séquence OSC 8, qui indique au terminal où pointe le libellé — l'URL peut donc être affichée au survol et copiée, alors qu'elle n'apparaît nulle part à l'écran.",
            "page.buttons.links.terminal": "Terminal",
            "page.buttons.links.osc8Status": "OSC 8",
            "page.buttons.links.honoured": "envoyée",
            "page.buttons.links.notHonoured": "non envoyée",
            "page.buttons.links.unidentified": "non identifié",
            "page.buttons.links.noteITerm2": "iTerm2 mémorise la destination — survolez un lien pour la voir. Le ⌘-clic parvient à l'application plutôt qu'au lien ; essayez plutôt le maj-clic (non testé — aucune sonde ne peut cliquer).",
            "page.buttons.links.noteGhostty": "Ghostty mémorise la destination dans son modèle de cellules et peut l'afficher au survol.",
            "page.buttons.links.noteTmux": "tmux mémorise le lien mais ne le transmet qu'aux clients auxquels il accorde la fonction hyperlinks. Si rien ne s'affiche : set -ga terminal-features '*:hyperlinks'",
            "page.buttons.links.noteAppleTerminal": "Apple Terminal ne gère aucun hyperlien : il avale la séquence et ne conserve rien, donc TUIkit n'en envoie pas.",
            "page.buttons.links.noteWarp": "Warp ne traite les liens qu'en dehors de l'écran alternatif — le seul tampon où dessine une application TUIkit — la séquence ne serait donc stockée nulle part et n'est pas envoyée.",
            "page.buttons.links.noteUnidentified": "Ce terminal n'a pas été identifié, les liens sont donc désactivés : un hôte non mesuré reçoit la réponse qui ne peut pas nuire. Définissez TUIKIT_HYPERLINKS=1 si le vôtre les gère.",
            "page.buttons.links.suppressed": "Ce dernier lien supprime la séquence avec .terminalHyperlinks(false) — ce que veut une application ouvrant son propre schéma d'URL, car un terminal qui ouvre un lien le fait par-dessus OpenURLAction.",
        ],

        "it": [
            "page.buttons.links.osc8": "Un collegamento porta anche una sequenza OSC 8, che dice al terminale dove punta l'etichetta — così l'URL può essere mostrato al passaggio del mouse e copiato, pur non comparendo da nessuna parte sullo schermo.",
            "page.buttons.links.terminal": "Terminale",
            "page.buttons.links.osc8Status": "OSC 8",
            "page.buttons.links.honoured": "inviata",
            "page.buttons.links.notHonoured": "non inviata",
            "page.buttons.links.unidentified": "non identificato",
            "page.buttons.links.noteITerm2": "iTerm2 memorizza la destinazione — passa sopra un collegamento per vederla. Il ⌘-clic arriva all'applicazione anziché al collegamento; prova invece il maiusc-clic (non verificato — nessuna sonda può cliccare).",
            "page.buttons.links.noteGhostty": "Ghostty memorizza la destinazione nel suo modello di celle e può mostrarla al passaggio del mouse.",
            "page.buttons.links.noteTmux": "tmux memorizza il collegamento ma lo inoltra solo ai client a cui riconosce la funzione hyperlinks. Se non compare nulla: set -ga terminal-features '*:hyperlinks'",
            "page.buttons.links.noteAppleTerminal": "Apple Terminal non gestisce affatto gli hyperlink: ingoia la sequenza e non conserva nulla, quindi TUIkit non ne invia.",
            "page.buttons.links.noteWarp": "Warp gestisce i collegamenti solo fuori dallo schermo alternativo — l'unico buffer in cui disegna un'app TUIkit — quindi la sequenza non verrebbe memorizzata da nessuna parte e non viene inviata.",
            "page.buttons.links.noteUnidentified": "Questo terminale non è stato identificato, quindi i collegamenti sono disattivati: un host non misurato riceve la risposta che non può nuocere. Imposta TUIKIT_HYPERLINKS=1 se il tuo li supporta.",
            "page.buttons.links.suppressed": "L'ultimo collegamento sopprime la sequenza con .terminalHyperlinks(false) — ciò che vuole un'app che apre il proprio schema URL, dato che un terminale che apre un collegamento lo fa scavalcando OpenURLAction.",
        ],

        "es": [
            "page.buttons.links.osc8": "Un enlace lleva además una secuencia OSC 8, que indica al terminal adónde apunta la etiqueta — así la URL puede mostrarse al pasar el ratón y copiarse, aunque no aparezca en ninguna parte de la pantalla.",
            "page.buttons.links.terminal": "Terminal",
            "page.buttons.links.osc8Status": "OSC 8",
            "page.buttons.links.honoured": "enviada",
            "page.buttons.links.notHonoured": "no enviada",
            "page.buttons.links.unidentified": "no identificado",
            "page.buttons.links.noteITerm2": "iTerm2 guarda el destino — pasa el ratón por un enlace para verlo. El ⌘-clic llega a la aplicación en vez de al enlace; prueba en su lugar el mayús-clic (sin verificar — ninguna sonda puede hacer clic).",
            "page.buttons.links.noteGhostty": "Ghostty guarda el destino en su modelo de celdas y puede mostrarlo al pasar el ratón.",
            "page.buttons.links.noteTmux": "tmux guarda el enlace pero solo lo reenvía a los clientes a los que reconoce la función hyperlinks. Si no aparece nada: set -ga terminal-features '*:hyperlinks'",
            "page.buttons.links.noteAppleTerminal": "Apple Terminal no admite hiperenlaces en absoluto: se traga la secuencia y no conserva nada, así que TUIkit no envía ninguna.",
            "page.buttons.links.noteWarp": "Warp solo gestiona enlaces fuera de la pantalla alternativa — el único búfer en el que dibuja una app TUIkit — de modo que la secuencia no se guardaría en ningún sitio y no se envía.",
            "page.buttons.links.noteUnidentified": "Este terminal no se identificó, así que los enlaces están desactivados: un host sin medir recibe la respuesta que no puede hacer daño. Define TUIKIT_HYPERLINKS=1 si el tuyo sí los admite.",
            "page.buttons.links.suppressed": "Ese último enlace suprime la secuencia con .terminalHyperlinks(false) — lo que quiere una app que abre su propio esquema de URL, ya que un terminal que abre un enlace lo hace por encima de OpenURLAction.",
        ],

        "zh": [
            "page.buttons.links.osc8": "链接还会带上一段 OSC 8 转义序列，告诉终端标签指向何处——于是即便 URL 从未显示在屏幕上，也能在悬停时查看并复制。",
            "page.buttons.links.terminal": "终端",
            "page.buttons.links.osc8Status": "OSC 8",
            "page.buttons.links.honoured": "已发送",
            "page.buttons.links.notHonoured": "未发送",
            "page.buttons.links.unidentified": "未识别",
            "page.buttons.links.noteITerm2": "iTerm2 会保存目标地址——悬停在链接上即可看到。⌘-点击会送到应用而不是链接，可改试 Shift-点击（未经验证——探针无法点击）。",
            "page.buttons.links.noteGhostty": "Ghostty 在其单元格模型中保存目标地址，并可在悬停时预览。",
            "page.buttons.links.noteTmux": "tmux 会保存链接，但只转发给它认可具备 hyperlinks 特性的客户端。若什么都没有：set -ga terminal-features '*:hyperlinks'",
            "page.buttons.links.noteAppleTerminal": "Apple Terminal 完全不支持超链接：它吞掉该序列且不保留任何内容，因此 TUIkit 不会发送。",
            "page.buttons.links.noteWarp": "Warp 仅在备用屏幕之外处理链接，而备用屏幕是 TUIkit 应用唯一绘制的缓冲区——序列无处可存，因此不发送。",
            "page.buttons.links.noteUnidentified": "未能识别此终端，因此链接已关闭：未经实测的主机采用不会造成损害的答案。若你的终端支持，请设置 TUIKIT_HYPERLINKS=1。",
            "page.buttons.links.suppressed": "最后那个链接用 .terminalHyperlinks(false) 抑制了该序列——自行打开 URL 方案的应用正需要如此，因为终端打开链接时会越过 OpenURLAction。",
        ],

        "ja": [
            "page.buttons.links.osc8": "リンクには OSC 8 エスケープも付き、ラベルの指す先を端末に伝えます——URL は画面のどこにも現れないのに、ホバーで表示してコピーできます。",
            "page.buttons.links.terminal": "端末",
            "page.buttons.links.osc8Status": "OSC 8",
            "page.buttons.links.honoured": "送信",
            "page.buttons.links.notHonoured": "未送信",
            "page.buttons.links.unidentified": "未識別",
            "page.buttons.links.noteITerm2": "iTerm2 は宛先を保存します——リンクにホバーすると見えます。⌘-クリックはリンクではなくアプリに届くので、代わりに Shift-クリックを試してください（未検証——探査プログラムはクリックできません）。",
            "page.buttons.links.noteGhostty": "Ghostty はセルモデルに宛先を保存し、ホバーでプレビューできます。",
            "page.buttons.links.noteTmux": "tmux はリンクを保存しますが、hyperlinks 機能を認めたクライアントにしか転送しません。何も出ない場合は：set -ga terminal-features '*:hyperlinks'",
            "page.buttons.links.noteAppleTerminal": "Apple Terminal はハイパーリンクを一切扱いません。シーケンスを飲み込んで何も保持しないため、TUIkit は送信しません。",
            "page.buttons.links.noteWarp": "Warp は代替画面の外でしかリンクを扱いません。TUIkit アプリが描画するのは代替画面だけなので、シーケンスはどこにも保存されず、送信しません。",
            "page.buttons.links.noteUnidentified": "この端末は識別できなかったためリンクは無効です。未計測のホストには害のない答えを返します。対応しているなら TUIKIT_HYPERLINKS=1 を設定してください。",
            "page.buttons.links.suppressed": "最後のリンクは .terminalHyperlinks(false) でシーケンスを抑止しています——独自 URL スキームを開くアプリが求める挙動で、端末がリンクを開くときは OpenURLAction を飛び越えてしまうからです。",
        ],
    ]
}

// swiftlint:enable line_length
