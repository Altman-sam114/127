# Codex v5.0-v5.9 任务提示词：从 WWIIHexV0 迁移为唐宋时代 AI Agent 历史策略游戏

> 本文是交给后续实现 Agent / 子 Agent 的总提示词。它不是本轮代码实现记录，而是唐宋题材迁移的产品目标、架构合同、版本路线、并发分工、最终发布效果和验收标准。执行前必须先读 `AGENTS.md`、`update_log.md`、`md/flow/flow.md`、`md/flow/flowchart.md`、`md/test/test.md` 和本文件。不要凭旧 prompt、旧记忆或题材想象直接改代码。

---

## 0. 当前项目判断

你接手的是 `WWIIHexV0`，不是空项目。当前工程已经有成熟的 Swift + SwiftUI + SpriteKit hex 战棋骨架，并混合了多个版本方向：动态战区、前线、部署层、统一命令管线、地图编辑器、将军数据、玩家双轨命令、元帅模拟 LLM JSON、经济、外交、macOS 主游戏 target 等。

当前真实主链路大致是：

```text
MapEditor / JSON 数据
  -> DataLoader
  -> GameState
  -> HexTile.controller + Division.coord
  -> Region 聚合
  -> EconomyState 收入 / 生产 / 补员
  -> DiplomacyState 国家 / 集团 / 关系草案
  -> Initial Theater snapshot + runtime hexToTheater
  -> FrontLine 动态 hex 接触
  -> WarDeployment hexToFrontZone + FRONT/DEPTH/GARRISON + GeneralAssignment
  -> MarshalAgent / TheaterDirective JSON
  -> TheaterDirectiveDecoder / TheaterDirectiveCompiler
  -> ZoneDirective
  -> WarCommandExecutor
  -> RuleEngine
  -> StrategicStateSynchronizer
  -> UI overlay / 日志 / WarDirectiveRecord / PlayerPlannedOperation
```

必须尊重这些事实：

- `HexTile.controller` 和 `Division.coord` 是战术层权威。
- `RegionNode.controller` 是从 region 内 hex controller 聚合出来的战略快照。
- `regionToTheater` 是初始/基础战区归属，不是运行时推进层。
- `hexToTheater` 是运行时动态战区权威。
- `hexToFrontZone` 是部署层动态归属权威。
- 玩家、AI、聊天命令、MockAI 都必须落到 `Command` / `ZoneDirective`，再经 `WarCommandExecutor`、`CommandValidator`、`RuleEngine` 执行。
- Legacy Agent D 保留作回归参考，默认战争 AI 主路径不得退回旧管线。
- 当前源码仍有二战绑定：`Faction.germany/allies`、`Faction.opponent`、`GamePhase.germanAI/alliedPlayer`、`Division`、`ComponentType.tank/motorizedInfantry`、`ProductionKind.panzerDivision`、阿登 JSON、Panzer、Germany、Allies、Bastogne、Guderian、Marshal/Ruler 英文二战文案等。
- 当前工作树可能有多版本未提交改动。任何实现前必须先审计分支和 dirty worktree，不能回滚他人改动。

迁移目标不是换皮，不是把 Germany 改成 Song、Allies 改成 Tang。目标是把现有引擎逐步迁移为一个可发布的、AI Agent 驱动的唐宋时代历史策略游戏。

---

## 1. 最终产品目标

暂定产品名：`山河一统 Agent`。英文工作名可用 `Mandate of Rivers Agent` 或 `Tang Song Agent Hex`。最终名称由人工确认。

### 1.1 题材定位

“唐宋时代”范围很大，首发必须选一个能闭环、势力清楚、AI 好发挥、地图规模可控的窗口。推荐首发剧本：

```text
id: jianlong_960_unification
displayName: 建隆元年：陈桥兵变与山河一统
时间范围：960-979 的抽象统一战争窗口，以 960 为开局
地图范围：中原、河东、幽燕边缘、关中、两淮、江南、荆湖、川蜀、岭南以抽象 hex/州府表达
核心冲突：赵宋继承后周中原根基，北有北汉与辽压力，南有南唐、后蜀、吴越、荆南、南汉等割据政权，玩家通过军事、粮道、外交归附和天命声望完成统一或改写格局
```

为什么首选 960：

- 它是唐末五代到宋初秩序重建的关键节点，能自然覆盖“唐宋转型”。
- 多势力关系清楚，但不需要一上来做完整唐朝 300 年或宋辽金元长时段。
- 适合 AI Agent：皇帝、枢密、宰相、节度使、转运使、州府守臣、外交使者都能有明确职责。
- 玩法闭环适合当前引擎：hex 推进、州府聚合、粮道、攻城、归附、战报复盘。

后续扩展剧本可在同一架构下追加：

- `tianbao_755_anfeng`: 天宝十四载：范阳兵起，安史之乱。
- `yuanhe_817_huaixi`: 元和十二年：淮西平藩。
- `chanyuan_1004_song_liao`: 景德元年：澶渊之盟。
- `jingkang_1126_north_song`: 靖康危局。

首发不要做全部剧本。先把 960 剧本做到可发布。

### 1.2 首发体验

发布候选必须达到这些效果：

1. 打开应用后直接进入可玩的历史战役地图，不做营销落地页。
2. 第一屏核心是地图、回合、当前政权、资源、军令、AI 战报；不是大段说明文字。
3. 玩家可选择至少一个势力，首发优先保证 `power_song` 可玩；其他势力由 AI Agent 驱动。
4. 地图以 hex 为战术权威，以州府/军州/关隘/仓城为战略聚合层，以路/道/方面/节镇为 AI 调度层。
5. 玩家既能微操军队，也能通过将领/方面/枢密院面板下达宏观命令：进军、固守、围城、断粮、驰援、会师、招抚。
6. AI Agent 不直接改 `GameState`。皇帝、宰相、枢密使、节度使、转运使、州府守臣、外交使者只能输出结构化 directive，经 decoder / validator / compiler 后落到统一规则系统。
7. 玩家能看到 AI 为什么攻太原、为什么守淮河、为什么招抚吴越、为什么暂缓伐蜀。
8. 发布前主游戏 UI、默认数据、日志、面板不能有玩家可见的二战残留：Germany、Allies、Ardennes、Panzer、Bastogne、Division、German AI、Allied Player、Manpower/Industry/Supplies 不得出现在默认主路径。
9. 发布候选必须有完整闭环：开局、选择势力、查看州府、选择军队、行军、战斗、围城/占领、粮草消耗、AI 回合、归附/外交事件、战报复盘、胜负判断。
10. iOS 主游戏、macOS 主游戏、macOS 地图编辑器三个方向都应保留；首发允许只把 iOS/macOS 主游戏做到可玩，把地图编辑器作为制作工具保留。

### 1.3 视觉目标

UI 要从二战调试原型升级为发布级唐宋历史策略质感：

- 地图底色可用绢帛、宣纸、浅墨山川，但不能整屏单一米色。
- 色彩层次建议：墨黑线、青绿山水、朱印势力标识、石青/石绿河山、铜色边框、玉色高亮、赭石道路。
- 势力标识用印章、军旗、州府符号，不用二战军标。
- 部队棋子区分禁军、厢军、骑军、弓弩、器械、守军、水师、藩镇兵。
- 地图 icon 区分都城、州府、军州、关隘、渡口、粮仓、山道、港口。
- 战线、进军箭头、围城圈、粮道虚线、归附标记、AI 计划必须可读。
- 面板应紧凑、克制、适合反复操作；不要做卡片堆叠的营销页。
- 图标优先使用系统 SF Symbols 或项目内统一绘制资产；不要引入未授权历史画作、影视、游戏素材。
- 触控目标不小于 44pt，按钮文案不溢出，Dynamic Type 和 VoiceOver 不应被破坏。

---

## 2. 迁移总原则

### 2.1 必须保留的工程资产

保留并迁移这些成熟资产：

- Hex 坐标、移动、攻击、占领、视野、补给落点的战术权威。
- Region 战略聚合层，不替代 hex。
- 动态战区、前线、部署层从 hex 和单位位置派生的关系。
- `Command` / `ZoneDirective` / `WarCommandExecutor` / `RuleEngine` 统一执行管线。
- `WarDirectiveRecord`、`AgentDecisionRecord`、`RulerDecisionRecord`、`PlayerPlannedOperation` 等审计/复盘机制。
- MapEditor 的稀疏 hex、region、theater、unit 编辑和导出能力。
- iOS 主游戏、macOS 主游戏、macOS 地图编辑器方向。
- 模拟 LLM / MockAI fallback 思路：真实模型不可用时仍能 deterministic 推进游戏。

### 2.2 必须替换或抽象的二战语义

按版本逐步替换这些题材绑定点：

- `Faction.germany/allies`：迁移为多政权体系。短期可扩展 enum，长期目标是数据驱动 `PowerId` / `PowerProfile`，`Faction` 仅作兼容桥。
- `Faction.opponent`：多势力不能用单一 opponent。敌我关系必须来自 `DiplomacyState` / `PowerRelation` / `WarRelationRules`。
- `GamePhase.germanAI/alliedPlayer`：迁移为通用 `playerCommand` / `aiCommand` / `resolution` 或基于 active power 的 phase。
- `Division`：源码可短期保留兼容名，但玩家可见语义必须是军队、军团、营、守军、行营、军寨。
- `ComponentType.tank/motorizedInfantry/infantry/artillery`：迁移为禁军、厢军、藩镇兵、骑军、弓弩、器械、水师、守军等。
- `EconomyResources.manpower/industry/supplies`：短期显示映射为丁口/钱帛/粮草；长期可拆为 `Population`、`Coin`、`Grain`、`Arms`、`Transport`。
- `ProductionKind.panzerDivision` 等：迁移为募禁军、募厢军、募骑军、造器械、整备粮草、修城、造船/水师等。
- `Theater`：UI 显示为方面、路、行营、节镇、边防区。
- `FrontZone`：UI 显示为方面防区、行营辖区、节镇防区。
- `Region`：UI 显示为州府、军州、关隘、仓城，不叫 province。
- `MarshalAgent`：迁移为枢密使/大将/行营都部署/谋主 Agent。
- `RulerAgent`：迁移为皇帝/国主/太后/权臣 Agent。
- `GeneralData`：迁移为历史人物数据，含统率、武勇、谋略、政务、威望、忠诚、野心、性格、技能。
- 阿登 JSON：迁移为唐宋首发剧本 JSON。
- 地图编辑器术语：地块、州府、方面/路、军队/人物、都城、粮仓、渡口、关隘。

### 2.3 必须新增或强化的唐宋语义

首发实现要克制，但必须体现唐宋题材：

- `Mandate / Legitimacy`：天命、正朔、国威、民心，影响归附、征兵、外交态度和胜利评价。
- `Court / Civil-Military Balance`：朝廷、枢密、宰辅、节度使。首版可以只作为 AI 层和事件层，不做复杂内阁。
- `Grain / Supply Lines`：粮草、漕运、仓城、转运。开封、洛阳、太原、扬州、金陵、成都等应有战略意义。
- `Siege`：围城、守城、破城、招降。州府/关隘不能只是普通地形。
- `River / Canal`：黄河、淮河、长江、大运河对移动、补给、边界和水师有影响。
- `Submission / Pacification`：归附、纳土、称臣、招抚。首版可作为外交/事件结果，但不得绕过规则直接改 hex。
- `Jiedushi / Military Governor`：节度使、行营将领有偏好和忠诚。玩家微操会影响满意度，但不能导致不可控崩坏。
- `Off-map Pressure`：辽、吐蕃/党项、岭南远方压力可先用 off-map 事件和外交 modifier 表达，不必全图展开。

### 2.4 禁止项

- 不要一次性大规模重命名所有类型再凭感觉修编译。先做兼容层和迁移合同，再分版本替换。
- 不要让任何 Agent 直接修改 `HexTile.controller`、`Division.coord`、`regionToTheater`、`hexToTheater` 或 `hexToFrontZone`。
- 不要把 region 当战术权威；进军、攻击、围城、占领仍必须落到 hex。
- 不要把完整唐朝、五代十国、北宋、南宋、辽金西夏全部一次性塞进首版。
- 不要恢复旧 Cabinet / Minister / StrategicDirective 污染管线。唐宋可以有朝廷/枢密/中书/转运使，但必须是新 schema 且仍收口到 `ZoneDirective -> WarCommandExecutor -> RuleEngine`。
- 不要使用受版权保护的影视、游戏、绘画头像、图标或 UI 资产。可用自制、生成、公共领域或明确授权素材。
- 不要硬编码真实 LLM API key、模型路径、网络端点。真实模型接入单独版本处理。
- 未获人工授权，不跑 `xcodebuild build/test`、模拟器、Probe、Smoke、Stage Regression、Full、性能测试或 app 启动。

---

## 3. 首发剧本设计

### 3.1 势力建议

首发 `jianlong_960_unification` 建议势力：

```text
power_song        宋 / 赵匡胤，开封中原核心，玩家首选
power_northern_han 北汉，太原核心，辽支援压力
power_liao_edge   辽边境压力，可首版半 off-map
power_southern_tang 南唐，金陵、江淮、长江中下游
power_later_shu   后蜀，成都、剑门、夔峡
power_wuyue       吴越，杭州、两浙，可外交归附重点
power_jingnan     荆南，江陵，体量小但卡荆湖
power_southern_han 南汉，广州、岭南，可作为后期目标或 off-map
power_local       地方豪强 / 中立州府 / 山寨
```

短期如 `Faction` 仍为 enum，可先扩展 case；长期必须迁移为数据驱动 `PowerId`。旧 `germany/allies` 只作为 legacy 数据兼容，不应出现在唐宋默认主路径。

### 3.2 地图规模

首发地图规模建议：

```text
hex: 140-220 个
region: 45-70 个州府 / 关隘 / 仓城
theater / front zone: 8-14 个方面 / 路 / 行营
initial armies: 24-45 支
turns: 18-36 回合
```

首发地图不要追求真实比例。优先保证：

- 开封中原、太原北线、江淮南唐、川蜀、两浙、荆湖、岭南边缘关系清楚。
- 粮道和河流有实际意义。
- 各势力开局目标明确。
- AI 能在 5-10 回合内产生可观察行动。

### 3.3 关键节点

必须考虑的州府/节点：

- 中原：开封、洛阳、郑州、滑州、澶州、宋州、许州、陈州。
- 河东北线：太原、晋阳、忻州、代州、雁门、潞州。
- 关中/西线：长安、同州、凤翔、秦州、汉中入口。
- 江淮：寿州、扬州、楚州、庐州、濠州、淮河渡口。
- 江南：金陵、润州、宣州、洪州、鄂州。
- 两浙：杭州、越州、明州。
- 荆湖：江陵、襄阳、潭州。
- 川蜀：成都、剑门、梓州、夔州。
- 岭南边缘：广州、韶州，首版可简化为边缘 theater。

关键地形/设施：

- 都城 / 国都：开封、金陵、成都、太原、杭州、广州。
- 关隘：潼关、虎牢、剑门、雁门。
- 河流：黄河、淮河、长江、汉水。
- 漕运/运河：汴河、淮扬线可抽象为 road/canal。
- 粮仓：开封仓、洛阳仓、扬州转运、成都府库等。

### 3.4 胜利目标

首发胜利建议：

- `power_song` 主胜利：
  - 控制开封、洛阳、太原、金陵、成都、杭州中的多数关键节点。
  - 天命/正朔达到阈值。
  - 完成至少 2 个南方政权的归附或征服。
- 其他势力：
  - 保持独立到指定回合。
  - 控制本方国都和若干边境州府。
  - 使宋无法达到统一阈值。
- 共同失败/危机：
  - 国都失陷。
  - 粮草崩溃。
  - 关键将领叛离或战线全线崩溃。

胜利判断必须走规则系统或专门 VictoryRules，不允许事件直接宣告胜负而不看真实 hex/region 控制。

---

## 4. AI Agent 设计目标

### 4.1 分层

唐宋 Agent 分层建议：

```text
RulerAgent / EmperorAgent
  皇帝、国主、辽主、权臣
  输出国家姿态：统一、固守、招抚、求和、北伐、先南后北

CourtAgent / ChancellorAgent
  宰相、中书、枢密院
  输出资源倾向、外交优先级、重点战区、风险约束

MarshalAgent / PrivyCouncilAgent
  枢密使、行营都部署、大将
  读取降维战场摘要，输出 TheaterDirective JSON

ZoneCommanderAgent / MilitaryGovernorAgent
  节度使、都部署、州府主将
  输出 ZoneDirective：进军、固守、围城、截粮、驰援、会师

GovernorAgent / PrefectAgent
  州府守臣
  输出治理倾向：征粮、修城、安抚、募兵；首版可只影响经济和事件

EnvoyAgent
  外交使者
  输出归附、称臣、停战、联盟意向；不得直接改 hex 控制
```

### 4.2 规则边界

- 上游 Agent 只能塑形目标、优先级、姿态、资源倾向和 directive envelope。
- 下游执行必须是 `ZoneDirective -> WarCommandExecutor -> RuleEngine`。
- 归附/外交必须先产生合法记录，再由规则层把具体州府、军队、关系变化落地。
- 真实 LLM 接入前，必须有 deterministic 模拟 Agent，保证无网络也能玩。

### 4.3 JSON / schema 原则

- 所有 Agent 输出必须 Codable。
- JSON id 使用 ASCII/pinyin：`power_song`、`region_kaifeng`、`general_zhao_kuangyin`。
- 中文只放在展示字段：`displayName`、`localizedName`、`biography`、`description`、`rationale`。
- decoder 必须校验：
  - schemaVersion。
  - issuerId。
  - turn。
  - power/faction。
  - zone/region 是否存在。
  - tactic/category 是否一致。
  - 目标是否与外交关系匹配。
- 解码失败不得执行半成品 JSON，必须 fallback 到安全 directive 或 hold。

---

## 5. 多 Agent 并发工作流

主 Agent 负责总体架构、接口合同、冲突整合和最终验收。子 Agent 只能在明确边界内并发，不得同时改同一 public API 或同一文件。

### 5.1 并发前主 Agent 必做

1. 读完 `AGENTS.md`、`update_log.md`、`md/flow/flow.md`、`md/flow/flowchart.md`、`md/test/test.md` 和本文件。
2. 审计工作树：

```sh
git branch --show-current
git status --short
rg -n "germany|allies|Ardennes|Bastogne|Panzer|Division|Manpower|Industry|Supplies|German AI|Allied Player|Guderian|opponent" WWIIHexV0 MapEditor README.md md
rg -n "enum Faction|enum GamePhase|struct Division|enum ComponentType|ProductionKind|EconomyResources|DiplomacyState|GeneralData|ZoneDirective|WarCommandExecutor|RuleEngine" WWIIHexV0
```

3. 写出本轮实际版本目标、非目标、文件边界和 public API 合同。
4. 没有接口合同前，不要让多个子 Agent 同时改 `Core/`、`Commands/`、`Rules/`。
5. `WWIIHexV0.xcodeproj/project.pbxproj` 只能由主 Agent 或唯一指定的 Project Agent 修改。
6. 默认不跑重测试；只能跑 `md/test/test.md` 允许的轻量检查。

### 5.2 推荐子 Agent 分工

每轮最多并发 3-5 个子 Agent。优先减少冲突，不追求数量。

#### Architecture / Contracts Agent

范围：

- `WWIIHexV0/Core/`
- `WWIIHexV0/Commands/`
- `WWIIHexV0/Rules/`
- 只读 `Data/`、`Agents/`

职责：

- 设计 `PowerId` / `PowerProfile` / `TurnOrderState` / `PowerRelation` 等兼容合同。
- 收口 `Faction.opponent`、`GamePhase.germanAI/alliedPlayer` 的替代方案。
- 规定哪些 legacy 类型短期保留，哪些 UI 不得显示。

禁止：

- 不改大 UI。
- 不写默认剧本 JSON。
- 不自行跑 Xcode / XCTest。

#### History / Data Agent

范围：

- `WWIIHexV0/Data/*.json`
- `WWIIHexV0/Data/ScenarioDefinition.swift`
- `WWIIHexV0/Data/RegionDataSet.swift`
- `WWIIHexV0/Data/DataLoader.swift`
- 只读 `Core/Faction.swift`、`Core/Terrain.swift`

职责：

- 设计 `jianlong_960_unification` 首发剧本。
- 建立势力、州府、地形、单位模板、人物/将领、胜利条件数据。
- 保证 JSON id 用 ASCII/pinyin，中文只放展示字段。
- 做数据规模控制，保证首版可玩，不追求百科全书。

禁止：

- 不改 `RuleEngine`。
- 不改 SwiftUI/SpriteKit 视觉。
- 不改 project 文件，除非主 Agent 明确指定。

#### Rules Agent

范围：

- `WWIIHexV0/Core/`
- `WWIIHexV0/Commands/`
- `WWIIHexV0/Rules/`

职责：

- 将二元阵营、二战单位、二战经济迁移为唐宋多势力可用规则抽象。
- 保持 `Command` / `ZoneDirective` / `WarCommandExecutor` / `RuleEngine` 统一入口。
- 落地围城、粮道、士气、兵种差异时先给最小可运行版本。
- 保证中立/地方豪强不会 fallback 到某个玩家势力。

禁止：

- 不改 UI 大布局。
- 不新增真实网络 LLM 调用。
- 不让外交或归附直接绕过 hex 占领规则。

#### AI Agent

范围：

- `WWIIHexV0/Agents/`
- `WWIIHexV0/Turn/`
- 只读 `Core/Commands/Rules`

职责：

- 设计皇帝、朝廷、枢密、节度使、转运使、州府守臣、外交使者 Agent 分层。
- 所有输出必须是 Codable JSON / directive。
- 上游 Agent 只能调整战略姿态、目标优先级、资源倾向或 directive envelope，不能直接执行底层命令。
- 提供 deterministic fallback，不依赖真实 LLM。

禁止：

- 不直接改 `GameState`。
- 不绕过 `WarCommandExecutor`。
- 不把旧 Cabinet / Minister 污染管线接回。

#### UI / Art Agent

范围：

- `WWIIHexV0/UI/`
- `WWIIHexV0/SpriteKit/`
- `Assets.xcassets` 如存在或由主 Agent 创建

职责：

- 迁移为唐宋视觉系统。
- 建立共享设计 token：字体、颜色、材料、间距、圆角、线宽、动效。
- 地图、军队、州府、粮道、战线、战报都要有发布级可读性。
- 把玩家可见术语从二战迁出。

要求：

- 44pt 触控目标。
- 不在 SwiftUI body 内做重复排序/过滤。
- 大列表用 `LazyVStack` / `LazyHStack`。
- 避免单一米色、单一暗蓝或单一紫色主题；历史底色只作底，需有朱印、墨色、青绿、铜色、势力色形成层次。
- 地图仍是第一屏主体，不做 landing page。

禁止：

- 不把规则写进 View。
- 不让 SpriteKit 直接改 `GameState`。
- 不使用未授权素材。

#### MapEditor Agent

范围：

- `MapEditor/`
- 只读 `Data/` schema

职责：

- 将编辑器术语迁移为地块、州府、方面/路、军队/人物。
- 支持唐宋地形、都城、州府、军州、关隘、渡口、港口、粮仓、初始人物和势力归属。
- 保持导出 JSON 能被主游戏 `DataLoader` 读取。

禁止：

- 不破坏主游戏 JSON 加载格式。
- 不独自修改 Xcode project。

#### Docs / QA Agent

范围：

- `README.md`
- `update_log.md`
- `md/flow/`
- `md/test/test.md`
- `md/prompt/v5.0-唐宋迁移/`

职责：

- 同步核心逻辑文档和阶段记录。
- 做轻量检查与冲突扫描。
- 记录未跑重测试原因和风险。

禁止：

- 不用“已验证”代替具体命令和结果。
- 不伪造 build/test/simulator 结果。

---

## 6. 版本路线

### v5.0 - 迁移审计与合同冻结

目标：

- 不急着写玩法，先把唐宋迁移合同写清楚。
- 明确哪些代码短期兼容，哪些玩家可见路径必须迁出二战。
- 定义首发剧本、数据命名规范、视觉方向、AI 分层、轻量检查边界。

主 Agent 任务：

1. 读取必读文档和源码。
2. 审计 dirty worktree、当前分支、二战残留、二元阵营依赖。
3. 写 `md/prompt/v5.0-唐宋迁移/codex-v5.0-唐宋aiagent历史策略迁移总提示词.md`。
4. 在 `update_log.md` 历史维护记录追加本迁移提示词。
5. 不改源码，不改 project，不跑重测试。

验收：

- 新提示词存在且覆盖目标、范围、禁止项、版本路线、并发分工、轻量检查、发布标准。
- `update_log.md` 记录新增迁移提示词。
- 文档尾随空白检查通过。

### v5.1 - 多势力与通用回合地基

目标：

- 从二元 `germany/allies` 和固定 `germanAI/alliedPlayer` 中解耦。
- 为唐宋多政权建立兼容层。

建议改动：

1. 新增或扩展：
   - `PowerId`
   - `PowerProfile`
   - `TurnOrderState`
   - `PowerRelation`
   - `WarRelationRules`
2. `Faction` 短期可保留 legacy case，但增加唐宋势力或桥接到 `PowerId`。
3. 废弃主路径对 `Faction.opponent` 的依赖。敌军判断改从关系表取 hostile / atWar。
4. `GamePhase` 抽象为通用 command / ai / resolution，或让 phase 只描述当前行动类型，不写死德国/盟军。
5. `CommandValidator.phaseAllowsCommands`、`CommandExecutor.executeEndTurn`、`AppContainer.shouldRunAI`、`TurnManager.isAITurn` 改为基于 turn order 和玩家控制权。
6. 保留旧阿登数据兼容，但默认唐宋剧本不应走 legacy fallback。

并发建议：

- Architecture Agent：改核心合同。
- Rules Agent：改回合、校验、敌我判断。
- Docs / QA Agent：只读扫残留和记录风险。

轻量检查：

```sh
rg -n "Faction\\.opponent|germanAI|alliedPlayer|case \\.germany|case \\.allies" WWIIHexV0/Core WWIIHexV0/Rules WWIIHexV0/Turn WWIIHexV0/App WWIIHexV0/Agents
```

验收：

- 回合推进不写死 Germany -> Allies。
- AI 触发不只为 `.germany` 服务。
- 玩家势力可由数据指定。
- 旧测试/旧数据未主动删除；legacy 风险有记录。

### v5.2 - 唐宋首发剧本数据与地图编辑器语义

目标：

- 让默认数据从阿登迁到 `jianlong_960_unification`。
- MapEditor 能制作/回读唐宋剧本。

建议改动：

1. 新增默认 JSON：
   - `tangsong_jianlong_960_scenario.json`
   - `tangsong_jianlong_960_regions.json`
   - `tangsong_unit_templates.json`
   - `tangsong_characters.json` 或迁移 `generals.json`
2. `DataLoader.loadInitialGameState()` 默认读取唐宋剧本；阿登变 legacy resource。
3. 地图数据包含：
   - 140-220 hex。
   - 45-70 region。
   - 8-14 theater/front zone。
   - 初始军队、人物、都城、粮仓、关隘、渡口、河流、道路。
4. `MapEditorExporter` 保证所有 hex 有 region，region theater assignment 仍只是初始布局。
5. `MapEditorView` 文案迁移为地块、州府、方面、军队/人物、粮仓、关隘。

并发建议：

- History / Data Agent：写数据与 schema。
- MapEditor Agent：改编辑器术语和字段。
- Docs / QA Agent：跑 JSON 轻量检查。

轻量检查：

```sh
jq empty WWIIHexV0/Data/tangsong_jianlong_960_scenario.json
jq empty WWIIHexV0/Data/tangsong_jianlong_960_regions.json
jq empty WWIIHexV0/Data/tangsong_unit_templates.json
jq empty WWIIHexV0/Data/tangsong_characters.json
```

验收：

- 默认主游戏不再加载阿登。
- 新剧本 region 覆盖所有 hex，zero overlap。
- 默认玩家可见场景名为唐宋剧本。
- MapEditor 导出仍可被游戏读取。

### v5.3 - 古代军制、粮草、围城与经济最小闭环

目标：

- 把二战兵种、生产、补给和城市经济迁移为唐宋可用规则。
- 实现最小围城/粮道闭环。

建议改动：

1. `ComponentType` 迁移或桥接：
   - `imperialGuard`
   - `prefectureInfantry`
   - `cavalry`
   - `crossbow`
   - `siegeEngine`
   - `garrison`
   - `naval`
2. `ProductionKind` 迁移：
   - 募禁军
   - 募厢军
   - 募骑军
   - 造器械
   - 整备粮草
   - 修城
   - 造船 / 水师
3. `EconomyResources` 显示迁移：
   - 丁口
   - 钱帛
   - 粮草
   - 可选军械
4. `CombatRules` 加最小古代兵种口径：
   - 骑军平原/道路机动优势。
   - 弓弩守城/防御加成。
   - 器械对城池/要塞有围攻加成，但野战脆弱。
   - 守军在州府/关隘防御提升。
5. `SupplyRules` / `EconomyRules` 加粮道：
   - 粮仓和可控道路/运河影响 supply。
   - 深入敌境、跨河、山道增加消耗或 lowSupply 风险。
6. `Command` 可先增加 `besiege` / `relieveSiege` / `repairFortification`，也可先把围城作为 attack/hold 的派生状态，但必须经 `RuleEngine`。

并发建议：

- Rules Agent：兵种、围城、粮草。
- History / Data Agent：unit template 和地形数据。
- UI Agent：资源显示名和围城状态读法。

验收：

- 玩家可围攻州府/关隘，并看到围城状态。
- 粮草不足会影响行军或战斗。
- 生产项不显示 Panzer / Division。
- 攻击/占领仍以 hex 为权威。

### v5.4 - 唐宋 AI Agent 分层与指令迁移

目标：

- 把二战元帅/将军文案迁移为唐宋朝廷/枢密/节度使体系。
- 保留当前 `TheaterDirective -> ZoneDirective -> WarCommandExecutor` 地基。

建议改动：

1. 新增或改名显示：
   - `RulerAgent` -> 皇帝/国主层显示。
   - `MarshalAgent` -> 枢密/行营层显示。
   - `ZoneCommanderAgent` -> 节度使/方面主将显示。
2. `TacticName` 增加唐宋显示映射，短期可保留 raw case：
   - `standardAttack` -> 进军
   - `breakthrough` -> 破阵
   - `pincerMovement` -> 合围
   - `fireCoverage` -> 弓弩压制 / 器械攻城
   - `feint` -> 佯动
   - `guerrillaWarfare` -> 轻骑袭扰 / 断粮
   - `holdPosition` -> 固守
   - `elasticDefense` -> 退守
   - `defenseInDepth` -> 纵深设防
   - `lastStand` -> 死守城关
3. `TheaterDirectiveEnvelope` schema 增加：
   - `mandateIntent`
   - `courtPolicy`
   - `pacificationTargets`
   - `supplyPriorities`
4. `MarshalBattlefieldSummarizer` 增加唐宋摘要：
   - 国都/州府控制。
   - 粮道状态。
   - 围城状态。
   - 将领满意度。
   - 外交归附机会。
5. AI 面板展示：
   - 诏令/军议摘要。
   - 战区军令。
   - 目标州府。
   - 规则执行结果。

验收：

- 默认 AI 不再展示 Guderian、Rundstedt、Eisenhower 等二战人物。
- AI raw JSON 能解释唐宋目标。
- JSON 解码失败时安全 fallback。
- AI 仍不直接修改 `GameState`。

### v5.5 - 发布级主界面与地图视觉

目标：

- 把主游戏从调试面板升级为可发布的唐宋历史策略 UI。

建议改动：

1. `RootGameView` 第一屏：
   - 地图全屏。
   - 顶部 HUD：剧本名、回合、当前政权、天命/国威、粮草、钱帛、下一步。
   - 左/右侧紧凑信息面板：军队、州府、军令、朝廷、战报、AI。
2. `TerrainStyle`：
   - 山地/丘陵/森林/河流/城池/关隘/港口/粮仓统一风格。
   - 势力色改为印章/旗帜体系。
3. `UnitNode`：
   - 棋子用军旗/兵种符号。
   - 禁军、骑军、弓弩、器械、守军、水师有不同 icon 或图案。
4. Overlay：
   - 初始方面、动态方面、前线、部署、粮道、围城圈、计划箭头。
5. 面板术语：
   - Unit -> 军队。
   - Region -> 州府。
   - General -> 将领。
   - Economy -> 府库。
   - Diplomacy -> 外交。
   - AI -> 军议 / 诏令。
6. Accessibility：
   - icon-only button 必须有文本 label。
   - 颜色之外要有图案/符号区分。
   - Reduce Motion 下减少大幅动画。

验收：

- 默认主界面无主要二战文案。
- 地图和 UI 不读成单一米色或单一暗蓝。
- 文本不溢出按钮/面板。
- 地图图层切换可读。

### v5.6 - 外交、归附、天命与治理

目标：

- 让唐宋题材不只是军事换皮，形成统一战争的政治闭环。

建议改动：

1. `DiplomacyState` 迁移为多政权关系：
   - allied
   - tributary
   - neutral
   - hostile
   - atWar
   - submitting / negotiating
2. 新增或扩展：
   - `MandateState`
   - `LegitimacyScore`
   - `PacificationRecord`
   - `GovernancePolicy`
3. 归附规则：
   - 只有满足威望、兵临城下、关系、粮草、国都压力等条件，才能触发归附。
   - 归附改变政权关系和若干 region/controller 时必须经规则层记录，不能让 Agent 直接改。
4. 治理：
   - 州府民心、治安、税粮。
   - 过度征发降低民心或提高叛乱风险。
5. 事件：
   - 陈桥兵变开局合法性。
   - 吴越纳土概率。
   - 北汉求援辽。
   - 南唐守江。
   - 后蜀山道防御。

验收：

- 玩家可以通过军事或外交推进统一。
- 归附/外交记录可在 UI 查看。
- 天命/国威影响胜利。
- 外交 Agent 不绕过规则系统。

### v5.7 - 教程、剧本包装与可玩闭环

目标：

- 让首发剧本能被普通玩家理解和完成。

建议改动：

1. 新增轻量开局引导，但不要做 landing page：
   - 第 1 回合提示当前目标。
   - 高亮开封、太原、淮河、金陵、成都、杭州。
   - 指向“军令”“州府”“战报”入口。
2. 选择势力：
   - 首版至少 Song 可选。
   - 其他势力可设为 AI-only 或 advanced。
3. 战报：
   - 每回合总结：战斗、占领、围城、粮草、外交。
   - AI 军议摘要可读。
4. 存档/新局：
   - 保留 reset/new game。
   - 若已有持久化系统，再接入；没有则不强行新增。

验收：

- 新玩家能在 3 分钟内知道下一步做什么。
- 不需要读 README 才能进行第一场行动。
- 每回合结束后有可解释战报。

### v5.8 - 发布候选硬化

目标：

- 准备发布候选，清理残留、性能风险、文档口径和资源授权。

任务：

1. 玩家可见残留扫描：

```sh
rg -n "Germany|Allies|Ardennes|Bastogne|Panzer|Division|Guderian|German AI|Allied Player|Manpower|Industry|Supplies|NATO" WWIIHexV0 MapEditor README.md md
```

2. 数据检查：

```sh
jq empty WWIIHexV0/Data/tangsong_jianlong_960_scenario.json
jq empty WWIIHexV0/Data/tangsong_jianlong_960_regions.json
jq empty WWIIHexV0/Data/tangsong_unit_templates.json
jq empty WWIIHexV0/Data/tangsong_characters.json
```

3. Project / XML：

```sh
plutil -lint WWIIHexV0.xcodeproj/project.pbxproj
xmllint --noout WWIIHexV0.xcodeproj/xcshareddata/xcschemes/WWIIHexV0.xcscheme
```

4. 轻量 Swift parse：只对少量改动文件执行；若触发 SDK/SwiftUI/SpriteKit 依赖或变慢，停止并记录。
5. 需要发布前 build、XCTest、模拟器、Playwright/截图、性能测试时，必须由人工明确授权。
6. 资源授权清单：
   - icon。
   - 地图纹理。
   - 人物头像。
   - 音效/字体。
   - 任何生成资产的 prompt 和许可说明。

验收：

- 默认启动进入唐宋剧本。
- 主要 UI 无二战残留。
- AI deterministic fallback 可推进。
- 地图操作可读。
- 所有重测试未授权时明确写明未跑。

### v5.9 - 可发布版本收口

目标：

- 形成一个可以给外部试玩的版本。

发布定义：

- 首发剧本 `建隆元年：陈桥兵变与山河一统` 可完整游玩。
- 玩家至少可使用宋完成统一目标。
- 其他主要势力可由 AI 推进，不会静默卡死。
- 有清晰地图、军令、州府、府库、外交、战报、AI 军议。
- 有 macOS 主游戏入口或明确标记为后续目标。
- 有地图编辑器可维护数据。
- README 和 `md/flow/*` 反映唐宋当前架构，不再把项目定位写成二战主产品。
- `update_log.md` 记录版本、关键文件、轻量检查、未跑重测试和风险。

发布候选必须由 Agent C 验收：

- 核对实现是否满足本文件。
- 核对并发子 Agent 是否冲突。
- 核对 schema / public API / project 文件。
- 核对 UI 术语。
- 核对数据加载默认路径。
- 核对命令管线没有被绕过。

---

## 7. 并发整合检查

多子 Agent 完成后，主 Agent 必须做整合检查。没有完成冲突检查前，不得声称可合并。

必查：

- 同一文件是否被多个子 Agent 修改。
- 同一 public API、类型名、枚举 case、JSON key 是否出现分叉。
- `WWIIHexV0.xcodeproj/project.pbxproj` 是否存在重复文件引用、缺失文件引用或 UUID 冲突。
- `Data/*.json` 与 `ScenarioDefinition` / `RegionDataSet` 是否同步。
- `Command` / `ZoneDirective` / `WarCommandExecutor` / `RuleEngine` 管线是否仍统一。
- `hexToTheater`、`hexToFrontZone`、`regionToTheater` 权威边界是否被破坏。
- README、`md/flow/*`、阶段 prompt、`update_log.md` 是否描述同一版本状态。
- UI 是否还有默认二战可见文案。

建议命令：

```sh
rg -n "struct |enum |class |protocol |case |func " WWIIHexV0 MapEditor
rg -n "hexToTheater|hexToFrontZone|regionToTheater|ZoneDirective|WarCommandExecutor|RuleEngine" WWIIHexV0 md README.md AGENTS.md
rg -n "<<<<<<<|=======|>>>>>>>" WWIIHexV0 MapEditor md README.md update_log.md
```

这些命令只用于定位冲突线索，不等于功能测试。

---

## 8. 交付格式

每个实现 Agent 最终回复必须简洁说明：

1. 完成了什么。
2. 改了哪些关键文件。
3. 跑了哪些轻量检查，具体结果是什么。
4. 哪些重测试没跑，原因是什么。
5. 还剩什么风险或下一步。

若进行了 git stage / commit / push，只能在实际成功后按 Codex 桌面规范输出对应 directive。

---

## 9. 最终验收标准

达到“可发布”必须满足：

- 默认产品定位是唐宋历史策略游戏，不是二战游戏。
- 默认启动剧本是 `建隆元年：陈桥兵变与山河一统` 或人工确认的唐宋剧本。
- Hex 仍是战术权威。
- Region 仍是战略聚合层。
- `regionToTheater` 不被运行时推进污染。
- `hexToTheater` / `hexToFrontZone` 仍按单 hex 推进。
- AI 和玩家仍走统一命令管线。
- 多政权回合不依赖 `Faction.opponent`。
- 玩家可见 UI 无主要二战残留。
- 首发地图美术和 UI 达到可试玩展示，不是调试面板。
- AI 军议、战报和 directive 结果可解释。
- 轻量检查有具体命令和结果。
- 未跑重测试有明确原因。
