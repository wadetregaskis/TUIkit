//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StressStrings+Chinese.swift
//
//  Created by LAYERED.work
//  License: MIT
//
//  Chinese. See `StressStrings+English.swift` for what is in scope and
//  what deliberately is not.

extension StressStrings {
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

        // MARK: truncate
        "stress.scenario.truncate.title": "截断表格",
        "stress.scenario.truncate.blurb": "N 行 × 6 列长句；每个单元格都被裁剪到狭窄的列宽。",
        "stress.scenario.truncate.stresses": "ANSI 感知裁剪 · 三种截断模式 · 逐单元格测量与填充",
        "stress.scenario.truncate.heading": "截断表格 — {0} 行 × 6 个被裁剪的列",

        // MARK: table-churn
        "stress.scenario.table-churn.title": "变动表格",
        "stress.scenario.table-churn.blurb": "N 行 × 6 列；每帧都替换数据，但只有约 2% 的行不同。",
        "stress.scenario.table-churn.stresses": "未变动行的重新绘制 · 单元格取值闭包 · 行级备忘的空间",
        "stress.scenario.table-churn.heading": "变动表格 — {0} 行，每帧每 {1} 行变动 1 行",

        // MARK: table-churn-wrapped
        "stress.scenario.table-churn-wrapped.title": "变动折行表格",
        "stress.scenario.table-churn-wrapped.blurb": "250 个折行行，低于估算器的上限；每帧约 2% 变动。",
        "stress.scenario.table-churn-wrapped.stresses": "多行布局 · 全部行的高度测量 · 单元格取值闭包",
        "stress.scenario.table-churn-wrapped.heading": "变动折行表格 — {0} 行，每帧每 {1} 行变动 1 行",

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

        // MARK: preferences
        "stress.scenario.preferences.title": "偏好行",
        "stress.scenario.preferences.blurb": "N 行，每行向一个收集器发布一个偏好。",
        "stress.scenario.preferences.stresses": "偏好副作用声明 · 值备忘失效 · 逐行重新测量",
        "stress.scenario.preferences.heading": "{0} 行 · 已发布 {1}",

        // MARK: customlayout
        "stress.scenario.customlayout.title": "自定义布局",
        "stress.scenario.customlayout.blurb": "N 个子视图由 AnyLayout 背后的 Layout 遵循排列。",
        "stress.scenario.customlayout.stresses": "Layout 协议调用模式 · 重复的子视图测量 · AnyLayout 类型擦除",
        "stress.scenario.customlayout.heading": "自定义 Layout 中的 {0} 个芯片",

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
        "stress.scenario.animating.title": "动画",
        "stress.scenario.animating.blurb": "N 行同时插值，全都无法缓存。",
        "stress.scenario.animating.stresses": "动画存储查询 · 不可缓存的子树 · 每帧的颜色解析",
        "stress.scenario.animating.heading": "动画 —— {0} 行，全都在动",
        "stress.scenario.translucent.title": "半透明",
        "stress.scenario.translucent.blurb": "大面积淡化面板叠在每帧都重绘的目标之上。",
        "stress.scenario.translucent.stresses": "双方都要拆成单元格 · 每个单元格查区域 · 重新发出 SGR",
        "stress.scenario.translucent.heading": "半透明 — {0} 行，每行都淡化叠在变化的色带上",
        "stress.scenario.gradients.title": "渐变",
        "stress.scenario.gradients.blurb": "一个渐变横跨长列表，逐视图渐变，四种几何形态，以及渐变填充。",
        "stress.scenario.gradients.stresses": "渐变量化 · 逐单元格几何 · 原点传递 · 移动时重新着色 · SGR 段",
        "stress.scenario.gradients.heading": "渐变 — {0} 行共用一个渐变，另有逐视图与几何条带",
        "stress.scenario.alpharamp.title": "Alpha 渐变",
        "stress.scenario.alpharamp.blurb": "四种 alpha 形状的半透明渐变，既作墨色也作填充。",
        "stress.scenario.alpharamp.stresses": "逐单元格的声明推导 · 跨合成的区域传递 · 不透明度解析",
        "stress.scenario.alpharamp.heading": "Alpha 渐变 — {0} 行半透明渐变，涵盖所有 alpha 形状",
        "stress.scenario.churn.heading": "翻动更新 — 第 {0} 帧，每帧失效 {1} 行",
        "stress.scenario.scrollfollow.title": "滚动跟随",
        "stress.scenario.scrollfollow.blurb": "底部锚定的 ScrollView，N 行可变高度；每个 tick 追加一行。",
        "stress.scenario.scrollfollow.stresses": "窗口化条带渲染 · 锚点推进 · 尾部估算 · 任意 N 均为 O(窗口)",
        "stress.scenario.scrollfollow.heading": "滚动跟随 — {0} 行，底部锚定（每帧追加一行）",

        // MARK: kitchensink
        "stress.scenario.menus.title": "菜单栏",
        "stress.scenario.menus.blurb": "带快捷键行的内联菜单，以及全部内置 ButtonStyle。",
        "stress.scenario.menus.stresses": "ButtonStyle 主体测量 · 菜单贴合宽度遍历 · 快捷键提示列 · 每行 @Environment 解析",
        "stress.scenario.menus.heading": "菜单栏 — {0} 个菜单，每个 {1} 行",
        "stress.scenario.keyrows.title": "按键行",
        "stress.scenario.keyrows.blurb": "每行各注册一个按键处理器和状态栏项的记忆化行，旁边是一个可刷新面板。",
        "stress.scenario.keyrows.stresses": "行记忆下的逐行注册 · 每帧清空的按键与状态栏注册表 · 可刷新的 Ctrl-R",
        "stress.scenario.keyrows.heading": "按键行 — {0} 行，每行一个按键处理器和一个状态栏项",
        "stress.scenario.kitchensink.title": "大杂烩",
        "stress.scenario.kitchensink.blurb": "分栏视图：大列表侧边栏 + 密集面板网格详情，二者同时。",
        "stress.scenario.kitchensink.stresses": "分栏视图布局 + 列表窗口化 + 容器网格同时进行",
        "stress.scenario.kitchensink.heading.items": "条目（{0}）",
        "stress.scenario.kitchensink.heading.metrics": "指标",
    ]
}
