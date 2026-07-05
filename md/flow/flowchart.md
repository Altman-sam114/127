# WWIIHexV0 Mermaid 核心流程图

> 本图参照 `md/flow/flow.md`。每个图块都用“中文解释 + 关键代码名”标注：先看中文理解逻辑，再用代码名回到源码定位。

## 0. 读图总纲

项目当前最重要的逻辑是：

```text
地图编辑器/JSON 数据
  -> 游戏启动加载为 GameState
  -> hex 是真实战术权威
  -> region / theater / front / deploy 都是从 hex 和单位位置派生出来的战略层
  -> economy 是 faction 级经济总账，收入仍从真实控制的 hex/region 聚合
  -> v0.5 元帅层是战略意图层，不替代战术权威
  -> 玩家和 AI 都必须把命令交给 RuleEngine
  -> 命令执行后再同步刷新战略层和 UI
```

图里颜色含义：

- 红色：权威状态，不能被下游反向覆盖。
- 绿色：派生状态，可以重建，但来源必须清楚。
- 蓝色：初始快照/基准状态，不是运行时推进状态。
- 紫色：命令管线，玩家、AI、未来聊天命令都要走这里。

## 0.1 云端协作与结果包验收

这张图只描述协作和验证闭环，不改变游戏运行时业务逻辑。当前默认只使用 `main` 直推，不使用 `smalldata_test`、`develop`、`codeb/...`、候选分支或 PR 合并流。

```mermaid
flowchart TD
    HUMAN["人工提出目标<br/>说明范围、禁止项、验收标准"]:::input
    A["Agent A<br/>读取 AGENTS / flow / test / prompt<br/>写版本化实现提示词"]:::agent
    B0["Agent B 开始<br/>git fetch origin<br/>git switch main<br/>git pull --ff-only origin main"]:::git
    B1["Agent B 实现<br/>只改本轮相关文件<br/>不改业务范围外逻辑"]:::agent
    LOCAL["本机轻量检查<br/>git diff --check / plutil / xmllint / jq / YAML<br/>不跑本机 xcodebuild"]:::check
    COMMIT["main 本地提交<br/>commit 范围只含本轮文件"]:::git
    PUSH["推送 origin/main<br/>git push origin main"]:::git
    GHA["GitHub Actions<br/>ci-results.yml<br/>静态检查 + 云端 xcodebuild build"]:::cloud
    ART["未加密 CI 结果包<br/>manifest / junit / xcodebuild.log / failure summary / xcresult"]:::artifact
    C0["Agent C<br/>gh auth login<br/>下载 artifact 到 /private/tmp/wwiihexv0-c-review-run_id"]:::agent
    C1{"manifest 是否匹配<br/>branch=main<br/>commitSha/runId/runAttempt 最新?"}:::decision
    C2{"CI 和日志是否通过?"}:::decision
    REJECT["退回清单<br/>Agent B 在 main 追加修复 commit<br/>重新 push 触发新 run"]:::stop
    ACCEPT["验收通过<br/>确认 origin/main 最新 run<br/>同步 flow / update_log"]:::ok

    HUMAN --> A --> B0 --> B1 --> LOCAL --> COMMIT --> PUSH --> GHA --> ART --> C0 --> C1
    C1 -->|否| REJECT --> B0
    C1 -->|是| C2
    C2 -->|失败| REJECT
    C2 -->|通过| ACCEPT

    classDef input fill:#fef3c7,stroke:#d97706,color:#1f1600
    classDef agent fill:#e0e7ff,stroke:#4f46e5,color:#111827
    classDef git fill:#e0f2fe,stroke:#0284c7,color:#082f49
    classDef check fill:#dcfce7,stroke:#16a34a,color:#052e16
    classDef cloud fill:#fae8ff,stroke:#a21caf,color:#2a0a2f
    classDef artifact fill:#f8f9fb,stroke:#6b7280,color:#111827
    classDef decision fill:#fff7ed,stroke:#ea580c,color:#1f1300
    classDef stop fill:#fee2e2,stroke:#b91c1c,color:#111827
    classDef ok fill:#ccfbf1,stroke:#0f766e,color:#042f2e
```

## 0.2 v6.0 现代战争迁移兼容层

这张图描述当前 v6.0 已落地的显示兼容层。它只改变玩家可见术语，不改变 JSON raw value、命令管线、战斗规则或默认剧本。

```mermaid
flowchart LR
    LEGACY["旧源码 / 旧 JSON 兼容名<br/>Faction.germany/allies<br/>GamePhase.germanAI/alliedPlayer<br/>Division.name<br/>ProductionKind.panzerDivision<br/>MapDisplayLayer.province"]:::legacy
    DISPLAY["现代显示层<br/>Red / Blue Force<br/>Red Command / Blue Command<br/>operationalDisplayName<br/>Armored / Mechanized Task Force<br/>Sector / Operational / Brigade"]:::display
    RULES["规则权威不变<br/>Command / ZoneDirective<br/>WarCommandExecutor<br/>RuleEngine"]:::rules
    RISK["后续兼容风险<br/>GamePhase raw value<br/>旧阿登 fallback<br/>深水 ROE fire rule"]:::risk

    LEGACY --> DISPLAY
    LEGACY --> RULES
    RULES --> RISK

    classDef legacy fill:#fef3c7,stroke:#d97706,color:#1f1600
    classDef display fill:#e0f2fe,stroke:#0284c7,color:#082f49
    classDef rules fill:#ccfbf1,stroke:#0f766e,color:#042f2e
    classDef risk fill:#fee2e2,stroke:#b91c1c,color:#111827
```

## 0.3 v6.1 作战方与 ROE 兼容层

这张图描述当前 v6.1 第一批实现。它让现代作战方、neutral fallback 和最小 ROE helper 进入底层，但还没有切换默认现代剧本。

```mermaid
flowchart LR
    DATA["JSON / MapEditor 数据值<br/>germany / allies<br/>blueForce / redForce<br/>power_blue / power_red<br/>neutral / civilian"]:::data
    FACTION["Faction.dataValue<br/>解析旧值和现代 alias"]:::state
    ALIGN["OperationalSideAlignment<br/>blue / red / green / neutral"]:::state
    ROE["ROE helper<br/>defaultROEStatus<br/>isHostile(to:)"]:::rules
    REGION["RegionDataSet fallback<br/>nil owner/controller -> neutral"]:::rules
    PIPE["命令与规则管线不变<br/>Command / ZoneDirective<br/>WarCommandExecutor / RuleEngine"]:::command
    TODO["后续 v6.9+<br/>试玩闭环 / 新局设置<br/>通用 phase raw value"]:::risk

    DATA --> FACTION --> ALIGN --> ROE --> PIPE
    DATA --> REGION --> PIPE
    PIPE --> TODO

    classDef data fill:#f8f9fb,stroke:#6b7280,color:#111827
    classDef state fill:#e0f2fe,stroke:#0284c7,color:#082f49
    classDef rules fill:#ccfbf1,stroke:#0f766e,color:#042f2e
    classDef command fill:#fae8ff,stroke:#a21caf,color:#2a0a2f
    classDef risk fill:#fee2e2,stroke:#b91c1c,color:#111827
```

## 0.4 v6.2 灰潮行动默认剧本种子

这张图描述当前 v6.2 第一批实现。默认新局优先加载现代剧本种子，旧阿登资源只保留作 fallback / 历史兼容。

```mermaid
flowchart LR
    ENTRY["DataLoader.loadInitialGameState"]:::data
    GREY["grey_tide_2030_scenario<br/>grey_tide_2030_regions"]:::data
    MAP["120 hex / 30 region<br/>Blue / Red / Neutral"]:::state
    EDITOR["MapEditor 默认资源桥<br/>读写 grey_tide_2030"]:::state
    PIPE["既有运行链<br/>Hex -> Region -> Theater<br/>FrontLine / WarDeployment"]:::rules
    FALLBACK["失败回退<br/>ardennes_v0 + ardennes_v02<br/>GameState.initial"]:::legacy
    TODO["后续 v6.10+<br/>运行时验证<br/>10-20 observer turns"]:::risk

    ENTRY --> GREY --> MAP --> PIPE
    GREY --> EDITOR
    ENTRY --> FALLBACK
    PIPE --> TODO

    classDef data fill:#f8f9fb,stroke:#6b7280,color:#111827
    classDef state fill:#e0f2fe,stroke:#0284c7,color:#082f49
    classDef rules fill:#ccfbf1,stroke:#0f766e,color:#042f2e
    classDef legacy fill:#fef3c7,stroke:#d97706,color:#1f1600
    classDef risk fill:#fee2e2,stroke:#b91c1c,color:#111827
```

## 0.5 v6.3 现代单位、移动、战斗和后勤基础

这张图描述当前 v6.3 第一批实现。默认现代剧本使用现代合成作战模板；旧阿登数据集仍固定使用 legacy 模板，避免旧测试和 fallback 语义被现代模板覆盖。

```mermaid
flowchart LR
    ENTRY["DataLoader.loadInitialGameState<br/>默认新局"]:::data
    GREY["grey_tide_2030_scenario<br/>现代 templateId"]:::data
    MODERN["modern_unit_templates.json<br/>armor / mech / recon / fires<br/>AD / engineer / logistics / UAV / EW"]:::state
    DIV["Division.components<br/>源码名保留 Division<br/>组件语义现代化"]:::state
    RULES["既有规则管线不变<br/>WarCommandExecutor<br/>RuleEngine"]:::command
    MODIFIERS["v6.3 首版 modifiers<br/>terrain movement<br/>combat multiplier<br/>supply degradation<br/>reinforcement cost"]:::rules
    UI["玩家可见显示<br/>task force / battery / detachment<br/>tacticDisplayName"]:::display
    LEGACY["loadArdennesDataSet<br/>unit_templates.json<br/>旧 id / fixture 兼容"]:::legacy
    TODO["v6.5 已接抽象火力<br/>后续 ammo / fuel<br/>readiness / signature"]:::risk

    ENTRY --> GREY --> MODERN --> DIV --> RULES --> MODIFIERS --> UI
    ENTRY --> LEGACY
    RULES --> TODO

    classDef data fill:#f8f9fb,stroke:#6b7280,color:#111827
    classDef state fill:#e0f2fe,stroke:#0284c7,color:#082f49
    classDef rules fill:#ccfbf1,stroke:#0f766e,color:#042f2e
    classDef command fill:#fae8ff,stroke:#a21caf,color:#2a0a2f
    classDef display fill:#e0f2fe,stroke:#0284c7,color:#082f49
    classDef legacy fill:#fef3c7,stroke:#d97706,color:#1f1600
    classDef risk fill:#fee2e2,stroke:#b91c1c,color:#111827
```

## 0.6 v6.4 ISR、ContactTrack 和电子战基础

这张图描述当前 v6.4 第一批实现。它让 AI/UI 读取 contact 摘要而不读取真实敌军列表；真实 `linkedDivisionId` 只在规则层内部用于把 medium+ contact 解析成可攻击目标。

```mermaid
flowchart LR
    UNITS["友军单位<br/>vision / recon / UAV / AD / EW"]:::state
    SENSOR["SensorCoverage<br/>coord / side / quality / source / jammed"]:::state
    EW["EWEffect<br/>jamming / comms degrade<br/>drone disrupt / spoof"]:::rules
    CONTACT["ContactTrack<br/>lastKnownCoord<br/>confidence / estimatedType<br/>source / age"]:::state
    CMD["Command.recon / electronicWarfare<br/>CommandValidator<br/>CommandExecutor"]:::command
    AI["AI 摘要<br/>AgentContext.contactSummaries<br/>Zone / Marshal contact strength"]:::agent
    UI["UI 摘要<br/>Region inspector contacts<br/>contact-gated attack highlights"]:::display
    EXEC["WarCommandExecutor<br/>medium+ contact -> internal linkedDivisionId<br/>再交 RuleEngine"]:::rules
    FIRES["v6.5 火力接入<br/>FireMission / AirTasking<br/>防空压制 / UAV recon"]:::rules

    UNITS --> SENSOR --> CONTACT
    EW --> SENSOR
    CMD --> SENSOR
    CMD --> EW
    CONTACT --> AI
    CONTACT --> UI
    CONTACT --> EXEC
    EXEC --> FIRES

    classDef state fill:#e0f2fe,stroke:#0284c7,color:#082f49
    classDef rules fill:#ccfbf1,stroke:#0f766e,color:#052e16
    classDef command fill:#fae8ff,stroke:#a21caf,color:#2a0a2f
    classDef agent fill:#e0e7ff,stroke:#4f46e5,color:#111827
    classDef display fill:#f8f9fb,stroke:#6b7280,color:#111827
    classDef risk fill:#fee2e2,stroke:#b91c1c,color:#111827
```

## 0.7 v6.5 精确火力、空地协同、无人系统和防空抽象

这张图描述当前 v6.5 第一批实现。火力和空中任务只通过 `Command` 进入规则系统；FireSupport 不占领 hex，只影响 damage、retreat、contact quality、AD suppression 和日志。

```mermaid
flowchart LR
    CONTACT["ContactTrack<br/>medium+ target quality<br/>contact / hex / region target"]:::state
    CMD["Command.fireMission<br/>uavRecon<br/>suppressAirDefense"]:::command
    VALID["CommandValidator<br/>source asset / ammo / cooldown<br/>target quality / range / ROE<br/>AD / EW / friendly risk"]:::rules
    FIRE["FireSupportRules<br/>FireMission plan<br/>MunitionClass<br/>FireMissionResult"]:::rules
    AIR["AirTaskingState<br/>sorties / AD threat<br/>airSuperiority / suppression"]:::state
    DAMAGE["有限效果<br/>strength damage<br/>retreat / destroyed<br/>no hex occupation"]:::rules
    LOG["fireSupport 日志<br/>success / degraded / failed / suppressed<br/>risk flags"]:::display
    GROUND["地面推进<br/>move / attack<br/>仍由 RuleEngine 处理"]:::command

    CONTACT --> CMD --> VALID --> FIRE
    VALID --> AIR
    FIRE --> AIR
    FIRE --> DAMAGE --> LOG
    FIRE --> GROUND

    classDef state fill:#e0f2fe,stroke:#0284c7,color:#082f49
    classDef rules fill:#ccfbf1,stroke:#0f766e,color:#052e16
    classDef command fill:#fae8ff,stroke:#a21caf,color:#2a0a2f
    classDef display fill:#f8f9fb,stroke:#6b7280,color:#111827
```

## 0.8 v6.6 现代 AI Agent 指挥链和审计复盘

这张图描述当前 v6.6 第一批实现。现代指挥链只作为 advisory JSON 和复盘层接入，不直接执行 sub-directive；最终行动仍回到 `ZoneDirective -> WarCommandExecutor -> RuleEngine`。

```mermaid
flowchart LR
    MARSHAL["MarshalAgent<br/>Battlefield summary<br/>Operational Directive JSON"]:::agent
    TDEC["TheaterDirectiveDecoder<br/>schema / issuer / turn / faction<br/>zone / region / tactic"]:::rules
    ORCH["ModernCommandChainOrchestrator<br/>National / Joint / Chief<br/>ISR / Fires / Air / EW / Logistics / Brigade"]:::agent
    CJSON["ModernCommandChainPlan JSON<br/>StrategicConstraintEnvelope<br/>JointCommandPlan<br/>ModernSubDirective"]:::data
    CDEC["ModernCommandChainDecoder<br/>nested schema / role<br/>zone / region / contact / mission"]:::rules
    FAIL["失败只写 diagnostics<br/>不执行半成品"]:::stop
    COMP["TheaterDirectiveCompiler<br/>编译 ZoneDirective"]:::command
    EXEC["WarCommandExecutor<br/>RuleEngine"]:::rules
    RECORD["AgentDecisionRecord<br/>rawJSON + commandChainReplayItems<br/>raw invalid JSON retained when available"]:::display
    PANEL["AgentPanelView<br/>role / mission / priority<br/>target / rationale / diagnostics"]:::display

    MARSHAL --> TDEC --> ORCH --> CJSON --> CDEC
    CDEC -->|通过| COMP --> EXEC
    CDEC -->|失败| FAIL
    TDEC --> COMP
    CJSON --> RECORD
    COMP --> RECORD
    EXEC --> RECORD
    RECORD --> PANEL

    classDef agent fill:#e0e7ff,stroke:#4f46e5,color:#111827
    classDef data fill:#f8f9fb,stroke:#6b7280,color:#111827
    classDef rules fill:#ccfbf1,stroke:#0f766e,color:#052e16
    classDef command fill:#fae8ff,stroke:#a21caf,color:#2a0a2f
    classDef display fill:#f8f9fb,stroke:#6b7280,color:#111827
    classDef stop fill:#fee2e2,stroke:#b91c1c,color:#111827
```

## 0.9 v6.7 玩家现代指挥 UI 和任务计划

这张图描述当前 v6.7 第一批实现。玩家通过任务面板发起现代任务，但 SwiftUI 只调用 `AppContainer`，最终仍进入 `Command` / `ZoneDirective` 与规则系统。

```mermaid
flowchart LR
    UI["ModernMissionPanelView<br/>Tasks tab<br/>8 类任务按钮"]:::display
    APP["AppContainer<br/>orderModern... 方法<br/>选择单位 / hex / region / contact"]:::app
    CMD["Command<br/>recon / uavRecon / fireMission<br/>suppressAirDefense / electronicWarfare / resupply"]:::command
    DIR["ZoneDirective<br/>Assault Objective<br/>Hold / Delay"]:::command
    VALID["CommandValidator<br/>phase / faction / range<br/>target quality / ammo / AD / EW"]:::rules
    WCE["WarCommandExecutor<br/>玩家宏观 directive<br/>生成具体 Command"]:::rules
    RE["RuleEngine<br/>CommandExecutor<br/>Visibility / FireSupport / Supply"]:::rules
    LOG["lastCommandMessage<br/>interaction log<br/>WarDirectiveRecord"]:::display
    PLAN["PlayerPlannedOperation<br/>attack / defend 计划线"]:::state

    UI --> APP
    APP --> CMD --> VALID --> RE --> LOG
    APP --> DIR --> WCE --> RE
    DIR --> PLAN
    WCE --> LOG

    classDef display fill:#f8f9fb,stroke:#6b7280,color:#111827
    classDef app fill:#e0e7ff,stroke:#4f46e5,color:#111827
    classDef command fill:#fae8ff,stroke:#a21caf,color:#2a0a2f
    classDef rules fill:#ccfbf1,stroke:#0f766e,color:#052e16
    classDef state fill:#e0f2fe,stroke:#0284c7,color:#082f49
```

## 0.10 v6.8 现代 C2 状态 UI 和地图态势 overlay

这张图描述当前 v6.8 第一批实现。它只从既有 `GameState` 读取态势并绘制 UI，不新增执行器，也不绕过 `Command` / `RuleEngine`。

```mermaid
flowchart LR
    GS["GameState<br/>作战态势权威容器"]:::state
    AWARE["OperationalAwarenessState<br/>contacts / sensorCoverage / ewEffects"]:::state
    FIRE["FireSupportState<br/>ammo / airTasking / lastMissionResults"]:::state
    ECON["EconomyState + Division.supplyState<br/>C2 queue / supply risk"]:::state
    TOKENS["ModernCommandDesignTokens<br/>spacing / radius / 44pt tap<br/>side / sensor / fires / EW colors"]:::display
    HUD["HUDView<br/>C2 status strip<br/>contacts / EW / ammo / air / supply"]:::display
    TASKS["ModernMissionPanelView<br/>tokenized mission controls<br/>Label + SF Symbols"]:::display
    MAP["BoardScene.drawModernC2Overlays<br/>sensor heatmap / contact marker<br/>EW area / fire result ring"]:::display
    RULES["Command / ZoneDirective<br/>WarCommandExecutor / RuleEngine<br/>仍是唯一写状态路径"]:::rules

    GS --> AWARE --> HUD
    GS --> FIRE --> HUD
    GS --> ECON --> HUD
    TOKENS --> HUD
    TOKENS --> TASKS
    AWARE --> MAP
    FIRE --> MAP
    TASKS --> RULES --> GS

    classDef state fill:#e0f2fe,stroke:#0284c7,color:#082f49
    classDef display fill:#f8f9fb,stroke:#6b7280,color:#111827
    classDef rules fill:#ccfbf1,stroke:#0f766e,color:#052e16
```

## 0.11 v6.9-v6.10 新局、继续和试玩闭环

这张图描述当前 v6.9-v6.10 试玩闭环。Playtest 面板只调用 `AppContainer`，红/蓝新局选择、本地快照和地图图层设置都不修改默认数据资源。

```mermaid
flowchart LR
    UI["ModernPlaytestPanelView<br/>Playtest tab<br/>Blue / Red selector<br/>New / Save / Continue / Clear"]:::display
    SETTINGS["试玩设置<br/>Observer AI toggle<br/>Default Layer picker"]:::display
    ROLE["红蓝新局与扮演方<br/>New Operation Side<br/>Player Side / Opposition<br/>Control Mode"]:::display
    GATE["Action Gate<br/>Player orders open<br/>AI ready / advance turn"]:::display
    OBJECTIVE["主目标控制摘要<br/>Blue / Red / Neutral count<br/>Victory threshold"]:::display
    GUIDE["短引导<br/>playtestGuidanceItems<br/>lastCommandMessage"]:::display
    APP["AppContainer<br/>resetGame(playerFaction:)<br/>save / load / clear snapshot"]:::app
    SNAP["UserDefaults 本地快照<br/>LocalPlaytestSnapshot envelope<br/>schemaVersion / playerFaction / GameState<br/>legacy GameState fallback"]:::data
    BOOT["StrategicStateBootstrapper<br/>refreshGeneralAssignments<br/>清空选择/高亮/临时日志"]:::rules
    STATE["GameState<br/>当前试玩局"]:::state
    RES["默认 JSON 资源<br/>grey_tide_2030<br/>不被存档写回"]:::data

    UI --> APP
    SETTINGS --> APP
    ROLE --> APP
    STATE --> ROLE
    STATE --> GATE
    STATE --> OBJECTIVE
    STATE --> GUIDE
    APP --> SNAP
    SNAP --> APP --> BOOT --> STATE
    APP --> STATE
    RES -.-> APP

    classDef display fill:#f8f9fb,stroke:#6b7280,color:#111827
    classDef app fill:#e0e7ff,stroke:#4f46e5,color:#111827
    classDef data fill:#fef3c7,stroke:#d97706,color:#1f1600
    classDef rules fill:#ccfbf1,stroke:#0f766e,color:#052e16
    classDef state fill:#e0f2fe,stroke:#0284c7,color:#082f49
```

## 0.12 v6.10 发布候选准备

这张图描述当前 v6.10 收口项。发布候选准备只处理玩家可见命名、残留扫描、证据矩阵和发布前验证清单，不改变命令执行权威。

```mermaid
flowchart LR
    DISPLAY["App Display Name<br/>Modern Command Agent"]:::display
    ICON["AppIcon asset catalog<br/>iOS / iPadOS / macOS sizes"]:::display
    MAP["HexNode supply marker<br/>SUP B / SUP R"]:::display
    COMMANDERS["Default commanders<br/>fictional Blue / Red C2 staff"]:::display
    TERMS["Visible terminology<br/>National Command / Operational Zone<br/>PER / MAT / LOG"]:::display
    REPORT["v6.10 release candidate report<br/>residual scan / evidence matrix"]:::doc
    RULES["规则权威不变<br/>Command / ZoneDirective<br/>WarCommandExecutor / RuleEngine"]:::rules
    CLOUD["main push<br/>GitHub Actions artifact<br/>manifest / junit / xcodebuild.log"]:::cloud
    SIDE["Playtest side selector<br/>Blue / Red new operation<br/>AI controls non-player hostile side"]:::display
    GATE["Playtest Action Gate<br/>player / AI / observer / end-turn state"]:::display
    OBJ["Playtest objective summary<br/>10 main objectives<br/>Blue threshold / Red hold condition"]:::display
    RUNTIME["人工授权后再做<br/>launch / UI smoke / screenshot<br/>10-20 observer turns / performance"]:::risk

    DISPLAY --> REPORT
    ICON --> REPORT
    MAP --> REPORT
    COMMANDERS --> REPORT
    TERMS --> REPORT
    SIDE --> REPORT
    GATE --> REPORT
    OBJ --> REPORT
    RULES --> REPORT
    REPORT --> CLOUD
    REPORT --> RUNTIME

    classDef display fill:#f8f9fb,stroke:#6b7280,color:#111827
    classDef doc fill:#e0e7ff,stroke:#4f46e5,color:#111827
    classDef rules fill:#ccfbf1,stroke:#0f766e,color:#052e16
    classDef cloud fill:#fae8ff,stroke:#a21caf,color:#2a0a2f
    classDef risk fill:#fee2e2,stroke:#b91c1c,color:#111827
```

## 1. 总主线：从地图数据到游戏行动

这张图看全局。左上是地图数据怎么进入游戏；中间是 hex、region、theater、front、deploy 的分层关系；右侧是玩家/AI 命令如何统一进入规则系统；底部是 UI 和日志怎么读取结果。

```mermaid
flowchart TD
    ME["地图编辑器<br/>MapEditor<br/>用来画格子、区域、作战区、初始任务编组"]:::editor
    JSON["游戏数据 JSON<br/>ScenarioDefinition + RegionDataSet<br/>保存地图、任务编组、区域、初始作战区"]:::data
    DL["数据加载器<br/>DataLoader.loadGameState<br/>把 JSON 变成可运行 GameState"]:::loader
    GS["运行时总状态<br/>GameState<br/>一局游戏所有状态都在这里"]:::state

    HEX["战术权威：六角格和单位位置<br/>HexTile.controller + Division.coord<br/>谁占哪个格、单位在哪，先看这里"]:::authority
    REGION["省份战略层<br/>RegionNode<br/>资源、补给、胜利点；控制权由 hex 聚合"]:::derived
    INIT["开局战区快照<br/>TheaterInitialSnapshot<br/>记录地图编辑器给的初始战区"]:::snapshot
    R2T["基础战区映射<br/>regionToTheater<br/>只作初始/基准，不表示战线推进"]:::snapshot
    H2T["动态战区权威<br/>hexToTheater<br/>运行时推进只改具体 hex"]:::authority
    FRONT["前线层<br/>FrontLine / FrontSegment<br/>按双方动态战区的真实相邻 hex 生成"]:::derived
    DEPLOY["部署层<br/>WarDeploymentState<br/>用 hexToFrontZone 把单位分成前线/纵深/驻军"]:::derived
    ECO["经济总账<br/>EconomyState / EconomyRules<br/>收入、维护费、生产队列、自动补员"]:::economy
    PLAYER["玩家输入<br/>点击地图、任务面板、试玩面板<br/>移动、攻击、结束回合"]:::input
    PLAYTEST["试玩闭环<br/>ModernPlaytestPanelView<br/>New / Save / Continue / Observer / Layer / Guide"]:::ui
    MISSION["玩家现代任务面板<br/>ModernMissionPanelView<br/>Recon / UAV / Fire / SEAD / EW / Assault / Hold / Resupply"]:::command
    AI["AI 元帅系统<br/>MarshalAgent + Operational Directive JSON<br/>TheaterDirective schema"]:::input
    DEC["元帅 JSON 解码<br/>TheaterDirectiveDecoder<br/>提取 fenced JSON、校验 id 与 schema"]:::command
    MCHAIN["现代指挥链校验<br/>ModernCommandChainPlan<br/>国家/联合/ISR/火力/空中/EW/后勤/旅级 advisory JSON"]:::command
    COMP["元帅意图编译<br/>TheaterDirectiveCompiler<br/>把 TheaterDirective 降级成 ZoneDirective"]:::command
    ZD["战争指令<br/>ZoneDirective<br/>战区级 attack/defend 意图"]:::command
    WCE["指令翻译器<br/>WarCommandExecutor<br/>把战区意图翻成具体单位命令"]:::command
    CMD["底层命令<br/>Command<br/>move / attack / hold / resupply / queueProduction / endTurn"]:::command
    RE["规则引擎<br/>RuleEngine<br/>先校验，再真正修改 GameState"]:::rules
    SYNC["战略同步器<br/>StrategicStateSynchronizer<br/>占领后刷新省份、战区、前线、部署"]:::rules

    UI["地图和面板显示<br/>SpriteKit / SwiftUI Overlay<br/>显示 hex、省份、战区、前线、部署<br/>v6.8 sensor/contact/EW/fire overlay"]:::ui
    LOG["日志和复盘记录<br/>EventLog / WarDirectiveRecord / AgentDecisionRecord<br/>RulerDecisionRecord 仅作未来/兼容预留"]:::ui

    ME --> JSON --> DL --> GS
    GS --> HEX
    HEX --> REGION
    HEX --> ECO
    REGION --> ECO
    REGION --> INIT
    INIT --> R2T
    R2T -.->|缺失时只用来补初始值| H2T
    HEX --> H2T
    H2T --> FRONT --> DEPLOY
    GS --> ECO

    PLAYER --> PLAYTEST
    PLAYER --> MISSION --> CMD
    PLAYER --> CMD
    MISSION --> ZD
    AI --> DEC --> MCHAIN --> COMP --> ZD --> WCE --> CMD
    DEC --> COMP
    CMD --> RE --> HEX
    RE --> ECO
    RE --> SYNC
    SYNC --> REGION
    SYNC --> H2T
    SYNC --> FRONT
    SYNC --> DEPLOY

    GS --> UI
    HEX --> UI
    REGION --> UI
    INIT --> UI
    H2T --> UI
    FRONT --> UI
    DEPLOY --> UI
    ECO --> UI
    DIP --> UI
    RE --> LOG
    WCE --> LOG

    classDef editor fill:#f6d365,stroke:#8a5a00,color:#1f1b10
    classDef data fill:#f8f9fb,stroke:#6b7280,color:#111827
    classDef loader fill:#dbeafe,stroke:#2563eb,color:#0f172a
    classDef state fill:#ede9fe,stroke:#7c3aed,color:#1f143d
    classDef authority fill:#fee2e2,stroke:#dc2626,color:#111827
    classDef derived fill:#dcfce7,stroke:#16a34a,color:#052e16
    classDef snapshot fill:#e0f2fe,stroke:#0284c7,color:#082f49
    classDef input fill:#fef3c7,stroke:#d97706,color:#1f1600
    classDef economy fill:#fef9c3,stroke:#ca8a04,color:#292107
    classDef command fill:#fae8ff,stroke:#a21caf,color:#2a0a2f
    classDef rules fill:#ccfbf1,stroke:#0f766e,color:#042f2e
    classDef ui fill:#e5e7eb,stroke:#4b5563,color:#111827
```

## 2. 占领与动态推进：一个单位移动后发生什么

这张图只看最容易出 bug 的链路：单位移动到敌控空格后，游戏如何占领这个 hex，并且只推进这个 hex 的动态战区和部署归属。

核心原则：占一个 hex，只改这个 hex 的 `hexToTheater` / `hexToFrontZone`；不能把整个 region 的 `regionToTheater` 改掉。

```mermaid
flowchart TD
    A["移动命令进入<br/>Command.move<br/>来源可以是玩家，也可以是 WarCommandExecutor"]:::command
    B["移动合法性检查<br/>CommandValidator.validateMove<br/>检查阶段、阵营、行动力、路径、目标是否被占"]:::rules
    C{"移动是否合法?"}:::decision
    R["命令被拒绝<br/>CommandResult rejected<br/>GameState 不变，只记录拒绝原因"]:::stop
    M["执行移动<br/>CommandExecutor.executeMove<br/>更新单位坐标、朝向、已行动标记"]:::rules
    O{"能否占领目标 hex?<br/>OccupationRules.canOccupy<br/>目标可占、非己方控制、没有其他单位"}:::decision
    NO["普通移动<br/>只改变单位位置<br/>不改变目标 hex 控制权"]:::state
    HC["改写真实占领权<br/>HexTile.controller = division.faction<br/>这是占领的权威来源"]:::authority
    SA{"是否需要推进动态战区?<br/>目标属于敌方 zone 或仍是敌控 hex 时才推进"}:::decision
    ET["推进动态战区<br/>TheaterSystem.expandDynamicTheater<br/>只把目标 hex 写入进攻方 hexToTheater"]:::authority
    AF["推进部署归属<br/>WarDeploymentManager.advanceHex<br/>只把目标 hex 写入进攻方 hexToFrontZone"]:::authority
    SS["占领后同步战略层<br/>StrategicStateSynchronizer<br/>把 hex 变化传导到 region/theater/front/deploy"]:::rules
    RO["刷新省份控制权<br/>RegionOccupationRules.aggregateControl<br/>按 region 内 hex 控制权加权计算"]:::derived
    TU["刷新动态战区摘要<br/>TheaterSystem.updateTheaters(force)<br/>重算控制比例、战区邻接、单位池"]:::derived
    FU["刷新前线<br/>FrontLineManager.update<br/>重新扫描动态战区之间的真实 hex 接触"]:::derived
    DU["刷新部署层<br/>WarDeploymentManager.update<br/>重分前线、纵深、驻军单位"]:::derived
    UI["刷新显示和日志<br/>UI overlay / inspector / EventLog<br/>玩家看到地图颜色、前线和面板变化"]:::ui

    A --> B --> C
    C -->|否| R
    C -->|是| M --> O
    O -->|否| NO --> UI
    O -->|是| HC --> SA
    SA -->|目标已经是己方动态战区| SS
    SA -->|目标仍属敌方动态战区| ET --> AF --> SS
    SS --> RO --> TU --> FU --> DU --> UI

    WARN1["绝对不要这样做<br/>占一个 hex 就把整个 regionToTheater 改掉<br/>会导致前线跳到敌军身后"]:::warn
    WARN2["也不要这样做<br/>只改 Region.controller<br/>却不改 HexTile.controller<br/>会破坏玩家/AI 对称性"]:::warn
    ET -.守住.-> WARN1
    HC -.守住.-> WARN2

    classDef command fill:#fae8ff,stroke:#a21caf,color:#2a0a2f
    classDef rules fill:#ccfbf1,stroke:#0f766e,color:#042f2e
    classDef decision fill:#fff7ed,stroke:#ea580c,color:#1f1300
    classDef stop fill:#fee2e2,stroke:#b91c1c,color:#111827
    classDef state fill:#ede9fe,stroke:#7c3aed,color:#1f143d
    classDef authority fill:#fee2e2,stroke:#dc2626,color:#111827
    classDef derived fill:#dcfce7,stroke:#16a34a,color:#052e16
    classDef ui fill:#e5e7eb,stroke:#4b5563,color:#111827
    classDef warn fill:#ffedd5,stroke:#f97316,color:#431407
```

## 3. v0.8 经济、生产与补员链路

这张图看 v0.8 初级经济。经济总账是 faction 级资源池，但收入和部署资格仍回到真实 hex 控制和 region 聚合；生产命令仍走 `RuleEngine`，UI 不直接改 `GameState`。

```mermaid
flowchart TD
    BOOT["经济启动补账<br/>EconomyRules.bootstrapIfNeeded<br/>旧状态缺 economyState 时从地图推导账本"]:::economy
    HEX["真实控制权<br/>HexTile.controller<br/>经济收入必须有己方控制 hex 证据"]:::authority
    REGION["战略聚合<br/>RegionNode<br/>city / factories / infrastructure / supplyValue"]:::derived
    INCOME["收入计算<br/>EconomyRules.income<br/>manpower / industry / supplies"]:::economy
    LEDGER["阵营总账<br/>FactionEconomyLedger<br/>库存、上回合收入、维护费、补员消耗、队列"]:::economy

    UI["经济面板<br/>EconomyPanelView<br/>展示资源和生产按钮"]:::ui
    QUEUE["生产命令<br/>Command.queueProduction<br/>玩家/未来 AI 共用底层命令"]:::command
    VALIDATE["生产校验<br/>CommandValidator.validateProduction<br/>检查 phase 与资源是否足够"]:::rules
    PAY["预付成本并入队<br/>EconomyRules.queueProduction<br/>扣 PER/MAT/LOG，追加 ProductionOrder"]:::economy

    END["结束当前阵营回合<br/>Command.endTurn<br/>CommandExecutor.executeEndTurn"]:::command
    SUPPLY["补给状态刷新<br/>SupplyRules.updateSupplyStates"]:::rules
    RESOLVE["经济结算<br/>EconomyRules.resolveFactionTurn<br/>收入、维护费、短缺、补员、生产推进"]:::economy
    SHORT{"补给库存够吗?"}:::decision
    LOW["战略补给短缺<br/>supplied 单位降为 lowSupply"]:::rules
    REINF["自动补员<br/>安全后方 supplied 非敌邻单位<br/>每回合最多 +2 strength"]:::rules
    PROD["推进生产队列<br/>remainingTurns - 1<br/>ready 后部署或发补给箱"]:::economy
    DEPLOY{"有合格后方部署点吗?"}:::decision
    SPAWN["部署新单位<br/>首都/城镇/工厂/高基建/高补给或 supply source<br/>必须己控、空置、非敌邻"]:::rules
    WAIT["保留订单<br/>本回合无安全 hex，等待后续回合"]:::economy
    NEXT["切换阵营并刷新运行时层<br/>StrategicStateBootstrapper.refreshRuntimeState"]:::rules

    BOOT --> LEDGER
    HEX --> REGION --> INCOME --> LEDGER
    UI --> QUEUE --> VALIDATE --> PAY --> LEDGER
    END --> SUPPLY --> RESOLVE
    LEDGER --> RESOLVE
    RESOLVE --> SHORT
    SHORT -->|不足| LOW --> REINF
    SHORT -->|足够| REINF
    REINF --> PROD --> DEPLOY
    DEPLOY -->|有| SPAWN --> NEXT
    DEPLOY -->|没有| WAIT --> NEXT
    RESOLVE --> LEDGER

    WARN["边界<br/>经济系统不能直接占 hex<br/>也不能把中立/空控制 region 收入算给某阵营"]:::warn
    HEX -.守住.-> WARN
    VALIDATE -.守住.-> WARN

    classDef authority fill:#fee2e2,stroke:#dc2626,color:#111827
    classDef derived fill:#dcfce7,stroke:#16a34a,color:#052e16
    classDef economy fill:#fef9c3,stroke:#ca8a04,color:#292107
    classDef command fill:#fae8ff,stroke:#a21caf,color:#2a0a2f
    classDef rules fill:#ccfbf1,stroke:#0f766e,color:#042f2e
    classDef decision fill:#fff7ed,stroke:#ea580c,color:#1f1300
    classDef ui fill:#e5e7eb,stroke:#4b5563,color:#111827
    classDef warn fill:#ffedd5,stroke:#f97316,color:#431407
```

## 4. AI / 元帅决策链：AI 怎么下命令

这张图看 v6.10 当前默认 AI 主路径。AI 不直接控制单位，也不直接改地图；元帅先读取降维战场摘要，模拟 LLM 输出 `TheaterDirectiveEnvelope` JSON，经 decoder 校验后进入 `ModernCommandChain` advisory 复盘，再由 compiler 降级成战区级 `DirectiveEnvelope`。`WarCommandExecutor` 再把这些战术翻译成底层 `Command`，最后交给 `RuleEngine`。

当前默认 AI 主线是 `MarshalAgent -> Operational Directive JSON (TheaterDirective schema) -> TheaterDirectiveDecoder -> ModernCommandChain advisory JSON -> TheaterDirectiveCompiler -> ZoneDirective -> WarCommandExecutor -> RuleEngine`。旧 v0.37 `TheaterCommanderPool -> ZoneCommanderAgent` 作为 fallback 和显式 `.zoneDirective` 路径保留。统治者层只作为后续上游预留，当前不在主链路调用。旧 Agent D 管线仍保留，但默认不走。

```mermaid
flowchart TD
    START["触发 AI 行动<br/>AppContainer.advanceOrRunAI / runAIIfNeeded<br/>玩家点下一回合，或命令后轮到 AI"]:::input
    CHECK{"当前阵营该由 AI 控制吗?<br/>非玩家敌对方可跑；observer 可接管玩家方"}:::decision
    STOP["不运行 AI<br/>等待玩家操作或阶段切换"]:::stop
    REFRESH["行动前刷新运行时战略层<br/>StrategicStateBootstrapper.refreshRuntimeState<br/>避免 AI 读到旧前线/旧部署"]:::rules
    TM["AI 回合编排器<br/>TurnManager.runAITurn<br/>默认 pipelineMode = marshalDirective"]:::rules
    SUM["战场摘要<br/>MarshalBattlefieldSummarizer<br/>只给元帅 front/deploy/目标/补给摘要，不给全量 hex"]:::ai
    LLM["模拟 LLM 客户端<br/>SimulatedMarshalLLMClient<br/>输出 fenced JSON，不接真实网络或模型"]:::ai
    DEC["元帅 JSON 解码器<br/>TheaterDirectiveDecoder<br/>提取 JSON、解码、校验 schema/zone/region/tactic"]:::command
    MCHAIN["现代指挥链 advisory<br/>ModernCommandChainOrchestrator / Decoder<br/>校验并记录 ISR/Fires/Air/EW/Logistics/Brigade 子任务"]:::command
    COMP["元帅意图编译器<br/>TheaterDirectiveCompiler<br/>TheaterDirective -> ZoneDirective<br/>传递 focus/convergence/coordinated 参数"]:::command
    ENV["指令信封<br/>DirectiveEnvelope<br/>收集编译后的 ZoneDirective"]:::command
    TACTIC["高级战术路由<br/>TacticName<br/>blitzkrieg / spearhead / breakthrough / pincer / fire / feint / guerrilla / elastic / depth / lastStand"]:::command
    WCE["指令执行器<br/>WarCommandExecutor.execute<br/>按战术 profile 选择单位、目标和 fallback"]:::command
    BOTTOM["具体单位命令<br/>Command<br/>attack / move / hold / allowRetreat"]:::command
    RE["统一规则校验执行<br/>RuleEngine<br/>AI 和玩家共用同一套规则"]:::rules
    RECORD["指令复盘记录<br/>WarDirectiveRecord<br/>记录 tactic、target、结果、拒绝原因"]:::ui
    END["AI 自动结束回合<br/>RuleEngine.execute(.endTurn)<br/>切换 activeFaction / phase"]:::rules

    START --> CHECK
    CHECK -->|否| STOP
    CHECK -->|是| REFRESH --> TM --> SUM --> LLM --> DEC --> MCHAIN --> COMP --> ENV
    ENV --> TACTIC --> WCE --> BOTTOM --> RE --> RECORD --> END

    FALLBACK["Fallback 将军池<br/>TheaterCommanderPool + ZoneCommanderAgent<br/>元帅 JSON 无效或某 zone 无指令时使用"]:::ai
    DEC -.解码失败.-> FALLBACK --> ENV
    COMP -.zone 缺指令.-> FALLBACK

    LEGACY["旧 Agent D 管线<br/>AgentContext -> DecisionProvider -> AgentCommandMapper<br/>只在 legacyAgentOrder 显式分支或测试中使用"]:::legacy
    TM -.默认不走.-> LEGACY

    MANUAL["手写战区指令<br/>手工 ZoneDirective<br/>玩家聊天命令也可以直接指定 tactic/focus/convergence"]:::input
    MANUAL --> TACTIC

    classDef input fill:#fef3c7,stroke:#d97706,color:#1f1600
    classDef decision fill:#fff7ed,stroke:#ea580c,color:#1f1300
    classDef stop fill:#fee2e2,stroke:#b91c1c,color:#111827
    classDef rules fill:#ccfbf1,stroke:#0f766e,color:#042f2e
    classDef ai fill:#e0e7ff,stroke:#4f46e5,color:#111827
    classDef command fill:#fae8ff,stroke:#a21caf,color:#2a0a2f
    classDef ui fill:#e5e7eb,stroke:#4b5563,color:#111827
    classDef legacy fill:#f3f4f6,stroke:#6b7280,stroke-dasharray:5 5,color:#111827
```

## 5. MapEditor 到游戏数据：地图怎么进入主游戏

这张图看地图编辑器的输出链路。编辑器里画的是初始地图和初始战区；运行时动态战区仍由游戏里的 `hexToTheater` 推进，不是编辑器脚本控制。

```mermaid
flowchart TD
    DOC["编辑器文档<br/>MapEditorDocument<br/>保存 hex、区域、作战区分配、初始任务编组"]:::editor
    MODE1["地块编辑<br/>hexPainter<br/>画地形、道路、控制方、补给点"]:::editor
    MODE2["区域编辑<br/>regionBuilder<br/>把每个 hex 分配给一个 region"]:::editor
    MODE3["初始作战区编辑<br/>theaterAssignment<br/>把 region 分配给开局 theater"]:::editor
    MODE4["任务编组编辑<br/>unitPlanner<br/>放置开局 formation 和模板"]:::editor
    EXPORT["导出器<br/>MapEditorExporter.export<br/>把编辑器文档转成游戏 JSON"]:::loader
    CHECK{"导出校验通过吗?<br/>每个 hex 必须有 region；region 不能为空"}:::decision
    ERR["导出失败<br/>unassignedHex / missingRegion / emptyRegion<br/>先回编辑器补数据"]:::stop
    SCEN["场景 JSON<br/>ScenarioDefinition<br/>保存 hex 地形、控制方、补给、目标、初始任务编组"]:::data
    REG["区域 JSON<br/>RegionDataSet<br/>保存 hexToRegion、区域、边、初始 theaterId"]:::data
    NEI["自动推导省份邻接<br/>真实 hex 邻接 -> Region.neighbors / RegionEdge<br/>避免手写邻接出错"]:::derived
    BRIDGE["默认资源桥<br/>MapEditorGameResourceBridge<br/>读取或覆盖项目默认地图资源"]:::loader
    PRESERVE["默认灰潮元数据保留<br/>maxTurns / victoryConditions / riverEdges<br/>VP / occupation / river crossing"]:::loader
    FILES["项目默认数据文件<br/>WWIIHexV0/Data<br/>grey_tide_2030_scenario.json + grey_tide_2030_regions.json"]:::data
    LOAD["游戏启动加载<br/>DataLoader.loadGameState<br/>DEBUG 下优先读源码 JSON"]:::loader
    MAP["地图状态<br/>MapState<br/>tiles + hexToRegion + RegionGraph"]:::state
    THEATER["战区状态<br/>TheaterState<br/>捕获 initialSnapshot，并 seed hexToTheater"]:::state
    FRONT["初始前线<br/>FrontLineState<br/>按开局动态战区接触生成"]:::derived
    DEPLOY["初始部署<br/>WarDeploymentState<br/>按前线/纵深/驻军分配单位"]:::derived
    GAME["游戏可运行<br/>GameState ready<br/>主游戏 UI 和规则系统开始读取"]:::state

    DOC --> MODE1 --> EXPORT
    DOC --> MODE2 --> EXPORT
    DOC --> MODE3 --> EXPORT
    DOC --> MODE4 --> EXPORT
    EXPORT --> CHECK
    CHECK -->|失败| ERR
    CHECK -->|通过| SCEN
    CHECK -->|通过| REG
    REG --> NEI --> REG
    SCEN --> BRIDGE
    REG --> BRIDGE
    BRIDGE --> PRESERVE --> FILES
    FILES --> LOAD --> MAP --> THEATER --> FRONT --> DEPLOY --> GAME

    NOTE["重要提醒<br/>MapEditor 的 theater assignment 只定义开局战区<br/>运行时推进看 hexToTheater，不看 regionToTheater"]:::warn
    MODE3 -.语义.-> NOTE

    classDef editor fill:#f6d365,stroke:#8a5a00,color:#1f1b10
    classDef loader fill:#dbeafe,stroke:#2563eb,color:#0f172a
    classDef decision fill:#fff7ed,stroke:#ea580c,color:#1f1300
    classDef stop fill:#fee2e2,stroke:#b91c1c,color:#111827
    classDef data fill:#f8f9fb,stroke:#6b7280,color:#111827
    classDef derived fill:#dcfce7,stroke:#16a34a,color:#052e16
    classDef state fill:#ede9fe,stroke:#7c3aed,color:#1f143d
    classDef warn fill:#ffedd5,stroke:#f97316,color:#431407
```

## 6. v1.1 主游戏 macOS 入口

这张图只说明 v1.1 新增的 macOS 主游戏 target。它复用主游戏数据、UI、SpriteKit 棋盘和规则系统；macOS 输入只是平台桥接，不是新的规则入口。

```mermaid
flowchart TD
    TARGET["macOS 主游戏 target<br/>WWIIHexV0Mac<br/>独立于 iOS target 和 MapEditorMac"]:::platform
    APP["macOS App 入口<br/>WWIIHexV0MacApp<br/>WindowGroup + Game 菜单"]:::platform
    BOOT["游戏容器<br/>AppContainer.bootstrap<br/>加载默认 JSON 并初始化规则/AI"]:::state
    ROOT["主游戏界面<br/>RootGameView<br/>HUD、图层、Info、棋盘"]:::ui
    BRIDGE["macOS SpriteKit 桥<br/>BoardSceneView + BoardEventSKView<br/>NSViewRepresentable 承载 SKView"]:::platform
    SCENE["棋盘场景<br/>BoardScene<br/>鼠标点击、拖拽、滚轮/触控板缩放"]:::ui
    TAP["hex 点击回调<br/>onHexTapped(coord)<br/>只传坐标，不改 GameState"]:::input
    CONTAINER["输入解释<br/>AppContainer.handleBoardTap<br/>选中、移动、攻击意图判断"]:::rules
    COMMAND["统一命令<br/>Command / ZoneDirective<br/>玩家和 AI 共用入口"]:::command
    ENGINE["规则权威<br/>RuleEngine / WarCommandExecutor<br/>校验后修改 GameState"]:::rules
    DATA["默认资源<br/>WWIIHexV0/Data JSON<br/>DEBUG 优先源码文件，bundle 作 fallback"]:::data

    TARGET --> APP --> BOOT --> ROOT --> BRIDGE --> SCENE --> TAP --> CONTAINER --> COMMAND --> ENGINE
    DATA --> BOOT
    ENGINE --> ROOT

    WARN["禁止绕过<br/>AppKit / SpriteKit 不得直接改 GameState<br/>仍必须走规则系统"]:::warn
    SCENE -.守住.-> WARN

    classDef platform fill:#e0f2fe,stroke:#0284c7,color:#082f49
    classDef state fill:#ede9fe,stroke:#7c3aed,color:#1f143d
    classDef ui fill:#e5e7eb,stroke:#4b5563,color:#111827
    classDef input fill:#fef3c7,stroke:#d97706,color:#1f1600
    classDef command fill:#fae8ff,stroke:#a21caf,color:#2a0a2f
    classDef rules fill:#ccfbf1,stroke:#0f766e,color:#042f2e
    classDef data fill:#f8f9fb,stroke:#6b7280,color:#111827
    classDef warn fill:#ffedd5,stroke:#f97316,color:#431407
```

## 7. v1.0 UI / AI / 初版试玩链路

这张图说明 v1.0 分支的收口点：它不新增规则入口，只改善 UI 可读性、AI 回放、轻量性能和试玩记录。

```mermaid
flowchart TD
    STATE["运行时状态<br/>GameState + EventLog + WarDirectiveRecord"]:::state
    ROOT["主界面<br/>RootGameView<br/>HUD + Info tabs"]:::ui
    LOG["日志面板<br/>EventLogView<br/>最近 60 条 LogDisplayEntry"]:::ui
    AIUI["AI 面板<br/>AgentPanelView<br/>raw JSON + command results + zone directives"]:::ui
    BOARD["地图场景<br/>BoardScene<br/>缓存 unit display hex 后排序绘制"]:::ui
    MARSHAL["模拟元帅 / MockAI<br/>MarshalAgent + SimulatedMarshalLLMClient"]:::ai
    ZD["战区指令<br/>ZoneDirective<br/>tactic / focus / intensity"]:::command
    WCE["执行解释<br/>WarCommandExecutor<br/>infiltration 限制默认投入"]:::command
    RULE["规则权威<br/>RuleEngine<br/>唯一修改 GameState"]:::rules
    PLAYTEST["初版试玩记录<br/>观察 UI、图层、AI diagnostics、拒绝原因"]:::doc

    STATE --> ROOT
    ROOT --> LOG
    ROOT --> AIUI
    ROOT --> BOARD
    MARSHAL --> ZD --> WCE --> RULE --> STATE
    AIUI --> PLAYTEST
    LOG --> PLAYTEST
    BOARD --> PLAYTEST

    WARN["边界<br/>UI / MockAI 不直接改 GameState<br/>仍必须走统一命令管线"]:::warn
    AIUI -.守住.-> WARN
    WCE -.守住.-> WARN

    classDef state fill:#ede9fe,stroke:#7c3aed,color:#1f143d
    classDef ui fill:#e5e7eb,stroke:#4b5563,color:#111827
    classDef ai fill:#e0e7ff,stroke:#4f46e5,color:#111827
    classDef command fill:#fae8ff,stroke:#a21caf,color:#2a0a2f
    classDef rules fill:#ccfbf1,stroke:#0f766e,color:#042f2e
    classDef doc fill:#fef3c7,stroke:#d97706,color:#1f1600
    classDef warn fill:#ffedd5,stroke:#f97316,color:#431407
```

## 8. Commander 与玩家双轨命令

这张图说明当前兼容主线：实体 commander 从 JSON / region 种子接入 FrontZone；玩家可以微操具体 formation，也可以通过 Commander Cell 发作战区宏观命令。两条路最终仍收口到规则系统。

```mermaid
flowchart TD
    GJSON["Commander 数据<br/>generals.json<br/>灰潮虚构 Blue / Red commander<br/>倾向、技能、忠诚/满意度"]:::data
    RJSON["Region 种子<br/>grey_tide_2030_regions.assignedGeneralId<br/>开局指定某 region 所属 commander"]:::data
    DL["加载器<br/>DataLoader.loadGeneralRegistry<br/>读取 GeneralRegistry"]:::loader
    DISP["Commander 指派器<br/>GeneralDispatcher.assignGenerals<br/>种子 -> 偏好 -> 同阵营后备池"]:::rules
    FZ["作战部署<br/>FrontZone.generalAssignment<br/>generalId、HQ region、辖下 formation、忠诚/满意度"]:::state
    POOL["Commander fallback 池<br/>TheaterCommanderPool<br/>用 GeneralData 生成 ZoneCommanderAgentConfig"]:::ai

    TAP["玩家地图点击<br/>RootGameView / BoardScene<br/>选单位、选 region、选目标"]:::input
    MICRO["全微操<br/>AppContainer.submit(Command)<br/>move / attack / hold / resupply"]:::command
    LOCK["微操锁<br/>PlayerCommandState.micromanagedDivisionIds<br/>本回合玩家亲控单位"]:::state
    GENUI["Commander Cell<br/>GeneralCommandPanelView<br/>Hold Line / Assault Objective"]:::ui
    ZD["玩家作战区指令<br/>ZoneDirective<br/>defense holdLine 或 attack selected objective"]:::command
    WCE["执行器<br/>WarCommandExecutor.execute(excluding lockedIds)<br/>跳过已微操单位"]:::command
    RE["规则权威<br/>RuleEngine<br/>校验并修改 GameState"]:::rules
    RECORD["记录<br/>WarDirectiveRecord + PlayerPlannedOperation<br/>AI 面板、日志、计划线共用"]:::ui
    BOARD["视觉反馈<br/>BoardScene<br/>进攻箭头、防御圆环、微操单位金色圈"]:::ui
    PROFILE["将军档案<br/>GeneralProfileView<br/>履历、技能、忠诚、满意度、辖下部队"]:::ui

    GJSON --> DL --> DISP
    RJSON --> DISP --> FZ --> POOL
    FZ --> GENUI --> PROFILE
    TAP --> MICRO --> RE --> LOCK
    LOCK --> WCE
    TAP --> GENUI --> ZD --> WCE --> RE --> RECORD --> BOARD
    FZ --> GENUI

    WARN["边界<br/>UI 和将军不直接改 hex / division<br/>行动必须走 Command 或 ZoneDirective"]:::warn
    GENUI -.守住.-> WARN
    WCE -.守住.-> WARN

    classDef data fill:#f8f9fb,stroke:#6b7280,color:#111827
    classDef loader fill:#dbeafe,stroke:#2563eb,color:#0f172a
    classDef state fill:#ede9fe,stroke:#7c3aed,color:#1f143d
    classDef ai fill:#e0e7ff,stroke:#4f46e5,color:#111827
    classDef input fill:#fef3c7,stroke:#d97706,color:#1f1600
    classDef command fill:#fae8ff,stroke:#a21caf,color:#2a0a2f
    classDef rules fill:#ccfbf1,stroke:#0f766e,color:#042f2e
    classDef ui fill:#e5e7eb,stroke:#4b5563,color:#111827
    classDef warn fill:#ffedd5,stroke:#f97316,color:#431407
```
