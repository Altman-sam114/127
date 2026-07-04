# Codex v3.0-v3.8 任务提示词：从 WWIIHexV0 迁移为 AI Agent 驱动的拿破仑战争战棋

> 本文是交给后续实现 Agent 的总提示词。它不是本轮代码实现记录，而是后续多版本迁移的路线、边界、并发分工和验收标准。执行前必须先读 `AGENTS.md`、`update_log.md`、`md/flow/flow.md`、`md/flow/flowchart.md`、`md/test/test.md` 和本文件。

---

## 0. 当前项目判断

你接手的是 `WWIIHexV0`，当前代码不是早期原型，而是一个已经有多条方向沉淀的 Swift + SwiftUI + SpriteKit 战棋工程。现有主链路包括：

```text
MapEditor / JSON
  -> DataLoader
  -> GameState
  -> HexTile.controller + Division.coord
  -> Region 聚合
  -> EconomyState 收入 / 生产 / 补员
  -> Theater / FrontLine / WarDeployment 派生层
  -> General / Marshal / Ruler / Diplomacy 草案
  -> TheaterDirective / ZoneDirective
  -> WarCommandExecutor
  -> RuleEngine
  -> UI / SpriteKit / 日志 / WarDirectiveRecord
```

当前代码和文档中已经确认这些事实：

- `HexTile.controller` 和 `Division.coord` 是战术层权威。
- `RegionNode.controller` 是从 hex 聚合出来的战略快照。
- `regionToTheater` 是初始/基础战区，不是运行时推进权威。
- `hexToTheater` 是运行时动态战区权威。
- `hexToFrontZone` 是部署层动态归属权威。
- 玩家、AI、聊天命令和 MockAI 都必须落到 `Command` / `ZoneDirective`，再经 `WarCommandExecutor`、`CommandValidator`、`RuleEngine` 执行。
- 当前默认 AI 文档口径是 `MarshalAgent -> TheaterDirective JSON -> TheaterDirectiveDecoder -> TheaterDirectiveCompiler -> ZoneDirective -> WarCommandExecutor -> RuleEngine`。
- Legacy Agent D 管线保留作回归参考，默认战争 AI 主路径不得退回旧管线。
- 当前 `Faction` 仍只有 `germany/allies`，且 `Faction.opponent`、`GamePhase.germanAI/alliedPlayer`、`CommandValidator`、`SupplyRules`、`FrontLineManager`、`WarCommandExecutor` 等处仍有二元阵营假设。
- 当前单位源码类型叫 `Division`，兵种仍是 `tank`、`motorizedInfantry`、`infantry`、`artillery`。
- 当前经济仍是 `manpower / industry / supplies`，生产项仍有 `Panzer Division`、`Motorized Division` 等二战语义。
- 当前默认数据和 UI 仍有阿登、Germany、Allies、Bastogne、Guderian、Montgomery、Panzer、Division 等二战语义。
- 当前工作树可能混有 v0.4、v0.5、v0.7、v0.8、v0.9、v1.0、v1.1 等未提交改动。任何实现前必须做分支和文件冲突审查，不能回滚他人改动。

迁移目标不是“换一套文字和颜色”，而是把这个工程逐步迁移为一个可发布的 AI Agent 驱动拿破仑战争战棋。

---

## 1. 最终产品目标

暂定产品名：`拿破仑战棋 Agent`。英文工作名可用 `Napoleon Command Agent` 或 `Napoleonic Command Hex`。

最终首发体验应达到以下效果：

1. 打开应用后直接进入可玩的拿破仑战争战役，不做营销落地页。
2. 第一批可发布战役建议选择范围可控、辨识度高、Agent 行为明显的战役：
   - 首选：`滑铁卢 1815`。阵营清晰，联军协同、普军迟到、法军机动、英荷防线、村庄据点、炮兵与骑兵冲锋都能体现。
   - 备选：`奥斯特里茨 1805`。适合表现拿破仑诱敌、中央突破、联军多国协同、右翼弱点和高地争夺。
   - 不要第一版就做完整欧洲大战略、半岛战争全图或 1805-1815 全战役沙盒。
3. 玩家可选择一个阵营或国家；其他阵营由 AI Agent 驱动。
4. 地图以 hex 为战术权威，以村庄/高地/道路节点/战役区块为 region 聚合层，以军团/翼/军区为 AI 调度层。
5. 玩家既能微操具体部队，也能通过元帅/军团长面板下达宏观命令。
6. AI 不直接改 `GameState`。皇帝、君主、总司令、元帅、军团长、参谋等 Agent 只能输出结构化 directive，经 decoder/validator/compiler 后落到规则系统。
7. UI 视觉要摆脱当前调试原型感：应有 19 世纪军事地图质感，包含羊皮纸/战役地图、军旗、军团色、红蓝铅笔进军箭头、村庄/桥梁/高地/林地/炮兵阵地图标、军团长头像、战报和命令回放。
8. UI 不能堆说明卡片。第一屏核心是地图、部队、命令、回合和战报。
9. 发布前必须没有主要二战文案残留：Germany、Allies、Ardennes、Bastogne、Panzer、tank、motorized、WWII、Division 等不应出现在主游戏 UI、默认数据、日志和玩家可见面板中。源码兼容名可分阶段保留，但必须在文档中声明。
10. 发布前必须有一个可演示闭环：开局、选择阵营、查看军团和指挥官、移动、炮击、骑兵冲锋、步兵进攻/方阵、防守村庄、占领目标、AI 回合、战报复盘、胜负判断。

首发战役建议规格：

```text
scenarioId: waterloo_1815
displayName: 滑铁卢 1815
地图范围：滑铁卢战场核心区，可抽象包含 Mont-Saint-Jean、La Haye Sainte、Hougoumont、Papelotte、Plancenoit、Wavre/普军来援方向
主要阵营：France、Anglo-Allied、Prussia
首版规模：约 80-160 个 hex，20-45 个 region，4-8 个 army wing / corps zone
首版回合：12-24 回合，代表战役日内关键时段
胜利条件：法军突破联军中心/占领关键据点/阻止普军会合；联军守住关键线并消耗法军，或普军抵达后夺取法军侧后方
```

---

## 2. 迁移总原则

### 2.1 保留的工程骨架

必须保留并迁移这些成熟资产：

- Hex 坐标、移动、攻击、占领、视野、补给落点的战术权威。
- Region 作为战略聚合层，不替代 hex。
- Dynamic Theater、FrontLine、WarDeployment 的派生关系。
- `Command` / `ZoneDirective` / `WarCommandExecutor` / `RuleEngine` 统一执行管线。
- `WarDirectiveRecord`、`AgentDecisionRecord`、`RulerDecisionRecord` 等审计/复盘记录。
- MapEditor 的稀疏 hex、region、theater、unit 编辑与导出能力。
- iOS 主游戏、macOS 主游戏和 macOS 地图编辑器三个方向。
- 当前轻量检查规范和禁止重测试规则。

### 2.2 必须替换或抽象的二战语义

必须逐步替换这些题材绑定点：

- `Faction.germany/allies`：迁移为拿战国家/阵营体系，至少支持 `france`、`angloAllied`、`prussia`、`austria`、`russia`、`spain`、`neutral`。首发滑铁卢可先只启用 France / Anglo-Allied / Prussia / neutral。
- `Faction.opponent`：多方敌我必须来自 `DiplomacyState` / `CoalitionState` / `PowerRelation`，不能继续用二元 opponent。
- `GamePhase.germanAI/alliedPlayer`：迁移为通用 phase，例如 playerCommand / aiCommand / resolution，或至少抽出显示与控制逻辑，避免 Germany/Allies 绑定。
- `Division` 显示语义：源码可短期保留兼容名，但 UI 应显示为军团、师、旅、部队或 formation。拿破仑时代也有 division，但不得沿用二战“装甲师/摩步师”语义。
- `ComponentType.tank/motorizedInfantry/infantry/artillery`：迁移为 lineInfantry、lightInfantry、cavalry、artillery、guard、engineer/sapper、supplyTrain 等。
- `EconomyResources.manpower/industry/supplies`：战役首版可显示为 recruits / treasury / supplies / ammunition / forage / horses，短期源码字段可兼容但 UI 不显示 Industry/Panzer 等现代语义。
- `ProductionKind.panzerDivision/motorizedDivision`：迁移为 line infantry reserve、cavalry reserve、artillery battery、supply wagon、guard detachment 等；滑铁卢短战役可弱化生产，改为援军/预备队到达。
- `Theater` 显示为 Army / Wing / Corps Sector，不显示二战战区。
- `FrontZone` 显示为军团防区/翼/sector。
- `RulerAgent` 显示为皇帝/君主/联军政治层，只能位于总司令上游。
- `MarshalAgent` 显示为总司令/元帅/参谋长，负责战役意图。
- `ZoneCommanderAgent` 显示为军团长/翼指挥官，负责把战役意图转成战术行动。
- 阿登 JSON：迁移为拿战剧本 JSON。
- 默认 UI 文案：中文优先，必要时保留英文开发字段和内部 id。

### 2.3 拿破仑战争核心玩法方向

首发版本要体现拿战特色，但不能一次性把模拟做得过重。优先级如下：

1. **线列步兵与士气**：战斗不只看 strength，至少要有 morale / cohesion 的轻量模型或战斗修正。没有字段也可先通过 supplyState、retreatMode 和日志表现。
2. **炮兵**：有射程、火力准备、Grand Battery 这类战术；炮兵不能像装甲一样推进突破。
3. **骑兵**：机动高、适合追击和冲锋，但对方阵或村庄/森林/高地有明显限制。
4. **方阵/队形**：最小实现可先用 stance / retreatMode / tactic 表达 line / column / square / skirmish，不要第一轮就做复杂 formation state machine。
5. **村庄与据点**：Hougoumont、La Haye Sainte、Plancenoit 这类目标应有防御价值和战役意义。
6. **命令摩擦**：AI 指令可以被拒绝、延迟、降级或只部分执行；必须记录原因。
7. **联军协同**：Prussia 与 Anglo-Allied 可以是不同国家/阵营成员，外交/联军状态可先影响 AI 目标和增援到场，不必首版做完整外交系统。
8. **补给与疲劳**：短战役中表现为 ammunition / fatigue / supply warning，而不是现代工业生产。

### 2.4 不能做的事

- 不要一次性大规模重命名所有类型再凭感觉修编译。先建立兼容层和迁移合同，再分版本替换。
- 不要让任何 Agent 直接修改 `HexTile.controller`、`Division.coord`、`regionToTheater`、`hexToTheater`、`hexToFrontZone` 或经济账本。
- 不要绕过 `WarCommandExecutor`、`CommandValidator`、`RuleEngine`。
- 不要恢复旧 Cabinet / Minister / StrategicDirective 污染。拿战可以有皇帝、君主、元帅、军团长、参谋，但必须是新 schema 和新管线。
- 不要删除 Legacy Agent D；只隔离和保留回归参考。
- 不要把 region 当成战术权威；进军、攻击、占领仍必须落到 hex。
- 不要第一版就做完整欧洲地图、完整 1805-1815 大战略、海军、殖民地、复杂外交、完整内政。
- 不要使用受版权保护的游戏素材、电影剧照、商业将领头像或未经授权地图。可使用自制、生成、公共领域或明确授权素材。
- 不要硬编码 API key、模型路径或云端 LLM 请求。真实 LLM 接入必须单独版本，有 deterministic fallback。
- 未获人工授权，不跑 Xcode / XCTest / 模拟器 / macOS app 启动 / Probe / Smoke / Stage Regression / Full / 性能测试。

---

## 3. 多 Agent 并发工作流

主 Agent 负责总体架构、接口合同、冲突整合和最终验收。子 Agent 只能在明确边界内并发，不得同时改同一 public API 或同一文件。

### 3.1 并发前主 Agent 必做

1. 读完必读文档和本文件。
2. 执行轻量只读审计：

```sh
git branch --show-current
git status --short
rg -n "Germany|Allies|germany|allies|Ardennes|ardennes|Bastogne|Panzer|tank|motorized|Division|Guderian|Montgomery|Faction\\.opponent|germanAI|alliedPlayer" WWIIHexV0 MapEditor README.md md
rg -n "enum Faction|struct Division|enum ComponentType|EconomyResources|ProductionKind|DiplomacyState|ZoneDirective|WarCommandExecutor|RuleEngine" WWIIHexV0
```

3. 写出本轮实际版本目标和非目标。
4. 定义本轮公共接口合同。没有接口合同前，不要让多个子 Agent 同时改 `Core/`、`Commands/`、`Rules/`。
5. 明确 `WWIIHexV0.xcodeproj/project.pbxproj` 只能由主 Agent 或唯一指定的 Project Agent 修改。
6. 如果当前工作树已有不属于本轮的 dirty 文件，先记录并绕开，不要回滚。

### 3.2 推荐子 Agent 分工

每轮最多并发 3-5 个子 Agent。优先减少冲突，不追求数量。

#### Audit / Docs Agent

范围：

- `README.md`
- `update_log.md`
- `md/flow/`
- `md/test/test.md`
- `md/prompt/v3.0-拿战迁移/`

职责：

- 扫描二战硬编码、二元阵营、旧 phase、旧资源、旧单位。
- 维护迁移词汇表、版本审计表、风险清单。
- 更新 flow / flowchart，使它们描述当前真实代码。
- 记录轻量检查和未跑重测试原因。

禁止：

- 不改 Swift 业务逻辑。
- 不把未验证运行时行为写成已验证。

#### Data Agent

范围：

- `WWIIHexV0/Data/*.json`
- `WWIIHexV0/Data/ScenarioDefinition.swift`
- `WWIIHexV0/Data/RegionDataSet.swift`
- `WWIIHexV0/Data/DataLoader.swift`

职责：

- 迁移剧本、地图、地形、兵种、指挥官、国家/阵营数据。
- 建立 `waterloo_1815_scenario.json`、`waterloo_1815_regions.json`、`napoleonic_unit_templates.json`、`napoleonic_generals.json`、`napoleonic_terrain_rules.json`。
- 保证 JSON key 稳定，id 使用 ASCII，例如 `power_france`、`region_hougoumont`、`commander_napoleon`。
- 中文只放在 `displayName`、`localizedName`、`biography` 等展示字段。

禁止：

- 不改 `RuleEngine`。
- 不改 UI。
- 不改 project 文件，除非主 Agent 明确指定。

#### Rules Agent

范围：

- `WWIIHexV0/Core/`
- `WWIIHexV0/Commands/`
- `WWIIHexV0/Rules/`

职责：

- 将二元阵营、二战单位、二战补给经济迁移为拿战可用的规则抽象。
- 保持 `Command` / `ZoneDirective` / `WarCommandExecutor` / `RuleEngine` 统一入口。
- 落地士气、疲劳、方阵、炮兵准备、骑兵冲锋、村庄防御时必须先给最小可解释版本。
- 处理 neutral 不再 fallback 到 allies 的历史债。

禁止：

- 不改 SpriteKit/SwiftUI 视觉。
- 不新增真实网络 LLM 调用。
- 不用复杂状态机替代已有命令管线。

#### AI Agent

范围：

- `WWIIHexV0/Agents/`
- `WWIIHexV0/Turn/`
- 只读 `Core/Commands/Rules`

职责：

- 设计并实现皇帝/君主、总司令/元帅、军团长、参谋、外交官等 Agent 分层。
- 所有输出必须是 JSON / Codable directive。
- 上游 Agent 只能调整战略姿态、目标优先级、增援/预备队倾向或 directive envelope，不能直接执行底层命令。
- MockAI 必须有 deterministic fallback，不依赖真实模型。

禁止：

- 不直接改 `GameState`。
- 不绕过 `WarCommandExecutor`。
- 不把真实 API key 或模型路径写进仓库。

#### UI / SpriteKit Agent

范围：

- `WWIIHexV0/UI/`
- `WWIIHexV0/SpriteKit/`
- `Assets.xcassets` 如存在或由主 Agent 创建

职责：

- 迁移为拿破仑战争视觉系统。
- 建立共享设计 token：字体、颜色、材料、间距、圆角、线宽、动效。
- 地图、部队、指挥官、据点、炮兵阵地、战线、命令箭头、战报都要有发布级可读性。

要求：

- 44pt 触控目标。
- 不在 SwiftUI body 内做重复排序/过滤。
- 大列表用 `LazyVStack` / `LazyHStack`。
- 不使用一整屏单色羊皮纸；羊皮纸只能作底，需有墨线、军团色、红蓝铅笔线、金属/皮革色、旗帜色形成层次。
- 图标按钮优先使用系统符号或已有图标系统；陌生图标需要 tooltip/accessibility label。

禁止：

- 不把规则写进 View。
- 不让 SpriteKit 直接改 `GameState`。
- 不使用商业游戏或影视素材。

#### MapEditor Agent

范围：

- `MapEditor/`
- 只读 `Data/` schema

职责：

- 将编辑器术语迁移为地块、战役区、军团防区、部队/指挥官。
- 支持拿战地形：高地、村庄、林地、道路、桥梁、河流、沼泽、农庄、炮兵阵地、补给点。
- 支持初始指挥官、军团归属、增援入口和默认剧本资源切换。

禁止：

- 不破坏主游戏 JSON 加载格式。
- 不单独发明另一套 map schema。

#### Project / Assets Agent

范围：

- `WWIIHexV0.xcodeproj/project.pbxproj`
- `Assets.xcassets`
- 新增资源文件引用

职责：

- 仅在主 Agent 明确指定时修改 project 文件。
- 检查重复 UUID、缺失引用、target membership、bundle resource。
- 接入新 JSON 和资产。

禁止：

- 不同时让其他子 Agent 改 project 文件。
- 不做 Xcode build，除非人工授权。

### 3.3 并发整合规则

子 Agent 完成后，主 Agent 必须检查：

- 是否多个子 Agent 改了同一文件。
- 是否出现 public API 分叉。
- 是否出现 JSON schema 分叉。
- 是否出现 `Faction`、`PowerId`、`CountryId`、`CoalitionId` 多套概念混乱。
- 是否出现 `project.pbxproj` 重复引用、缺失引用或 UUID 冲突。
- 是否出现 README、`md/flow/*`、阶段记录口径不一致。
- 是否有人绕过 `RuleEngine` 修改状态。
- 是否有玩家可见二战文案残留。

没有完成这些检查前，不得声称“多 Agent 工作可合并”。

---

## 4. 版本路线

### v3.0：迁移审计、兼容合同和拿战产品定义

建议分支：`codex/v3.0-napoleonic-audit-contract`

目标：

- 建立拿战迁移的工程合同。
- 找出所有二战硬编码和二元阵营假设。
- 明确首发剧本、最终效果、非目标和并发分工。
- 不急着实现完整拿战玩法。

范围：

- 新增或更新阶段记录：`md/prompt/v3.0-拿战迁移/v3.0_audit_and_contract.md`。
- 新增迁移词汇表和命名约定：
  - `Faction` 当前源码兼容名，目标语义为 power / coalition side。
  - `Division` 当前源码兼容名，目标显示为 corps / brigade / formation。
  - `Theater` 显示为 army wing / corps sector。
  - `Region` 显示为 village / ridge / sector / battlefield region。
  - `FrontZone` 显示为 corps sector / wing sector。
- 抽出 UI 显示名，不要让主要面板继续硬编码 Ardennes、Germany、Allies。
- 记录所有必须在 v3.1-v3.4 处理的硬编码点。

推荐并发：

- Audit / Docs Agent：硬编码扫描、审计表、词汇表。
- UI Agent：只读定位 UI 硬编码，不实现大 UI。
- Rules Agent：只读定位 `Faction.opponent`、二元 switch、二战兵种耦合。
- Data Agent：只读定位默认资源和 JSON schema。

验收：

- 有完整审计清单。
- 有拿战迁移词汇表。
- 有版本拆分和风险清单。
- 没有大范围重命名导致不确定风险。

轻量检查：

- 文档尾随空白检查。
- 冲突标记扫描。
- 不跑 Xcode / XCTest / 模拟器。

### v3.1：国家、联军、多方敌我和通用回合阶段

建议分支：`codex/v3.1-napoleonic-powers-coalitions`

目标：

- 从二元 `germany/allies` 迁移到可支持多国家/多联军的拿战架构。
- 首发至少支持 France、Anglo-Allied、Prussia、neutral。
- 为后续 Austria、Russia、Spain、Ottoman 等留扩展空间。
- 保持旧数据可兼容加载或有明确迁移 fallback。

设计建议：

1. 审计 `Faction` 的所有使用点。
2. 如果短期发布优先，可先扩展 `Faction` enum：
   - `france`
   - `angloAllied`
   - `prussia`
   - `austria`
   - `russia`
   - `spain`
   - `neutral`
3. 如果改为数据驱动 `PowerId`，必须先做兼容桥，不要一轮内强行改完全项目。
4. 移除或弃用 `Faction.opponent`。敌我必须来自 `DiplomacyState` / `CoalitionState` / relation helper。
5. `DiplomacyState` 可迁移为拿战联军关系：
   - allied / coalitionPartner / coBelligerent / neutral / hostile / atWar / truce
6. 中立地块/region 不能 fallback 到某个玩家阵营。
7. `GamePhase` 要从 `germanAI/alliedPlayer` 脱钩。可以保留 raw value 兼容旧存档，但 UI 和新数据必须用通用语义。
8. `AppContainer.shouldRunAI` 必须基于 active power 是否由 AI 控制，而不是 germany/allies 写死。

推荐文件：

- `WWIIHexV0/Core/Faction.swift`
- `WWIIHexV0/Core/DiplomacyState.swift`
- `WWIIHexV0/Core/GamePhase.swift`
- `WWIIHexV0/Core/GameState.swift`
- `WWIIHexV0/Data/ScenarioDefinition.swift`
- `WWIIHexV0/Data/DataLoader.swift`
- `WWIIHexV0/Rules/CommandValidator.swift`
- `WWIIHexV0/Rules/OccupationRules.swift`
- `WWIIHexV0/Rules/SupplyRules.swift`
- `WWIIHexV0/Rules/FrontLineManager.swift`
- `WWIIHexV0/Rules/StrategicStateSynchronizer.swift`
- `WWIIHexV0/App/AppContainer.swift`

推荐并发：

- Rules Agent：敌我判断、phase、active faction。
- Data Agent：power / coalition profile JSON 草案。
- AI Agent：只读确认 agent config 对多势力的影响。
- Docs / QA Agent：文档和检查。

验收：

- 多国家/多阵营可以被 JSON 表达。
- 敌我判断不再依赖 `.opponent`。
- 中立地块/region 不会被错误算给某个势力。
- `CommandValidator` 对玩家与 AI 仍对称。
- 旧二战数据如果仍保留，必须通过兼容路径，不污染新默认剧本。

轻量检查：

- `jq empty` 检查改动 JSON。
- 对直接改动且可单文件 parse 的 Swift 文件运行 `swiftc -parse`；如果跨文件依赖导致不可行，停止并记录。
- `plutil -lint` 仅在 project 文件变更时运行。

### v3.2：滑铁卢剧本、拿战数据和地图编辑器迁移

建议分支：`codex/v3.2-waterloo-scenario-map`

目标：

- 建立第一张可玩拿战剧本地图。
- 保留 MapEditor 导出链路。
- 默认新局加载滑铁卢剧本，而不是阿登。

默认剧本建议：

```text
id: waterloo_1815
displayName: 滑铁卢 1815
地图范围：滑铁卢核心战场和普军来援方向的抽象区域
主要势力：France、Anglo-Allied、Prussia、Neutral
主目标：Mont-Saint-Jean、La Haye Sainte、Hougoumont、Papelotte、Plancenoit、Brussels Road、French Ridge
首版规模：80-160 个 hex，20-45 个 region，4-8 个 army wing / corps zone
```

拿战地形建议：

- plain -> open ground / 平原
- forest -> woodland / 林地
- hill -> ridge / 高地
- city -> village / village strongpoint
- fortress -> fortified farm / chateau / strongpoint
- road -> road / chaussée
- river edge -> stream / bridge crossing
- 可后置：marsh、orchard、sunkenRoad、field、mud

拿战 JSON 文件建议：

- `WWIIHexV0/Data/waterloo_1815_scenario.json`
- `WWIIHexV0/Data/waterloo_1815_regions.json`
- `WWIIHexV0/Data/napoleonic_unit_templates.json`
- `WWIIHexV0/Data/napoleonic_generals.json`
- `WWIIHexV0/Data/napoleonic_terrain_rules.json`

MapEditor 迁移：

- `province` UI 改为战役区/地段。
- `theater` UI 改为军团防区/翼。
- `unit` UI 改为部队/军团/旅。
- 支持 `assignedGeneralId` 显示为指挥官。
- 支持村庄、高地、桥梁、农庄、炮兵阵地、补给点、增援入口；如果 schema 暂不支持，先记录后置，不要塞到无关字段。

推荐并发：

- Data Agent：新 JSON 和 DataLoader 默认入口。
- MapEditor Agent：编辑器中文术语和导出字段兼容。
- UI Agent：地图层显示名和 accessibility label。
- Docs / QA Agent：同步 flow 和 README。

验收：

- 默认新局加载滑铁卢剧本路径。
- `MapEditorExporter` 可以导出拿战语义地图而不丢 region/theater/unit。
- 默认数据不再出现阿登主剧本名。
- 所有 id 使用 ASCII，展示名可为中文。

轻量检查：

- 对新/改 JSON 跑 `jq empty`。
- 如果改 project，跑 `plutil -lint WWIIHexV0.xcodeproj/project.pbxproj`。
- 文档尾随空白和冲突标记扫描。

### v3.3：拿战部队、士气、炮兵、骑兵和队形规则

建议分支：`codex/v3.3-napoleonic-war-rules`

目标：

- 把二战单位和战术转换为拿战战棋规则。
- 保留 hex 战术权威和统一命令管线。
- 首版规则要可解释、可调参，不追求复杂模拟。

单位模型建议：

- 源码可短期保留 `Division`，但 UI 显示为军团、师、旅、炮兵连或 formation。
- `ComponentType` 迁移为：
  - lineInfantry
  - lightInfantry
  - cavalry
  - artillery
  - guard
  - engineer
  - supplyTrain
- stats 仍可保留 attack / defense / movement / range / vision。
- 新增 morale / fatigue / cohesion / ammunition 可分阶段；首版若字段风险过大，可先用 strength + supplyState + retreatMode + combat modifiers 兼容。

战术映射建议：

- `standardAttack` -> 线列进攻 / 普通进攻
- `spearhead` -> 纵队突击
- `breakthrough` -> 中央突破
- `pincerMovement` -> 两翼合围
- `fireCoverage` -> 炮兵准备 / Grand Battery
- `feint` -> 佯攻
- `guerrillaWarfare` -> 散兵袭扰 / 侧翼骚扰
- `holdPosition` -> 固守
- `elasticDefense` -> 弹性退守
- `defenseInDepth` -> 纵深防御
- `lastStand` -> 死守据点

新增或迁移规则：

- 炮兵：range > 1，优先打密集步兵和据点；炮兵准备不主动占领。
- 骑兵：高移动和追击优势；攻击方阵、村庄、森林、高地时受惩罚。
- 方阵：可作为 defensive stance 或 `allowRetreat/hold` 之外的新姿态；对骑兵强，对炮兵和步兵火力弱。
- 线列/纵队：线列防御和火力更强，纵队移动/冲击更强但受炮火影响更大。
- 士气：战斗损失、侧翼、包围、补给不足、指挥官技能影响 morale；低士气增加撤退和拒绝命令概率。
- 疲劳：连续行动、冲锋、困难地形增加 fatigue；休整或补给恢复。
- 村庄/据点：强化步兵防御，骑兵惩罚，炮兵可压制。
- 指挥官影响：首版可通过 `GeneralAssignment` 的 skill 调整 tactic 选择或小幅战斗修正，不能直接跳过规则。

推荐文件：

- `WWIIHexV0/Core/Division.swift`
- `WWIIHexV0/Core/SupplyState.swift`
- `WWIIHexV0/Core/Terrain.swift`
- `WWIIHexV0/Rules/CombatRules.swift`
- `WWIIHexV0/Rules/MovementRules.swift`
- `WWIIHexV0/Rules/SupplyRules.swift`
- `WWIIHexV0/Rules/CommandValidator.swift`
- `WWIIHexV0/Commands/WarDirective.swift`
- `WWIIHexV0/Commands/WarCommandExecutor.swift`
- `WWIIHexV0/Agents/ZoneCommanderAgent.swift`

推荐并发：

- Rules Agent：部队、战斗、士气、疲劳、炮兵、骑兵、队形。
- AI Agent：战术分类器拿战化。
- Data Agent：unit templates。
- UI Agent：只做术语显示，不做大 UI。

验收：

- 玩家和 AI 的移动、攻击、防守、补给仍经 `RuleEngine`。
- 炮兵、骑兵、方阵、村庄防御的日志能被解释。
- 战术名称在 UI 和 `WarDirectiveRecord` 中拿战化。
- 没有 Panzer / tank / motorized 作为玩家可见文本残留。

轻量检查：

- 改 JSON 跑 `jq empty`。
- 少量 Swift 文件可尝试单文件 parse；失败则记录依赖风险。
- 禁止跑全项目 build/test。

### v3.4：皇帝、总司令、元帅、军团长 AI Agent 分层

建议分支：`codex/v3.4-napoleonic-agent-command`

目标：

- 构建真正有拿战味道的 AI Agent 层级。
- Agent 之间可以协作，但最终都必须输出结构化 directive。
- 让 AI 行为可审计、可回放、可调参。

推荐层级：

```text
SovereignAgent / EmperorAgent
  -> 决定国家/联军总战略：速胜、守势、等待援军、分兵、争夺交通线

CommanderInChiefAgent / MarshalAgent
  -> 把总战略变成战役目标：夺取 La Haye Sainte、压制 Hougoumont、等待 Prussia、攻 Plancenoit

ChiefOfStaffAgent
  -> 处理命令优先级、预备队、行军路线、增援时机

CorpsCommanderAgent
  -> 把方面目标变为 ZoneDirective：进攻、防守、炮兵准备、骑兵冲锋、方阵、撤退

DiplomatAgent / CoalitionAgent
  -> 输出联军协同姿态：守到普军抵达、避免孤军突进、协同反攻
```

执行链路要求：

```text
SovereignAgent / EmperorAgent / CoalitionAgent
  -> StrategicPostureEnvelope
  -> CommanderInChiefAgent / MarshalAgent
  -> TheaterDirectiveEnvelope
  -> decoder / validator / compiler
  -> ZoneDirective / Command
  -> WarCommandExecutor / RuleEngine
  -> WarDirectiveRecord / AgentDecisionRecord / RulerDecisionRecord
```

结构化输出要求：

- 所有 Agent 输出必须 Codable。
- 所有外部模型输出必须 fenced JSON 或纯 JSON，由 decoder 校验。
- decoder 必须校验 schemaVersion、turn、issuerId、power/faction、zone、region、tactic。
- decoder 失败时走安全 fallback，不执行半成品。
- Agent prompt 中不能要求模型“直接修改状态”。

Mock / 本地 LLM 要求：

- 首版仍可用模拟 LLM / MockAI。
- 真实本地 LLM 接入必须单独版本，不能把 API key 或模型路径硬编码进仓库。
- 网络或本地模型不可用时，必须有 deterministic fallback。

Agent 个性建议：

- Napoleon：进取、重视中央突破、集中炮兵和近卫预备队，接受较高风险。
- Ney：猛烈进攻、骑兵冲锋倾向强，可能过早投入预备队。
- Wellington：防守、利用反斜面和村庄据点，等待联军时机。
- Blucher：积极会合，偏好强行军和侧翼压迫。
- Grouchy：谨慎追击和迟滞，可用于后续剧本。
- Austrian / Russian commanders：可后置，用于 Austerlitz 或 Leipzig 版本。

推荐并发：

- AI Agent：Agent schema、prompt builder、fallback。
- Rules Agent：新增 directive 的 validator 和 executor 边界。
- UI Agent：AI 决策复盘面板显示层。
- Docs / QA Agent：更新 flowchart。

验收：

- AI 回合能解释“皇帝/总司令想要什么、军团长做了什么”。
- 玩家能在 AI 面板看到 raw JSON、编译后的 directive、命令结果和拒绝原因。
- Agent 决策失败不会破坏回合。
- 仍未绕过 `RuleEngine`。

### v3.5：战役后勤、增援、弹药、疲劳和胜负节奏

建议分支：`codex/v3.5-napoleonic-logistics-reinforcement`

目标：

- 让滑铁卢首发从“单位互打”变成有战役节奏的拿战体验。
- 以轻量方式表现后勤、弹药、疲劳、增援和联军到场。

设计建议：

- 短战役不做现代生产，优先做 reserve / reinforcement schedule。
- `EconomyState` 可保留兼容，但 UI 显示为：
  - Recruits / 兵员
  - Ammunition / 弹药
  - Supplies / 补给
  - Horses / 马匹
  - Command points / 命令点，可后置
- 增援规则：
  - Prussian reinforcement 按 turn 或 objective 条件出现。
  - French reserve / Imperial Guard 作为延迟可投入力量。
  - 增援进入必须走安全 hex 和规则系统。
- 疲劳规则：
  - 连续移动、冲锋、困难地形、低补给增加疲劳。
  - 休整、后方、安全补给减少疲劳。
- 弹药规则：
  - 炮兵准备和远程攻击消耗 ammunition。
  - 弹药不足降低炮兵效果。
- 胜负节奏：
  - 法军需在固定回合前突破或夺取关键目标。
  - 联军可通过坚守、普军会合、消耗法军获得胜利。

推荐文件：

- `WWIIHexV0/Core/EconomyState.swift`
- `WWIIHexV0/Rules/EconomyRules.swift`
- `WWIIHexV0/Rules/SupplyRules.swift`
- `WWIIHexV0/Rules/VictoryRules.swift`
- `WWIIHexV0/Rules/CommandExecutor.swift`
- `WWIIHexV0/Data/waterloo_1815_*.json`
- `WWIIHexV0/UI/EconomyPanelView.swift`
- `WWIIHexV0/UI/HUDView.swift`

推荐并发：

- Rules Agent：后勤、增援、疲劳、胜负。
- Data Agent：增援和目标数据。
- UI Agent：HUD/战报显示。
- Docs / QA Agent：同步文档。

验收：

- 战役关键节奏可被日志解释。
- 增援不直接塞进状态，必须经规则或 bootstrap 明确入口。
- 经济 UI 不再显示 Industry / Panzer 等二战语义。
- 胜负条件与滑铁卢目标一致。

### v3.6：发布级拿战 UI、美术和交互收口

建议分支：`codex/v3.6-napoleonic-ui-polish`

目标：

- 把当前工程从开发调试界面提升到可发布演示界面。
- 不靠说明文字，而靠地图、面板、状态、动效让玩家理解战局。

视觉方向：

- 主地图：19 世纪战役地图/羊皮纸风格，但避免单一米色。用墨线、地形色、红蓝铅笔箭头、军旗色、金属/皮革色形成层次。
- 部队：军牌/棋子能区分步兵、轻步兵、骑兵、炮兵、近卫、补给车，显示 strength、morale、fatigue、行动状态、弹药警告。
- 指挥官：头像、姓名、军衔、国家、风格、技能、忠诚/主动性/谨慎度。
- 据点：村庄、农庄、桥梁、高地、林地、炮兵阵地有不同图标。
- 战线：敌我接触线、计划箭头、炮击目标、骑兵冲锋路径、撤退路线、增援入口清晰可读。
- 战报：展示本回合关键行动、拒绝原因、占领变化、增援、士气崩溃、AI 指令。

主界面布局建议：

```text
顶部：回合、时段、当前阵营、士气/弹药/预备队、胜利状态、结束回合
中央：SpriteKit 战场地图，全屏优先
左侧或底部：选中部队/据点摘要，移动端可折叠
右侧或底部：军团长/命令/战报/AI/后勤 tabs
地图上：选中、可移动、可攻击、炮击范围、冲锋路径、前线、计划线、增援入口
```

SwiftUI 要求：

- 建立 `NapoleonicDesignTokens` 或类似共享设计常量。
- 44pt 最小触控区。
- 使用 `Label` 替代不必要的手写 icon+text。
- 避免 body 内重复排序、过滤、JSON 格式化。
- 大列表用 Lazy 容器。
- 复杂面板拆成独立 View，不要继续膨胀 `RootGameView`。
- 不引入第三方框架，除非人工确认。

SpriteKit 要求：

- 地图必须在桌面和移动端都可缩放、平移、点击。
- 文字不能重叠到不可读。
- 单位和据点图标有稳定尺寸，不因状态变化造成跳动。
- 图层切换清晰：地形、战役区、军团防区、前线、补给、AI 计划。
- 视觉资产必须是自制、生成、公共领域或明确授权。

推荐并发：

- UI Agent：SwiftUI 面板、设计 token。
- SpriteKit Agent：地图绘制、单位、图层、箭头。
- Data / Art Agent：头像占位、旗帜、图标资源和 asset catalog。
- Docs / QA Agent：截图检查清单和未跑重测试风险。

验收：

- 主游戏第一屏不再像调试板。
- 主要 UI 无二战文案残留。
- 移动端和 macOS 布局都有明确约束。
- UI 只读状态，操作仍走 `AppContainer` 和规则系统。

### v3.7：新手引导、存档、设置、macOS/iOS 试玩闭环

建议分支：`codex/v3.7-napoleonic-playtest-loop`

目标：

- 从“规则和 UI 迁移完成”收口到“玩家能理解并完成一局短战役”。
- 补齐新局、继续、设置、重置、战报回放和错误恢复。

范围：

- 新局：选择战役、选择阵营、选择 AI 控制选项。
- 继续：本地存档 schema，保存/加载 GameState 或受控 snapshot。
- 设置：AI 速度、日志详细度、地图图层默认值、Reduce Motion、文字大小适配。
- 引导：第一次选中部队、炮击、骑兵冲锋、结束回合时给短提示；不要做大篇说明页面。
- AI 回放：显示元帅意图、军团长命令、执行结果、拒绝原因。
- 错误恢复：JSON 加载失败、AI 解码失败、无可行动单位、命令被拒绝必须有玩家可读反馈。

推荐并发：

- UI Agent：新局/设置/引导/回放。
- Rules/State Agent：存档 schema 与兼容。
- AI Agent：AI 回放摘要。
- Docs / QA Agent：试玩检查单。

验收：

- 玩家能从新局进入滑铁卢并完成多个回合。
- AI 失败有 fallback，不会卡死。
- 存档/重置不会污染默认资源。
- 引导不遮挡地图核心交互。

### v3.8：发布候选和发布前验收

建议分支：`codex/v3.8-napoleonic-release-candidate`

目标：

- 从“可玩迁移版”收口到“可发布候选版”。
- 补齐版本说明、残留扫描、资源检查、人工授权重验证清单。

发布候选必须具备：

- App 名称、图标、默认剧本、主界面、基础设置。
- 新局 / 继续 / 重置。
- 一个完整可玩滑铁卢剧本。
- AI 回合不会卡死或静默失败。
- 玩家可理解的命令反馈。
- 关键 JSON 数据可解析。
- README 和 flow 文档准确描述当前拿战架构。
- `update_log.md` 记录 v3.0-v3.8 每版完成内容、关键文件、轻量检查和未跑重测试。
- 玩家可见层面无主要二战残留。

发布前需要人工授权的重验证：

- Xcode build。
- iOS Simulator 或真机启动。
- macOS target 启动。
- 至少 10-20 回合观察者模式。
- 基础 UI 点击烟测。
- SpriteKit 截图或人工视觉检查。
- 性能体感检查。

在未获授权前，不得声称“已发布”或“可发布已验证”。只能写“发布候选代码和文档已准备，运行时验证未授权，风险未验证”。

---

## 5. 数据 schema 方向

实际实现可沿用现有结构，但必须在阶段文档写明哪些字段是兼容旧名、哪些字段已经拿战化。

### Power / Coalition

```json
{
  "id": "power_france",
  "displayName": "France",
  "localizedName": "法兰西第一帝国",
  "shortName": "France",
  "coalitionId": "coalition_french_empire",
  "rulerAgentId": "emperor_napoleon",
  "bannerAsset": "banner_france_1815",
  "primaryColor": "#1D4E89",
  "secondaryColor": "#D8B35A",
  "warSupport": 84,
  "commandDoctrine": "central_breakthrough"
}
```

### Commander

```json
{
  "id": "commander_napoleon",
  "name": "Napoleon Bonaparte",
  "localizedName": "拿破仑",
  "rank": "Emperor",
  "power": "france",
  "commandStyle": "aggressive",
  "attributes": {
    "command": 98,
    "initiative": 95,
    "logistics": 82,
    "caution": 35,
    "charisma": 96
  },
  "skills": ["central_position", "grand_battery", "reserve_commitment"],
  "portrait": "portrait_napoleon_generated",
  "biography": "A decisive commander who concentrates force, exploits weak centers, and accepts risk for operational tempo.",
  "preferredZoneIds": ["zone_french_center", "zone_french_reserve"],
  "baseLoyalty": 100,
  "baseSatisfaction": 86
}
```

### Unit Template

```json
{
  "id": "line_infantry_brigade",
  "displayName": "Line Infantry Brigade",
  "localizedName": "线列步兵旅",
  "maxStrength": 10,
  "morale": 7,
  "components": [
    { "type": "lineInfantry", "weight": 0.85 },
    { "type": "lightInfantry", "weight": 0.15 }
  ],
  "allowedFormations": ["line", "column", "square"]
}
```

### Region / Battlefield Sector

```json
{
  "id": "region_hougoumont",
  "name": "Hougoumont",
  "localizedName": "乌古蒙",
  "owner": "angloAllied",
  "controller": "angloAllied",
  "terrain": "fortress",
  "theaterId": "zone_anglo_right",
  "displayHexes": [{ "q": 4, "r": 6 }],
  "representativeHex": { "q": 4, "r": 6 },
  "city": {
    "name": "Hougoumont",
    "victoryPoints": 4,
    "isCapital": false
  },
  "infrastructure": 2,
  "supplyValue": 2,
  "resources": [
    { "type": "supplies", "amount": 2 },
    { "type": "ammunition", "amount": 1 }
  ],
  "coreOf": ["angloAllied"],
  "isPassable": true
}
```

### Theater Directive

```json
{
  "schemaVersion": 6,
  "issuerId": "marshal_napoleon",
  "turn": 6,
  "power": "france",
  "strategicIntent": "Fix the Allied right, prepare a grand battery against the center, then commit cavalry if the line wavers.",
  "directives": [
    {
      "id": "directive_french_center_6",
      "zoneId": "zone_french_center",
      "category": "offense",
      "tactic": "grandBattery",
      "priority": 92,
      "targetTheaterId": "zone_anglo_center",
      "weightedRegions": ["region_la_haye_sainte", "region_mont_saint_jean"],
      "focusRegionId": "region_la_haye_sainte",
      "supportRegionIds": ["region_hougoumont"],
      "reserveBias": 2,
      "intensity": "limitedCounter",
      "maxCommittedUnits": 3,
      "rationale": "Artillery can weaken the center before committing infantry."
    }
  ]
}
```

---

## 6. 文档更新要求

每个版本完成后至少更新：

- `update_log.md`：版本号、完成日期、核心变更、关键文件、轻量检查、未跑重测试、遗留风险。
- `md/flow/flow.md`：当前真实核心逻辑。
- `md/flow/flowchart.md`：关键流程图，尤其是数据加载、动态战区、AI 指令链。
- `README.md`：当前项目定位、玩法、AI 管线、检查规则。
- 当前阶段提示词或实现记录：放在 `md/prompt/v3.0-拿战迁移/`。

若源码行为、检查规则、核心流程、分支策略或版本状态改变，相关文档必须同步更新。

---

## 7. 轻量检查和禁止项

执行前必须读 `md/test/test.md`。当前默认不做 Xcode / XCTest / 模拟器 / 性能类测试。

允许的轻量检查：

```sh
rg -n "[[:blank:]]+$" AGENTS.md README.md update_log.md md/test/test.md md/flow/flow.md md/flow/flowchart.md md/prompt/v3.0-拿战迁移
rg -n "<<<<<<<|=======|>>>>>>>" AGENTS.md README.md update_log.md md/flow WWIIHexV0 MapEditor md/prompt/v3.0-拿战迁移
rg -n "Germany|Allies|Ardennes|Bastogne|Panzer|tank|motorized|germanAI|alliedPlayer" WWIIHexV0 MapEditor README.md md/flow md/prompt/v3.0-拿战迁移
jq empty WWIIHexV0/Data/waterloo_1815_scenario.json
jq empty WWIIHexV0/Data/waterloo_1815_regions.json
jq empty WWIIHexV0/Data/napoleonic_unit_templates.json
jq empty WWIIHexV0/Data/napoleonic_generals.json
jq empty WWIIHexV0/Data/napoleonic_terrain_rules.json
plutil -lint WWIIHexV0.xcodeproj/project.pbxproj
```

Swift 单文件 parse 只在少量纯 Swift 改动且不会触发项目构建时使用：

```sh
swiftc -parse path/to/ChangedFile.swift
```

禁止主动执行：

- `xcodebuild test`
- `xcodebuild build`
- `xcodebuild build-for-testing`
- `xcrun simctl ...`
- Probe / Smoke / Stage Regression / Dynamic Theater Regression / Full
- XCTest、UI test、性能测试、快照测试
- 启动 iOS Simulator
- 启动 app 做人工烟测
- 全项目 Swift 编译、全量 lint、全量格式化

如果某问题必须依赖重测试才能确认，只记录风险，不擅自运行。

---

## 8. 发布级验收清单

发布候选前必须逐项确认：

- 默认场景是拿战剧本，不是阿登。
- 主 UI 第一屏是可操作战场，不是说明页。
- 玩家可选择阵营或至少明确扮演方。
- AI 能通过结构化 directive 行动，失败有 fallback。
- 玩家和 AI 都经 `Command` / `ZoneDirective` / `WarCommandExecutor` / `RuleEngine`。
- `HexTile.controller` 和 `Division.coord` 仍是战术权威。
- `regionToTheater` 仍是初始/基础映射，不表示运行时推进。
- `hexToTheater` 和 `hexToFrontZone` 仍是动态权威。
- 炮兵、骑兵、方阵/防守姿态、村庄据点、士气/疲劳至少有一个可解释的首版实现。
- AI 面板能展示 raw JSON、编译后 directive、命令结果、拒绝原因。
- 战报能解释关键战斗、占领、撤退、增援、命令失败。
- UI 没有主要二战文案残留。
- 新 JSON 都通过 `jq empty`。
- project 文件如改动通过 `plutil -lint`。
- 文档准确描述当前真实状态。
- 未跑重测试的范围和风险写清楚。

---

## 9. 风险清单

实现前必须主动关注这些风险：

- 当前工作树很脏，且历史记录显示分支多次漂移；合并前必须重新确认分支、基点、dirty 文件和冲突。
- `Faction` 二元模型是最大风险点；如果一次性强改，容易连锁破坏 AI、补给、前线、部署、UI 和数据加载。
- `Faction.opponent` 残留会直接破坏多方联军和中立逻辑。
- `GamePhase.germanAI/alliedPlayer` 残留会让新阵营控制权表现错误。
- `RegionDataSet.toRegions()` 中 owner/controller nil fallback 到 `.allies` 是历史债，拿战迁移时必须修或隔离。
- `DataLoader` 默认资源、fallback components、validation 仍硬编码阿登和 Guderian。
- `project.pbxproj` 已多次被多分支修改，只能由一个 Agent 处理。
- UI/SpriteKit 改动需要视觉验证，但当前规范禁止主动启动 app；必须记录未验证风险。
- 真实 LLM 接入、模型输出质量、长回合稳定性必须单独版本验证。
- 历史准确性和玩法可读性要平衡：首版可抽象，但不能把拿战变成换皮二战。

---

## 10. 给后续 Agent 的交付格式

每个实现 Agent 最终必须简洁说明：

1. 完成了什么。
2. 改了哪些关键文件。
3. 跑了哪些轻量检查，具体结果是什么。
4. 哪些重测试没跑，原因是什么。
5. 还剩什么风险或下一步。

如果进行了 git stage / commit / push，只能在实际成功后按 Codex 桌面规范输出对应 directive。

