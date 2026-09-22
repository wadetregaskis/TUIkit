//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StressStrings+Spanish.swift
//
//  Created by LAYERED.work
//  License: MIT
//
//  Spanish. See `StressStrings+English.swift` for what is in scope and
//  what deliberately is not.

// swiftlint:disable line_length

extension StressStrings {
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

        // MARK: truncate
        "stress.scenario.truncate.title": "Tabla truncada",
        "stress.scenario.truncate.blurb": "N filas × 6 columnas de frases largas; cada celda se recorta a una columna estrecha.",
        "stress.scenario.truncate.stresses": "Recorte compatible con ANSI · los tres modos de truncamiento · medida/relleno por celda",
        "stress.scenario.truncate.heading": "Tabla truncada — {0} filas × 6 columnas recortadas",

        // MARK: table-churn
        "stress.scenario.table-churn.title": "Tabla cambiante",
        "stress.scenario.table-churn.blurb": "N filas × 6 columnas; los datos se reemplazan cada fotograma pero solo ~2% de las filas difieren.",
        "stress.scenario.table-churn.stresses": "redibujado de filas sin cambios · closures de valor de celda · margen para un memo por fila",
        "stress.scenario.table-churn.heading": "Tabla cambiante — {0} filas, una de cada {1} cambia por fotograma",

        // MARK: table-churn-wrapped
        "stress.scenario.table-churn-wrapped.title": "Tabla ajustada cambiante",
        "stress.scenario.table-churn-wrapped.blurb": "250 filas ajustadas por debajo del límite del estimador; ~2% cambian por fotograma.",
        "stress.scenario.table-churn-wrapped.stresses": "maquetación de filas multilínea · medición de altura de todas las filas · closures de valor de celda",
        "stress.scenario.table-churn-wrapped.heading": "Tabla ajustada cambiante — {0} filas, una de cada {1} cambia por fotograma",

        // MARK: table-tail
        "stress.scenario.table-tail.title": "Tabla de seguimiento",
        "stress.scenario.table-tail.blurb": "Una ventana sobre una secuencia creciente: cada fila conserva su contenido y sube una línea por fotograma.",
        "stress.scenario.table-tail.stresses": "identidad de fila entre posiciones · redibujado de filas desplazadas · closures de valor de celda",
        "stress.scenario.table-tail.heading": "Tabla de seguimiento — ventana de {0} filas sobre una secuencia creciente",

        // MARK: table-api
        "stress.scenario.table-api.title": "Matriz de la API Table",
        "stress.scenario.table-api.blurb": "Una Table construida de todas las formas que permite la API — elige un punto con --variant.",
        "stress.scenario.table-api.stresses": "tipos de valor de columna · modos de ancho · truncamiento · selección · ordenación · patrones de actualización",
        "stress.scenario.table-api.heading": "API Table — {0}, {1} filas",

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

        // MARK: preferences
        "stress.scenario.preferences.title": "Filas con preferencias",
        "stress.scenario.preferences.blurb": "N filas, cada una publica una preferencia a un recolector.",
        "stress.scenario.preferences.stresses": "declaración del efecto secundario de preferencia · anulación del memo de valores · re-medición por fila",
        "stress.scenario.preferences.heading": "{0} filas · {1} publicadas",

        // MARK: customlayout
        "stress.scenario.customlayout.title": "Layout personalizado",
        "stress.scenario.customlayout.blurb": "N subvistas dispuestas por una conformidad Layout tras AnyLayout.",
        "stress.scenario.customlayout.stresses": "patrón de llamadas del protocolo Layout · medición repetida de subvistas · borrado de tipo AnyLayout",
        "stress.scenario.customlayout.heading": "{0} fichas en un Layout personalizado",

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
        "stress.scenario.animating.title": "Animación",
        "stress.scenario.animating.blurb": "N filas interpoladas a la vez, ninguna almacenable en caché.",
        "stress.scenario.animating.stresses": "consultas al almacén de animación · subárboles no cacheables · resolución de color por fotograma",
        "stress.scenario.animating.heading": "Animación — {0} filas, todas en movimiento",
        "stress.scenario.translucent.title": "Translúcido",
        "stress.scenario.translucent.blurb": "Un panel atenuado grande sobre un destino que se redibuja en cada fotograma.",
        "stress.scenario.translucent.stresses": "descomposición en celdas de ambos lados · búsqueda de región por celda · reemisión SGR",
        "stress.scenario.translucent.heading": "Translúcido — {0} filas, cada una atenuada sobre una banda cambiante",
        "stress.scenario.gradients.title": "Degradados",
        "stress.scenario.gradients.blurb": "Un degradado sobre una lista larga, degradados por vista, cuatro geometrías, rellenos degradados.",
        "stress.scenario.gradients.stresses": "cuantización del degradado · geometría por celda · propagación del origen · recoloreado al moverse · secuencias SGR",
        "stress.scenario.gradients.heading": "Degradados — {0} filas bajo un mismo degradado, más bandas por vista y por geometría",
        "stress.scenario.alpharamp.title": "Degradados con alfa",
        "stress.scenario.alpharamp.blurb": "Degradados translúcidos en las cuatro formas de alfa, como tinta y como relleno.",
        "stress.scenario.alpharamp.stresses": "derivación de reclamaciones por celda · transporte de regiones en la composición · resolución de opacidad",
        "stress.scenario.alpharamp.heading": "Degradados con alfa — {0} filas de degradado translúcido en todas las formas de alfa",
        "stress.scenario.churn.heading": "Actualización continua — fotograma {0}, {1} filas invalidadas/fotograma",
        "stress.scenario.scrollfollow.title": "Seguimiento de desplazamiento",
        "stress.scenario.scrollfollow.blurb": "ScrollView anclado abajo sobre N filas de altura variable; se añade una fila por tick.",
        "stress.scenario.scrollfollow.stresses": "renderizado de banda en ventana · avance del ancla · estimación de cola · O(ventana) para cualquier N",
        "stress.scenario.scrollfollow.heading": "Seguimiento de desplazamiento — {0} filas, anclado abajo (se añade una fila por fotograma)",

        // MARK: kitchensink
        "stress.scenario.menus.title": "Barra de menús",
        "stress.scenario.menus.blurb": "Menús en línea de filas con atajos, junto a todos los ButtonStyle integrados.",
        "stress.scenario.menus.stresses": "medición del cuerpo del ButtonStyle · pasada de ancho ajustado del menú · columna de atajos · resolución de @Environment por fila",
        "stress.scenario.menus.heading": "Barra de menús — {0} menús de {1} filas",
        "stress.scenario.keyrows.title": "Filas con teclas",
        "stress.scenario.keyrows.blurb": "Filas memoizadas que registran cada una un manejador de teclas y elementos de la barra de estado, junto a un panel actualizable.",
        "stress.scenario.keyrows.stresses": "registros por fila bajo el memo de fila · registros de teclas y barra de estado vaciados en cada fotograma · Ctrl-R actualizable",
        "stress.scenario.keyrows.heading": "Filas con teclas — {0} filas, cada una con un manejador de teclas y un elemento de la barra de estado",
        "stress.scenario.kitchensink.title": "Todo en uno",
        "stress.scenario.kitchensink.blurb": "Vista dividida: lista grande en la barra lateral + detalle de cuadrícula de paneles densa, juntos.",
        "stress.scenario.kitchensink.stresses": "disposición de vista dividida + ventaneo de lista + cuadrícula de contenedores simultáneamente",
        "stress.scenario.kitchensink.heading.items": "Elementos ({0})",
        "stress.scenario.kitchensink.heading.metrics": "Métricas",
    ]
}

// swiftlint:enable line_length
