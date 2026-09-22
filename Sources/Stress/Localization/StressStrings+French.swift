//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StressStrings+French.swift
//
//  Created by LAYERED.work
//  License: MIT
//
//  French. See `StressStrings+English.swift` for what is in scope and
//  what deliberately is not.

// swiftlint:disable line_length

extension StressStrings {
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

        // MARK: truncate
        "stress.scenario.truncate.title": "Tableau tronqué",
        "stress.scenario.truncate.blurb": "N lignes × 6 colonnes de longues phrases ; chaque cellule est rognée à une colonne étroite.",
        "stress.scenario.truncate.stresses": "Rognage compatible ANSI · les trois modes de troncature · mesure/remplissage par cellule",
        "stress.scenario.truncate.heading": "Tableau tronqué — {0} lignes × 6 colonnes rognées",

        // MARK: table-churn
        "stress.scenario.table-churn.title": "Tableau en mouvement",
        "stress.scenario.table-churn.blurb": "N lignes × 6 colonnes ; les données sont remplacées à chaque image mais ~2% des lignes diffèrent.",
        "stress.scenario.table-churn.stresses": "reconstruction de lignes inchangées · closures de valeur de cellule · marge pour un mémo de ligne",
        "stress.scenario.table-churn.heading": "Tableau en mouvement — {0} lignes, une sur {1} change par image",

        // MARK: table-churn-wrapped
        "stress.scenario.table-churn-wrapped.title": "Tableau enroulé en mouvement",
        "stress.scenario.table-churn-wrapped.blurb": "250 lignes enroulées sous la limite de l'estimateur ; ~2% changent par image.",
        "stress.scenario.table-churn-wrapped.stresses": "mise en page multiligne · mesure de hauteur de toutes les lignes · closures de valeur de cellule",
        "stress.scenario.table-churn-wrapped.heading": "Tableau enroulé en mouvement — {0} lignes, une sur {1} change par image",

        // MARK: table-tail
        "stress.scenario.table-tail.title": "Tableau suiveur",
        "stress.scenario.table-tail.blurb": "Une fenêtre sur une séquence croissante : chaque ligne garde son contenu et remonte d'une ligne par image.",
        "stress.scenario.table-tail.stresses": "identité de ligne à travers les positions · reconstruction des lignes déplacées · closures de valeur de cellule",
        "stress.scenario.table-tail.heading": "Tableau suiveur — fenêtre de {0} lignes sur une séquence croissante",

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

        // MARK: preferences
        "stress.scenario.preferences.title": "Lignes à préférences",
        "stress.scenario.preferences.blurb": "N lignes publiant chacune une préférence vers un collecteur.",
        "stress.scenario.preferences.stresses": "déclaration d'effet de bord de préférence · mise en échec du mémo de valeur · re-mesure par ligne",
        "stress.scenario.preferences.heading": "{0} lignes · {1} publiées",

        // MARK: customlayout
        "stress.scenario.customlayout.title": "Layout personnalisé",
        "stress.scenario.customlayout.blurb": "N sous-vues disposées par une conformité Layout derrière AnyLayout.",
        "stress.scenario.customlayout.stresses": "schéma d'appel du protocole Layout · mesure répétée des sous-vues · effacement de type AnyLayout",
        "stress.scenario.customlayout.heading": "{0} puces dans un Layout personnalisé",

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
        "stress.scenario.animating.title": "Animation",
        "stress.scenario.animating.blurb": "N lignes interpolées en même temps, aucune ne peut être mise en cache.",
        "stress.scenario.animating.stresses": "accès au magasin d’animation · sous-arbres non cachables · résolution des couleurs par image",
        "stress.scenario.animating.heading": "Animation — {0} lignes, toutes en mouvement",
        "stress.scenario.translucent.title": "Translucide",
        "stress.scenario.translucent.blurb": "Un grand panneau estompé sur une destination redessinée à chaque image.",
        "stress.scenario.translucent.stresses": "décomposition en cellules des deux côtés · recherche de région par cellule · réémission SGR",
        "stress.scenario.translucent.heading": "Translucide — {0} lignes, chacune estompée sur une bande changeante",
        "stress.scenario.gradients.title": "Dégradés",
        "stress.scenario.gradients.blurb": "Un dégradé sur une longue liste, des dégradés par vue, quatre géométries, des remplissages dégradés.",
        "stress.scenario.gradients.stresses": "quantisation du dégradé · géométrie par cellule · propagation de l'origine · recoloration au déplacement · séquences SGR",
        "stress.scenario.gradients.heading": "Dégradés — {0} lignes sous un même dégradé, plus des bandes par vue et par géométrie",
        "stress.scenario.alpharamp.title": "Dégradés alpha",
        "stress.scenario.alpharamp.blurb": "Dégradés translucides dans les quatre formes d'alpha, en encre et en remplissage.",
        "stress.scenario.alpharamp.stresses": "dérivation des revendications par cellule · transport des régions à la composition · résolution de l'opacité",
        "stress.scenario.alpharamp.heading": "Dégradés alpha — {0} lignes de dégradé translucide dans toutes les formes d'alpha",
        "stress.scenario.churn.heading": "Mise à jour continue — image {0}, {1} lignes invalidées/image",
        "stress.scenario.scrollfollow.title": "Suivi du défilement",
        "stress.scenario.scrollfollow.blurb": "ScrollView ancrée en bas sur N lignes de hauteur variable ; une ligne ajoutée à chaque tick.",
        "stress.scenario.scrollfollow.stresses": "rendu de bande fenêtré · avance de l'ancre · estimation de fin · O(fenêtre) pour tout N",
        "stress.scenario.scrollfollow.heading": "Suivi du défilement — {0} lignes, ancré en bas (une ligne ajoutée par image)",

        // MARK: kitchensink
        "stress.scenario.menus.title": "Barre de menus",
        "stress.scenario.menus.blurb": "Menus intégrés de lignes à raccourcis, à côté de tous les styles de Button intégrés.",
        "stress.scenario.menus.stresses": "mesure du corps du ButtonStyle · passe de largeur au plus juste du menu · colonne des raccourcis · résolution d'@Environment par ligne",
        "stress.scenario.menus.heading": "Barre de menus — {0} menus de {1} lignes",
        "stress.scenario.keyrows.title": "Lignes à touches",
        "stress.scenario.keyrows.blurb": "Lignes mémoïsées qui enregistrent chacune un gestionnaire de touche et des éléments de barre d'état, à côté d'un panneau actualisable.",
        "stress.scenario.keyrows.stresses": "enregistrements par ligne sous le mémo de ligne · registres de touches et de barre d'état vidés à chaque image · Ctrl-R actualisable",
        "stress.scenario.keyrows.heading": "Lignes à touches — {0} lignes, chacune avec un gestionnaire de touche et un élément de barre d'état",
        "stress.scenario.kitchensink.title": "Tout-en-un",
        "stress.scenario.kitchensink.blurb": "Vue divisée : grande liste en barre latérale + détail en grille de panneaux dense, ensemble.",
        "stress.scenario.kitchensink.stresses": "disposition en vue divisée + fenêtrage de liste + grille de conteneurs simultanément",
        "stress.scenario.kitchensink.heading.items": "Éléments ({0})",
        "stress.scenario.kitchensink.heading.metrics": "Métriques",
    ]
}

// swiftlint:enable line_length
