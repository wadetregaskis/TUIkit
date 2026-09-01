//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StressStrings+German.swift
//
//  Created by LAYERED.work
//  License: MIT
//
//  German. See `StressStrings+English.swift` for what is in scope and
//  what deliberately is not.

// swiftlint:disable line_length

extension StressStrings {
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
        "stress.scenario.animating.title": "Animation",
        "stress.scenario.animating.blurb": "N Zeilen interpolieren gleichzeitig, keine davon zwischenspeicherbar.",
        "stress.scenario.animating.stresses": "Zugriffe auf den Animationsspeicher · nicht cachebare Teilbäume · Farbauflösung pro Frame",
        "stress.scenario.animating.heading": "Animation — {0} Zeilen, alle in Bewegung",
        "stress.scenario.translucent.title": "Durchscheinend",
        "stress.scenario.translucent.blurb": "Eine große abgeschwächte Fläche über einem Ziel, das sich jedes Bild neu zeichnet.",
        "stress.scenario.translucent.stresses": "Zellzerlegung beider Seiten · Regionssuche pro Zelle · SGR-Neuausgabe",
        "stress.scenario.translucent.heading": "Durchscheinend — {0} Zeilen, je über einem wechselnden Band",
        "stress.scenario.churn.heading": "Churn-Aktualisierung — Frame {0}, {1} Zeilen pro Frame invalidiert",
        "stress.scenario.scrollfollow.title": "Scroll-Verfolgung",
        "stress.scenario.scrollfollow.blurb": "Unten verankerte ScrollView über N Zeilen variabler Höhe; pro Tick kommt eine Zeile hinzu.",
        "stress.scenario.scrollfollow.stresses": "gefensterte Band-Darstellung · Anker-Fortschreibung · End-Schätzung · O(Fenster) bei jedem N",
        "stress.scenario.scrollfollow.heading": "Scroll-Verfolgung — {0} Zeilen, unten verankert (pro Frame kommt eine Zeile hinzu)",

        // MARK: kitchensink
        "stress.scenario.kitchensink.title": "Komplettpaket",
        "stress.scenario.kitchensink.blurb": "Geteilte Ansicht: große Listen-Seitenleiste + dichtes Panel-Raster-Detail, zusammen.",
        "stress.scenario.kitchensink.stresses": "Geteilte-Ansicht-Layout + Listenfensterung + Container-Raster gleichzeitig",
        "stress.scenario.kitchensink.heading.items": "Einträge ({0})",
        "stress.scenario.kitchensink.heading.metrics": "Metriken",
    ]
}

// swiftlint:enable line_length
