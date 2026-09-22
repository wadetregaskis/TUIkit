//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StressStrings+Japanese.swift
//
//  Created by LAYERED.work
//  License: MIT
//
//  Japanese. See `StressStrings+English.swift` for what is in scope and
//  what deliberately is not.

extension StressStrings {
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

        // MARK: truncate
        "stress.scenario.truncate.title": "切り詰めテーブル",
        "stress.scenario.truncate.blurb": "N 行 × 6 列の長い文。各セルは狭い列に合わせて切り詰められます。",
        "stress.scenario.truncate.stresses": "ANSI 対応のクリップ · 3 つの切り詰めモードすべて · セルごとの計測とパディング",
        "stress.scenario.truncate.heading": "切り詰めテーブル — {0} 行 × 6 列（切り詰め）",

        // MARK: table-churn
        "stress.scenario.table-churn.title": "更新テーブル",
        "stress.scenario.table-churn.blurb": "N 行 × 6 列。データは毎フレーム差し替えられますが、異なる行は約 2% です。",
        "stress.scenario.table-churn.stresses": "変化していない行の再描画 · セル値クロージャ · 行メモの余地",
        "stress.scenario.table-churn.heading": "更新テーブル — {0} 行、{1} 行に 1 行がフレームごとに変化",

        // MARK: table-churn-wrapped
        "stress.scenario.table-churn-wrapped.title": "更新折り返しテーブル",
        "stress.scenario.table-churn-wrapped.blurb": "推定器の上限を下回る 250 行の折り返し行。約 2% がフレームごとに変化します。",
        "stress.scenario.table-churn-wrapped.stresses": "複数行のレイアウト · 全行の高さ計測 · セル値クロージャ",
        "stress.scenario.table-churn-wrapped.heading": "更新折り返しテーブル — {0} 行、{1} 行に 1 行がフレームごとに変化",

        // MARK: table-tail
        "stress.scenario.table-tail.title": "追従テーブル",
        "stress.scenario.table-tail.blurb": "増え続けるシーケンスへのウィンドウ。各行は内容を保ったままフレームごとに 1 行上がります。",
        "stress.scenario.table-tail.stresses": "位置をまたぐ行のアイデンティティ · 移動した行の再描画 · セル値クロージャ",
        "stress.scenario.table-tail.heading": "追従テーブル — 増え続けるシーケンスへの {0} 行のウィンドウ",

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

        // MARK: preferences
        "stress.scenario.preferences.title": "プリファレンス行",
        "stress.scenario.preferences.blurb": "N 行、各行が 1 つのコレクターにプリファレンスを発行。",
        "stress.scenario.preferences.stresses": "プリファレンス副作用の宣言 · 値メモの無効化 · 行ごとの再測定",
        "stress.scenario.preferences.heading": "{0} 行 · {1} 件発行",

        // MARK: customlayout
        "stress.scenario.customlayout.title": "カスタムレイアウト",
        "stress.scenario.customlayout.blurb": "AnyLayout の背後にある Layout 準拠で配置された N 個のサブビュー。",
        "stress.scenario.customlayout.stresses": "Layout プロトコルの呼び出しパターン · サブビューの繰り返し測定 · AnyLayout の型消去",
        "stress.scenario.customlayout.heading": "カスタム Layout 内の {0} 個のチップ",

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
        "stress.scenario.animating.title": "アニメーション",
        "stress.scenario.animating.blurb": "N 行が同時に補間され、どれもキャッシュできません。",
        "stress.scenario.animating.stresses": "アニメーションストアの参照 · キャッシュできないサブツリー · フレームごとの色解決",
        "stress.scenario.animating.heading": "アニメーション —— {0} 行、すべて動作中",
        "stress.scenario.translucent.title": "半透明",
        "stress.scenario.translucent.blurb": "毎フレーム描き直される背景の上に置かれた大きな淡いパネル。",
        "stress.scenario.translucent.stresses": "両側のセル分解 · セルごとの領域探索 · SGR の再出力",
        "stress.scenario.translucent.heading": "半透明 — {0} 行、変化する帯の上でそれぞれ淡く",
        "stress.scenario.gradients.title": "グラデーション",
        "stress.scenario.gradients.blurb": "長いリスト全体にかかる 1 つのランプ、ビューごとのランプ、4 つのジオメトリ、グラデーション塗り。",
        "stress.scenario.gradients.stresses": "ランプの量子化 · セルごとのジオメトリ · 原点の伝播 · 移動時の再描画 · SGR ラン",
        "stress.scenario.gradients.heading": "グラデーション — {0} 行が 1 つのランプを共有、ビュー別とジオメトリ別の帯も",
        "stress.scenario.alpharamp.title": "アルファグラデーション",
        "stress.scenario.alpharamp.blurb": "4 種類のアルファ形状すべてで、インクと塗りとして描く半透明グラデーション。",
        "stress.scenario.alpharamp.stresses": "セル単位のクレーム導出 · 合成をまたぐ領域の運搬 · 不透明度の解決",
        "stress.scenario.alpharamp.heading": "アルファグラデーション — 半透明グラデーション {0} 行、すべてのアルファ形状",
        "stress.scenario.churn.heading": "チャーン更新 — フレーム {0}、毎フレーム {1} 行を無効化",
        "stress.scenario.scrollfollow.title": "スクロール追従",
        "stress.scenario.scrollfollow.blurb": "下部アンカーの ScrollView、可変高さの N 行。tick ごとに 1 行追加。",
        "stress.scenario.scrollfollow.stresses": "ウィンドウ化バンド描画 · アンカー前進 · 末尾推定 · どの N でも O(ウィンドウ)",
        "stress.scenario.scrollfollow.heading": "スクロール追従 — {0} 行、下部アンカー（毎フレーム 1 行追加）",

        // MARK: kitchensink
        "stress.scenario.menus.title": "メニューバー",
        "stress.scenario.menus.blurb": "ショートカット付きの行から成るインラインメニューと、組み込みの ButtonStyle 一式。",
        "stress.scenario.menus.stresses": "ButtonStyle ボディの計測 · メニューの最小幅パス · ショートカット表示列 · 行ごとの @Environment 解決",
        "stress.scenario.menus.heading": "メニューバー — {0} 個のメニュー × {1} 行",
        "stress.scenario.keyrows.title": "キー行",
        "stress.scenario.keyrows.blurb": "それぞれキーハンドラーとステータスバー項目を登録するメモ化された行と、その横のリフレッシュ可能なパネル。",
        "stress.scenario.keyrows.stresses": "行メモ下での行ごとの登録 · フレームごとに空になるキーとステータスバーのレジストリ · リフレッシュ可能な Ctrl-R",
        "stress.scenario.keyrows.heading": "キー行 — {0} 行、各行にキーハンドラーとステータスバー項目",
        "stress.scenario.kitchensink.title": "全部入り",
        "stress.scenario.kitchensink.blurb": "分割ビュー：大きなリストのサイドバー + 高密度パネルグリッドの詳細を同時に。",
        "stress.scenario.kitchensink.stresses": "分割ビューのレイアウト + リストのウィンドウ化 + コンテナグリッドを同時に",
        "stress.scenario.kitchensink.heading.items": "アイテム（{0}）",
        "stress.scenario.kitchensink.heading.metrics": "メトリクス",
    ]
}
