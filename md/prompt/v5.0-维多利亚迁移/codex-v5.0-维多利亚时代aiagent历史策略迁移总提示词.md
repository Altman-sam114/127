# Codex v5.0-v5.9 任务提示词：从 WWIIHexV0 迁移为维多利亚时代 AI Agent 历史策略游戏

> 本文是交给后续实现 Agent 的总提示词。它不是本轮代码实现记录，而是维多利亚时代迁移的产品目标、架构边界、版本路线、并发子 Agent 分工和发布级验收标准。执行前必须先读 `AGENTS.md`、`update_log.md`、`md/flow/flow.md`、`md/flow/flowchart.md`、`md/test/test.md` 和本文件。

---

## 0. 当前项目判断

你接手的是 `WWIIHexV0`，当前代码不是早期空壳，而是一个已经包含 hex 战棋、战略 region、动态战区、前线、部署、经济、外交草案、将领、元帅、统治者预留、macOS 主游戏 target 和 macOS 地图编辑器方向的 Swift + SwiftUI + SpriteKit 工程。

当前真实主链路是：

```text
MapEditor / JSON 数据
  -> DataLoader
  -> GameState
  -> HexTile.controller + Division.coord
  -> Region 聚合
  -> EconomyState 收入 / 生产 / 补员
  -> DiplomacyState 草案
  -> Initial Theater snapshot + runtime hexToTheater
  -> FrontLine 动态 hex 接触
  -> WarDeployment hexToFrontZone + FRONT/DEPTH/GARRISON
  -> MarshalAgent / TheaterDirective JSON
  -> TheaterDirectiveDecoder / TheaterDirectiveCompiler
  -> ZoneDirective
  -> WarCommandExecutor
  -> RuleEngine
  -> StrategicStateSynchronizer
  -> UI / SpriteKit / 日志 / WarDirectiveRecord
```

当前源码和文档中必须尊重的事实：

- `HexTile.controller` 和 `Division.coord` 是战术层权威。
- `RegionNode.controller` 是从 region 内 hex controller 聚合出来的战略快照。
- `regionToTheater` 是初始/基础战区归属，不是运行时推进权威。
- `hexToTheater` 是运行时动态战区权威。
- `hexToFrontZone` 是部署层动态归属权威。
- 玩家、AI、聊天命令和 MockAI 都必须落到 `Command` / `ZoneDirective`，再经 `WarCommandExecutor`、`CommandValidator`、`RuleEngine` 执行。
- Legacy Agent D 管线保留作回归参考，默认战争 AI 主路径不得退回旧管线。
- 当前 `Faction` 仍只有 `germany/allies`，`Faction.opponent`、`GamePhase.germanAI/alliedPlayer`、`DataLoader` 的 `playerFaction/aiFaction`、`CommandValidator` 的阶段判断仍强绑定二元对立。
- 当前单位模型叫 `Division`，兵种仍是 `tank/motorizedInfantry/infantry/artillery`。
- 当前经济模型仍是 `manpower/industry/supplies`，生产项仍有 `panzerDivision` 等二战语义。
- 当前默认数据和 UI 仍有阿登、Germany、Allies、Bastogne、Panzer、Division、German AI、Allied Player、Manpower、Industry、Supplies 等玩家可见残留。
- 当前工作树可能混有 v0.4、v0.5、v0.7、v0.8、v0.9、v1.0、v1.1、三国迁移、拿战迁移、隋唐迁移、明末迁移等未提交改动。任何实现前必须做分支和文件冲突审查，不能回滚他人改动。

迁移目标不是“换几段文案和颜色”，也不是直接做一个完整全球沙盒。目标是把现有工程逐步迁移为一款可发布演示的 AI Agent 驱动维多利亚时代历史策略游戏，首发先做范围可控的剧本，随后扩展到全球工业化与外交博弈。

---

## 1. 最终产品目标

暂定产品名：`蒸汽帝国 Agent`。英文工作名可用 `Steam & Empire Agent Strategy`。最终名称由人工确认，避免与现有商业游戏标题形成直接混淆。

时代范围：约 1837-1901 年的维多利亚时代。第一版不要试图覆盖完整全球七十年，而是用一个可玩、可调、可发布的局部危机剧本证明系统。

### 1.1 首发默认剧本

首发推荐剧本：

```text
id: black_sea_crisis_1853
displayName: 黑海危机 1853
时间范围：1853-1856 克里米亚战争的抽象战役窗口
地图范围：黑海、克里米亚、多瑙河口、巴尔干北缘、高加索西缘、君士坦丁堡方向
主要势力：俄罗斯帝国、奥斯曼帝国、大英帝国、法兰西第二帝国、奥地利帝国、撒丁王国、中立小邦/地方势力
首版规模：120-220 个 hex，35-70 个 region，8-16 个战区/军区/远征军防区
首版回合：18-36 回合，代表季度或战役阶段
```

选择这个剧本的原因：

- 它在维多利亚时代早期，能同时体现大国外交、远征军、港口、海上补给、堡垒围攻、铁路/电报早期影响、舆论和财政压力。
- 地图范围可控，不必第一版做全球全量省份。
- 多方 AI Agent 差异明显：俄罗斯追求黑海和巴尔干影响，奥斯曼保卫海峡和多瑙防线，英法进行远征和海上封锁，奥地利摇摆施压，撒丁寻求参战换取外交利益。
- 现有 hex / region / theater / front / deploy 层可以复用，海军和全球市场可以先用 off-map 影响层表达。

后续可扩展剧本：

- `revolutions_1848`：欧洲革命与保守秩序危机，偏内政和外交。
- `indian_rebellion_1857`：英属印度危机，需谨慎处理殖民题材表达。
- `italian_unification_1859`：意大利统一战争，适合外交和战役结合。
- `american_civil_war_1861`：美国内战，适合工业、铁路、战争经济。
- `franco_prussian_1870`：普法战争，适合铁路动员、总参谋部、战役节奏。
- `scramble_for_africa_1884`：殖民竞逐，偏外交、海权、补给与事件。
- `global_1836_sandbox`：长期目标，不是首发目标。

### 1.2 首发玩家体验

最终首发体验应达到以下效果：

1. 打开应用后直接进入可玩的维多利亚时代危机地图，不做营销落地页。
2. 玩家可选择一个大国或默认扮演一个势力；首发若只能保证一个玩家势力，默认玩家建议为奥斯曼帝国或大英帝国，因为它们同时有防御、远征、外交、财政和海权决策。
3. 其他势力由 AI Agent 驱动，且不同势力的行为应能被玩家看出差异。
4. 地图以 hex 为战术权威，以省份/州/战略港口/工业区为 region 聚合层，以军区/远征军/方面军/殖民辖区为 AI 调度层。
5. 玩家既能微操军队，也能通过内阁、外交部、陆军部、海军部、总司令和殖民总督面板下达宏观命令。
6. AI 不直接改 `GameState`。君主、首相、内阁、外交大臣、战争大臣、财政大臣、总参谋部、远征军司令、殖民总督、报界舆论等 Agent 只能输出结构化 directive，经 decoder / validator / compiler 后落到规则系统。
7. UI 视觉必须摆脱当前调试原型感，形成维多利亚时代战略桌面质感：雕版世界地图、铁路、电报线、港口、煤站、报纸战报、内阁文件夹、外交照会、议会压力、军令电报、红蓝铅笔推进箭头。
8. 第一屏核心是地图和行动，不是说明文字。玩家进入后应立即看见当前国家、回合时间、国库、工业/补给、威望、战争支持、活跃外交危机、可行动军队和内阁/军令入口。
9. 发布前主游戏 UI、默认数据、日志和玩家可见面板不得残留主要二战文案：Germany、Allies、Ardennes、Bastogne、Panzer、tank、motorized、WWII、Division、German AI、Allied Player、Manpower、Industry、Supplies 等不应出现在默认主游戏 UI 中。源码兼容名可分阶段保留，但必须在文档声明。
10. 发布级演示必须有完整闭环：开局、选择势力、查看省份/港口/工业区、选择军队、铁路/道路行军、战斗、围城、补给/弹药/财政消耗、外交危机、AI 回合、内阁/将领/报界决策复盘、胜负判断。
11. 发布级演示必须能看出维多利亚时代特色：工业动员、铁路补给、港口与海权、外交照会、列强干预、国会/舆论压力、战争目标、威望和财政约束。

---

## 2. 迁移总原则

### 2.1 保留的工程骨架

必须保留并迁移这些成熟资产：

- Hex 坐标、移动、攻击、占领、视野、补给落点的战术权威。
- Region 作为战略聚合层，不替代 hex。
- 动态战区、前线、部署层从 hex 和单位位置派生的关系。
- `Command` / `ZoneDirective` / `WarCommandExecutor` / `RuleEngine` 统一执行管线。
- `WarDirectiveRecord`、`AgentDecisionRecord`、`RulerDecisionRecord` 等审计/复盘记录。
- MapEditor 的稀疏 hex、region、theater、unit 编辑与导出能力。
- iOS 主游戏、macOS 主游戏、macOS 地图编辑器三个方向。
- 当前模拟 LLM / MockAI fallback 思路：真实模型不可用时仍能 deterministic 地推进游戏。
- 当前轻量检查规范和禁止重测试规则。

### 2.2 必须替换或抽象的二战语义

按版本逐步替换这些题材绑定点：

- `Faction.germany/allies`：迁移为多国家/多势力体系。短期可以扩展 enum，长期目标是数据驱动 `PowerId` / `CountryId` / `Faction` 兼容桥。
- `Faction.opponent`：维多利亚时代不是二元敌我，必须来自 `DiplomacyState`、`PowerRelation`、`WarRelationRules` 或 `DiplomaticPlayState`。
- `GamePhase.germanAI/alliedPlayer`：迁移为通用回合阶段，例如 `humanAction` / `aiAction` / `resolution` / `diplomacyResolution`，或基于 `activeFaction` 的解释层。
- `Division` 的玩家可见语义：迁移为军团、师、旅、远征军、殖民旅、守备队。源码可短期保留兼容名，但 UI 不显示二战 Division 语义。
- `ComponentType.tank/motorizedInfantry/infantry/artillery`：迁移为线列步兵、近卫步兵、骑兵、炮兵、工兵、非正规军、殖民部队、补给纵队等。
- `EconomyResources.manpower/industry/supplies`：短期显示映射为人口/国库/补给或兵源/财政/弹药粮秣；长期拆为国库、工业产能、煤、铁、弹药、粮食、运输力、船运量、行政力。
- `ProductionKind.panzerDivision` 等：迁移为动员步兵师、炮兵旅、骑兵旅、工兵队、补给车队、港口补给、铁路工程、要塞修筑、舰队整备。
- `Theater` UI：显示为军区、远征军区、殖民辖区、方面军。
- `FrontZone` UI：显示为作战区、防线、远征军防区。
- `MarshalAgent`：迁移为总参谋部、陆军大臣、远征军总司令或战区司令 Agent。
- `RulerAgent`：迁移为君主/首相/内阁首脑 Agent；不能直接执行底层命令。
- `GeneralData`：迁移为将领、外交官、大臣、总督、实业家等人物数据，含统率、组织、外交、财政、声望、派系、谨慎/冒险倾向。
- 阿登 JSON：迁移为维多利亚时代剧本 JSON。
- 地图编辑器术语：省份/州、军区、远征军、港口、铁路、电报线、煤站、堡垒、工业节点。

### 2.3 不能做的事

- 不要一次性大规模重命名所有类型再凭感觉修编译。先建立兼容层和迁移合同，再分版本替换。
- 不要让任何 Agent 直接修改 `HexTile.controller`、`Division.coord`、`regionToTheater`、`hexToTheater`、`hexToFrontZone` 或经济账本。
- 不要绕过 `WarCommandExecutor`、`CommandValidator`、`RuleEngine`。
- 不要删除 Legacy Agent D；只隔离和保留回归参考。
- 不要把 region 当战术权威；进军、攻击、围城、占领仍必须落到 hex。
- 不要第一版就做完整世界地图、完整全球市场、完整海军战术、完整殖民系统、完整意识形态政治、完整 1837-1901 全时间线。
- 不要把殖民扩张写成无成本的正面叙事。维多利亚时代题材必须呈现殖民、财政、舆论、外交和地方反抗的代价，不写现代仇恨表达。
- 不要使用受版权保护的游戏素材、影视剧照、商业人物头像或未经授权地图。可使用自制、生成、公共领域或明确授权素材。
- 不要硬编码真实 LLM API key、模型路径、网络端点。真实模型接入必须单独版本，有 deterministic fallback。
- 未获人工授权，不跑 Xcode / XCTest / 模拟器 / macOS app 启动 / Probe / Smoke / Stage Regression / Dynamic Theater Regression / Full / 性能测试。

---

## 3. 维多利亚时代核心设计合同

### 3.1 势力、国家和集团

短期可以保留源码 `Faction` 名称作为兼容层，但目标语义改为“规则控制方”。首发建议至少支持：

```text
britain       大英帝国
france        法兰西第二帝国
russia        俄罗斯帝国
ottoman       奥斯曼帝国
austria       奥地利帝国
sardinia      撒丁王国
neutral       中立小邦/地方势力
legacyGermany 仅用于旧数据兼容，可不暴露 UI
legacyAllies   仅用于旧数据兼容，可不暴露 UI
```

长期应迁移为数据驱动：

```text
PowerId / CountryId
  -> displayName
  -> governmentType
  -> capitalRegionId
  -> greatPowerRank
  -> prestige
  -> treasury
  -> rulingInterest
  -> primaryCulture / acceptedCultures
  -> aiProfile
  -> color / flag / mapPattern
```

原则：

- `Faction` 是规则层控制方；`CountryProfile` / `PowerProfile` 是政治实体资料。
- `HexTile.controller` 可为 `nil` 或 `neutral`，不能 fallback 给任意大国。
- `RegionNode.owner/controller/coreOf` 必须支持多方和中立，不再假设两个阵营。
- 敌我判断不能写 `faction != otherFaction` 就等价为可攻击；是否可攻击必须结合外交关系、战争状态、通行权、保护国、停战、远征协定、殖民冲突和中立规则。
- 大国集团不是永久阵营。英法可协同对俄，也可能在别的剧本竞争；奥地利可施压但不直接参战。

### 3.2 地图层

现有 hex / region / theater / front / deploy 分层继续有效，维多利亚语义建议为：

```text
Hex
  -> 战术格：城市、港口、铁路节点、要塞、山地、河流、道路、海岸、煤站

Region
  -> 省份/州/战略节点：人口、工业、财政、补给、港口、铁路、威望点、民族/宗教/治安标签

Theater
  -> 军区/远征军区/殖民辖区：克里米亚远征军、多瑙军区、高加索军区、君士坦丁堡防区

FrontLine
  -> 前线接触：真实动态战区相邻 hex 形成战线，不等于省界

WarDeployment
  -> 前线部队、预备队、驻防/要塞守军
```

关键边界不变：

- 占一个 hex，只推进该 hex 的 `hexToTheater` / `hexToFrontZone`。
- 不允许占一个省份节点就直接改整个 `regionToTheater`。
- 围城、港口登陆、铁路推进、侧翼包抄都必须通过具体 hex 位置表达。
- 首版海军不做完整战术舰队格斗。海权先通过港口、海上补给、封锁状态、远征军登陆许可和 off-map sea lane 表达。

### 3.3 军事规则层

首发规则要可解释，不追求复杂仿真。建议迁移：

- `strength` 继续代表战斗力，不恢复 organization。
- 可新增或复用轻量字段表达 `morale`、`fatigue`、`entrenchment`，但不要第一轮写复杂状态机。
- `supplyState` 显示为补给/弹药/粮秣状态：充足、紧张、断供/被围。
- `RetreatMode.hold/retreatable` 显示为固守/可撤。
- 步兵：稳定、适合守线和攻城，铁路动员后补充快。
- 近卫：强战斗力和高士气，高维护费。
- 骑兵：侦察、追击、平原机动强，对要塞/山地/堑壕弱。
- 炮兵：围城、压制和火力准备强，机动差，弹药消耗高。
- 工兵：修铁路、破坏铁路、围城、渡河和要塞攻坚加成。
- 非正规军/地方武装：维护低、地形适应强，正面战斗和补给组织弱。
- 殖民部队：远征消耗低或适合特定地形，但政治/舆论风险要在后续经济政治层表达。
- 堑壕/要塞：首版可作为地形与 region 防御 modifier，不要上来做逐格工事系统。

### 3.4 经济、工业和社会层

当前 `EconomyState` 是 faction 级资源总账，可分阶段迁移：

短期显示映射：

```text
manpower -> 兵源 / 可动员人口
industry -> 国库 / 工业产能
supplies -> 补给 / 弹药粮秣
```

中期扩展：

```text
treasury      国库
industrialCap 工业产能
coal          煤
iron          铁
arms          军械
ammunition    弹药
food          粮食
convoys       船运量
railCapacity  铁路运输力
adminCapacity 行政力
prestige      威望
warSupport    战争支持
infamy        国际恶名
```

Region 经济标签建议：

- `population`：人口规模，用于兵源和税收。
- `industryLevel`：工业化程度。
- `railLevel`：铁路等级，影响移动、补给、动员速度。
- `portLevel`：港口等级，影响远征补给和海上贸易。
- `coalOutput`、`ironOutput`、`grainOutput`：首版可先用抽象数字。
- `unrest`：治安/动荡。
- `nationalityTags`：民族/文化标签，后置，不要首版过度复杂化。

首发经济闭环要求：

- 每回合按真实控制的 region 聚合国库、兵源、补给。
- 远征军、炮兵、近卫和海上补给消耗更高。
- 铁路/港口影响补给和部署，不直接改变 hex 占领权。
- 玩家可下达“动员”“修铁路”“整备远征军”“补充弹药”“修筑要塞”等命令，最终仍走 `Command` 或扩展后的统一命令系统。

### 3.5 外交和危机层

维多利亚时代迁移必须把外交当作主玩法，不只是状态面板。首发可做轻量版：

```text
DiplomaticPlay
  -> issuerPowerId
  -> targetPowerId
  -> regionId / strategicRegionId
  -> warGoal
  -> escalation
  -> backers
  -> opposingBackers
  -> deadlineTurn
  -> outcome
```

外交状态建议：

- `allied`
- `coBelligerent`
- `neutral`
- `inSphere`
- `protectorate`
- `guaranteed`
- `hostile`
- `atWar`
- `truce`
- `militaryAccess`
- `blockaded`

外交行动建议：

- 发出照会。
- 要求撤军。
- 支持一方。
- 提供贷款/补给。
- 要求通行权。
- 宣布封锁。
- 调停停战。
- 扩大战争目标。

所有外交行动也必须通过 directive / command / validator 进入状态，不能让 UI 或 Agent 直接改外交关系。

### 3.6 AI Agent 层

维多利亚时代 AI Agent 的重点是多角色协同、利益冲突和可解释决策。推荐层级：

```text
HeadOfStateAgent 君主/皇帝/苏丹/总统
  决定国家姿态、战争承受度、威望底线

PrimeMinisterAgent / CabinetAgent 首相/内阁
  平衡财政、舆论、外交、战争目标

ForeignMinisterAgent 外交大臣
  处理照会、结盟、调停、通行权、支持外交危机

WarMinisterAgent 陆军部 / 战争大臣
  分配兵源、动员、远征军、要塞、补给优先级

AdmiraltyAgent 海军部
  首版只输出封锁、护航、远征补给、港口优先级，不直接控制战术海战

TreasuryAgent 财政部
  控制预算、贷款、军费、铁路投资

IndustrialistAgent 实业/铁路派系
  推动铁路、煤铁、军工和市场建设，但可能与财政/外交目标冲突

GovernorAgent 总督/殖民官
  处理殖民辖区治安、补给和地方招募

GeneralStaffAgent 总参谋部
  把国家目标转为 theater / zone 目标

TheaterCommanderAgent 战区司令
  输出 ZoneDirective，仍走 WarCommandExecutor

PressAgent 报界/舆论
  只输出舆论压力、战争支持变化建议或事件，不直接改状态
```

所有上游 Agent 输出必须是 Codable JSON directive，不能直接执行状态修改。安全执行链路为：

```text
Agent JSON
  -> Decoder / Validator
  -> CabinetDirectiveEnvelope / DiplomaticPlayDirective / IndustrialDirective / TheaterDirectiveEnvelope / ZoneDirective
  -> Compiler
  -> Command / WarCommandExecutor
  -> RuleEngine
  -> WarDirectiveRecord / AgentDecisionRecord / DiplomacyRecord / EconomyRecord
```

示例 JSON 结构方向：

```json
{
  "schemaVersion": 50,
  "issuerId": "cabinet_britain_1853",
  "turn": 4,
  "powerId": "britain",
  "strategicIntent": "Preserve Ottoman access to the Straits while avoiding uncontrolled escalation.",
  "directives": [
    {
      "id": "cabinet_britain_4_black_sea",
      "domain": "diplomacy",
      "priority": 90,
      "action": "support_diplomatic_play",
      "targetPowerId": "ottoman",
      "opposingPowerId": "russia",
      "regionId": "region_black_sea",
      "rationale": "Russian pressure threatens naval access and prestige."
    },
    {
      "id": "cabinet_britain_4_expedition",
      "domain": "military",
      "priority": 75,
      "action": "prepare_expeditionary_force",
      "theaterId": "theater_crimea_expedition",
      "budgetLimit": 3,
      "rationale": "Prepare limited force before escalation deadline."
    }
  ]
}
```

要求：

- schemaVersion、issuerId、turn、power/faction、目标 id、region/theater/zone id 必须校验。
- 无效 JSON、未知 id、非法关系、超预算和越权行动必须拒绝或降级，并写入记录。
- 真实 LLM 不可用时必须有 deterministic fallback。
- Agent 的“个性”不能绕过规则，只能影响优先级、风险阈值、目标排序、预算倾向和 fallback 策略。

---

## 4. 多 Agent 并发工作流

主 Agent 负责总体架构、接口合同、冲突整合和最终验收。子 Agent 只能在明确边界内并发，不得同时改同一 public API 或同一文件。

### 4.1 并发前主 Agent 必做

1. 读完 `AGENTS.md`、`update_log.md`、`md/flow/flow.md`、`md/flow/flowchart.md`、`md/test/test.md` 和本文件。
2. 审计工作树：

```sh
git branch --show-current
git status --short
rg -n "Germany|Allies|germany|allies|Ardennes|ardennes|Bastogne|Panzer|tank|motorized|Division|Guderian|Montgomery|German AI|Allied Player|Manpower|Industry|Supplies|Faction\\.opponent|germanAI|alliedPlayer" WWIIHexV0 MapEditor README.md md
rg -n "enum Faction|enum GamePhase|struct Division|enum ComponentType|EconomyResources|ProductionKind|DiplomacyState|CountryProfile|GeneralData|ZoneDirective|WarCommandExecutor|RuleEngine|TurnManager|AppContainer" WWIIHexV0
```

3. 写出本轮实际版本目标、非目标和文件边界。
4. 定义公共接口合同。没有接口合同前，不要让多个子 Agent 同时改 `Core/`、`Commands/`、`Rules/`。
5. 明确 `WWIIHexV0.xcodeproj/project.pbxproj` 只能由主 Agent 或唯一指定的 Project Agent 修改。
6. 若工作树已有用户/其他 Agent 改动，先记录相关文件，不得回滚。
7. 明确默认不跑重测试；只能跑 `md/test/test.md` 允许的轻量检查。

### 4.2 推荐子 Agent 分工

每轮最多并发 3-5 个子 Agent。优先减少冲突，不追求数量。

#### Audit / Docs / QA Agent

范围：

- `README.md`
- `update_log.md`
- `md/flow/`
- `md/test/test.md`
- `md/prompt/v5.0-维多利亚迁移/`

职责：

- 扫描二战硬编码、二元阵营、旧 phase、旧资源、旧单位。
- 维护迁移词汇表、版本审计表、风险清单。
- 更新 flow / flowchart，使它们描述当前真实代码。
- 记录轻量检查和未跑重测试原因。

禁止：

- 不改 Swift 业务逻辑。
- 不把未验证运行时行为写成已验证。

#### Data / Scenario Agent

范围：

- `WWIIHexV0/Data/*.json`
- `WWIIHexV0/Data/ScenarioDefinition.swift`
- `WWIIHexV0/Data/RegionDataSet.swift`
- `WWIIHexV0/Data/DataLoader.swift`

职责：

- 迁移剧本、地图、地形、兵种、人物、国家/势力数据。
- 建立 `black_sea_crisis_1853_scenario.json`、`black_sea_crisis_1853_regions.json`、`victorian_powers.json`、`victorian_unit_templates.json`、`victorian_personas.json`、`victorian_terrain_rules.json`。
- 保证 JSON key 稳定，id 使用 ASCII，例如 `power_britain`、`region_sevastopol`、`theater_crimea_expedition`、`person_palmerston`。
- 中文只放在 `displayName`、`localizedName`、`biography`、`description` 等展示字段。
- 如果需要历史细节校准，可查可靠资料并在阶段文档记录来源；不要把不确定史实写成规则硬条件。

禁止：

- 不改 `RuleEngine`。
- 不改 UI。
- 不改 project 文件，除非主 Agent 明确指定。

#### Core / Rules Agent

范围：

- `WWIIHexV0/Core/`
- `WWIIHexV0/Commands/`
- `WWIIHexV0/Rules/`

职责：

- 将二元阵营、二战单位、二战补给经济迁移为维多利亚多国家规则抽象。
- 保持 `Command` / `ZoneDirective` / `WarCommandExecutor` / `RuleEngine` 统一入口。
- 落地铁路补给、港口补给、围城、堑壕/要塞、炮兵、远征军维护时必须先给最小可解释版本。
- 处理 neutral 不再 fallback 到 allies 的历史债。

禁止：

- 不改 SpriteKit/SwiftUI 视觉。
- 不新增真实网络 LLM 调用。
- 不用复杂状态机替代已有命令管线。

#### Economy / Society Agent

范围：

- `WWIIHexV0/Core/EconomyState.swift`
- `WWIIHexV0/Rules/EconomyRules.swift`
- `WWIIHexV0/Commands/Command.swift`
- `WWIIHexV0/Rules/CommandValidator.swift`
- `WWIIHexV0/Rules/CommandExecutor.swift`
- 必要时只读 `Region.swift`、`DataLoader.swift`

职责：

- 把 `manpower/industry/supplies` 显示和语义迁移为兵源/国库/补给，再逐步扩展工业、煤铁、军械、铁路运输力。
- 设计动员、铁路建设、港口补给、远征军维护、贷款/预算的最小规则闭环。
- 所有经济行动仍必须通过统一命令和校验。

禁止：

- 不直接改 `HexTile.controller` 或 `Division.coord`。
- 不让经济规则直接吞掉外交和战争规则边界。

#### Diplomacy / Politics Agent

范围：

- `WWIIHexV0/Core/DiplomacyState.swift`
- `WWIIHexV0/Agents/RulerAgent.swift`
- 可新增外交 directive 文件，但必须经主 Agent 同意公共接口
- 只读 `TurnManager.swift`、`AppContainer.swift`

职责：

- 扩展国家、集团、外交关系、外交危机、战争目标、威望、恶名、战争支持。
- 设计外交行动的 decoder / validator / compiler 合同。
- 确保外交状态影响 canAttack / canEnter / canSupport，但不绕过 hex 占领。

禁止：

- 不直接执行宣战、割地、占领等状态变更，必须走命令和校验。
- 不把所有国家硬塞进 `Faction` 后再写大量 switch。

#### AI Agent

范围：

- `WWIIHexV0/Agents/`
- `WWIIHexV0/Turn/`
- 只读 `Core/Commands/Rules`

职责：

- 设计君主、首相、内阁、外交大臣、战争大臣、财政大臣、海军部、总参谋部、总督、战区司令、报界舆论 Agent 分层。
- 所有输出必须是 JSON / Codable directive。
- 上游 Agent 只能调整战略姿态、目标优先级、预算倾向、外交选择或 directive envelope，不能直接执行底层命令。
- MockAI 必须有 deterministic fallback，不依赖真实模型。

禁止：

- 不直接改 `GameState`。
- 不绕过 `WarCommandExecutor`。
- 不把真实 API key 或模型路径写进仓库。

#### UI / SpriteKit / Art Direction Agent

范围：

- `WWIIHexV0/UI/`
- `WWIIHexV0/SpriteKit/`
- `Assets.xcassets` 如存在或由主 Agent 创建

职责：

- 建立维多利亚时代视觉系统：地图、铁路、港口、报纸、外交照会、内阁、军令电报、舆论压力、工业预算。
- 建立共享设计 token：颜色、字体、材料、间距、圆角、线宽、动效。
- 主界面必须地图优先，信息密度高但不杂乱。
- 保证 iOS/macOS 触控/鼠标目标和可读性。

要求：

- 44pt 触控目标。
- 使用 SwiftUI Dynamic Type，避免硬编码小字号。
- icon-only button 必须有文本 label 或 accessibility label。
- 颜色不能是单一米色/棕色/暗蓝主题；维多利亚风格可以有纸张底色，但必须用海军蓝、朱红、铜色、钢灰、铁路黑、国家旗色和地图绿/蓝形成层次。
- 不能把 UI 做成大卡片堆砌，第一屏应是地图、紧凑 HUD、侧栏 inspector 和底部战报/电报。
- 不在 SwiftUI body 内做重复排序、过滤、JSON 格式化。
- 大列表用 `LazyVStack` / `LazyHStack`。
- 不引入第三方框架，除非人工确认。

禁止：

- 不把规则写进 View。
- 不让 SpriteKit 直接改 `GameState`。

#### MapEditor Agent

范围：

- `MapEditor/`
- 只读 `Data/` schema

职责：

- 将编辑器术语迁移为地块、省份/州、军区/远征区、军队/人物。
- 支持铁路、电报线、港口、煤站、堡垒、城市、要塞、海岸和初始人物/国家归属。
- 保持导出产物仍能被 `DataLoader` 读取。

禁止：

- 不破坏主游戏 JSON 加载格式。
- 不把编辑器底图写入游戏 JSON。

#### Project / Integration Agent

范围：

- `WWIIHexV0.xcodeproj/project.pbxproj`
- 资源 target membership
- 分支整合记录

职责：

- 唯一负责 project 文件变更。
- 检查重复文件引用、缺失引用、UUID 冲突、resource phase 是否包含新 JSON。
- 在多 Agent 完成后执行文件级冲突、public API、schema、文档口径整合审查。

禁止：

- 不改业务逻辑，除非主 Agent 明确授权。

### 4.3 并发整合规则

子 Agent 完成后，主 Agent 必须检查：

- 是否多个子 Agent 改了同一文件。
- 是否出现 public API 分叉。
- 是否出现 JSON schema 分叉。
- 是否出现 `Faction`、`PowerId`、`CountryId`、`BlocId`、`DiplomaticBlocId` 五套概念混乱。
- 是否出现 `project.pbxproj` 重复引用、缺失引用或 UUID 冲突。
- 是否出现 README、`md/flow/*`、阶段记录口径不一致。
- 是否有人绕过 `RuleEngine` 修改状态。
- 是否把 `regionToTheater`、`hexToTheater`、`hexToFrontZone` 的权威边界写乱。
- 是否把外交、经济、海军、殖民事件直接写成无校验状态变更。

没有完成这些检查前，不得声称“多 Agent 工作可合并”。

---

## 5. 版本路线

### v5.0：迁移审计、产品合同和维多利亚术语层

建议分支：`v5.0-victorian-audit-contract`

目标：

- 建立维多利亚迁移的工程合同。
- 找出所有二战硬编码、二元阵营假设、旧 phase 和 UI 残留。
- 定义首发剧本、最终体验、术语映射、版本边界和并发 Agent 协作方案。
- 不急着实现完整维多利亚玩法。

范围：

- 新增或更新阶段记录：`md/prompt/v5.0-维多利亚迁移/v5.0_audit_and_contract.md`。
- 新增迁移词汇表和命名约定：
  - `Faction` 当前源码兼容名，目标语义为规则控制方。
  - `PowerId` / `CountryId` 为政治实体 id。
  - `Division` 当前源码兼容名，目标显示为军团/旅/远征军/部队。
  - `Theater` 显示为军区/远征军区。
  - `Region` 显示为省份/州/战略节点。
  - `FrontZone` 显示为作战区/防线。
  - `Supply` 显示为补给/弹药/粮秣。
  - `Production` 显示为动员/军工/铁路/港口/要塞工程。
- 抽出 UI 显示名，不要让主要面板继续硬编码 Ardennes、Germany、Allies。
- 记录所有必须在 v5.1-v5.5 处理的硬编码点。

推荐并发：

- Docs / QA Agent：硬编码扫描、审计表、术语表。
- UI Agent：只读定位 UI 硬编码，不实现大 UI。
- Rules Agent：只读定位 `Faction.opponent`、二元 switch、二战兵种耦合。
- Data Agent：只读定位阿登数据入口和 JSON schema 限制。

验收：

- 有完整审计清单。
- 有维多利亚迁移词汇表。
- 有版本拆分和风险清单。
- 没有大范围重命名导致不确定风险。

轻量检查：

- 文档尾随空白检查。
- 冲突标记扫描。
- 不跑 Xcode / XCTest / 模拟器。

### v5.1：多国家、通用回合、外交关系和敌我判断

建议分支：`v5.1-victorian-powers-turns-diplomacy`

目标：

- 从二元 `germany/allies` 迁移到维多利亚多国家架构。
- 首版至少支持 Britain、France、Russia、Ottoman、Austria、Sardinia、Neutral。
- 移除主路径对 `Faction.opponent` 和固定 `germanAI/alliedPlayer` 的依赖。
- 保持旧阿登数据可兼容加载或有明确 legacy fallback。

设计建议：

1. 审计 `Faction` 的所有使用点。
2. 短期发布优先可先扩展 `Faction` enum，保留 `germany/allies` 作为 legacy case。
3. 新增或迁移 `PowerProfile` / `CountryProfile`，把 display name、旗色、首都、政府、AI 配置放进数据。
4. 建立统一敌我判断：
   - `canAttack(attacker:target:state:)`
   - `isHostile(lhs:rhs:state:)`
   - `isFriendly(lhs:rhs:state:)`
   - `canEnterTerritory(faction:controller:state:)`
   - `canSupportDiplomaticPlay(power:play:state:)`
5. `DiplomacyState` 支持基础关系：allied、coBelligerent、neutral、hostile、atWar、truce、militaryAccess。
6. 通用回合顺序建议：
   - `turnOrder: [Faction]`
   - `activeFaction`
   - `isHumanControlled(faction:)`
   - `shouldRunAI(for:)`
   - 不再用德国/盟军阶段名决定谁能行动。
7. 中立地块/省份不应被错误算给任何大国。

推荐文件：

- `WWIIHexV0/Core/Faction.swift`
- `WWIIHexV0/Core/GamePhase.swift`
- `WWIIHexV0/Core/DiplomacyState.swift`
- `WWIIHexV0/Core/GameState.swift`
- `WWIIHexV0/Data/ScenarioDefinition.swift`
- `WWIIHexV0/Data/DataLoader.swift`
- `WWIIHexV0/Rules/CommandValidator.swift`
- `WWIIHexV0/Rules/OccupationRules.swift`
- `WWIIHexV0/Rules/SupplyRules.swift`
- `WWIIHexV0/Rules/StrategicStateSynchronizer.swift`
- `WWIIHexV0/Turn/TurnManager.swift`
- `WWIIHexV0/App/AppContainer.swift`

推荐并发：

- Rules Agent：`Faction`、外交关系和敌我判断迁移。
- Data Agent：势力 profile JSON 草案。
- AI Agent：通用 AI 回合编排影响评估。
- Docs / QA Agent：文档和冲突扫描。

验收：

- 多国家可以被 JSON 表达。
- 敌我判断不再依赖 `.opponent`。
- `AppContainer` 不再只为 `.germany` 跑 AI。
- 中立地块/region 不会 fallback 到 `.allies` 或任意大国。
- `CommandValidator` 对玩家与 AI 仍对称。

轻量检查：

- 改 JSON 跑 `jq empty`。
- 对直接改动且可单文件 parse 的 Swift 文件运行 `swiftc -parse`；如果 SwiftUI/SpriteKit/跨文件依赖导致不可行，停止并记录。
- `plutil -lint` 仅在 project 文件变更时运行。

### v5.2：黑海危机地图、剧本数据和地图编辑器迁移

建议分支：`v5.2-victorian-black-sea-scenario`

目标：

- 建立第一张可玩维多利亚时代剧本地图。
- 保留 MapEditor 导出链路。
- 默认新局加载黑海危机剧本，而不是阿登。

默认剧本建议：

```text
id: black_sea_crisis_1853
displayName: 黑海危机 1853
地图范围：黑海、克里米亚、多瑙河口、巴尔干北缘、高加索西缘、君士坦丁堡方向
主要势力：Britain、France、Russia、Ottoman、Austria、Sardinia、Neutral
核心目标：塞瓦斯托波尔、君士坦丁堡、瓦尔纳、锡利斯特拉、多瑙河口、敖德萨、克里米亚港口、巴尔干通道
首版规模：120-220 个 hex，35-70 个 region，8-16 个军区/远征区
```

维多利亚地形建议：

- plain -> 平原
- forest -> 林地
- hill / mountain -> 丘陵 / 山地
- city -> 城市
- fortress -> 要塞 / 堡垒
- river -> 多瑙河、德涅斯特河等河道边
- road -> 道路
- rail -> 铁路，若现有 schema 暂不支持，先作为 region/hex tag 或 road 强化记录
- port -> 港口，若 terrain 不支持，先通过 city/fortress + region tag 表达
- coast -> 海岸
- seaLane -> 海上通道，首版可 off-map 或特殊 passable 规则后置

新 JSON 文件建议：

- `WWIIHexV0/Data/black_sea_crisis_1853_scenario.json`
- `WWIIHexV0/Data/black_sea_crisis_1853_regions.json`
- `WWIIHexV0/Data/victorian_powers.json`
- `WWIIHexV0/Data/victorian_unit_templates.json`
- `WWIIHexV0/Data/victorian_personas.json`
- `WWIIHexV0/Data/victorian_terrain_rules.json`

MapEditor 迁移：

- `province` UI 改为省份/州/战略节点。
- `theater` UI 改为军区/远征区。
- `unit` UI 改为军队/指挥官。
- 支持铁路、港口、煤站、要塞、城市、海岸、初始人物、国家归属。
- 支持 `assignedGeneralId` 显示为将领/总督/远征军司令。
- 如果 schema 暂不支持新字段，先以 `dataNotes` 或阶段文档记录后置，不要塞到无关字段。

推荐并发：

- Data Agent：新 JSON 和 DataLoader 默认入口。
- MapEditor Agent：编辑器术语和导出字段兼容。
- UI Agent：地图层显示名和 accessibility label。
- Docs / QA Agent：同步 flow 和 README。

验收：

- 默认新局加载黑海危机剧本路径。
- `MapEditorExporter` 可以导出维多利亚语义地图而不丢 region/theater/unit。
- 默认数据不再出现阿登主剧本名。
- 所有 id 使用 ASCII，展示名可为中文。

轻量检查：

- 对新/改 JSON 跑 `jq empty`。
- 如果改 project，跑 `plutil -lint WWIIHexV0.xcodeproj/project.pbxproj`。
- 文档尾随空白和冲突标记扫描。

### v5.3：维多利亚军队、铁路补给、港口远征和围城规则

建议分支：`v5.3-victorian-war-logistics`

目标：

- 把二战单位和战术转换为维多利亚时代战棋规则。
- 保留 hex 战术权威和统一命令管线。
- 首版规则可解释、可调参，不追求复杂模拟。

单位模型建议：

- 源码可短期保留 `Division`，但 UI 显示必须是军队/师/旅/远征军/守备队。
- `ComponentType` 迁移为：
  - `lineInfantry`
  - `guardInfantry`
  - `cavalry`
  - `artillery`
  - `engineers`
  - `irregulars`
  - `colonialInfantry`
  - `supplyTrain`
- 若不能一次改 enum，可先建立 display adapter，把旧 `infantry/artillery/motorized/tank` 映射为维多利亚显示语义，并在 v5.4 再迁移 schema。

规则建议：

- 铁路 hex / region：降低移动成本、提高补给范围、加快新部队部署。
- 港口：远征军登陆/补给落点；被封锁后补给下降。
- 要塞/城市：提高防御，围城需要炮兵/工兵或多回合消耗。
- 山地/河流：移动和攻击惩罚。
- 炮兵：对要塞和城市有效，弹药/补给消耗高。
- 工兵：围城、渡河、修铁路、修要塞加成。
- 远征军：跨海作战维护费高，缺港口或海权时 supply 降级。
- 战争支持：高伤亡、久攻不下、财政透支会下降；首版可只写日志和 modifier。

推荐文件：

- `WWIIHexV0/Core/Division.swift`
- `WWIIHexV0/Core/Terrain.swift`
- `WWIIHexV0/Core/EconomyState.swift`
- `WWIIHexV0/Rules/MovementRules.swift`
- `WWIIHexV0/Rules/CombatRules.swift`
- `WWIIHexV0/Rules/SupplyRules.swift`
- `WWIIHexV0/Rules/CommandValidator.swift`
- `WWIIHexV0/Rules/CommandExecutor.swift`
- `WWIIHexV0/Commands/Command.swift`
- `WWIIHexV0/Commands/WarCommandExecutor.swift`
- `WWIIHexV0/UI/UnitInspectorView.swift`
- `WWIIHexV0/SpriteKit/UnitNode.swift`

推荐并发：

- Rules Agent：军事规则和校验。
- Economy Agent：维护费、补给、铁路/港口资源影响。
- UI Agent：单位显示名、图标、日志文案。
- Docs / QA Agent：规则说明和风险。

验收：

- 玩家可见路径不再显示 Panzer、Tank、Motorized、二战 Division。
- 铁路/港口/要塞至少有一个可观察规则效果。
- 围城/要塞战不会绕过 hex 占领。
- AI 和玩家仍走同一命令管线。

轻量检查：

- JSON 改动跑 `jq empty`。
- 少量纯 Swift 改动可尝试 `swiftc -parse`。
- 不跑全量 build/test。

### v5.4：工业经济、预算、动员和建设命令

建议分支：`v5.4-victorian-industry-budget`

目标：

- 把初级经济迁移为维多利亚时代工业和财政玩法。
- 建立玩家可理解的预算、动员、铁路、军工和补给闭环。
- 不做完整全球市场模拟。

首版资源建议：

```text
recruits        可动员人口 / 兵源
treasury        国库
industrialCap   工业产能
supplies        军需补给
railCapacity    铁路运输力
convoys         船运量
prestige        威望
warSupport      战争支持
```

命令建议：

- `mobilizeReserves`
- `queueRailway(regionId)`
- `fortifyRegion(regionId)`
- `prepareExpedition(theaterId)`
- `buySupplies`
- `raiseWarLoan`
- `subsidizeArmsIndustry`

实现建议：

- 如果不适合直接扩展 `Command`，先定义 `StrategicCommand` / `EconomyCommand`，但最终也必须经统一 validator/executor。
- 生产/建设不应直接改战术占领权。
- 铁路建设完成只改 region/hex 的 logistics tag 或 economy modifier。
- 战争贷款提升国库但增加后续维护/舆论风险。
- 战争支持影响 AI 风险阈值和胜负评价，首版可不强制结束战争。

推荐并发：

- Economy Agent：资源和命令。
- UI Agent：预算/建设面板。
- AI Agent：财政大臣/工业派系 deterministic 策略。
- Docs / QA Agent：说明资源映射和风险。

验收：

- 经济面板不再显示 Manpower / Industry / Supplies 英文二战口径。
- 玩家能排一个建设或动员命令，并通过规则系统扣费/完成。
- AI 不会无预算无限动员。
- Region inspector 能展示铁路/港口/工业/人口/补给信息。

### v5.5：外交危机、战争目标、列强干预和舆论压力

建议分支：`v5.5-victorian-diplomatic-play`

目标：

- 建立维多利亚时代核心外交玩法的最小闭环。
- 让战争不只是两个阵营互殴，而是外交危机升级后的结果。

外交危机流程建议：

```text
createDiplomaticPlay
  -> chooseWarGoal
  -> inviteBackers / threaten / offerConcession
  -> escalation ticks each turn
  -> back down / negotiated settlement / war
  -> war goals feed victory evaluation
```

首版战争目标：

- 保卫奥斯曼领土。
- 要求俄罗斯撤出多瑙公国。
- 控制黑海港口。
- 保持海峡开放。
- 削弱对方威望。
- 取得保护权或赔款。

规则边界：

- 外交行动改变外交状态，不直接占领 hex。
- 战争目标影响胜利条件、AI 优先级和谈判结果。
- 开战后战术行动仍走 hex / command / RuleEngine。
- 中立国家支持某方不等于自动参战，必须有关系状态和权限。

Agent 设计：

- ForeignMinisterAgent 输出外交选择。
- HeadOfStateAgent 设置底线和风险。
- PressAgent 输出舆论压力和战争支持变化建议。
- CabinetAgent 平衡财政、外交、军事。

推荐文件：

- `WWIIHexV0/Core/DiplomacyState.swift`
- `WWIIHexV0/Commands/Command.swift` 或新外交命令文件
- `WWIIHexV0/Rules/CommandValidator.swift`
- `WWIIHexV0/Rules/CommandExecutor.swift`
- `WWIIHexV0/Agents/RulerAgent.swift`
- `WWIIHexV0/UI/DiplomacyPanelView.swift`
- `WWIIHexV0/UI/AgentPanelView.swift`

验收：

- 至少能创建或加载一个黑海危机外交 play。
- 至少一个 AI 国家能支持、反对或保持中立，并留下解释记录。
- 外交危机可以通过回合推进升级到战争或降级为让步。
- UI 能展示双方、支持者、战争目标、升级进度、下一回合风险。

### v5.6：维多利亚 Agent 指挥链和结构化 JSON 合同

建议分支：`v5.6-victorian-agent-chain`

目标：

- 将现有元帅/统治者草案迁移为维多利亚多角色 Agent 指挥链。
- 所有 Agent 输出 JSON directive，严格 decoder / validator / compiler。
- 形成可复盘的 AI 行为。

推荐主链路：

```text
HeadOfStateAgent / PrimeMinisterAgent
  -> CabinetDirectiveEnvelope
  -> ForeignMinisterAgent / WarMinisterAgent / TreasuryAgent / AdmiraltyAgent
  -> StrategicDirectiveEnvelope
  -> GeneralStaffAgent
  -> TheaterDirectiveEnvelope
  -> TheaterDirectiveCompiler
  -> ZoneDirective
  -> WarCommandExecutor
  -> RuleEngine
```

首版可简化为：

```text
CabinetAgent
  -> Diplomatic / Military / Economy priority JSON
  -> GeneralStaffAgent
  -> TheaterDirectiveEnvelope
  -> ZoneDirective
  -> WarCommandExecutor
  -> RuleEngine
```

Agent 人设建议：

- Britain：谨慎财政、重视海权和威望，避免陆战过度消耗。
- France：重视威望和远征胜利，较积极。
- Russia：重视黑海、巴尔干和正统保护权，陆军保守但兵力充足。
- Ottoman：防御海峡和多瑙，依赖盟友与要塞。
- Austria：避免俄国过强，同时避免直接高成本战争。
- Sardinia：寻找低成本参战争取外交收益。

验收：

- AI 面板能展示至少一个 Cabinet / Foreign / War / GeneralStaff 决策记录。
- 无效 JSON 被拒绝或 fallback，不执行半成品。
- 每个 Agent 的输出不直接改 `GameState`。
- 同一回合的外交、经济、军事 directive 不互相覆盖。

### v5.7：发布级 UI、地图视觉、报纸战报和可访问性

建议分支：`v5.7-victorian-ui-polish`

目标：

- 把主游戏从调试界面推进到可发布演示品质。
- 建立维多利亚视觉语言和信息架构。
- iOS/macOS 都要可读、可操作。

第一屏布局建议：

```text
Top HUD:
  日期/回合、当前国家、国库、兵源、补给、威望、战争支持、危机状态

Main Map:
  hex 地图、region overlay、铁路、港口、要塞、前线、远征补给线、外交热点

Left Rail:
  内阁、外交、经济、军队、海军/港口、报纸

Right Inspector:
  选中 hex / region / unit / general / diplomatic play 详情

Bottom Strip:
  电报、战报、AI 决策摘要、拒绝原因
```

视觉要求：

- 地图底色可有纸张/雕版质感，但不能一屏单调米色。
- 使用国家旗色和图案区分势力，支持 `accessibilityDifferentiateWithoutColor` 时用纹理/描边/图标补充。
- 铁路、电报线、港口、煤站、要塞必须有清晰符号。
- 战线和进攻箭头不能遮挡单位和文字。
- 报纸/电报用于战报和 AI 理由，不要堆长篇说明。
- 图标按钮必须有 label / tooltip / accessibility label。
- 文本不许挤出按钮或面板；长国名和地名要换行或截断处理。
- SwiftUI 面板内标题不要使用 hero 级大字号。
- 不要使用卡片套卡片。

玩家可见文案要求：

- 默认 UI 中文优先。
- 可保留内部 id 但不要暴露给普通玩家。
- 不再显示 Ardennes、Germany、Allies、Panzer、Bastogne、German AI、Allied Player。
- `Division` 可以在源码里保留，但 UI 显示为军队/师/旅/远征军。

验收：

- 主界面能完成开局、选中、移动、攻击、结束回合、AI 复盘。
- Economy / Diplomacy / Agent / Region / Unit 面板有维多利亚语义。
- VoiceOver label 和按钮可访问性达到基本可用。
- 文字在常见 iPhone、iPad、macOS 窗口尺寸不重叠。

验证：

- 按当前规范不主动启动模拟器或 app。
- 如人工授权，可后置做截图/人工烟测。

### v5.8：内容扩展、事件、历史人物和多剧本框架

建议分支：`v5.8-victorian-content-events`

目标：

- 在首发剧本稳定后，扩展内容深度。
- 建立多剧本选择和事件系统。
- 不让内容直接绕过规则。

事件类型建议：

- 报纸舆论事件。
- 议会预算争议。
- 战争贷款。
- 疫病/冬季/补给危机。
- 港口封锁。
- 外交调停。
- 革命浪潮。
- 殖民地治安。
- 铁路事故或工程延期。
- 将领争功/失和。

事件执行要求：

- 事件必须有触发条件、可见描述、可选项、结果预览。
- 事件结果必须经 command / validator / rules 或明确的 event resolver。
- 不得直接任意改 hex 控制权和单位位置。

多剧本框架：

- 场景选择可以先是简单列表，不做营销首页。
- 每个剧本有 id、displayName、时间、地图、国家、胜利条件、推荐玩家势力、复杂度。
- 默认仍进入上次/推荐剧本，避免空白启动。

验收：

- 至少新增 8-12 个黑海危机相关事件。
- 至少建立第二剧本数据骨架或选择框架。
- 事件能被日志和报纸面板复盘。

### v5.9：发布候选、残留清理、试玩闭环和文档收口

建议分支：`v5.9-victorian-release-candidate`

目标：

- 达到可发布演示状态。
- 清理玩家可见二战残留。
- 完成文档、轻量检查、风险记录和交付说明。

发布候选必须具备：

1. 默认启动进入黑海危机或明确的维多利亚剧本。
2. 玩家可选择或默认扮演一个势力。
3. 可查看省份、港口、铁路、要塞、军队、外交危机。
4. 可移动、攻击、围城/占领、补给、结束回合。
5. AI 至少能完成外交/军事/经济中的两类决策，并留下结构化记录。
6. 外交危机或战争目标影响胜负。
7. 战报、报纸、电报或 AI 面板能解释关键决策。
8. 主 UI 无主要二战残留。
9. README、`md/flow/flow.md`、`md/flow/flowchart.md`、`update_log.md` 和阶段记录口径一致。
10. 明确列出未跑 Xcode / XCTest / 模拟器 / 性能测试的原因和风险。

残留扫描建议：

```sh
rg -n "Germany|Allies|Ardennes|Bastogne|Panzer|tank|motorized|WWII|German AI|Allied Player|Manpower|Industry|Supplies|Guderian|Montgomery" WWIIHexV0 MapEditor README.md md
rg -n "Faction\\.opponent|germanAI|alliedPlayer" WWIIHexV0
```

注意：

- 源码兼容层、历史测试和旧迁移文档中可以保留旧词，但发布主路径、默认 UI、默认数据、README 当前状态和 flow 不应把旧题材当作当前游戏。
- 如果保留 legacy case，必须在文档说明只用于旧数据/旧测试兼容。

轻量检查：

- 改动文档尾随空白。
- 冲突标记扫描。
- JSON `jq empty`。
- `plutil -lint` project 文件。
- 少量纯 Swift `swiftc -parse`，不可行就记录。
- 多 Agent 整合冲突检查。

未跑：

- 没有人工明确授权时，不跑 Xcode / XCTest / 模拟器 / app 启动 / Probe / Smoke / Stage Regression / Dynamic Theater Regression / Full / 性能测试。

---

## 6. 迁移硬编码审计重点

后续实现前至少扫描这些点：

```sh
rg -n "germany|allies|Germany|Allies|Ardennes|ardennes|Bastogne|Panzer|tank|motorized|Division|German AI|Allied Player|Manpower|Industry|Supplies|Guderian|Montgomery" WWIIHexV0 MapEditor README.md md
rg -n "Faction\\.opponent|enum Faction|enum GamePhase|phase == \\.alliedPlayer|phase == \\.germanAI|activeFaction == \\.germany|activeFaction == \\.allies" WWIIHexV0 MapEditor
rg -n "ComponentType|ProductionKind|EconomyResources|DiplomacyState|CountryProfile|RulerAgent|MarshalAgent|ZoneDirective|WarCommandExecutor|RuleEngine" WWIIHexV0
```

典型风险文件：

- `WWIIHexV0/Core/Faction.swift`
- `WWIIHexV0/Core/GamePhase.swift`
- `WWIIHexV0/Core/GameState.swift`
- `WWIIHexV0/Core/Division.swift`
- `WWIIHexV0/Core/EconomyState.swift`
- `WWIIHexV0/Core/DiplomacyState.swift`
- `WWIIHexV0/Data/DataLoader.swift`
- `WWIIHexV0/Data/ScenarioDefinition.swift`
- `WWIIHexV0/Rules/CommandValidator.swift`
- `WWIIHexV0/Rules/CommandExecutor.swift`
- `WWIIHexV0/Rules/SupplyRules.swift`
- `WWIIHexV0/Rules/VictoryRules.swift`
- `WWIIHexV0/Commands/WarDirective.swift`
- `WWIIHexV0/Commands/WarCommandExecutor.swift`
- `WWIIHexV0/Agents/ZoneCommanderAgent.swift`
- `WWIIHexV0/Agents/RulerAgent.swift`
- `WWIIHexV0/Turn/TurnManager.swift`
- `WWIIHexV0/App/AppContainer.swift`
- `WWIIHexV0/UI/*`
- `WWIIHexV0/SpriteKit/*`
- `MapEditor/*`

---

## 7. 发布级验收标准

### 7.1 产品体验

- 第一屏是可玩的维多利亚时代地图，不是说明页。
- 地图、HUD、内阁、外交、经济、军队、战报形成完整信息架构。
- 玩家能在 1-2 分钟内完成：选中军队、查看目标、下达移动/攻击/防守、结束回合、查看 AI 复盘。
- 至少一个维多利亚机制可被明确感知：铁路、港口远征、外交危机、战争支持、工业预算中的至少两个。
- AI Agent 的理由能被复盘，不是黑箱行动。

### 7.2 架构边界

- Hex 仍是战术权威。
- Region 仍是聚合层。
- `regionToTheater` 不作为运行时推进权威。
- `hexToTheater` 和 `hexToFrontZone` 的动态权威不被破坏。
- 玩家、AI、外交、经济命令最终都经过统一规则系统或有明确的新 validator/executor。
- Legacy Agent D 保留，不作为默认战争 AI 主路径。

### 7.3 数据和内容

- 默认数据为维多利亚剧本。
- JSON id 为 ASCII。
- 展示字段可以中文。
- 中立和多国家不 fallback 到旧 allies。
- 历史人物和事件服务玩法，不追求百科全书堆料。
- 殖民和帝国题材表达要有代价、冲突和多方视角，避免单向歌颂。

### 7.4 UI 和可访问性

- 主 UI 无主要二战残留。
- 44pt 触控目标。
- Dynamic Type 基本可用。
- icon-only 控件有 accessibility label。
- 颜色区分有图标/纹理/描边辅助。
- 长国名、地名、命令名不会挤出容器。
- macOS 和 iOS 入口共享规则，不新增平台专用规则绕路。

### 7.5 验证和文档

- 每轮按 `md/test/test.md` 做轻量检查。
- 不伪造测试通过。
- 未跑 Xcode / XCTest / 模拟器 / 性能测试时明确说明原因。
- README、`md/flow/flow.md`、`md/flow/flowchart.md`、`update_log.md` 和阶段记录口径一致。
- 多 Agent 并发后完成文件/API/schema/project/doc 冲突检查。

---

## 8. 给执行 Agent 的开工模板

每个后续实现 Agent 开始时先写一段本轮开工说明，格式建议：

```text
本轮目标：
- v5.x ...

本轮非目标：
- 不做 ...

已读文档：
- AGENTS.md
- update_log.md
- md/flow/flow.md
- md/flow/flowchart.md
- md/test/test.md
- md/prompt/v5.0-维多利亚迁移/codex-v5.0-维多利亚时代aiagent历史策略迁移总提示词.md

文件边界：
- 可改 ...
- 只读 ...
- 不碰 ...

并发安排：
- Agent A ...
- Agent B ...

轻量检查：
- ...

风险：
- ...
```

执行完后交付必须说明：

1. 完成了什么。
2. 改了哪些关键文件。
3. 跑了哪些轻量检查，具体结果是什么。
4. 哪些重测试没跑，原因是什么。
5. 还剩什么风险或下一步。

---

## 9. 最重要的底线

- 维多利亚迁移可以大胆改变题材、UI、数据和 Agent 层，但不能破坏现有规则权威链路。
- 不要用一次性大重命名制造不可控风险。
- 不要让 AI、UI、外交、经济绕过 `Command` / `ZoneDirective` / `WarCommandExecutor` / `RuleEngine`。
- 不要把发布级目标理解成堆功能。首发要小而完整：一个好玩的黑海危机剧本、清晰的工业/外交/军事闭环、可解释的 Agent、没有主要二战残留、视觉完成度足够高。
