# Codex v2.0-v2.6 任务提示词：从 WWIIHexV0 迁移为 AI Agent 驱动的三国战棋

> 本文是交给后续实现 Agent 的总提示词。它不是本轮代码实现记录，而是后续多版本迁移的路线、边界、分工和验收标准。执行前必须先读 `AGENTS.md`、`update_log.md`、`md/flow/flow.md`、`md/flow/flowchart.md`、`md/test/test.md` 和本文件。

---

## 0. 当前项目判断

你接手的是 `WWIIHexV0`，当前代码不是一个干净的早期原型，而是一个已经混入多条方向的 Swift + SwiftUI + SpriteKit 战棋工程。现有主链路包括：

```text
MapEditor / JSON
  -> DataLoader
  -> GameState
  -> HexTile.controller + Division.coord
  -> Region 聚合
  -> Theater / FrontLine / WarDeployment 派生层
  -> Economy / Diplomacy / General / Ruler 草案
  -> MarshalAgent / TheaterDirective / ZoneDirective
  -> WarCommandExecutor
  -> RuleEngine
  -> UI / SpriteKit / 日志 / WarDirectiveRecord
```

当前代码和文档中存在这些事实：

- `HexTile.controller` 和 `Division.coord` 是战术层权威。
- `regionToTheater` 是初始/基础战区，不是运行时推进权威。
- `hexToTheater` 是运行时动态战区权威。
- `hexToFrontZone` 是部署层动态归属权威。
- 玩家、AI、未来聊天命令都必须落到 `Command` / `ZoneDirective`，再经 `WarCommandExecutor`、`CommandValidator`、`RuleEngine` 执行。
- 当前 `Faction` 只有 `germany/allies`，很多代码仍假设二元对立。
- 当前单位模型叫 `Division`，兵种仍是坦克、摩步、步兵、炮兵。
- 当前地图和 UI 仍有阿登、德军、盟军、二战战术语义。
- 当前工作树可能混有 v0.4、v0.5、v0.7、v0.8、v0.9、v1.0、v1.1 等未提交改动。任何实现前必须做分支和文件冲突审查，不能回滚他人改动。

迁移目标不是“换几段文字和颜色”，而是把这个工程逐步迁移为一个可发布的 AI Agent 驱动三国战棋。

---

## 1. 最终产品目标

暂定产品名：`三国棋策 Agent`。如果实现阶段需要英文 bundle/display name，可使用 `Three Kingdoms Agent Hex` 作为工作名。

最终首发体验应达到以下效果：

1. 打开应用后直接进入可玩的三国战役地图，不做营销落地页。
2. 第一批可发布战役建议选择一个范围可控但有多方 AI 味道的剧本：
   - 首选：`官渡前夜 200`，曹操、袁绍、刘备、孙策/孙权、刘表、马腾、汉室/中立。
   - 备选：`赤壁前夜 208`，曹操、孙权、刘备、刘表残部、中立郡县。
   - 不要第一版就做完整全国全势力沙盒，先做一张精制可玩的区域大战役图。
3. 玩家可选择一个势力；其他势力由 AI Agent 驱动。
4. 地图以 hex 为战术权威，以郡/州为战略聚合层，以方面军/战区为 AI 调度层。
5. 玩家既能微操部队，也能通过武将/军师面板下达宏观命令。
6. AI 不直接改 `GameState`。君主、军师、太守、武将等 Agent 只能输出结构化 directive，经验证后落到规则系统。
7. UI 视觉要摆脱当前调试原型感：应有三国历史战棋质感，包含水墨/绢帛地图、朱印/青铜/玉色点缀、势力旗帜、武将头像、城池/关隘/渡口图标、战线/进军箭头/粮道可视化。
8. UI 不能成为大卡片堆砌。第一屏核心是地图和行动，不是说明文字。
9. 发布前必须没有主要二战文案残留：德国、盟军、阿登、Panzer、Division 等不应出现在主游戏 UI、默认数据、日志和玩家可见面板中。
10. 发布前必须有一个可演示闭环：开局、选择势力、查看城郡、选择军队、进军、战斗、围城/占领、粮草消耗、AI 回合、战报复盘、胜负判断。

---

## 2. 迁移总原则

### 2.1 保留的工程骨架

必须保留并迁移这些成熟资产：

- Hex 坐标、移动、攻击、占领、视野、补给落点的战术权威。
- Region 作为战略聚合层，不替代 hex。
- 动态战区、前线、部署层的派生关系。
- `Command` / `ZoneDirective` / `WarCommandExecutor` / `RuleEngine` 统一执行管线。
- `WarDirectiveRecord`、`AgentDecisionRecord` 等审计/复盘记录。
- MapEditor 的稀疏 hex、region、theater、unit 编辑与导出能力。
- iOS 主游戏和 macOS 主游戏/地图编辑器目标的方向。

### 2.2 必须替换或抽象的二战语义

必须逐步替换这些题材绑定点：

- `Faction.germany/allies`：迁移为三国势力体系，至少支持曹、袁、刘、孙、刘表、马腾、汉室/中立。
- `Division` 的显示语义：迁移为军队/部曲/营寨/军团。源码可分阶段保留兼容名，但玩家可见文本不能叫 Division。
- `ComponentType.tank/motorizedInfantry/infantry/artillery`：迁移为步兵、骑兵、弓弩、器械、水军/舟师等三国兵种。
- `EconomyResources.manpower/industry/supplies`：迁移为人口/钱粮/军械或人口/金钱/粮草/辎重。
- `Theater` 的二战战区文案：保留抽象层，但 UI 显示为方面、军区、战线或都督区。
- `FrontZone`：UI 可显示为方面军/防区/军团辖区。
- `RulerAgent`：迁移为君主 Agent。
- `MarshalAgent`：迁移为军师/都督 Agent。
- `GeneralData`：迁移为武将数据，含统率、武力、智谋、政治、魅力、忠诚、性格、技能。
- 阿登 JSON：迁移为三国剧本 JSON。
- 默认 UI 文案：迁移为中文优先，必要时保留英文开发字段。

### 2.3 不能做的事

- 不要一次性大规模重命名所有类型再凭感觉修编译。先建立兼容层和迁移合同，再分版本替换。
- 不要让任何 Agent 直接修改 `GameState` 的 hex controller、unit coord、dynamic theater、front zone。
- 不要恢复旧 Cabinet / Minister / StrategicDirective 管线。三国可以有君主、军师、太守、武将，但必须是新 schema 和新管线。
- 不要删除 Legacy Agent D；只隔离和保留回归参考。
- 不要把 region 当成战术权威；进军、攻击、围城、占领仍必须落到 hex。
- 不要把整张中国地图、全部 190-280 年剧本、完整外交内政一次性塞进首版。
- 不要使用受版权保护的三国游戏素材、头像、图标或 UI。可用自制、生成、公共领域或明确授权素材。
- 未获人工授权，不跑 Xcode / XCTest / 模拟器 / Probe / Smoke / Stage Regression / Full / 性能测试。

---

## 3. 多 Agent 并发工作流

主 Agent 负责总体架构、接口合同、冲突整合和最终验收。子 Agent 只能在明确边界内并发，不得同时改同一 public API 或同一文件。

### 3.1 并发前主 Agent 必做

1. 读完必读文档和本文件。
2. 执行轻量只读审计：
   - `git branch --show-current`
   - `git status --short`
   - `rg -n "germany|allies|Ardennes|Panzer|Division|Bastogne|MockAI|Marshal|Ruler|Faction\\.opponent" WWIIHexV0 MapEditor README.md md`
   - `rg -n "enum Faction|struct Division|ComponentType|EconomyResources|DiplomacyState|GeneralData|ZoneDirective|WarCommandExecutor|RuleEngine" WWIIHexV0`
3. 写出本轮实际版本目标和非目标。
4. 定义本轮公共接口合同。没有接口合同前，不要让多个子 Agent 同时改 `Core/`、`Commands/`、`Rules/`。
5. 明确 `WWIIHexV0.xcodeproj/project.pbxproj` 只能由主 Agent 或唯一指定的 Project Agent 修改。

### 3.2 推荐子 Agent 分工

每轮最多并发 3-5 个子 Agent。优先减少冲突，不追求数量。

#### Data Agent

范围：

- `WWIIHexV0/Data/*.json`
- `WWIIHexV0/Data/ScenarioDefinition.swift`
- `WWIIHexV0/Data/RegionDataSet.swift`
- `WWIIHexV0/Data/DataLoader.swift`

职责：

- 迁移剧本、地图、地形、兵种、武将、势力数据。
- 保证 JSON key 稳定，id 使用 ASCII/pinyin，例如 `power_cao`, `region_xuchang`。
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

- 将二元阵营、二战单位、二战补给经济迁移为三国可用的规则抽象。
- 保持 `Command` / `ZoneDirective` / `WarCommandExecutor` / `RuleEngine` 统一入口。
- 落地围城、粮草、士气、兵种克制等规则时必须先给最小可测版本。

禁止：

- 不改 SpriteKit/SwiftUI 视觉。
- 不新增真实网络 LLM 调用。

#### AI Agent

范围：

- `WWIIHexV0/Agents/`
- `WWIIHexV0/Turn/`
- 只读 `Core/Commands/Rules`

职责：

- 设计并实现君主、军师、太守、武将 Agent 分层。
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

- 迁移为三国视觉系统。
- 建立共享设计 token：字体、颜色、材料、间距、圆角、线宽、动效。
- 地图、军队、武将、城池、粮道、战线、战报都要有发布级可读性。

要求：

- 44pt 触控目标。
- 不在 SwiftUI body 内做重复排序/过滤。
- 大列表用 `LazyVStack` / `LazyHStack`。
- 避免单一米色或单一暗蓝主题；绢帛色只能作底，需有朱印、墨色、青绿、铜色、势力色形成层次。

禁止：

- 不把规则写进 View。
- 不让 SpriteKit 直接改 `GameState`。

#### MapEditor Agent

范围：

- `MapEditor/`
- 只读 `Data/` schema

职责：

- 将编辑器术语迁移为地块、郡县、州/方面、军队/武将。
- 支持三国地形、城池、关隘、渡口、港口、粮仓、初始武将和势力归属。

禁止：

- 不破坏主游戏 JSON 加载格式。

#### Docs / QA Agent

范围：

- `README.md`
- `update_log.md`
- `md/flow/`
- `md/test/test.md`
- `md/prompt/v2.0-三国迁移/`

职责：

- 同步核心逻辑文档和阶段记录。
- 做轻量检查与冲突扫描。
- 记录未跑重测试的风险。

### 3.3 并发整合规则

子 Agent 完成后，主 Agent 必须检查：

- 是否多个子 Agent 改了同一文件。
- 是否出现 public API 分叉。
- 是否出现 JSON schema 分叉。
- 是否出现 `Faction`、`PowerId`、`CountryId` 三套概念混乱。
- 是否出现 `project.pbxproj` 重复引用、缺失引用或 UUID 冲突。
- 是否出现 README、`md/flow/*`、阶段记录口径不一致。
- 是否有人绕过 `RuleEngine` 修改状态。

没有完成这些检查前，不得声称“多 Agent 工作可合并”。

---

## 4. 版本路线

### v2.0：迁移审计、兼容层和题材剥离

建议分支：`v2.0-sanguo-audit-compat`

目标：

- 建立三国迁移的工程合同。
- 找出所有二战硬编码和二元阵营假设。
- 先把玩家可见文案和数据入口从二战专名中解耦。
- 不急着实现完整三国玩法。

范围：

- 新增或更新阶段记录：`md/prompt/v2.0-三国迁移/v2.0_audit_and_contract.md`。
- 新增迁移词汇表和命名约定：
  - `Faction` 当前源码兼容名，目标语义为势力。
  - `Division` 当前源码兼容名，目标显示为军队/部曲。
  - `Theater` 显示为方面/军区。
  - `Region` 显示为郡/州。
  - `FrontZone` 显示为方面军防区。
- 抽出 UI 显示名，不要让主要面板继续硬编码 Ardennes、Germany、Allies。
- 记录所有必须在 v2.1-v2.3 处理的硬编码点。

推荐并发：

- Docs / QA Agent：做硬编码扫描、写审计表。
- UI Agent：只读定位 UI 硬编码，不实现大 UI。
- Rules Agent：只读定位 `Faction.opponent`、二元 switch、二战兵种耦合。

验收：

- 有完整审计清单。
- 有三国迁移词汇表。
- 有版本拆分和风险清单。
- 没有大范围重命名导致不确定风险。

轻量检查：

- 文档尾随空白检查。
- 冲突标记扫描。

### v2.1：势力、多方外交和三国数据基础

建议分支：`v2.1-sanguo-powers`

目标：

- 从二元 `germany/allies` 迁移到多势力三国架构。
- 首版至少支持曹操、袁绍、刘备、孙权/孙策、刘表、马腾、汉室/中立。
- 保持旧数据可兼容加载或有明确迁移 fallback。

设计建议：

1. 审计 `Faction` 的所有使用点。
2. 如果短期发布优先，可先扩展 `Faction` enum：
   - `cao`
   - `yuan`
   - `liuBei`
   - `sun`
   - `liuBiao`
   - `maTeng`
   - `han`
   - `neutral`
3. 移除或弃用 `Faction.opponent`。多势力敌我必须来自 `DiplomacyState` 或新的 `PowerRelation`。
4. 若改为数据驱动 `PowerId`，必须先做兼容桥，不要一轮内强行改完全项目。
5. `DiplomacyState` 迁移为三国势力关系：
   - allied / vassal / neutral / hostile / atWar / truce
   - 增加 legitimacy、prestige、trust、tribute 或 warSupport 可后置。
6. 经济和控制逻辑不能把 neutral fallback 到某个玩家势力。

推荐文件：

- `WWIIHexV0/Core/Faction.swift`
- `WWIIHexV0/Core/DiplomacyState.swift`
- `WWIIHexV0/Core/GameState.swift`
- `WWIIHexV0/Data/ScenarioDefinition.swift`
- `WWIIHexV0/Data/DataLoader.swift`
- `WWIIHexV0/Rules/CommandValidator.swift`
- `WWIIHexV0/Rules/OccupationRules.swift`
- `WWIIHexV0/Rules/StrategicStateSynchronizer.swift`

推荐并发：

- Rules Agent：`Faction` 和敌我判断迁移。
- Data Agent：势力 profile JSON 草案。
- AI Agent：只读确认 agent config 对多势力的影响。
- Docs / QA Agent：文档和检查。

验收：

- 多势力可以被 JSON 表达。
- 敌我判断不再依赖 `.opponent`。
- 中立地块/郡不会被错误算给某个势力。
- `CommandValidator` 对玩家与 AI 仍对称。

轻量检查：

- `jq empty` 检查改动 JSON。
- 对直接改动且可单文件 parse 的 Swift 文件运行 `swiftc -parse`；如果 SwiftUI/SpriteKit/跨文件依赖导致不可行，停止并记录。
- `plutil -lint` 仅在 project 文件变更时运行。

### v2.2：三国地图、剧本和地图编辑器迁移

建议分支：`v2.2-sanguo-scenario-map`

目标：

- 建立第一张可玩三国剧本地图。
- 保留 MapEditor 导出链路。
- 玩家可在默认资源中加载三国剧本，而不是阿登。

默认剧本建议：

```text
id: guandu_200
displayName: 官渡前夜
地图范围：河北、河南、淮北、荆北、江东的抽象区域
主要势力：曹操、袁绍、刘备、孙氏、刘表、马腾、汉室/中立
主目标：官渡、许昌、邺城、下邳、汝南、襄阳、江夏、寿春
首版规模：约 80-160 个 hex，20-40 个 region，6-10 个方面/初始战区
```

三国地形建议：

- plain -> 平原
- forest -> 林地
- hill/mountain -> 丘陵/山地
- city -> 城池
- fortress -> 关隘/要塞
- river -> 黄河/淮水/长江支流
- road -> 官道
- 可后置：farmland、marsh、pass、port

三国 JSON 文件建议：

- `WWIIHexV0/Data/guandu_200_scenario.json`
- `WWIIHexV0/Data/guandu_200_regions.json`
- `WWIIHexV0/Data/sanguo_unit_templates.json`
- `WWIIHexV0/Data/sanguo_generals.json`
- `WWIIHexV0/Data/sanguo_terrain_rules.json`

MapEditor 迁移：

- `province` UI 改为郡/州。
- `theater` UI 改为方面/战线。
- `unit` UI 改为军队/武将。
- 支持 `assignedGeneralId` 显示为武将。
- 支持城池、关隘、渡口、粮仓、港口等字段；如果 schema 暂不支持，先记录后置，不要塞到无关字段。

推荐并发：

- Data Agent：新 JSON 和 DataLoader 默认入口。
- MapEditor Agent：编辑器中文术语和导出字段兼容。
- UI Agent：地图层显示名和 accessibility label。
- Docs / QA Agent：同步 flow 和 README。

验收：

- 默认新局加载三国剧本路径。
- `MapEditorExporter` 可以导出三国语义地图而不丢 region/theater/unit。
- 默认数据不再出现阿登主剧本名。
- 所有 id 使用 ASCII，展示名可为中文。

轻量检查：

- 对新/改 JSON 跑 `jq empty`。
- 如果改 project，跑 `plutil -lint WWIIHexV0.xcodeproj/project.pbxproj`。
- 文档尾随空白和冲突标记扫描。

### v2.3：三国军队、战术、围城和粮草规则

建议分支：`v2.3-sanguo-war-rules`

目标：

- 把二战单位和战术转换为三国战棋规则。
- 保留 hex 战术权威和统一命令管线。
- 首版规则要可解释、可调参，不追求复杂模拟。

单位模型建议：

- 源码可短期保留 `Division`，但 UI 显示必须是军队/部曲/营。
- `ComponentType` 迁移为：
  - infantry：步卒
  - cavalry：骑兵
  - archer：弓弩
  - siegeEngine：攻城器械
  - naval：舟师，若首张地图无水战可后置
  - guard：禁军/亲卫，可后置
- stats 仍可保留 attack/defense/movement/range/vision。
- 增加 morale / fatigue / grainCarry 可后置；首版可用 strength + supplyState 兼容。

战术映射建议：

- `standardAttack` -> 正攻
- `spearhead` -> 突击
- `breakthrough` -> 破阵
- `pincerMovement` -> 合围
- `fireCoverage` -> 箭雨/器械压制
- `feint` -> 佯攻
- `guerrillaWarfare` -> 奇袭/袭扰
- `holdPosition` -> 固守
- `elasticDefense` -> 诱敌/退守
- `defenseInDepth` -> 层层设防
- `lastStand` -> 死守

新增或迁移规则：

- 粮草：`SupplyRules` 保留基础，展示为粮道/粮草。
- 围城：城池 region 或 fortress hex 被敌邻接且粮道断绝时，防御和恢复下降；占领仍必须从 hex 执行。
- 士气：可先从日志和战斗修正开始，不强制首轮加字段。
- 武将影响：首版可通过 `GeneralAssignment` 的 skill 调整 tactic 选择或小幅战斗修正，不能直接跳过规则。
- 兵种克制：骑兵在平原机动优势，弓弩有 range，器械对城池/关隘有效，山地限制骑兵。

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

推荐并发：

- Rules Agent：军队、战斗、粮草、围城。
- AI Agent：战术分类器三国化。
- Data Agent：unit templates。
- UI Agent：只做术语显示，不做大 UI。

验收：

- 玩家和 AI 的移动、攻击、防守、补给仍经 `RuleEngine`。
- 围城和粮草日志能被解释。
- 战术名称在 UI 和 `WarDirectiveRecord` 中三国化。
- 没有二战兵种显示残留。

轻量检查：

- 改 JSON 跑 `jq empty`。
- 少量 Swift 文件可尝试单文件 parse；失败则记录依赖风险。
- 禁止跑全项目 build/test。

### v2.4：君主、军师、太守、武将 AI Agent 分层

建议分支：`v2.4-sanguo-agent-court`

目标：

- 构建真正有三国味道的 AI Agent 层级。
- Agent 之间可以协作，但最终都必须输出结构化 directive。
- 让 AI 行为可审计、可回放、可调参。

推荐层级：

```text
MonarchAgent 君主
  -> 决定总战略：扩张、守成、联盟、背刺、收拢民心、勤王

StrategistAgent 军师
  -> 把君主战略变成方面目标：攻许昌、守官渡、断粮道、取江夏

GovernorAgent 太守
  -> 处理郡县内政：征兵、修路、屯田、治安、补给

GeneralAgent 武将
  -> 把方面目标变为 ZoneDirective：进攻、防守、佯攻、合围、围城

DiplomatAgent 外交
  -> 输出外交提案：同盟、停战、借道、称臣、讨伐檄文
```

执行链路要求：

```text
MonarchAgent / StrategistAgent / GovernorAgent / DiplomatAgent
  -> StrategicDirectiveEnvelope 或 TheaterDirectiveEnvelope
  -> decoder / validator / compiler
  -> ZoneDirective / Command
  -> WarCommandExecutor / RuleEngine
  -> WarDirectiveRecord / AgentDecisionRecord / Diplomacy record
```

结构化输出要求：

- 所有 Agent 输出必须 Codable。
- 所有外部模型输出必须 fenced JSON 或纯 JSON，由 decoder 校验。
- decoder 必须校验 schemaVersion、turn、issuerId、faction/power、zone、region、tactic。
- decoder 失败时走安全 fallback，不执行半成品。
- Agent prompt 中不能要求模型“直接修改状态”。

Mock / 本地 LLM 要求：

- 首版仍可用模拟 LLM / MockAI。
- 真实本地 LLM 接入必须单独版本，不能把 API key 或模型路径硬编码进仓库。
- 网络或本地模型不可用时，必须有 deterministic fallback。

Agent 个性建议：

- 曹操：进取、重视粮道和奇袭，偏好集中优势。
- 袁绍：兵力充足但优柔，偏好大规模压迫，响应较慢。
- 刘备：保守求存、重视同盟和民心，倾向避实击虚。
- 孙氏：重视江淮/水网机动，偏好侧翼和快速夺城。
- 刘表：守成，重视荆州稳定。
- 马腾：骑兵突袭，低内政权重。

推荐并发：

- AI Agent：Agent schema、prompt builder、fallback。
- Rules Agent：外交/内政 directive 的 validator 和 executor 边界。
- UI Agent：AI 决策复盘面板显示层。
- Docs / QA Agent：更新 flowchart。

验收：

- AI 回合能解释“君主想要什么、军师选哪里、武将做了什么”。
- 玩家能在 AI 面板看到 raw JSON、编译后的 directive、命令结果和拒绝原因。
- Agent 决策失败不会破坏回合。
- 仍未绕过 `RuleEngine`。

### v2.5：发布级三国 UI、美术和交互收口

建议分支：`v2.5-sanguo-ui-polish`

目标：

- 把当前工程从开发调试界面提升到可发布演示界面。
- 不靠一堆说明文字，而靠地图、面板、状态、动效让玩家理解当前战局。

视觉方向：

- 主地图：绢帛/水墨质感，但不要整屏单一米色。用地形色、势力色、墨线、朱印、青绿河流和铜色 UI 形成层次。
- 势力：每个势力有旗色、印章图标、简短称号。
- 城池：城市、关隘、渡口、粮仓、港口有不同图标。
- 部队：棋子/军牌要能区分步、骑、弓、器械，显示 strength、行动状态、粮草警告。
- 武将：头像、姓名、字/称号、统率/武力/智谋/政治/魅力、忠诚、性格、技能。
- 战线：用墨线/朱线表现敌我接触，用箭头表现计划行动，用粮道虚线表现补给。
- 战报：用简洁列表展示本回合关键行动、拒绝原因、占领变化、外交事件。

主界面布局建议：

```text
顶部：回合、当前势力、资源、胜利状态、结束回合
中央：SpriteKit 战场地图，全屏优先
左侧或底部：选中对象摘要，移动端可折叠
右侧或底部：武将/军令/城郡/战报/AI tabs
地图上：选中、可移动、可攻击、计划线、前线、粮道
```

SwiftUI 要求：

- 建立 `SanguoDesignTokens` 或类似共享设计常量。
- 44pt 最小触控区。
- 使用 `Label` 替代不必要的手写 icon+text。
- 避免 body 内重复排序、过滤、JSON 格式化。
- 大列表用 Lazy 容器。
- 复杂面板拆成独立 View，不要继续膨胀 `RootGameView`。
- 不引入第三方框架，除非人工确认。

SpriteKit 要求：

- 地图必须在桌面和移动端都可缩放、平移、点击。
- 文字不能重叠到不可读。
- 单位和城池图标有稳定尺寸，不因状态变化造成跳动。
- 图层切换清晰：地形、郡县、势力、前线、粮道、AI 计划。

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

- 若要生成头像/地图纹理等 raster 资产，必须保证不是抄袭现有商业游戏角色图。
- 资产命名用 ASCII，例如 `portrait_cao_cao`, `banner_sun`, `icon_grain`.

### v2.6：发布候选、存档、新手引导和验收

建议分支：`v2.6-sanguo-release-candidate`

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
- README 和 flow 文档准确描述当前三国架构。
- `update_log.md` 记录 v2.0-v2.6 每版完成内容、关键文件、轻量检查和未跑重测试。

发布前需要人工授权的重验证：

- Xcode build。
- iOS Simulator 或真机启动。
- macOS target 启动。
- 至少 10-20 回合观察者模式。
- 基础 UI 点击烟测。
- 性能体感检查。

在未获授权前，不得声称“可发布”。只能写“发布候选代码和文档已准备，运行时验证未授权，风险未验证”。

---

## 5. 数据 schema 方向

建议新建或迁移为这些数据概念：

### 势力

```json
{
  "id": "power_cao",
  "displayName": "曹操",
  "shortName": "曹",
  "capitalRegionId": "region_xuchang",
  "rulerAgentId": "ruler_cao_cao",
  "bannerAsset": "banner_cao",
  "primaryColor": "#8A1F1F",
  "secondaryColor": "#D6B15E",
  "legitimacy": 62,
  "warSupport": 78
}
```

### 武将

```json
{
  "id": "general_zhang_liao",
  "name": "Zhang Liao",
  "localizedName": "张辽",
  "courtesyName": "文远",
  "rank": "偏将军",
  "faction": "cao",
  "commandStyle": "aggressive",
  "attributes": {
    "command": 91,
    "valor": 88,
    "strategy": 76,
    "governance": 54,
    "charisma": 72
  },
  "skills": ["cavalry_charge", "discipline", "night_raid"],
  "biography": "善骑战，长于突击与整肃军阵。",
  "preferredRegionIds": ["region_hefei"],
  "baseLoyalty": 82,
  "baseSatisfaction": 74
}
```

### 城郡

```json
{
  "id": "region_xuchang",
  "name": "许昌",
  "owner": "cao",
  "controller": "cao",
  "terrain": "plain",
  "city": {
    "name": "许昌",
    "victoryPoints": 5,
    "isCapital": true
  },
  "infrastructure": 5,
  "supplyValue": 5,
  "resources": [
    { "type": "grain", "amount": 5 },
    { "type": "copper", "amount": 2 }
  ],
  "coreOf": ["cao", "han"]
}
```

实际实现可沿用现有结构，但必须在阶段文档写明哪些字段是兼容旧名、哪些字段已经三国化。

---

## 6. 文档更新要求

每个版本完成后至少更新：

- `update_log.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- 当前版本实现记录，例如：
  - `md/prompt/v2.0-三国迁移/v2.0_audit_and_contract.md`
  - `md/prompt/v2.0-三国迁移/v2.1_powers_implementation_record.md`
  - `md/prompt/v2.0-三国迁移/v2.2_scenario_map_record.md`

当项目身份正式从 WWII 迁移到三国后，才更新：

- `AGENTS.md` 的项目总览和基本规则。
- `README.md` 的项目定位、架构图和当前进度。

不要在只完成提示词或审计时伪装成正式版本完成。

---

## 7. 轻量检查要求

执行任何版本前必须读 `md/test/test.md`。当前默认只允许轻量检查。

通用允许项：

```sh
rg -n "[[:blank:]]+$" AGENTS.md README.md update_log.md md/test/test.md md/flow/flow.md md/flow/flowchart.md md/prompt/v2.0-三国迁移
rg -n "<<<<<<<|=======|>>>>>>>" AGENTS.md README.md update_log.md md/test/test.md md/flow WWIIHexV0 MapEditor
```

JSON 改动：

```sh
jq empty WWIIHexV0/Data/guandu_200_scenario.json
jq empty WWIIHexV0/Data/guandu_200_regions.json
jq empty WWIIHexV0/Data/sanguo_unit_templates.json
jq empty WWIIHexV0/Data/sanguo_generals.json
```

project 改动：

```sh
plutil -lint WWIIHexV0.xcodeproj/project.pbxproj
```

Swift 轻量 parse：

```sh
swiftc -parse path/to/ChangedFile.swift
```

如果 Swift 文件依赖 SwiftUI、SpriteKit、跨文件类型或 SDK 导致单文件 parse 不可靠，立即停止，记录“未做语法检查，需授权 Xcode build 确认”，不要扩大为全项目构建。

禁止默认执行：

- `xcodebuild build`
- `xcodebuild test`
- `xcodebuild build-for-testing`
- `xcrun simctl`
- Probe / Smoke / Stage Regression / Dynamic Theater Regression / Full
- 模拟器启动
- app 启动
- 性能测试

---

## 8. 验收总标准

每个阶段最终回复必须包含：

1. 完成了什么。
2. 改了哪些关键文件。
3. 跑了哪些轻量检查，具体结果是什么。
4. 哪些重测试没跑，原因是什么。
5. 还剩什么风险或下一步。

v2.6 发布候选的最终验收额外要求：

- 主 UI 和默认数据无主要二战残留。
- 默认剧本是三国剧本。
- 多势力关系不依赖二元 `opponent`。
- AI Agent 决策可追踪到 JSON、directive、command result。
- 玩家命令和 AI 命令仍共用规则管线。
- MapEditor 能维护三国地图语义。
- 文档与代码口径一致。
- 如果没有人工授权重测试，必须明确“运行时发布风险未验证”。

---

## 9. 给执行 Agent 的起步指令

请按下面顺序开始，不要跳步：

1. 阅读 `AGENTS.md`、`update_log.md`、`md/flow/flow.md`、`md/flow/flowchart.md`、`md/test/test.md`、本文件。
2. 读取当前源码中与目标版本有关的文件，不凭旧记忆修改。
3. 先做当前工作树和分支审计，不回滚用户改动。
4. 如果本轮是 v2.0，先写审计和接口合同，不要直接大迁移。
5. 如果本轮是 v2.1 或之后，先确认上一版本记录已经存在且与源码一致。
6. 需要并发时，主 Agent 先给子 Agent 分文件边界和输出格式。
7. 子 Agent 完成后，主 Agent 做冲突整合检查。
8. 只跑 `md/test/test.md` 允许的轻量检查。
9. 同步文档。
10. 最终回复按项目交付格式写清楚结果、检查和风险。

本迁移任务的核心难点不是写更多功能，而是守住三条线：

- 规则权威线：所有行动仍归 `RuleEngine`。
- 状态权威线：hex 和动态映射不能被战略层反向覆盖。
- Agent 审计线：AI 输出必须结构化、可验证、可回放。
