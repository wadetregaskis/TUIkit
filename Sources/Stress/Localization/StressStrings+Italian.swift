//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StressStrings+Italian.swift
//
//  Created by LAYERED.work
//  License: MIT
//
//  Italian. See `StressStrings+English.swift` for what is in scope and
//  what deliberately is not.

// swiftlint:disable line_length

extension StressStrings {
    static let it: [String: String] = [
        // MARK: shell
        "stress.shell.menu.title": "TUIkit — Stress test",
        "stress.shell.label.scale": "scala",
        "stress.shell.label.seed": "seed",
        "stress.shell.label.autopilot": "pilota automatico",
        "stress.shell.autopilot.on": "attivo",
        "stress.shell.autopilot.off": "disattivo",
        "stress.shell.autopilot.frame": "frame",
        "stress.shell.menu.help": "↑/↓ seleziona · invio apri · +/− scala · a pilota automatico · esc esci",
        "stress.shell.footer.hint": "esc indietro · +/− scala · a pilota automatico",

        // MARK: megalist
        "stress.scenario.megalist.title": "Mega elenco",
        "stress.scenario.megalist.blurb": "Elenco con finestra di N righe; contenuto con hash per indice (nessun array di supporto).",
        "stress.scenario.megalist.stresses": "Windowing List/ForEach · risoluzione ID riga · contenuto riga lazy · memo per riga",
        "stress.scenario.megalist.heading": "Mega elenco — {0} righe",

        // MARK: table
        "stress.scenario.table.title": "Tabella larga",
        "stress.scenario.table.blurb": "N righe × 8 colonne; stringhe per cella sintetizzate dall'hash della riga.",
        "stress.scenario.table.stresses": "Calcolo larghezza colonne · windowing righe · closure di valore per cella",
        "stress.scenario.table.heading": "Tabella larga — {0} righe × 8 colonne",

        // MARK: table-multiline
        "stress.scenario.table-multiline.title": "Tabella multiriga",
        "stress.scenario.table-multiline.blurb": "N righe × 4 colonne; una colonna Dettagli va a capo su ≤3 righe, quindi l'altezza delle righe varia.",
        "stress.scenario.table-multiline.stresses": "A capo cella multiriga · dimensionamento riga lazy (solo finestra + coda) · windowing ad altezza variabile",
        "stress.scenario.table-multiline.heading": "Tabella multiriga — {0} righe, Dettagli va a capo su ≤3 righe",

        // MARK: truncate
        "stress.scenario.truncate.title": "Tabella troncata",
        "stress.scenario.truncate.blurb": "N righe × 6 colonne di frasi lunghe; ogni cella viene ritagliata a una colonna stretta.",
        "stress.scenario.truncate.stresses": "Ritaglio compatibile ANSI · tutte e tre le modalità di troncamento · misura/riempimento per cella",
        "stress.scenario.truncate.heading": "Tabella troncata — {0} righe × 6 colonne ritagliate",

        // MARK: table-churn
        "stress.scenario.table-churn.title": "Tabella in movimento",
        "stress.scenario.table-churn.blurb": "N righe × 6 colonne; i dati vengono sostituiti a ogni frame ma solo ~2% delle righe differisce.",
        "stress.scenario.table-churn.stresses": "ridisegno di righe invariate · closure dei valori di cella · margine per un memo per riga",
        "stress.scenario.table-churn.heading": "Tabella in movimento — {0} righe, una su {1} cambia per frame",

        // MARK: table-churn-wrapped
        "stress.scenario.table-churn-wrapped.title": "Tabella a capo in movimento",
        "stress.scenario.table-churn-wrapped.blurb": "250 righe a capo sotto il limite dello stimatore; ~2% cambiano per frame.",
        "stress.scenario.table-churn-wrapped.stresses": "layout di righe multilinea · misurazione dell'altezza di ogni riga · closure dei valori di cella",
        "stress.scenario.table-churn-wrapped.heading": "Tabella a capo in movimento — {0} righe, una su {1} cambia per frame",

        // MARK: table-tail
        "stress.scenario.table-tail.title": "Tabella inseguitrice",
        "stress.scenario.table-tail.blurb": "Una finestra su una sequenza crescente: ogni riga mantiene il contenuto e sale di una riga per frame.",
        "stress.scenario.table-tail.stresses": "identità di riga tra le posizioni · ridisegno delle righe spostate · closure dei valori di cella",
        "stress.scenario.table-tail.heading": "Tabella inseguitrice — finestra di {0} righe su una sequenza crescente",

        // MARK: tables-scroll
        "stress.scenario.tables-scroll.title": "Tabelle in una vista a scorrimento",
        "stress.scenario.tables-scroll.blurb": "N tabelle impilate in una vista a scorrimento; ognuna materializza le sue righe e calcola le proprie larghezze di colonna.",
        "stress.scenario.tables-scroll.stresses": "Più istanze di Table · calcolo larghezza colonne per tabella · windowing della vista a scorrimento sul buffer combinato",
        "stress.scenario.tables-scroll.heading": "Tabelle in una vista a scorrimento — {0} tabelle × {1} righe",

        // MARK: tables-vstack
        "stress.scenario.tables-vstack.title": "Tabelle in un VStack",
        "stress.scenario.tables-vstack.blurb": "N tabelle impilate direttamente in un VStack (senza scorrimento); lo stack misura e dispone ogni tabella.",
        "stress.scenario.tables-vstack.stresses": "Più istanze di Table · calcolo larghezza colonne per tabella · misura/disposizione VStack su molti figli",
        "stress.scenario.tables-vstack.heading": "Tabelle in un VStack — {0} tabelle × {1} righe",
        "stress.scenario.tables.tableLabel": "Tabella {0}",

        // MARK: deep
        "stress.scenario.deep.title": "Ricorsione profonda",
        "stress.scenario.deep.blurb": "Una vista annidata in se stessa fino alla profondità D (con bordo/spaziatura a ogni livello).",
        "stress.scenario.deep.stresses": "Profondità catena ViewIdentity · ricorsione di misura · propagazione del contesto",
        "stress.scenario.deep.heading": "Ricorsione profonda — profondità {0}",
        "stress.scenario.deep.leaf": "foglia @ {0}: {1}",
        "stress.scenario.deep.level": "livello {0}",

        // MARK: fanout
        "stress.scenario.fanout.title": "Ampia diramazione",
        "stress.scenario.fanout.blurb": "Un VStack non-lazy con N figli diretti (ogni figlio misurato a ogni frame).",
        "stress.scenario.fanout.stresses": "misura del contenitore su tutti i figli · distribuzione dello spazio · layout O(n)",
        "stress.scenario.fanout.heading": "Ampia diramazione — {0} fratelli in un solo VStack",

        // MARK: modifiers
        "stress.scenario.modifiers.title": "Catene di modificatori",
        "stress.scenario.modifiers.blurb": "N righe, ognuna avvolta in una lunga catena di modificatori.",
        "stress.scenario.modifiers.stresses": "Stratificazione ModifiedView/modificatore d'ambiente · overhead di misura per nodo",
        "stress.scenario.modifiers.heading": "Catene di modificatori — {0} righe fortemente modificate",

        // MARK: preferences
        "stress.scenario.preferences.title": "Righe con preferenze",
        "stress.scenario.preferences.blurb": "N righe, ognuna pubblica una preferenza a un collettore.",
        "stress.scenario.preferences.stresses": "dichiarazione dell'effetto collaterale di preferenza · elusione del memo dei valori · nuova misurazione per riga",
        "stress.scenario.preferences.heading": "{0} righe · {1} pubblicate",

        // MARK: customlayout
        "stress.scenario.customlayout.title": "Layout personalizzato",
        "stress.scenario.customlayout.blurb": "N sottoviste disposte da una conformità Layout dietro AnyLayout.",
        "stress.scenario.customlayout.stresses": "schema di chiamata del protocollo Layout · misurazione ripetuta delle sottoviste · cancellazione di tipo AnyLayout",
        "stress.scenario.customlayout.heading": "{0} chip in un Layout personalizzato",

        // MARK: textwall
        "stress.scenario.textwall.title": "Muro di testo",
        "stress.scenario.textwall.blurb": "N lunghi paragrafi a capo di prosa sintetizzata.",
        "stress.scenario.textwall.stresses": "misura larghezza testo · a capo automatico · throughput dei glifi",
        "stress.scenario.textwall.heading": "Muro di testo — {0} paragrafi a capo",

        // MARK: anyview
        "stress.scenario.anyview.title": "Tempesta di AnyView",
        "stress.scenario.anyview.blurb": "N righe eterogenee, ognuna cancellata tramite AnyView.",
        "stress.scenario.anyview.stresses": "fallback di cancellazione di tipo · percorso render-verso-misura · dispatch concreto perso",
        "stress.scenario.anyview.heading": "Tempesta di AnyView — {0} righe a tipo cancellato",

        // MARK: dashboard
        "stress.scenario.dashboard.title": "Dashboard",
        "stress.scenario.dashboard.blurb": "Una griglia di N pannelli di metriche (barre + avanzamento) — layout di contenitori denso.",
        "stress.scenario.dashboard.stresses": "Misura contenitore Panel/Card · condivisione riga a larghezza flessibile · foglie miste",
        "stress.scenario.dashboard.heading": "Dashboard — {0} pannelli di metriche",
        "stress.scenario.framedcolumns.title": "Colonne incorniciate",
        "stress.scenario.framedcolumns.blurb": "Colonne a frame fissi di righe interattive (List, Card di Toggle, un Panel di log).",
        "stress.scenario.framedcolumns.stresses": "misura dei .frame finiti · cascata di frame in stack in frame · righe interattive non memorizzabili",
        "stress.scenario.framedcolumns.heading": "Colonne incorniciate — {0} righe di toggle per card",

        // MARK: churn
        "stress.scenario.churn.title": "Aggiornamento continuo",
        "stress.scenario.churn.blurb": "N righe il cui contenuto cambia a ogni frame (guidato dal tick) — nessun successo di memo.",
        "stress.scenario.churn.stresses": "render completo per frame · invalidazione cache · misura senza memo",
        "stress.scenario.animating.title": "Animazione",
        "stress.scenario.animating.blurb": "N righe interpolate insieme, nessuna memorizzabile in cache.",
        "stress.scenario.animating.stresses": "accessi all’archivio delle animazioni · sottoalberi non memorizzabili · risoluzione dei colori per frame",
        "stress.scenario.animating.heading": "Animazione — {0} righe, tutte in movimento",
        "stress.scenario.translucent.title": "Traslucido",
        "stress.scenario.translucent.blurb": "Un grande pannello sbiadito su una destinazione ridisegnata a ogni fotogramma.",
        "stress.scenario.translucent.stresses": "scomposizione in celle di entrambi i lati · ricerca di regione per cella · riemissione SGR",
        "stress.scenario.translucent.heading": "Traslucido — {0} righe, ciascuna sbiadita su una banda che cambia",
        "stress.scenario.gradients.title": "Sfumature",
        "stress.scenario.gradients.blurb": "Una sfumatura su un lungo elenco, sfumature per vista, quattro geometrie, riempimenti sfumati.",
        "stress.scenario.gradients.stresses": "quantizzazione della sfumatura · geometria per cella · propagazione dell'origine · ricolorazione allo spostamento · sequenze SGR",
        "stress.scenario.gradients.heading": "Sfumature — {0} righe sotto un'unica sfumatura, più bande per vista e per geometria",
        "stress.scenario.alpharamp.title": "Sfumature alfa",
        "stress.scenario.alpharamp.blurb": "Sfumature traslucide in tutte e quattro le forme di alfa, come inchiostro e come riempimento.",
        "stress.scenario.alpharamp.stresses": "derivazione delle rivendicazioni per cella · trasporto delle regioni nella composizione · risoluzione dell'opacità",
        "stress.scenario.alpharamp.heading": "Sfumature alfa — {0} righe di sfumatura traslucida in ogni forma di alfa",
        "stress.scenario.churn.heading": "Aggiornamento continuo — frame {0}, {1} righe invalidate/frame",
        "stress.scenario.scrollfollow.title": "Scorrimento ancorato",
        "stress.scenario.scrollfollow.blurb": "ScrollView ancorata in basso su N righe di altezza variabile; una riga aggiunta a ogni tick.",
        "stress.scenario.scrollfollow.stresses": "rendering a banda finestrata · avanzamento dell'àncora · stima della coda · O(finestra) per ogni N",
        "stress.scenario.scrollfollow.heading": "Scorrimento ancorato — {0} righe, ancorato in basso (una riga aggiunta per frame)",

        // MARK: kitchensink
        "stress.scenario.menus.title": "Barra dei menu",
        "stress.scenario.menus.blurb": "Menu inline di righe con scorciatoie, accanto a ogni ButtonStyle integrato.",
        "stress.scenario.menus.stresses": "misura del corpo del ButtonStyle · passata di larghezza aderente del menu · colonna delle scorciatoie · risoluzione di @Environment per riga",
        "stress.scenario.menus.heading": "Barra dei menu — {0} menu da {1} righe",
        "stress.scenario.keyrows.title": "Righe con tasti",
        "stress.scenario.keyrows.blurb": "Righe memoizzate che registrano ciascuna un gestore di tasti ed elementi della barra di stato, accanto a un pannello aggiornabile.",
        "stress.scenario.keyrows.stresses": "registrazioni per riga sotto il memo di riga · registri di tasti e barra di stato svuotati a ogni frame · Ctrl-R aggiornabile",
        "stress.scenario.keyrows.heading": "Righe con tasti — {0} righe, ciascuna con un gestore di tasti e un elemento della barra di stato",
        "stress.scenario.kitchensink.title": "Tutto in uno",
        "stress.scenario.kitchensink.blurb": "Vista divisa: grande elenco nella barra laterale + dettaglio a griglia di pannelli densa, insieme.",
        "stress.scenario.kitchensink.stresses": "layout vista divisa + windowing elenco + griglia di contenitori simultaneamente",
        "stress.scenario.kitchensink.heading.items": "Elementi ({0})",
        "stress.scenario.kitchensink.heading.metrics": "Metriche",
    ]
}

// swiftlint:enable line_length
