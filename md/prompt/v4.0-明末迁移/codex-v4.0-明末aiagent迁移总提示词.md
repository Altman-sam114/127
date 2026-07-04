# Codex v4.0-v4.8 任务提示词：从 WWIIHexV0 迁移为 AI Agent 驱动的明末历史策略游戏

> 本文是交给后续实现 Agent 的总提示词。它不是本轮代码实现记录，而是明末迁移的产品目标、架构边界、版本路线、并发子 Agent 分工和发布级验收标准。执行前必须先读 `AGENTS.md`、`update_log.md`、`md/flow/flow.md`、`md/flow/flowchart.md`、`md/test/test.md` 和本文件。

---

## 0. 当前项目判断

你接手的是 `WWIIHexV0`，当前代码不是干净的早期原型，而是一个已经包含 hex 战棋、战略省份、动态战区、前线、部署、经济、外交草案、将领、元帅、统治者预留和 macOS target 的 Swift + SwiftUI + SpriteKit 工程。

当前真实主链路是：

```text
MapEditor / JSON 数据
  -> DataLoader
  -> GameState
  -> HexTile.controller + Division.coord
  -> Region 聚合
  -> Economy / Diplomacy 草案
  -> Theater / FrontLine / WarDeployment 派生层
  -> MarshalAgent / TheaterDirective / ZoneDirective
  -> WarCommandExecutor
  -> RuleEngine
  -> UI / SpriteKit / 日志 / WarDirectiveRecord
```

当前源码和文档中必须尊重的事实：

- `HexTile.controller` 和 `Division.coord` 是战术层权威。
- `RegionNode.controller` 是从 region 内 hex controller 聚合出来的战略快照。
- `regionToTheater` 是初始/基础战区，不是运行时推进权威。
- `hexToTheater` 是运行时动态战区权威。
- `hexToFrontZone` 是部署层动态归属权威。
- 玩家、AI、未来聊天命令都必须落到 `Command` / `ZoneDirective`，再经 `WarCommandExecutor`、`CommandValidator`、`RuleEngine` 执行。
- Legacy Agent D 管线保留作回归参考，默认战争 AI 主路径不得退回旧管线。
- 当前 `Faction` 只有 `germany/allies`，`Faction.opponent`、`GamePhase.germanAI/alliedPlayer`、`DataLoader` 的 `playerFaction/aiFaction`、`CommandValidator` 的阶段判断仍强绑定二元对立。
- 当前单位模型叫 `Division`，兵种仍是 `tank/motorizedInfantry/infantry/artillery`。
- 当前经济模型仍是 `manpower/industry/supplies`，生产项仍有 `panzerDivision` 等二战语义。
- 当前 UI、SpriteKit 和默认数据仍有 `Ardennes V0`、Germany、Allies、Bastogne、Panzer、NATO 符号等玩家可见残留。
- 当前工作树可能混有 v0.4、v0.5、v0.7、v0.8、v0.9、v1.0、v1.1、三国迁移、拿战迁移、隋唐迁移等未提交改动。任何实现前必须做分支和文件冲突审查，不能回滚他人改动。

迁移目标不是“换几段文案和颜色”，而是把现有工程逐步迁移为一款可发布演示的 AI Agent 驱动明末历史策略游戏。

---

## 1. 最终产品目标

暂定产品名：`明末棋策 Agent`。如果实现阶段需要英文 bundle/display name，可使用 `Late Ming Agent Strategy` 作为工作名。

最终首发体验应达到以下效果：

1. 打开应用后直接进入可玩的明末战役地图，不做营销落地页。
2. 首发默认剧本建议为 `崇祯十五年：天下裂变`：
   - 时间：约 1642 年，松锦战后前后、明廷财政和边防濒临崩溃、流民军进入扩张期。
   - 地图范围：辽西、山海关、畿辅、山东、河南、陕西、湖广北部的抽象区域；不要第一版就做完整全国沙盒。
   - 首版规模：约 100-180 个 hex，30-55 个 region，8-14 个初始方面/防区。
   - 主要势力：明廷、后金/清、李自成大顺、张献忠大西、地方中立/乡绅团练；南明、蒙古诸部、朝鲜可后置或作为边缘事件。
3. 玩家可选择一个势力；其他势力由 AI Agent 驱动。首发若只能做一个玩家势力，默认玩家为明廷，清、大顺、大西由 AI 控制。
4. 地图以 hex 为战术权威，以州府/卫所/战略区为 region 聚合层，以辽东、畿辅、秦陕、河南、湖广等方面军/防区为 AI 调度层。
5. 玩家既能微操军队，也能通过朝廷/督抚/将领面板下达宏观命令，例如“固守山海关”“解锦州之围”“剿抚河南”“南撤保南京”“筹饷补辽”。
6. AI 不直接改 `GameState`。皇帝、摄政王、首辅、督师、总兵、义军首领、谋士、粮台等 Agent 只能输出结构化 directive，经 decoder/validator/compiler 后落到规则系统。
7. UI 视觉要摆脱当前调试原型感：应有晚明军机图、奏疏、舆图、军令牌、关城、驿道、漕运、旗号、印玺和战报质感。
8. UI 不能成为大卡片堆砌。第一屏核心是地图和行动，不是说明文字。
9. 发布前玩家可见面板不得残留主要二战文案：德国、盟军、阿登、巴斯托涅、Panzer、Division、NATO 符号、Manpower/Industry/Supplies 不应出现在默认主游戏 UI、日志和数据中。
10. 发布前必须有完整试玩闭环：开局、选择势力、查看州府、选择军队、进军、战斗、围城/占领、粮草与军饷消耗、AI 回合、朝廷/将领决策复盘、胜负判断。
11. 发布级演示必须能看出 AI Agent 的差异：明廷朝议迟缓但可集中资源，清军重骑突击和围点打援，大顺偏好破城扩粮，大西偏好流动作战和劫掠补给。

---

## 2. 迁移总原则

### 2.1 保留的工程骨架

必须保留并迁移这些成熟资产：

- Hex 坐标、移动、攻击、占领、视野、补给落点的战术权威。
- Region 作为战略聚合层，不替代 hex。
- 动态战区、前线、部署层的派生关系。
- `Command` / `ZoneDirective` / `WarCommandExecutor` / `RuleEngine` 统一执行管线。
- `WarDirectiveRecord`、`AgentDecisionRecord`、`RulerDecisionRecord` 等审计/复盘记录。
- MapEditor 的稀疏 hex、region、theater、unit 编辑与导出能力。
- iOS 主游戏、macOS 主游戏和 macOS 地图编辑器方向。

### 2.2 必须替换或抽象的二战语义

必须逐步替换这些题材绑定点：

- `Faction.germany/allies`：迁移为明末多势力体系，至少支持 `ming`、`qing`、`dashun`、`daxi`、`localNeutral`。
- `Faction.opponent`：多方关系不能用单一 opponent，必须来自 `DiplomacyState`、`PowerRelation` 或 `WarRelationRules`。
- `GamePhase.germanAI/alliedPlayer`：迁移为通用回合阶段，例如 `humanAction` / `aiAction` / `resolution`，或增加基于 `activeFaction` 的通用解释层。
- `Division` 的玩家可见语义：迁移为军队、营兵、边军、旗营、流民军、团练。源码可分阶段保留兼容名，但 UI 不应显示 Division。
- `ComponentType.tank/motorizedInfantry/infantry/artillery`：迁移为步军、骑兵、火器、炮队、旗骑、攻城器械、水师/舟师、团练等明末兵种。
- `EconomyResources.manpower/industry/supplies`：迁移为民力、银两、粮草；可后续扩展军械、马匹、火药、民心。
- `ProductionKind.panzerDivision` 等：迁移为募营兵、募骑兵、造炮队、整训团练、筹粮、修城、征饷等。
- `Theater` UI：显示为方面、防区、军镇、督师辖区。
- `FrontZone` UI：显示为前线军区、镇守区、战区。
- `MarshalAgent`：迁移为督师/枢辅/军机 Agent。
- `RulerAgent`：迁移为皇帝、摄政王、义军首领 Agent。
- `GeneralData`：迁移为将领/文臣/首领数据，含统率、勇武、谋略、政务、声望、忠诚、贪腐/清廉、派系。
- 阿登 JSON：迁移为明末剧本 JSON。
- 默认 UI 文案：中文优先，必要时保留英文开发字段。

### 2.3 不能做的事

- 不要一次性大规模重命名所有类型再凭感觉修编译。先建立兼容层和迁移合同，再分版本替换。
- 不要让任何 Agent 直接修改 `GameState` 的 hex controller、unit coord、dynamic theater、front zone 或 economy ledger。
- 不要恢复旧 Cabinet / Minister / StrategicDirective 污染。明末可以有朝廷、阁臣、督抚、总兵、粮台，但必须是新 schema 和新管线。
- 不要删除 Legacy Agent D；只隔离和保留回归参考。
- 不要把 region 当成战术权威；进军、攻击、围城、占领仍必须落到 hex。
- 不要把完整 1618-1662 全国所有势力、所有事件、所有官制一次性塞进首版。
- 不要使用受版权保护的影视、游戏、小说人物图或 UI 素材。可用自制、生成、公共领域或明确授权素材。
- 不要写族群仇恨或现代政治表达。后金/清、明、流民军等都按历史策略游戏的制度和军事逻辑表达。
- 未获人工授权，不跑 Xcode / XCTest / 模拟器 / Probe / Smoke / Stage Regression / Full / 性能测试。

---

## 3. 明末核心设计合同

### 3.1 势力与国家层

推荐先保留源码 `Faction` 名称作为兼容层，但目标语义改为“势力”。首发建议：

```text
ming          明廷
qing          后金/清
dashun        大顺
daxi          大西
localNeutral  地方中立/乡绅团练/未定归属
```

可后置：

```text
southernMing   南明
mongolAllies   蒙古盟部
joseon         朝鲜
pirateCoast    海商/郑氏/沿海势力
```

原则：

- `Faction` 是规则层控制方；`CountryProfile` / `PowerProfile` 是政治实体资料。
- `HexTile.controller` 可为 nil 或 `localNeutral`，不要 fallback 给明廷。
- `RegionNode.owner/controller/coreOf` 必须支持多方和中立，不再假设两个阵营。
- 敌我判断不能写 `faction != otherFaction` 就等价为可攻击；是否可攻击必须结合外交状态、同盟、停战、借道、叛乱或中立规则。

### 3.2 地图层

现有 hex/region/theater/front/deploy 分层继续有效，明末语义建议为：

```text
Hex
  -> 格：城池、关隘、山地、平原、林地、河道、驿道、堡寨

Region
  -> 州府/卫所/战略区：收入、粮草、城防、民心、灾荒、胜利点

Theater
  -> 方面/防区/军镇：辽东防线、山海关、畿辅、河南、秦陕、湖广

FrontLine
  -> 前线接触：真实动态战区相邻 hex 形成战线，不等于省界

WarDeployment
  -> 前线军、纵深军、守城/驻防军
```

关键边界不变：

- 占一个 hex，只推进该 hex 的 `hexToTheater` / `hexToFrontZone`。
- 不允许占一个州府就直接改整个 `regionToTheater`。
- 围城、关隘突破、流动作战都必须通过具体 hex 位置表达。

### 3.3 军事规则层

首发规则要可解释，不追求复杂仿真。建议迁移：

- `strength` 继续代表兵力战斗力，不恢复 organization。
- `supplyState` 显示为粮草状态：有粮、缺粮、断粮/被围。
- `RetreatMode.hold/retreatable` 显示为死守/可撤。
- 步军：防守稳定，城池/山地加成。
- 骑兵：平原和驿道机动强，山地/城池受限。
- 火器：中近程压制，对密集军队和守城有加成，但受雨雪/补给影响可后置。
- 炮队/攻城器械：对城池、关隘、堡寨有效，机动差。
- 旗骑/精锐边军：高机动高攻击，高粮饷消耗。
- 流民军：补给依赖占领和劫粮，低稳定但扩张快。
- 团练/乡兵：守城和治安强，野战弱。

### 3.4 经济与内政层

现有 `EconomyState` 可迁移为明末资源总账：

```text
manpower -> 民力/兵源
industry -> 银两/军费
supplies -> 粮草
```

建议 v4.4 后再扩展：

- 民心/治安：影响征粮、叛乱、流民军扩张。
- 腐败/拖欠军饷：影响将领忠诚和部队士气。
- 灾荒/瘟疫：影响 region 收入、补员和流民军生成。
- 城防/修城：影响围城回合和防御修正。
- 漕运/驿道：影响粮草补给路径。

### 3.5 AI Agent 层

明末 AI Agent 的重点不是“更聪明的单个 AI”，而是多角色协同和冲突。推荐层级：

```text
RulerAgent 最高政治意志
  明：崇祯皇帝
  清：皇太极/多尔衮
  大顺：李自成
  大西：张献忠

CourtAgent / CouncilAgent 朝廷或军议
  明：首辅、兵部、监军、督师意见
  清：贝勒议政、八旗分兵
  流民军：谋士、老营、先锋

MarshalAgent / TheaterAgent 督师/方面统帅
  把战略意图变成方面目标和 ZoneDirective

GovernorAgent 督抚/巡抚/地方官
  处理征饷、修城、屯田、治安、募兵

GeneralAgent 总兵/将领
  把具体防区目标转成 attack/defend/hold/resupply

QuartermasterAgent 粮台/后勤
  输出粮草优先级、补给路线和生产建议

DiplomatAgent 外交/招抚
  输出招抚、借道、停战、结盟、离间、归降提案
```

所有上游 Agent 输出必须是 Codable JSON directive，不能直接执行状态修改。安全执行链路为：

```text
Agent JSON
  -> Decoder / Validator
  -> StrategicDirectiveEnvelope / TheaterDirectiveEnvelope / ZoneDirective
  -> Compiler
  -> WarCommandExecutor / Command
  -> RuleEngine
  -> WarDirectiveRecord / AgentDecisionRecord / Diplomacy record
```

---

## 4. 多 Agent 并发工作流

主 Agent 负责总体架构、接口合同、冲突整合和最终验收。子 Agent 只能在明确边界内并发，不得同时改同一 public API 或同一文件。

### 4.1 并发前主 Agent 必做

1. 读完 `AGENTS.md`、`update_log.md`、`md/flow/flow.md`、`md/flow/flowchart.md`、`md/test/test.md` 和本文件。
2. 执行轻量只读审计：
   - `git branch --show-current`
   - `git status --short`
   - `rg -n "germany|allies|Ardennes|Bastogne|Panzer|Division|Manpower|Industry|Supplies|Field Marshal|Ruler|Marshal|opponent" WWIIHexV0 MapEditor README.md md`
   - `rg -n "enum Faction|GamePhase|struct Division|ComponentType|ProductionKind|EconomyResources|DiplomacyState|GeneralData|ZoneDirective|WarCommandExecutor|RuleEngine" WWIIHexV0`
3. 写出本轮实际版本目标和非目标。
4. 定义本轮公共接口合同。没有接口合同前，不要让多个子 Agent 同时改 `Core/`、`Commands/`、`Rules/`。
5. 明确 `WWIIHexV0.xcodeproj/project.pbxproj` 只能由主 Agent 或唯一指定的 Project Agent 修改。
6. 若工作树已有用户/其他 Agent 改动，先记录相关文件，不得回滚。

### 4.2 推荐子 Agent 分工

每轮最多并发 3-5 个子 Agent。优先减少冲突，不追求数量。

#### Data / Scenario Agent

范围：

- `WWIIHexV0/Data/*.json`
- `WWIIHexV0/Data/ScenarioDefinition.swift`
- `WWIIHexV0/Data/RegionDataSet.swift`
- `WWIIHexV0/Data/DataLoader.swift`

职责：

- 迁移剧本、地图、地形、兵种、将领、势力数据。
- 保证 JSON key 稳定，id 使用 ASCII/pinyin，例如 `power_ming`、`region_shanhaiguan`、`unit_guanning_cavalry_01`。
- 中文只放在 `displayName`、`localizedName`、`biography`、`description` 等展示字段。

禁止：

- 不改 `RuleEngine`。
- 不改 UI。
- 不改 project 文件，除非主 Agent 明确指定。

#### Rules / Core Agent

范围：

- `WWIIHexV0/Core/`
- `WWIIHexV0/Commands/`
- `WWIIHexV0/Rules/`

职责：

- 将二元阵营、二战单位、二战补给经济迁移为明末多势力规则抽象。
- 保持 `Command` / `ZoneDirective` / `WarCommandExecutor` / `RuleEngine` 统一入口。
- 落地围城、粮草、军饷、士气、兵种克制时必须先给最小可解释版本。

禁止：

- 不改 SpriteKit/SwiftUI 视觉。
- 不新增真实网络 LLM 调用。

#### AI Agent

范围：

- `WWIIHexV0/Agents/`
- `WWIIHexV0/Turn/`
- 只读 `Core/Commands/Rules`

职责：

- 设计并实现皇帝/摄政王、朝议、督师、督抚、将领、粮台、外交 Agent 分层。
- 所有输出必须是 JSON / Codable directive。
- 上游 Agent 只能调整战略姿态、目标优先级、资源倾向或 directive envelope，不能直接执行底层命令。

禁止：

- 不直接改 `GameState`。
- 不绕过 `WarCommandExecutor`。

#### UI / Art Agent

范围：

- `WWIIHexV0/UI/`
- `WWIIHexV0/SpriteKit/`
- `Assets.xcassets` 如存在或由主 Agent 创建

职责：

- 迁移为明末视觉系统。
- 建立共享设计 token：字体、颜色、材料、间距、圆角、线宽、动效。
- 地图、军队、将领、城池、关隘、粮道、战线、奏疏、战报都要有发布级可读性。

要求：

- 44pt 触控目标。
- 不在 SwiftUI body 内做重复排序、过滤、JSON 格式化。
- 大列表用 `LazyVStack` / `LazyHStack`。
- 避免单一米色、单一暗蓝、单一红黑主题。舆图底色只能作底，必须用朱印、墨色、青绿水系、铜色控件、势力旗色形成层次。
- 不引入第三方框架，除非人工确认。

禁止：

- 不把规则写进 View。
- 不让 SpriteKit 直接改 `GameState`。

#### MapEditor Agent

范围：

- `MapEditor/`
- 只读 `Data/` schema

职责：

- 将编辑器术语迁移为地块、州府、方面/防区、军队/将领。
- 支持明末地形、城池、关隘、堡寨、渡口、驿站、粮仓、港口、初始将领和势力归属。

禁止：

- 不破坏主游戏 JSON 加载格式。

#### Docs / QA Agent

范围：

- `README.md`
- `update_log.md`
- `md/flow/`
- `md/test/test.md`
- `md/prompt/v4.0-明末迁移/`

职责：

- 同步核心逻辑文档和阶段记录。
- 做轻量检查与冲突扫描。
- 记录未跑重测试的风险。

### 4.3 并发整合规则

子 Agent 完成后，主 Agent 必须检查：

- 是否多个子 Agent 改了同一文件。
- 是否出现 public API 分叉。
- 是否出现 JSON schema 分叉。
- 是否出现 `Faction`、`PowerId`、`CountryId`、`BlocId` 四套概念混乱。
- 是否出现 `project.pbxproj` 重复引用、缺失引用或 UUID 冲突。
- 是否出现 README、`md/flow/*`、阶段记录口径不一致。
- 是否有人绕过 `RuleEngine` 修改状态。
- 是否把 `regionToTheater`、`hexToTheater`、`hexToFrontZone` 的权威边界写乱。

没有完成这些检查前，不得声称“多 Agent 工作可合并”。

---

## 5. 版本路线

### v4.0：迁移审计、兼容层和明末题材合同

建议分支：`v4.0-ming-audit-contract`

目标：

- 建立明末迁移的工程合同。
- 找出所有二战硬编码、二元阵营假设和 UI 残留。
- 定义明末术语、首发剧本、版本边界和 Agent 协作方案。
- 不急着实现完整明末玩法。

范围：

- 新增或更新阶段记录：`md/prompt/v4.0-明末迁移/v4.0_audit_and_contract.md`。
- 新增迁移词汇表和命名约定：
  - `Faction` 当前源码兼容名，目标语义为势力。
  - `Division` 当前源码兼容名，目标显示为军队/营兵。
  - `Theater` 显示为方面/防区。
  - `Region` 显示为州府/卫所/战略区。
  - `FrontZone` 显示为前线军区。
  - `Supply` 显示为粮草/粮道。
  - `Production` 显示为征募/筹饷/整训/修城。
- 抽出 UI 显示名，不要让主要面板继续硬编码 Ardennes、Germany、Allies。
- 记录所有必须在 v4.1-v4.4 处理的硬编码点。

推荐并发：

- Docs / QA Agent：做硬编码扫描、写审计表。
- UI Agent：只读定位 UI 硬编码，不实现大 UI。
- Rules Agent：只读定位 `Faction.opponent`、二元 switch、二战兵种耦合。
- Data Agent：只读定位阿登数据入口和 JSON schema 限制。

验收：

- 有完整审计清单。
- 有明末迁移词汇表。
- 有版本拆分和风险清单。
- 没有大范围重命名导致不确定风险。

轻量检查：

- 文档尾随空白检查。
- 冲突标记扫描。
- 不跑 Xcode / XCTest / 模拟器。

### v4.1：多势力、外交关系和通用回合编排

建议分支：`v4.1-ming-powers-turns`

目标：

- 从二元 `germany/allies` 迁移到明末多势力架构。
- 首版至少支持明廷、后金/清、大顺、大西、地方中立。
- 移除主路径对 `Faction.opponent` 和固定 `germanAI/alliedPlayer` 的依赖。
- 保持旧阿登数据可兼容加载或有明确 fallback。

设计建议：

1. 审计 `Faction` 的所有使用点。
2. 短期发布优先可先扩展 `Faction` enum：
   - `ming`
   - `qing`
   - `dashun`
   - `daxi`
   - `localNeutral`
   - 保留 `germany/allies` 作为 legacy case，直到旧测试/旧数据迁出。
3. 新增或迁移 `PowerProfile` / `CountryProfile`，把 display name、旗色、首都、统治者、AI 配置放进数据。
4. 建立统一敌我判断：
   - `canAttack(attacker:target:state:)`
   - `isHostile(lhs:rhs:state:)`
   - `isFriendly(lhs:rhs:state:)`
   - `canEnterTerritory(faction:controller:state:)`
5. `DiplomacyState` 支持：
   - allied
   - vassal
   - neutral
   - hostile
   - atWar
   - truce
   - passage
6. 通用回合顺序建议：
   - `turnOrder: [Faction]`
   - `activeFaction`
   - `isHumanControlled(faction:)`
   - `shouldRunAI(for:)`
   - 不再用德国/盟军阶段名决定谁能行动。
7. 中立地块/州府不应被错误算给明廷或任何势力。

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

- 多势力可以被 JSON 表达。
- 敌我判断不再依赖 `.opponent`。
- `AppContainer` 不再只为 `.germany` 跑 AI。
- 中立地块/州府不会被错误算给某个势力。
- `CommandValidator` 对玩家与 AI 仍对称。

轻量检查：

- 改 JSON 跑 `jq empty`。
- 对直接改动且可单文件 parse 的 Swift 文件运行 `swiftc -parse`；如果 SwiftUI/SpriteKit/跨文件依赖导致不可行，停止并记录。
- `plutil -lint` 仅在 project 文件变更时运行。

### v4.2：明末地图、剧本数据和地图编辑器迁移

建议分支：`v4.2-ming-scenario-map`

目标：

- 建立第一张可玩明末剧本地图。
- 保留 MapEditor 导出链路。
- 默认新局加载明末剧本，而不是阿登。

默认剧本建议：

```text
id: chongzhen_1642_collapse
displayName: 崇祯十五年：天下裂变
地图范围：辽西、山海关、畿辅、山东、河南、陕西、湖广北部
主要势力：明廷、后金/清、大顺、大西、地方中立
核心目标：北京、山海关、锦州、宁远、宣府、大同、开封、洛阳、西安、襄阳、武昌
首版规模：100-180 个 hex，30-55 个 region，8-14 个方面/防区
```

明末地形建议：

- plain -> 平原
- forest -> 林地
- hill/mountain -> 丘陵/山地
- city -> 城池
- fortress -> 关隘/堡寨
- river -> 黄河/淮河/汉水/辽河等河道边
- road -> 驿道/官道
- 可后置：farmland、marsh、pass、port、canal、steppe

明末 JSON 文件建议：

- `WWIIHexV0/Data/chongzhen_1642_scenario.json`
- `WWIIHexV0/Data/chongzhen_1642_regions.json`
- `WWIIHexV0/Data/ming_powers.json`
- `WWIIHexV0/Data/ming_unit_templates.json`
- `WWIIHexV0/Data/ming_generals.json`
- `WWIIHexV0/Data/ming_terrain_rules.json`
- `WWIIHexV0/Data/ming_events.json` 可后置到 v4.7

MapEditor 迁移：

- `province` UI 改为州府/战略区。
- `theater` UI 改为方面/防区。
- `unit` UI 改为军队/将领。
- 支持 `assignedGeneralId` 显示为将领或督抚。
- 支持城池、关隘、堡寨、渡口、驿站、粮仓、港口等字段；如果 schema 暂不支持，先记录后置，不要塞到无关字段。

推荐并发：

- Data Agent：新 JSON 和 DataLoader 默认入口。
- MapEditor Agent：编辑器中文术语和导出字段兼容。
- UI Agent：地图层显示名和 accessibility label。
- Docs / QA Agent：同步 flow 和 README。

验收：

- 默认新局加载明末剧本路径。
- `MapEditorExporter` 可以导出明末语义地图而不丢 region/theater/unit。
- 默认数据不再出现阿登主剧本名。
- 所有 id 使用 ASCII，展示名可为中文。

轻量检查：

- 对新/改 JSON 跑 `jq empty`。
- 如果改 project，跑 `plutil -lint WWIIHexV0.xcodeproj/project.pbxproj`。
- 文档尾随空白和冲突标记扫描。

### v4.3：明末军队、围城、粮草和战术规则

建议分支：`v4.3-ming-war-rules`

目标：

- 把二战单位和战术转换为明末战棋规则。
- 保留 hex 战术权威和统一命令管线。
- 首版规则可解释、可调参，不追求复杂模拟。

单位模型建议：

- 源码可短期保留 `Division`，但 UI 显示必须是军队/营兵/旗营/团练。
- `ComponentType` 迁移为：
  - infantry：步军
  - cavalry：骑兵
  - firearm：火器营/鸟铳手
  - artillery：炮队
  - bannerCavalry：旗骑/精锐骑兵
  - militia：团练/乡兵
  - siegeEngine：攻城器械
  - naval：水师，可后置
- stats 仍可保留 attack/defense/movement/range/vision。
- 增加 morale / payStatus / grainCarry 可后置；首版可用 strength + supplyState 兼容。

战术映射建议：

- `standardAttack` -> 正攻
- `blitzkrieg` -> 疾袭
- `spearhead` -> 突骑破阵
- `breakthrough` -> 破围
- `pincerMovement` -> 合围
- `fireCoverage` -> 火器压制
- `feint` -> 佯攻
- `guerrillaWarfare` -> 流动作战/袭粮
- `holdPosition` -> 固守
- `elasticDefense` -> 诱敌退守
- `defenseInDepth` -> 层层设防
- `lastStand` -> 死守城关

新增或迁移规则：

- 粮草：`SupplyRules` 保留基础，展示为粮道/粮草。
- 军饷：缺银影响补员、士气和将领满意度，首版可只做经济日志与轻微战斗修正。
- 围城：城池/关隘 hex 被敌邻接且粮道断绝时，防御恢复下降；若围城方有炮队/器械，攻城效率上升。
- 士气：首版可从战斗修正和日志开始，不强制首轮加字段。
- 将领影响：通过 `GeneralAssignment` / `GeneralData.skills` 调整 tactic 选择或小幅战斗修正，不能直接跳过规则。
- 兵种克制：骑兵在平原/驿道优势，火器可压制但近战脆弱，炮队攻城强但机动差，团练守城强野战弱。
- 流民军扩粮：大顺/大西可通过占领粮草 region 获得补给，但治安和民心下降应在 v4.4 或 v4.7 扩展。

推荐文件：

- `WWIIHexV0/Core/Division.swift`
- `WWIIHexV0/Core/SupplyState.swift`
- `WWIIHexV0/Rules/CombatRules.swift`
- `WWIIHexV0/Rules/MovementRules.swift`
- `WWIIHexV0/Rules/SupplyRules.swift`
- `WWIIHexV0/Rules/CommandValidator.swift`
- `WWIIHexV0/Commands/WarDirective.swift`
- `WWIIHexV0/Commands/WarCommandExecutor.swift`
- `WWIIHexV0/Agents/ZoneCommanderAgent.swift`
- `WWIIHexV0/SpriteKit/UnitNode.swift`

推荐并发：

- Rules Agent：军队、战斗、粮草、围城。
- AI Agent：战术分类器明末化。
- Data Agent：unit templates。
- UI Agent：只做术语显示，不做大 UI。

验收：

- 玩家和 AI 的移动、攻击、防守、补给仍经 `RuleEngine`。
- 围城和粮草日志能被解释。
- 战术名称在 UI 和 `WarDirectiveRecord` 中明末化。
- 没有二战兵种显示残留。

轻量检查：

- 改 JSON 跑 `jq empty`。
- 少量 Swift 文件可尝试单文件 parse；失败则记录依赖风险。
- 禁止跑全项目 build/test。

### v4.4：明末经济、灾荒、军饷和地方治理

建议分支：`v4.4-ming-economy-governance`

目标：

- 把 v0.8 经济系统迁移为明末可玩的资源和内政系统。
- 让明廷困境、流民军扩张、清军补给压力都能通过规则表现。
- 不做复杂 grand strategy，先做轻量但有味道的经济闭环。

资源迁移：

```text
manpower -> 民力/兵源
industry -> 银两/军费
supplies -> 粮草
```

生产/政策迁移：

- `infantryDivision` -> 募营兵
- `panzerDivision` -> 募精骑/关宁骑
- `motorizedDivision` -> 募轻骑/哨骑
- `artilleryDivision` -> 造炮队/火器营
- `supplyStockpile` -> 筹粮
- 新增或后置：修城、赈济、征饷、屯田、整训团练。

Region 经济字段建议：

- `infrastructure` -> 驿道/治理基础
- `supplyValue` -> 粮草产出/仓储
- `factories` -> 工坊/军械能力
- `resources` -> grain, silver, horses, gunpowder, timber, iron
- `occupationState.resistance` -> 民变/治安压力
- `occupationState.compliance` -> 顺服/行政掌控

规则建议：

- 明廷：基础税赋高但腐败/拖欠军饷惩罚明显。
- 清：精锐成本高，长线补给压力明显，控制城池后稳定收入较低。
- 大顺/大西：占领粮食产区收益高，长期治理弱，民心/治安压力高。
- 地方中立：被战争波及会转向、叛乱或提供团练。
- 灾荒事件：降低 region 收入和补员，增加流民军扩张机会。

推荐并发：

- Rules Agent：经济结算、资源命名、生产迁移。
- Data Agent：region resources、production cost。
- AI Agent：经济优先级进入 Agent 摘要。
- UI Agent：经济面板明末化。

验收：

- 资源面板显示民力/银两/粮草。
- 生产/筹粮命令仍走 `Command.queueProduction` 或新统一命令。
- AI 摘要能看到粮草、军饷和关键缺口。
- 经济规则不直接改变 hex 控制权。

### v4.5：皇帝、朝议、督师、将领和流民军 AI Agent 分层

建议分支：`v4.5-ming-agent-court`

目标：

- 构建真正有明末味道的 AI Agent 层级。
- Agent 之间可以协作、争执和 fallback，但最终都必须输出结构化 directive。
- 让 AI 行为可审计、可回放、可调参。

推荐 Agent 配置：

```text
ming:
  RulerAgent: 崇祯
  CourtAgent: 内阁/兵部/监军
  MarshalAgent: 督师
  GovernorAgent: 巡抚/总督
  GeneralAgent: 总兵/参将
  QuartermasterAgent: 粮台

qing:
  RulerAgent: 皇太极/多尔衮
  CouncilAgent: 贝勒议政
  MarshalAgent: 旗主/统帅
  GeneralAgent: 旗营将领

dashun:
  RulerAgent: 李自成
  CouncilAgent: 谋士/老营
  GeneralAgent: 先锋/制将军

daxi:
  RulerAgent: 张献忠
  CouncilAgent: 谋士/亲军
  GeneralAgent: 流动作战将领
```

执行链路要求：

```text
RulerAgent / CourtAgent / GovernorAgent / QuartermasterAgent / DiplomatAgent
  -> StrategicDirectiveEnvelope
  -> decoder / validator
  -> TheaterDirectiveEnvelope
  -> compiler
  -> ZoneDirective / Command
  -> WarCommandExecutor / RuleEngine
  -> WarDirectiveRecord / AgentDecisionRecord / Diplomacy record
```

结构化输出要求：

- 所有 Agent 输出必须 Codable。
- 所有外部模型输出必须 fenced JSON 或纯 JSON，由 decoder 校验。
- decoder 必须校验 schemaVersion、turn、issuerId、faction/power、zone、region、tactic、resourcePolicy。
- decoder 失败时走安全 fallback，不执行半成品。
- Agent prompt 中不能要求模型“直接修改状态”。

Mock / 本地 LLM 要求：

- 首版仍可用模拟 LLM / MockAI。
- 真实本地 LLM 接入必须单独版本，不能把 API key 或模型路径硬编码进仓库。
- 网络或本地模型不可用时，必须有 deterministic fallback。

Agent 个性建议：

- 崇祯：风险厌恶与急切并存，重视北京和忠诚，容易频繁调整战略。
- 明廷阁臣：倾向保守筹饷、守城、避免孤注一掷。
- 辽东督师：重视关宁防线、锦宁援救和山海关。
- 清方统帅：重视围点打援、骑兵机动、分割补给。
- 李自成：偏好扩粮、破城、避开强关、快速吸纳兵力。
- 张献忠：偏好流动作战、劫粮、绕开坚城、打击后方。
- 地方督抚：优先保本地城池和粮仓，可能和中央战略冲突。

推荐并发：

- AI Agent：Agent schema、prompt builder、fallback。
- Rules Agent：外交/内政 directive 的 validator 和 executor 边界。
- UI Agent：AI 决策复盘面板显示层。
- Docs / QA Agent：更新 flowchart。

验收：

- AI 回合能解释“最高意志想要什么、朝议/军议如何调整、督师选哪里、将领做了什么”。
- 玩家能在 AI 面板看到 raw JSON、编译后的 directive、命令结果和拒绝原因。
- Agent 决策失败不会破坏回合。
- 仍未绕过 `RuleEngine`。

### v4.6：发布级明末 UI、美术和交互收口

建议分支：`v4.6-ming-ui-polish`

目标：

- 把当前工程从开发调试界面提升到可发布演示界面。
- 不靠说明文字，而靠地图、面板、状态、动效让玩家理解当前战局。

视觉方向：

- 主地图：晚明舆图和军机图质感，底色克制，水系、山脉、驿道、城池清晰。
- 势力：每个势力有旗色、印章图标、简短称号。
- 城池：北京、山海关、锦州、宁远、开封、洛阳、西安、襄阳等城市必须有清晰层级。
- 关隘/堡寨：山海关、宁远、锦州等要在第一眼可识别。
- 部队：军牌要能区分步、骑、火器、炮队、团练、旗营，显示兵力、行动状态、粮草警告。
- 将领：头像或印章占位、姓名、官职、统率/勇武/谋略/政务/声望、忠诚、派系、技能。
- 战线：用墨线/朱线表现敌我接触，用箭头表现计划行动，用虚线表现粮道。
- 战报：用简洁列表展示本回合关键行动、拒绝原因、占领变化、灾荒/外交事件。

主界面布局建议：

```text
顶部：回合、当前势力、民力/银两/粮草、胜利状态、结束回合
中央：SpriteKit 战场地图，全屏优先
左侧或底部：选中对象摘要，移动端可折叠
右侧或底部：军令/州府/将领/朝议/经济/战报/AI tabs
地图上：选中、可移动、可攻击、计划线、前线、粮道
```

SwiftUI 要求：

- 建立 `MingDesignTokens` 或类似共享设计常量。
- 44pt 最小触控区。
- 使用 `Label` 和 SF Symbols；不手写常见图标。
- 避免 body 内重复排序、过滤、JSON 格式化。
- 大列表用 Lazy 容器。
- 复杂面板拆成独立 View，不要继续膨胀 `RootGameView`。
- 不引入第三方框架，除非人工确认。

SpriteKit 要求：

- 地图必须在桌面和移动端都可缩放、平移、点击。
- 文字不能重叠到不可读。
- 单位和城池图标有稳定尺寸，不因状态变化造成跳动。
- 图层切换清晰：地形、州府、势力、前线、粮道、AI 计划。
- `UnitNode` 不再显示 NATO 风格符号；改为军牌/兵种符号。

推荐并发：

- UI Agent：SwiftUI 面板、设计 token。
- SpriteKit Agent：地图绘制、单位、图层、箭头。
- Data/Art Agent：头像占位、旗帜、图标资源和 asset catalog。
- Docs / QA Agent：截图检查清单和未跑重测试风险。

验收：

- 主游戏第一屏不再像调试板。
- 主要 UI 无二战文案残留。
- 移动端和 macOS 布局都有明确约束。
- UI 只读状态，操作仍走 `AppContainer` 和规则系统。

注意：

- 若要生成头像、旗帜、地图纹理等 raster 资产，必须保证不是抄袭现有商业作品。
- 资产命名用 ASCII，例如 `portrait_chongzhen`, `banner_ming`, `icon_grain`, `unit_banner_cavalry`。

### v4.7：历史事件、教程、战役内容和可玩性收口

建议分支：`v4.7-ming-content-onboarding`

目标：

- 从“系统迁移版”收口到“玩家能理解并愿意试玩的历史策略游戏”。
- 加入可控的历史事件、教程提示和战役目标。
- 不做全量历史模拟，做少量高影响事件。

事件建议：

- 松锦失利：明军辽东士气与兵力压力上升。
- 崇祯催饷：短期银两提升，民心/治安下降。
- 流民饥荒：河南/陕西粮草下降，大顺扩军机会增加。
- 山海关压力：清方若逼近关口，明廷优先级改变。
- 开封围城：大顺/明廷围城与救援目标。
- 将领猜忌：忠诚低或军饷不足时，将领满意度下降。
- 招抚/归降：地方势力可被外交或军事压力吸收。

教程目标：

- 第一回合只提示地图、选中军队、移动/攻击、结束回合。
- 第一次缺粮时解释粮道。
- 第一次围城时解释城防和炮队。
- 第一次 AI 回合后解释 Agent 决策复盘。
- 不做大段说明文字，不挡住地图。

胜负建议：

- 明廷：守住北京、山海关和若干核心州府到指定回合，或收复河南关键城。
- 清：夺取山海关/北京方向通路，消灭辽东主力。
- 大顺：夺取洛阳/开封/西安，建立粮草链。
- 大西：控制湖广/四川方向关键粮区，可后置。

推荐并发：

- Data Agent：事件 JSON、胜利条件、教程触发点。
- Rules Agent：事件执行器和 validator。
- AI Agent：事件进入摘要和决策权重。
- UI Agent：事件提示和战报展示。
- Docs / QA Agent：内容验收清单。

验收：

- 有一个 10-20 回合可试玩目标链。
- 事件不会绕过规则直接破坏权威状态。
- 新玩家能通过 UI 理解基本玩法。
- 事件结果有日志和复盘记录。

### v4.8：发布候选、存档、设置和验收

建议分支：`v4.8-ming-release-candidate`

目标：

- 从“能跑的迁移版”收口到“可发布候选版”。
- 补齐玩家初次体验、错误恢复、存档、版本说明和发布前检查。

发布候选必须具备：

- App 名称、图标、默认剧本、主界面、基础设置。
- 新局 / 继续 / 重置。
- 一个完整可玩剧本。
- AI 回合不会卡死或静默失败。
- 玩家可理解的命令反馈。
- 关键 JSON 数据可解析。
- README 和 flow 文档准确描述当前明末架构。
- `update_log.md` 记录 v4.0-v4.8 每版完成内容、关键文件、轻量检查和未跑重测试。

发布前需要人工授权的重验证：

- Xcode build。
- iOS Simulator 或真机启动。
- macOS target 启动。
- 至少 10-20 回合观察者模式。
- 基础 UI 点击烟测。
- 性能体感检查。

在未获授权前，不得声称“可发布”。只能写“发布候选代码和文档已准备，运行时验证未授权，风险未验证”。

---

## 6. 数据 schema 方向

实际实现可沿用现有结构，但必须在阶段文档写明哪些字段是兼容旧名、哪些字段已经明末化。

### 6.1 势力

```json
{
  "id": "power_ming",
  "faction": "ming",
  "displayName": "明廷",
  "shortName": "明",
  "capitalRegionId": "region_beijing",
  "rulerAgentId": "ruler_chongzhen",
  "bannerAsset": "banner_ming",
  "primaryColor": "#8A1F1F",
  "secondaryColor": "#D8B45A",
  "legitimacy": 72,
  "treasuryStress": 84,
  "warSupport": 61
}
```

### 6.2 将领 / 官员

```json
{
  "id": "general_hong_chengchou",
  "name": "Hong Chengchou",
  "localizedName": "洪承畴",
  "rank": "蓟辽督师",
  "faction": "ming",
  "commandStyle": "cautious",
  "attributes": {
    "command": 86,
    "valor": 58,
    "strategy": 82,
    "governance": 78,
    "prestige": 74
  },
  "skills": ["defense_in_depth", "siege_relief", "logistics"],
  "portrait": "portrait_hong_chengchou",
  "biography": "长于防务与筹饷，适合组织辽东防线和救援战。",
  "preferredRegionIds": ["region_jinzhou", "region_ningyuan"],
  "baseLoyalty": 76,
  "baseSatisfaction": 62
}
```

### 6.3 州府 / 战略区

```json
{
  "id": "region_shanhaiguan",
  "name": "山海关",
  "owner": "ming",
  "controller": "ming",
  "terrain": "fortress",
  "city": {
    "name": "山海关",
    "victoryPoints": 6,
    "isCapital": false
  },
  "infrastructure": 4,
  "supplyValue": 5,
  "factories": 1,
  "resources": [
    { "type": "grain", "amount": 3 },
    { "type": "silver", "amount": 1 },
    { "type": "gunpowder", "amount": 1 }
  ],
  "coreOf": ["ming"],
  "occupationState": {
    "resistance": 12,
    "compliance": 65
  }
}
```

### 6.4 军队模板

```json
{
  "id": "guanning_cavalry",
  "displayName": "关宁铁骑",
  "maxHP": 10,
  "components": [
    { "type": "bannerCavalry", "weight": 0.65 },
    { "type": "firearm", "weight": 0.20 },
    { "type": "infantry", "weight": 0.15 }
  ],
  "cost": {
    "manpower": 70,
    "silver": 90,
    "grain": 26
  }
}
```

### 6.5 Agent directive 示例

```json
{
  "schemaVersion": 1,
  "issuerId": "ruler_chongzhen",
  "turn": 6,
  "faction": "ming",
  "strategicPosture": "defensive",
  "priorityRegions": ["region_beijing", "region_shanhaiguan", "region_kaifeng"],
  "resourcePolicy": {
    "grainPriority": "liaodong_front",
    "silverPriority": "pay_border_army",
    "recruitmentPriority": "henan_garrison"
  },
  "constraints": [
    "do_not_abandon_beijing",
    "avoid_all_out_attack_if_grain_low"
  ],
  "rationale": "京畿和山海关为国本，河南缺粮但不可任由流民军扩张。"
}
```

---

## 7. 文档更新要求

每个版本完成后至少更新：

- `update_log.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- 当前版本 prompt / implementation record
- 必要时更新 `README.md`
- 若检查规则变化，更新 `md/test/test.md`

文档必须说明：

- 当前版本完成了什么。
- 改了哪些关键文件。
- 轻量检查命令和结果。
- 未跑哪些重测试及原因。
- 遗留风险。
- 多 Agent 并发时的冲突审查结论。

---

## 8. 轻量检查要求

执行时严格遵守 `md/test/test.md`。默认不跑 Xcode / XCTest / 模拟器 / 性能类测试。

推荐轻量检查：

```sh
rg -n "[[:blank:]]+$" AGENTS.md README.md update_log.md md/test/test.md md/flow/flow.md md/flow/flowchart.md md/prompt/v4.0-明末迁移
```

```sh
rg -n "<<<<<<<|=======|>>>>>>>" AGENTS.md README.md update_log.md md WWIIHexV0 MapEditor
```

```sh
rg -n "germany|allies|Ardennes|Bastogne|Panzer|Division|Manpower|Industry|Supplies|Field Marshal|NATO|opponent" WWIIHexV0 MapEditor README.md md
```

仅当修改 JSON 时：

```sh
jq empty WWIIHexV0/Data/chongzhen_1642_scenario.json
jq empty WWIIHexV0/Data/chongzhen_1642_regions.json
jq empty WWIIHexV0/Data/ming_powers.json
jq empty WWIIHexV0/Data/ming_unit_templates.json
jq empty WWIIHexV0/Data/ming_generals.json
```

仅当修改 project 文件时：

```sh
plutil -lint WWIIHexV0.xcodeproj/project.pbxproj
```

仅当少量 Swift 文件可单文件 parse 且不会触发全量构建时：

```sh
swiftc -parse path/to/ChangedFile.swift
```

如果 `swiftc -parse` 因 SwiftUI/SpriteKit/跨文件依赖、SDK、耗时等问题不可行，立即停止并记录未验证风险。

---

## 9. 发布级验收清单

发布候选前必须逐项核对：

- 默认打开是明末剧本，不是阿登测试板。
- 玩家可见 UI 无主要二战文案和 NATO 符号残留。
- 至少明廷、清、大顺、大西、地方中立可在数据层表达。
- 多势力敌我判断不依赖 `Faction.opponent`。
- AI 回合可按 active faction 通用运行，不只为德国运行。
- 玩家和 AI 命令都经过 `Command` / `ZoneDirective`、`WarCommandExecutor`、`RuleEngine`。
- 占领、前线、部署仍遵守 hex 权威。
- 经济面板显示民力、银两、粮草。
- 军队显示为明末军队/营兵/旗营/团练，不显示 Division。
- 地图、战线、粮道、战报、Agent 决策复盘可读。
- 至少一个剧本有明确胜负条件。
- 所有关键 JSON 通过 `jq empty`。
- project 文件若修改过，通过 `plutil -lint`。
- 未经授权不得声称 Xcode build、模拟器、UI 烟测或性能验证通过。

---

## 10. 给后续 Agent B 的执行口径

你不是在写一个新项目，而是在迁移一个已经有复杂规则和历史包袱的战棋工程。

你的优先级：

1. 保住规则权威：hex 是战术权威，命令必须走规则系统。
2. 先拆二战硬编码，再做明末内容。
3. 先做多势力和外交敌我判断，再做复杂 AI。
4. 先做一个精制可玩剧本，不做全国无限沙盒。
5. 每轮只改当前版本范围，不顺手重构无关文件。
6. 多 Agent 并发时，先约定接口，再分文件实现，最后必须做冲突审查。
7. 轻量检查必须写具体命令和结果；重测试未授权必须明确说明未跑。

最终目标不是“文案换成明末”，而是让玩家在第一屏就能感到：这是一张晚明天下崩裂的战局图，朝廷、边军、清军和流民军都在通过可审计的 AI Agent 做决策，而所有决策都被同一套战棋规则约束。
