//  🖥️ TUIKit — Terminal UI Kit for Swift
//  StressStrings+Languages.swift
//
//  Created by LAYERED.work
//  License: MIT
//
//  Per-language translation tables for the TUIkitStress harness. English is the
//  source of truth; other languages fall back to English (then the key) for any
//  key they omit.
//
//  Scope: the interactive shell's own UI plus each scenario's title / blurb /
//  `stresses` summary / rendered heading. Headings that show a live count keep
//  the number via `{0}` / `{1}` placeholders (see `Lf(_:_:)`); only the static
//  phrasing is translated. The `--bench` / `--selfcheck` stdout diagnostics, the
//  `--scenario` id strings, the synthetic sample data, and the table column
//  headers are intentionally NOT here — they stay English.

// swiftlint:disable line_length

extension StressStrings {
    static let en: [String: String] = [
        // MARK: shell
        "stress.shell.menu.title": "TUIkit — Stress Test",
        "stress.shell.label.scale": "scale",
        "stress.shell.label.seed": "seed",
        "stress.shell.label.autopilot": "autopilot",
        "stress.shell.autopilot.on": "on",
        "stress.shell.autopilot.off": "off",
        "stress.shell.autopilot.frame": "frame",
        "stress.shell.menu.help": "↑/↓ select · enter open · +/− scale · a autopilot · esc quit",
        "stress.shell.footer.hint": "esc back · +/− scale · a autopilot",

        // MARK: megalist
        "stress.scenario.megalist.title": "Mega List",
        "stress.scenario.megalist.blurb": "Windowed List of N rows; content hashed per index (no backing array).",
        "stress.scenario.megalist.stresses": "List/ForEach windowing · row-id resolution · lazy row content · per-row memo",
        "stress.scenario.megalist.heading": "Mega List — {0} rows",

        // MARK: table
        "stress.scenario.table.title": "Wide Table",
        "stress.scenario.table.blurb": "N rows × 8 columns; per-cell strings synthesised from the row hash.",
        "stress.scenario.table.stresses": "Table column-width computation · row windowing · per-cell value closures",
        "stress.scenario.table.heading": "Wide Table — {0} rows × 8 columns",

        // MARK: table-multiline
        "stress.scenario.table-multiline.title": "Multi-line Table",
        "stress.scenario.table-multiline.blurb": "N rows × 4 columns; a Details column wraps to ≤3 lines, so rows vary in height.",
        "stress.scenario.table-multiline.stresses": "Multi-line cell wrapping · lazy row sizing (window + suffix only) · variable-height windowing",
        "stress.scenario.table-multiline.heading": "Multi-line Table — {0} rows, Details wraps to ≤3 lines",

        // MARK: tables-scroll
        "stress.scenario.tables-scroll.title": "Tables in a ScrollView",
        "stress.scenario.tables-scroll.blurb": "N tables stacked in a ScrollView; each materialises its rows and computes its own column widths.",
        "stress.scenario.tables-scroll.stresses": "Multiple Table instances · per-table column-width computation · ScrollView windowing over the combined buffer",
        "stress.scenario.tables-scroll.heading": "Tables in a ScrollView — {0} tables × {1} rows",

        // MARK: tables-vstack
        "stress.scenario.tables-vstack.title": "Tables in a VStack",
        "stress.scenario.tables-vstack.blurb": "N tables stacked directly in a VStack (no scroll); the stack measures and lays out every table.",
        "stress.scenario.tables-vstack.stresses": "Multiple Table instances · per-table column-width computation · VStack measure/layout over many children",
        "stress.scenario.tables-vstack.heading": "Tables in a VStack — {0} tables × {1} rows",
        "stress.scenario.tables.tableLabel": "Table {0}",

        // MARK: deep
        "stress.scenario.deep.title": "Deep Recursion",
        "stress.scenario.deep.blurb": "One view nested in itself to depth D (bordered/padded at each level).",
        "stress.scenario.deep.stresses": "ViewIdentity chain depth · measure recursion · context propagation",
        "stress.scenario.deep.heading": "Deep Recursion — depth {0}",
        "stress.scenario.deep.leaf": "leaf @ {0}: {1}",
        "stress.scenario.deep.level": "level {0}",

        // MARK: fanout
        "stress.scenario.fanout.title": "Wide Fanout",
        "stress.scenario.fanout.blurb": "One non-lazy VStack with N direct children (every child measured each frame).",
        "stress.scenario.fanout.stresses": "container measure over all children · space distribution · O(n) layout",
        "stress.scenario.fanout.heading": "Wide Fanout — {0} siblings in one VStack",

        // MARK: modifiers
        "stress.scenario.modifiers.title": "Modifier Chains",
        "stress.scenario.modifiers.blurb": "N rows, each wrapped in a long modifier chain.",
        "stress.scenario.modifiers.stresses": "ModifiedView/environment-modifier layering · per-node measure overhead",
        "stress.scenario.modifiers.heading": "Modifier Chains — {0} deeply-modified rows",

        // MARK: textwall
        "stress.scenario.textwall.title": "Text Wall",
        "stress.scenario.textwall.blurb": "N long wrapping paragraphs of synthesised prose.",
        "stress.scenario.textwall.stresses": "text width measurement · word wrapping · glyph throughput",
        "stress.scenario.textwall.heading": "Text Wall — {0} wrapping paragraphs",

        // MARK: anyview
        "stress.scenario.anyview.title": "AnyView Storm",
        "stress.scenario.anyview.blurb": "N heterogeneous rows, each erased through AnyView.",
        "stress.scenario.anyview.stresses": "type-erasure fallback · render-to-measure path · lost concrete dispatch",
        "stress.scenario.anyview.heading": "AnyView Storm — {0} type-erased rows",

        // MARK: dashboard
        "stress.scenario.dashboard.title": "Dashboard",
        "stress.scenario.dashboard.blurb": "A grid of N metric Panels (bars + progress) — dense container layout.",
        "stress.scenario.dashboard.stresses": "Panel/Card container measure · flexible-width row sharing · mixed leaves",
        "stress.scenario.dashboard.heading": "Dashboard — {0} metric panels",
        "stress.scenario.framedcolumns.title": "Framed Columns",
        "stress.scenario.framedcolumns.blurb": "Fixed-frame columns of interactive rows (List, Toggle Cards, a log Panel).",
        "stress.scenario.framedcolumns.stresses": "non-infinity .frame measure · frames-in-stacks-in-frames cascade · uncacheable interactive rows",
        "stress.scenario.framedcolumns.heading": "Framed columns — {0} toggle rows per card",

        // MARK: churn
        "stress.scenario.churn.title": "Churn Update",
        "stress.scenario.churn.blurb": "N rows whose content changes every frame (tick-driven) — no memo hits.",
        "stress.scenario.churn.stresses": "full re-render per frame · cache invalidation · measure with no memo",
        "stress.scenario.churn.heading": "Churn Update — frame {0}, {1} rows invalidated/frame",
        "stress.scenario.scrollfollow.heading": "Scroll Follow — {0} rows, bottom-anchored (a row appends every frame)",

        // MARK: kitchensink
        "stress.scenario.kitchensink.title": "Kitchen Sink",
        "stress.scenario.kitchensink.blurb": "Split view: big list sidebar + dense panel-grid detail, together.",
        "stress.scenario.kitchensink.stresses": "split-view layout + list windowing + container grid simultaneously",
        "stress.scenario.kitchensink.heading.items": "Items ({0})",
        "stress.scenario.kitchensink.heading.metrics": "Metrics",
    ]

    static let de: [String: String] = [
        // MARK: shell
        "stress.shell.menu.title": "TUIkit — Stresstest",
        "stress.shell.label.scale": "Skalierung",
        "stress.shell.label.seed": "Seed",
        "stress.shell.label.autopilot": "Autopilot",
        "stress.shell.autopilot.on": "an",
        "stress.shell.autopilot.off": "aus",
        "stress.shell.autopilot.frame": "Frame",
        "stress.shell.menu.help": "↑/↓ auswählen · Enter öffnen · +/− Skalierung · a Autopilot · Esc beenden",
        "stress.shell.footer.hint": "Esc zurück · +/− Skalierung · a Autopilot",

        // MARK: megalist
        "stress.scenario.megalist.title": "Mega-Liste",
        "stress.scenario.megalist.blurb": "Gefensterte Liste mit N Zeilen; Inhalt pro Index gehasht (kein Backing-Array).",
        "stress.scenario.megalist.stresses": "List/ForEach-Fensterung · Zeilen-ID-Auflösung · Lazy-Zeileninhalt · Memo pro Zeile",
        "stress.scenario.megalist.heading": "Mega-Liste — {0} Zeilen",

        // MARK: table
        "stress.scenario.table.title": "Breite Tabelle",
        "stress.scenario.table.blurb": "N Zeilen × 8 Spalten; Zellzeichenfolgen aus dem Zeilen-Hash synthetisiert.",
        "stress.scenario.table.stresses": "Tabellen-Spaltenbreitenberechnung · Zeilenfensterung · Wertclosures pro Zelle",
        "stress.scenario.table.heading": "Breite Tabelle — {0} Zeilen × 8 Spalten",

        // MARK: table-multiline
        "stress.scenario.table-multiline.title": "Mehrzeilige Tabelle",
        "stress.scenario.table-multiline.blurb": "N Zeilen × 4 Spalten; eine Details-Spalte bricht auf ≤3 Zeilen um, daher variiert die Zeilenhöhe.",
        "stress.scenario.table-multiline.stresses": "Mehrzeiliger Zellumbruch · Lazy-Zeilengröße (nur Fenster + Schluss) · Fensterung mit variabler Höhe",
        "stress.scenario.table-multiline.heading": "Mehrzeilige Tabelle — {0} Zeilen, Details bricht auf ≤3 Zeilen um",

        // MARK: tables-scroll
        "stress.scenario.tables-scroll.title": "Tabellen in einer Scrollansicht",
        "stress.scenario.tables-scroll.blurb": "N Tabellen in einer Scrollansicht gestapelt; jede materialisiert ihre Zeilen und berechnet eigene Spaltenbreiten.",
        "stress.scenario.tables-scroll.stresses": "Mehrere Tabelleninstanzen · Spaltenbreitenberechnung pro Tabelle · Scrollansicht-Fensterung über den kombinierten Puffer",
        "stress.scenario.tables-scroll.heading": "Tabellen in einer Scrollansicht — {0} Tabellen × {1} Zeilen",

        // MARK: tables-vstack
        "stress.scenario.tables-vstack.title": "Tabellen in einem VStack",
        "stress.scenario.tables-vstack.blurb": "N Tabellen direkt in einem VStack gestapelt (kein Scrollen); der Stack misst und ordnet jede Tabelle an.",
        "stress.scenario.tables-vstack.stresses": "Mehrere Tabelleninstanzen · Spaltenbreitenberechnung pro Tabelle · VStack-Messung/-Anordnung über viele Kinder",
        "stress.scenario.tables-vstack.heading": "Tabellen in einem VStack — {0} Tabellen × {1} Zeilen",
        "stress.scenario.tables.tableLabel": "Tabelle {0}",

        // MARK: deep
        "stress.scenario.deep.title": "Tiefe Rekursion",
        "stress.scenario.deep.blurb": "Eine in sich selbst bis Tiefe D verschachtelte Ansicht (auf jeder Ebene umrandet/mit Abstand).",
        "stress.scenario.deep.stresses": "ViewIdentity-Kettentiefe · Messrekursion · Kontextweitergabe",
        "stress.scenario.deep.heading": "Tiefe Rekursion — Tiefe {0}",
        "stress.scenario.deep.leaf": "Blatt @ {0}: {1}",
        "stress.scenario.deep.level": "Ebene {0}",

        // MARK: fanout
        "stress.scenario.fanout.title": "Breite Auffächerung",
        "stress.scenario.fanout.blurb": "Ein nicht-lazy VStack mit N direkten Kindern (jedes Kind wird pro Frame gemessen).",
        "stress.scenario.fanout.stresses": "Container-Messung über alle Kinder · Raumverteilung · O(n)-Layout",
        "stress.scenario.fanout.heading": "Breite Auffächerung — {0} Geschwister in einem VStack",

        // MARK: modifiers
        "stress.scenario.modifiers.title": "Modifikatorketten",
        "stress.scenario.modifiers.blurb": "N Zeilen, jede in eine lange Modifikatorkette gehüllt.",
        "stress.scenario.modifiers.stresses": "ModifiedView-/Umgebungsmodifikator-Schichtung · Mess-Overhead pro Knoten",
        "stress.scenario.modifiers.heading": "Modifikatorketten — {0} stark modifizierte Zeilen",

        // MARK: textwall
        "stress.scenario.textwall.title": "Textwand",
        "stress.scenario.textwall.blurb": "N lange umbrechende Absätze synthetisierter Prosa.",
        "stress.scenario.textwall.stresses": "Textbreitenmessung · Wortumbruch · Glyphendurchsatz",
        "stress.scenario.textwall.heading": "Textwand — {0} umbrechende Absätze",

        // MARK: anyview
        "stress.scenario.anyview.title": "AnyView-Sturm",
        "stress.scenario.anyview.blurb": "N heterogene Zeilen, jede durch AnyView typgelöscht.",
        "stress.scenario.anyview.stresses": "Typlöschungs-Fallback · Render-zu-Mess-Pfad · verlorene konkrete Verteilung",
        "stress.scenario.anyview.heading": "AnyView-Sturm — {0} typgelöschte Zeilen",

        // MARK: dashboard
        "stress.scenario.dashboard.title": "Dashboard",
        "stress.scenario.dashboard.blurb": "Ein Raster aus N Metrik-Panels (Balken + Fortschritt) — dichtes Container-Layout.",
        "stress.scenario.dashboard.stresses": "Panel/Card-Container-Messung · Zeilenteilung mit flexibler Breite · gemischte Blätter",
        "stress.scenario.dashboard.heading": "Dashboard — {0} Metrik-Panels",
        "stress.scenario.framedcolumns.title": "Gerahmte Spalten",
        "stress.scenario.framedcolumns.blurb": "Spalten mit festen Frames und interaktiven Zeilen (List, Toggle-Cards, ein Log-Panel).",
        "stress.scenario.framedcolumns.stresses": "Messung endlicher .frames · Kaskade aus Frames in Stacks in Frames · nicht cachebare interaktive Zeilen",
        "stress.scenario.framedcolumns.heading": "Gerahmte Spalten — {0} Toggle-Zeilen pro Card",

        // MARK: churn
        "stress.scenario.churn.title": "Churn-Aktualisierung",
        "stress.scenario.churn.blurb": "N Zeilen, deren Inhalt sich pro Frame ändert (tick-gesteuert) — keine Memo-Treffer.",
        "stress.scenario.churn.stresses": "vollständiges Neu-Rendern pro Frame · Cache-Invalidierung · Messung ohne Memo",
        "stress.scenario.churn.heading": "Churn-Aktualisierung — Frame {0}, {1} Zeilen pro Frame invalidiert",
        "stress.scenario.scrollfollow.heading": "Scroll-Verfolgung — {0} Zeilen, unten verankert (pro Frame kommt eine Zeile hinzu)",

        // MARK: kitchensink
        "stress.scenario.kitchensink.title": "Komplettpaket",
        "stress.scenario.kitchensink.blurb": "Geteilte Ansicht: große Listen-Seitenleiste + dichtes Panel-Raster-Detail, zusammen.",
        "stress.scenario.kitchensink.stresses": "Geteilte-Ansicht-Layout + Listenfensterung + Container-Raster gleichzeitig",
        "stress.scenario.kitchensink.heading.items": "Einträge ({0})",
        "stress.scenario.kitchensink.heading.metrics": "Metriken",
    ]

    static let fr: [String: String] = [
        // MARK: shell
        "stress.shell.menu.title": "TUIkit — Test de charge",
        "stress.shell.label.scale": "échelle",
        "stress.shell.label.seed": "graine",
        "stress.shell.label.autopilot": "pilote auto",
        "stress.shell.autopilot.on": "activé",
        "stress.shell.autopilot.off": "désactivé",
        "stress.shell.autopilot.frame": "image",
        "stress.shell.menu.help": "↑/↓ sélectionner · entrée ouvrir · +/− échelle · a pilote auto · échap quitter",
        "stress.shell.footer.hint": "échap retour · +/− échelle · a pilote auto",

        // MARK: megalist
        "stress.scenario.megalist.title": "Méga-liste",
        "stress.scenario.megalist.blurb": "Liste fenêtrée de N lignes ; contenu haché par index (sans tableau sous-jacent).",
        "stress.scenario.megalist.stresses": "Fenêtrage List/ForEach · résolution d'ID de ligne · contenu de ligne lazy · mémo par ligne",
        "stress.scenario.megalist.heading": "Méga-liste — {0} lignes",

        // MARK: table
        "stress.scenario.table.title": "Tableau large",
        "stress.scenario.table.blurb": "N lignes × 8 colonnes ; chaînes par cellule synthétisées à partir du hachage de la ligne.",
        "stress.scenario.table.stresses": "Calcul de largeur de colonne · fenêtrage des lignes · closures de valeur par cellule",
        "stress.scenario.table.heading": "Tableau large — {0} lignes × 8 colonnes",

        // MARK: table-multiline
        "stress.scenario.table-multiline.title": "Tableau multiligne",
        "stress.scenario.table-multiline.blurb": "N lignes × 4 colonnes ; une colonne Détails se replie sur ≤3 lignes, la hauteur des lignes varie donc.",
        "stress.scenario.table-multiline.stresses": "Repli de cellule multiligne · dimensionnement de ligne lazy (fenêtre + fin seulement) · fenêtrage à hauteur variable",
        "stress.scenario.table-multiline.heading": "Tableau multiligne — {0} lignes, Détails se replie sur ≤3 lignes",

        // MARK: tables-scroll
        "stress.scenario.tables-scroll.title": "Tableaux dans une vue défilante",
        "stress.scenario.tables-scroll.blurb": "N tableaux empilés dans une vue défilante ; chacun matérialise ses lignes et calcule ses propres largeurs de colonne.",
        "stress.scenario.tables-scroll.stresses": "Plusieurs instances de Table · calcul de largeur de colonne par tableau · fenêtrage de la vue défilante sur le tampon combiné",
        "stress.scenario.tables-scroll.heading": "Tableaux dans une vue défilante — {0} tableaux × {1} lignes",

        // MARK: tables-vstack
        "stress.scenario.tables-vstack.title": "Tableaux dans un VStack",
        "stress.scenario.tables-vstack.blurb": "N tableaux empilés directement dans un VStack (sans défilement) ; la pile mesure et dispose chaque tableau.",
        "stress.scenario.tables-vstack.stresses": "Plusieurs instances de Table · calcul de largeur de colonne par tableau · mesure/disposition VStack sur de nombreux enfants",
        "stress.scenario.tables-vstack.heading": "Tableaux dans un VStack — {0} tableaux × {1} lignes",
        "stress.scenario.tables.tableLabel": "Tableau {0}",

        // MARK: deep
        "stress.scenario.deep.title": "Récursion profonde",
        "stress.scenario.deep.blurb": "Une vue imbriquée en elle-même jusqu'à la profondeur D (bordée/avec marge à chaque niveau).",
        "stress.scenario.deep.stresses": "Profondeur de chaîne ViewIdentity · récursion de mesure · propagation du contexte",
        "stress.scenario.deep.heading": "Récursion profonde — profondeur {0}",
        "stress.scenario.deep.leaf": "feuille @ {0} : {1}",
        "stress.scenario.deep.level": "niveau {0}",

        // MARK: fanout
        "stress.scenario.fanout.title": "Large éventail",
        "stress.scenario.fanout.blurb": "Un VStack non-lazy avec N enfants directs (chaque enfant mesuré à chaque image).",
        "stress.scenario.fanout.stresses": "mesure du conteneur sur tous les enfants · répartition de l'espace · disposition en O(n)",
        "stress.scenario.fanout.heading": "Large éventail — {0} frères dans un seul VStack",

        // MARK: modifiers
        "stress.scenario.modifiers.title": "Chaînes de modificateurs",
        "stress.scenario.modifiers.blurb": "N lignes, chacune enveloppée dans une longue chaîne de modificateurs.",
        "stress.scenario.modifiers.stresses": "Empilement ModifiedView/modificateur d'environnement · surcoût de mesure par nœud",
        "stress.scenario.modifiers.heading": "Chaînes de modificateurs — {0} lignes fortement modifiées",

        // MARK: textwall
        "stress.scenario.textwall.title": "Mur de texte",
        "stress.scenario.textwall.blurb": "N longs paragraphes à retour à la ligne de prose synthétisée.",
        "stress.scenario.textwall.stresses": "mesure de largeur du texte · retour à la ligne · débit de glyphes",
        "stress.scenario.textwall.heading": "Mur de texte — {0} paragraphes à retour à la ligne",

        // MARK: anyview
        "stress.scenario.anyview.title": "Tempête d'AnyView",
        "stress.scenario.anyview.blurb": "N lignes hétérogènes, chacune effacée via AnyView.",
        "stress.scenario.anyview.stresses": "repli d'effacement de type · chemin rendu-vers-mesure · perte de la répartition concrète",
        "stress.scenario.anyview.heading": "Tempête d'AnyView — {0} lignes à type effacé",

        // MARK: dashboard
        "stress.scenario.dashboard.title": "Tableau de bord",
        "stress.scenario.dashboard.blurb": "Une grille de N panneaux de métriques (barres + progression) — disposition de conteneurs dense.",
        "stress.scenario.dashboard.stresses": "Mesure de conteneur Panel/Card · partage de ligne à largeur flexible · feuilles mixtes",
        "stress.scenario.dashboard.heading": "Tableau de bord — {0} panneaux de métriques",
        "stress.scenario.framedcolumns.title": "Colonnes cadrées",
        "stress.scenario.framedcolumns.blurb": "Colonnes à cadres fixes de lignes interactives (List, Cards de Toggles, un Panel de journal).",
        "stress.scenario.framedcolumns.stresses": "mesure des .frame finis · cascade de frames dans des stacks dans des frames · lignes interactives non mémorisables",
        "stress.scenario.framedcolumns.heading": "Colonnes cadrées — {0} lignes de toggles par card",

        // MARK: churn
        "stress.scenario.churn.title": "Mise à jour continue",
        "stress.scenario.churn.blurb": "N lignes dont le contenu change à chaque image (piloté par tick) — aucun succès de mémo.",
        "stress.scenario.churn.stresses": "rendu complet par image · invalidation du cache · mesure sans mémo",
        "stress.scenario.churn.heading": "Mise à jour continue — image {0}, {1} lignes invalidées/image",
        "stress.scenario.scrollfollow.heading": "Suivi du défilement — {0} lignes, ancré en bas (une ligne ajoutée par image)",

        // MARK: kitchensink
        "stress.scenario.kitchensink.title": "Tout-en-un",
        "stress.scenario.kitchensink.blurb": "Vue divisée : grande liste en barre latérale + détail en grille de panneaux dense, ensemble.",
        "stress.scenario.kitchensink.stresses": "disposition en vue divisée + fenêtrage de liste + grille de conteneurs simultanément",
        "stress.scenario.kitchensink.heading.items": "Éléments ({0})",
        "stress.scenario.kitchensink.heading.metrics": "Métriques",
    ]

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
        "stress.scenario.churn.heading": "Aggiornamento continuo — frame {0}, {1} righe invalidate/frame",
        "stress.scenario.scrollfollow.heading": "Scorrimento ancorato — {0} righe, ancorato in basso (una riga aggiunta per frame)",

        // MARK: kitchensink
        "stress.scenario.kitchensink.title": "Tutto in uno",
        "stress.scenario.kitchensink.blurb": "Vista divisa: grande elenco nella barra laterale + dettaglio a griglia di pannelli densa, insieme.",
        "stress.scenario.kitchensink.stresses": "layout vista divisa + windowing elenco + griglia di contenitori simultaneamente",
        "stress.scenario.kitchensink.heading.items": "Elementi ({0})",
        "stress.scenario.kitchensink.heading.metrics": "Metriche",
    ]

    static let es: [String: String] = [
        // MARK: shell
        "stress.shell.menu.title": "TUIkit — Prueba de estrés",
        "stress.shell.label.scale": "escala",
        "stress.shell.label.seed": "semilla",
        "stress.shell.label.autopilot": "piloto automático",
        "stress.shell.autopilot.on": "activado",
        "stress.shell.autopilot.off": "desactivado",
        "stress.shell.autopilot.frame": "fotograma",
        "stress.shell.menu.help": "↑/↓ seleccionar · intro abrir · +/− escala · a piloto automático · esc salir",
        "stress.shell.footer.hint": "esc volver · +/− escala · a piloto automático",

        // MARK: megalist
        "stress.scenario.megalist.title": "Mega lista",
        "stress.scenario.megalist.blurb": "Lista con ventana de N filas; contenido con hash por índice (sin array de respaldo).",
        "stress.scenario.megalist.stresses": "Ventaneo List/ForEach · resolución de ID de fila · contenido de fila lazy · memo por fila",
        "stress.scenario.megalist.heading": "Mega lista — {0} filas",

        // MARK: table
        "stress.scenario.table.title": "Tabla ancha",
        "stress.scenario.table.blurb": "N filas × 8 columnas; cadenas por celda sintetizadas a partir del hash de la fila.",
        "stress.scenario.table.stresses": "Cálculo de ancho de columna · ventaneo de filas · closures de valor por celda",
        "stress.scenario.table.heading": "Tabla ancha — {0} filas × 8 columnas",

        // MARK: table-multiline
        "stress.scenario.table-multiline.title": "Tabla multilínea",
        "stress.scenario.table-multiline.blurb": "N filas × 4 columnas; una columna Detalles se ajusta a ≤3 líneas, por lo que la altura de las filas varía.",
        "stress.scenario.table-multiline.stresses": "Ajuste de celda multilínea · dimensionado de fila lazy (solo ventana + cola) · ventaneo de altura variable",
        "stress.scenario.table-multiline.heading": "Tabla multilínea — {0} filas, Detalles se ajusta a ≤3 líneas",

        // MARK: tables-scroll
        "stress.scenario.tables-scroll.title": "Tablas en una vista de desplazamiento",
        "stress.scenario.tables-scroll.blurb": "N tablas apiladas en una vista de desplazamiento; cada una materializa sus filas y calcula sus propios anchos de columna.",
        "stress.scenario.tables-scroll.stresses": "Varias instancias de Table · cálculo de ancho de columna por tabla · ventaneo de la vista de desplazamiento sobre el búfer combinado",
        "stress.scenario.tables-scroll.heading": "Tablas en una vista de desplazamiento — {0} tablas × {1} filas",

        // MARK: tables-vstack
        "stress.scenario.tables-vstack.title": "Tablas en un VStack",
        "stress.scenario.tables-vstack.blurb": "N tablas apiladas directamente en un VStack (sin desplazamiento); la pila mide y dispone cada tabla.",
        "stress.scenario.tables-vstack.stresses": "Varias instancias de Table · cálculo de ancho de columna por tabla · medición/disposición VStack sobre muchos hijos",
        "stress.scenario.tables-vstack.heading": "Tablas en un VStack — {0} tablas × {1} filas",
        "stress.scenario.tables.tableLabel": "Tabla {0}",

        // MARK: deep
        "stress.scenario.deep.title": "Recursión profunda",
        "stress.scenario.deep.blurb": "Una vista anidada en sí misma hasta la profundidad D (con borde/margen en cada nivel).",
        "stress.scenario.deep.stresses": "Profundidad de cadena ViewIdentity · recursión de medición · propagación de contexto",
        "stress.scenario.deep.heading": "Recursión profunda — profundidad {0}",
        "stress.scenario.deep.leaf": "hoja @ {0}: {1}",
        "stress.scenario.deep.level": "nivel {0}",

        // MARK: fanout
        "stress.scenario.fanout.title": "Despliegue amplio",
        "stress.scenario.fanout.blurb": "Un VStack no-lazy con N hijos directos (cada hijo se mide en cada fotograma).",
        "stress.scenario.fanout.stresses": "medición del contenedor sobre todos los hijos · distribución del espacio · disposición O(n)",
        "stress.scenario.fanout.heading": "Despliegue amplio — {0} hermanos en un solo VStack",

        // MARK: modifiers
        "stress.scenario.modifiers.title": "Cadenas de modificadores",
        "stress.scenario.modifiers.blurb": "N filas, cada una envuelta en una larga cadena de modificadores.",
        "stress.scenario.modifiers.stresses": "Estratificación ModifiedView/modificador de entorno · sobrecarga de medición por nodo",
        "stress.scenario.modifiers.heading": "Cadenas de modificadores — {0} filas muy modificadas",

        // MARK: textwall
        "stress.scenario.textwall.title": "Muro de texto",
        "stress.scenario.textwall.blurb": "N párrafos largos con ajuste de línea de prosa sintetizada.",
        "stress.scenario.textwall.stresses": "medición de ancho de texto · ajuste de línea · rendimiento de glifos",
        "stress.scenario.textwall.heading": "Muro de texto — {0} párrafos con ajuste de línea",

        // MARK: anyview
        "stress.scenario.anyview.title": "Tormenta de AnyView",
        "stress.scenario.anyview.blurb": "N filas heterogéneas, cada una borrada mediante AnyView.",
        "stress.scenario.anyview.stresses": "alternativa de borrado de tipo · ruta de renderizado-a-medición · despacho concreto perdido",
        "stress.scenario.anyview.heading": "Tormenta de AnyView — {0} filas con tipo borrado",

        // MARK: dashboard
        "stress.scenario.dashboard.title": "Panel de control",
        "stress.scenario.dashboard.blurb": "Una cuadrícula de N paneles de métricas (barras + progreso) — disposición de contenedores densa.",
        "stress.scenario.dashboard.stresses": "Medición de contenedor Panel/Card · compartición de fila de ancho flexible · hojas mixtas",
        "stress.scenario.dashboard.heading": "Panel de control — {0} paneles de métricas",
        "stress.scenario.framedcolumns.title": "Columnas enmarcadas",
        "stress.scenario.framedcolumns.blurb": "Columnas de marcos fijos con filas interactivas (List, Cards de Toggles, un Panel de registro).",
        "stress.scenario.framedcolumns.stresses": "medición de .frame finitos · cascada de frames en stacks en frames · filas interactivas no cacheables",
        "stress.scenario.framedcolumns.heading": "Columnas enmarcadas — {0} filas de toggles por card",

        // MARK: churn
        "stress.scenario.churn.title": "Actualización continua",
        "stress.scenario.churn.blurb": "N filas cuyo contenido cambia en cada fotograma (impulsado por tick) — sin aciertos de memo.",
        "stress.scenario.churn.stresses": "renderizado completo por fotograma · invalidación de caché · medición sin memo",
        "stress.scenario.churn.heading": "Actualización continua — fotograma {0}, {1} filas invalidadas/fotograma",
        "stress.scenario.scrollfollow.heading": "Seguimiento de desplazamiento — {0} filas, anclado abajo (se añade una fila por fotograma)",

        // MARK: kitchensink
        "stress.scenario.kitchensink.title": "Todo en uno",
        "stress.scenario.kitchensink.blurb": "Vista dividida: lista grande en la barra lateral + detalle de cuadrícula de paneles densa, juntos.",
        "stress.scenario.kitchensink.stresses": "disposición de vista dividida + ventaneo de lista + cuadrícula de contenedores simultáneamente",
        "stress.scenario.kitchensink.heading.items": "Elementos ({0})",
        "stress.scenario.kitchensink.heading.metrics": "Métricas",
    ]

    static let zh: [String: String] = [
        // MARK: shell
        "stress.shell.menu.title": "TUIkit — 压力测试",
        "stress.shell.label.scale": "规模",
        "stress.shell.label.seed": "种子",
        "stress.shell.label.autopilot": "自动驾驶",
        "stress.shell.autopilot.on": "开",
        "stress.shell.autopilot.off": "关",
        "stress.shell.autopilot.frame": "帧",
        "stress.shell.menu.help": "↑/↓ 选择 · 回车 打开 · +/− 规模 · a 自动驾驶 · esc 退出",
        "stress.shell.footer.hint": "esc 返回 · +/− 规模 · a 自动驾驶",

        // MARK: megalist
        "stress.scenario.megalist.title": "超级列表",
        "stress.scenario.megalist.blurb": "N 行的窗口化列表；内容按索引哈希生成（无后备数组）。",
        "stress.scenario.megalist.stresses": "List/ForEach 窗口化 · 行 ID 解析 · 惰性行内容 · 逐行备忘",
        "stress.scenario.megalist.heading": "超级列表 — {0} 行",

        // MARK: table
        "stress.scenario.table.title": "宽表格",
        "stress.scenario.table.blurb": "N 行 × 8 列；每个单元格的字符串由行哈希合成。",
        "stress.scenario.table.stresses": "表格列宽计算 · 行窗口化 · 逐单元格取值闭包",
        "stress.scenario.table.heading": "宽表格 — {0} 行 × 8 列",

        // MARK: table-multiline
        "stress.scenario.table-multiline.title": "多行表格",
        "stress.scenario.table-multiline.blurb": "N 行 × 4 列；详情列换行至 ≤3 行，因此行高各不相同。",
        "stress.scenario.table-multiline.stresses": "多行单元格换行 · 惰性行尺寸（仅窗口 + 末尾）· 可变行高窗口化",
        "stress.scenario.table-multiline.heading": "多行表格 — {0} 行，详情换行至 ≤3 行",

        // MARK: tables-scroll
        "stress.scenario.tables-scroll.title": "滚动视图中的多个表格",
        "stress.scenario.tables-scroll.blurb": "N 个表格堆叠在滚动视图中；每个都物化自己的行并计算各自的列宽。",
        "stress.scenario.tables-scroll.stresses": "多个 Table 实例 · 逐表格列宽计算 · 滚动视图对合并缓冲区的窗口化",
        "stress.scenario.tables-scroll.heading": "滚动视图中的多个表格 — {0} 个表格 × {1} 行",

        // MARK: tables-vstack
        "stress.scenario.tables-vstack.title": "VStack 中的多个表格",
        "stress.scenario.tables-vstack.blurb": "N 个表格直接堆叠在 VStack 中（不滚动）；由该堆栈测量并布局每个表格。",
        "stress.scenario.tables-vstack.stresses": "多个 Table 实例 · 逐表格列宽计算 · VStack 对众多子项的测量/布局",
        "stress.scenario.tables-vstack.heading": "VStack 中的多个表格 — {0} 个表格 × {1} 行",
        "stress.scenario.tables.tableLabel": "表格 {0}",

        // MARK: deep
        "stress.scenario.deep.title": "深度递归",
        "stress.scenario.deep.blurb": "一个视图自我嵌套至深度 D（每一层都带边框/内边距）。",
        "stress.scenario.deep.stresses": "ViewIdentity 链深度 · 测量递归 · 上下文传播",
        "stress.scenario.deep.heading": "深度递归 — 深度 {0}",
        "stress.scenario.deep.leaf": "叶 @ {0}：{1}",
        "stress.scenario.deep.level": "层级 {0}",

        // MARK: fanout
        "stress.scenario.fanout.title": "宽扇出",
        "stress.scenario.fanout.blurb": "一个非惰性 VStack，包含 N 个直接子项（每帧都测量每个子项）。",
        "stress.scenario.fanout.stresses": "对所有子项的容器测量 · 空间分配 · O(n) 布局",
        "stress.scenario.fanout.heading": "宽扇出 — 一个 VStack 中的 {0} 个同级项",

        // MARK: modifiers
        "stress.scenario.modifiers.title": "修饰符链",
        "stress.scenario.modifiers.blurb": "N 行，每行都包裹在一条长修饰符链中。",
        "stress.scenario.modifiers.stresses": "ModifiedView/环境修饰符分层 · 逐节点测量开销",
        "stress.scenario.modifiers.heading": "修饰符链 — {0} 个深度修饰的行",

        // MARK: textwall
        "stress.scenario.textwall.title": "文本墙",
        "stress.scenario.textwall.blurb": "N 段合成散文的长换行段落。",
        "stress.scenario.textwall.stresses": "文本宽度测量 · 自动换行 · 字形吞吐量",
        "stress.scenario.textwall.heading": "文本墙 — {0} 个换行段落",

        // MARK: anyview
        "stress.scenario.anyview.title": "AnyView 风暴",
        "stress.scenario.anyview.blurb": "N 个异构行，每行都通过 AnyView 进行类型擦除。",
        "stress.scenario.anyview.stresses": "类型擦除回退 · 渲染到测量路径 · 丢失具体派发",
        "stress.scenario.anyview.heading": "AnyView 风暴 — {0} 个类型擦除行",

        // MARK: dashboard
        "stress.scenario.dashboard.title": "仪表盘",
        "stress.scenario.dashboard.blurb": "由 N 个指标面板组成的网格（条形 + 进度）— 密集容器布局。",
        "stress.scenario.dashboard.stresses": "Panel/Card 容器测量 · 弹性宽度行共享 · 混合叶子节点",
        "stress.scenario.dashboard.heading": "仪表盘 — {0} 个指标面板",
        "stress.scenario.framedcolumns.title": "定框列",
        "stress.scenario.framedcolumns.blurb": "固定 frame 的交互行列（List、Toggle 卡片、日志 Panel）。",
        "stress.scenario.framedcolumns.stresses": "有限 .frame 测量 · frame 嵌套 stack 嵌套 frame 的级联 · 不可缓存的交互行",
        "stress.scenario.framedcolumns.heading": "定框列 — 每张卡片 {0} 行开关",

        // MARK: churn
        "stress.scenario.churn.title": "翻动更新",
        "stress.scenario.churn.blurb": "N 行内容每帧都变化（由 tick 驱动）— 无备忘命中。",
        "stress.scenario.churn.stresses": "每帧完全重渲染 · 缓存失效 · 无备忘的测量",
        "stress.scenario.churn.heading": "翻动更新 — 第 {0} 帧，每帧失效 {1} 行",
        "stress.scenario.scrollfollow.heading": "滚动跟随 — {0} 行，底部锚定（每帧追加一行）",

        // MARK: kitchensink
        "stress.scenario.kitchensink.title": "大杂烩",
        "stress.scenario.kitchensink.blurb": "分栏视图：大列表侧边栏 + 密集面板网格详情，二者同时。",
        "stress.scenario.kitchensink.stresses": "分栏视图布局 + 列表窗口化 + 容器网格同时进行",
        "stress.scenario.kitchensink.heading.items": "条目（{0}）",
        "stress.scenario.kitchensink.heading.metrics": "指标",
    ]

    static let ja: [String: String] = [
        // MARK: shell
        "stress.shell.menu.title": "TUIkit — ストレステスト",
        "stress.shell.label.scale": "スケール",
        "stress.shell.label.seed": "シード",
        "stress.shell.label.autopilot": "オートパイロット",
        "stress.shell.autopilot.on": "オン",
        "stress.shell.autopilot.off": "オフ",
        "stress.shell.autopilot.frame": "フレーム",
        "stress.shell.menu.help": "↑/↓ 選択 · Enter 開く · +/− スケール · a オートパイロット · Esc 終了",
        "stress.shell.footer.hint": "Esc 戻る · +/− スケール · a オートパイロット",

        // MARK: megalist
        "stress.scenario.megalist.title": "メガリスト",
        "stress.scenario.megalist.blurb": "N 行のウィンドウ化リスト。内容はインデックスごとにハッシュ生成（バッキング配列なし）。",
        "stress.scenario.megalist.stresses": "List/ForEach ウィンドウ化 · 行 ID 解決 · 遅延行コンテンツ · 行ごとのメモ",
        "stress.scenario.megalist.heading": "メガリスト — {0} 行",

        // MARK: table
        "stress.scenario.table.title": "ワイドテーブル",
        "stress.scenario.table.blurb": "N 行 × 8 列。セルごとの文字列は行ハッシュから合成。",
        "stress.scenario.table.stresses": "テーブル列幅の計算 · 行ウィンドウ化 · セルごとの値クロージャ",
        "stress.scenario.table.heading": "ワイドテーブル — {0} 行 × 8 列",

        // MARK: table-multiline
        "stress.scenario.table-multiline.title": "複数行テーブル",
        "stress.scenario.table-multiline.blurb": "N 行 × 4 列。詳細列が ≤3 行に折り返すため、行の高さが変化します。",
        "stress.scenario.table-multiline.stresses": "複数行セルの折り返し · 遅延行サイズ計算（ウィンドウ + 末尾のみ）· 可変高ウィンドウ化",
        "stress.scenario.table-multiline.heading": "複数行テーブル — {0} 行、詳細は ≤3 行に折り返し",

        // MARK: tables-scroll
        "stress.scenario.tables-scroll.title": "スクロールビュー内のテーブル群",
        "stress.scenario.tables-scroll.blurb": "N 個のテーブルをスクロールビューに積み重ね。各テーブルが自分の行を実体化し、独自の列幅を計算します。",
        "stress.scenario.tables-scroll.stresses": "複数の Table インスタンス · テーブルごとの列幅計算 · 結合バッファに対するスクロールビューのウィンドウ化",
        "stress.scenario.tables-scroll.heading": "スクロールビュー内のテーブル群 — {0} テーブル × {1} 行",

        // MARK: tables-vstack
        "stress.scenario.tables-vstack.title": "VStack 内のテーブル群",
        "stress.scenario.tables-vstack.blurb": "N 個のテーブルを VStack に直接積み重ね（スクロールなし）。スタックが各テーブルを計測しレイアウトします。",
        "stress.scenario.tables-vstack.stresses": "複数の Table インスタンス · テーブルごとの列幅計算 · 多数の子に対する VStack の計測/レイアウト",
        "stress.scenario.tables-vstack.heading": "VStack 内のテーブル群 — {0} テーブル × {1} 行",
        "stress.scenario.tables.tableLabel": "テーブル {0}",

        // MARK: deep
        "stress.scenario.deep.title": "深い再帰",
        "stress.scenario.deep.blurb": "1 つのビューを深さ D まで自己ネスト（各レベルで枠線/パディング付き）。",
        "stress.scenario.deep.stresses": "ViewIdentity チェーンの深さ · 計測の再帰 · コンテキスト伝播",
        "stress.scenario.deep.heading": "深い再帰 — 深さ {0}",
        "stress.scenario.deep.leaf": "葉 @ {0}：{1}",
        "stress.scenario.deep.level": "レベル {0}",

        // MARK: fanout
        "stress.scenario.fanout.title": "ワイドファンアウト",
        "stress.scenario.fanout.blurb": "N 個の直接の子を持つ非遅延 VStack（各フレームですべての子を計測）。",
        "stress.scenario.fanout.stresses": "全子要素にわたるコンテナ計測 · 空間配分 · O(n) レイアウト",
        "stress.scenario.fanout.heading": "ワイドファンアウト — 1 つの VStack 内の {0} 個の兄弟",

        // MARK: modifiers
        "stress.scenario.modifiers.title": "モディファイアチェーン",
        "stress.scenario.modifiers.blurb": "N 行、各行が長いモディファイアチェーンで包まれています。",
        "stress.scenario.modifiers.stresses": "ModifiedView/環境モディファイアの階層化 · ノードごとの計測オーバーヘッド",
        "stress.scenario.modifiers.heading": "モディファイアチェーン — {0} 個の高度に修飾された行",

        // MARK: textwall
        "stress.scenario.textwall.title": "テキストウォール",
        "stress.scenario.textwall.blurb": "合成された散文の長い折り返し段落が N 個。",
        "stress.scenario.textwall.stresses": "テキスト幅の計測 · 単語の折り返し · グリフのスループット",
        "stress.scenario.textwall.heading": "テキストウォール — {0} 個の折り返し段落",

        // MARK: anyview
        "stress.scenario.anyview.title": "AnyView ストーム",
        "stress.scenario.anyview.blurb": "N 個の異種行、それぞれが AnyView で型消去されています。",
        "stress.scenario.anyview.stresses": "型消去フォールバック · レンダリングから計測へのパス · 具体ディスパッチの喪失",
        "stress.scenario.anyview.heading": "AnyView ストーム — {0} 個の型消去された行",

        // MARK: dashboard
        "stress.scenario.dashboard.title": "ダッシュボード",
        "stress.scenario.dashboard.blurb": "N 個のメトリックパネル（バー + 進捗）のグリッド — 高密度のコンテナレイアウト。",
        "stress.scenario.dashboard.stresses": "Panel/Card コンテナの計測 · 可変幅の行共有 · 混在したリーフ",
        "stress.scenario.dashboard.heading": "ダッシュボード — {0} 個のメトリックパネル",
        "stress.scenario.framedcolumns.title": "固定フレーム列",
        "stress.scenario.framedcolumns.blurb": "固定フレームの列に並ぶ対話行（List、Toggle カード、ログ Panel）。",
        "stress.scenario.framedcolumns.stresses": "有限 .frame の計測 · フレーム→スタック→フレームのカスケード · キャッシュ不能な対話行",
        "stress.scenario.framedcolumns.heading": "固定フレーム列 — カードあたり {0} 行のトグル",

        // MARK: churn
        "stress.scenario.churn.title": "チャーン更新",
        "stress.scenario.churn.blurb": "N 行の内容が毎フレーム変化（tick 駆動）— メモのヒットなし。",
        "stress.scenario.churn.stresses": "フレームごとの完全な再レンダリング · キャッシュ無効化 · メモなしの計測",
        "stress.scenario.churn.heading": "チャーン更新 — フレーム {0}、毎フレーム {1} 行を無効化",
        "stress.scenario.scrollfollow.heading": "スクロール追従 — {0} 行、下部アンカー（毎フレーム 1 行追加）",

        // MARK: kitchensink
        "stress.scenario.kitchensink.title": "全部入り",
        "stress.scenario.kitchensink.blurb": "分割ビュー：大きなリストのサイドバー + 高密度パネルグリッドの詳細を同時に。",
        "stress.scenario.kitchensink.stresses": "分割ビューのレイアウト + リストのウィンドウ化 + コンテナグリッドを同時に",
        "stress.scenario.kitchensink.heading.items": "アイテム（{0}）",
        "stress.scenario.kitchensink.heading.metrics": "メトリクス",
    ]
}

// swiftlint:enable line_length
