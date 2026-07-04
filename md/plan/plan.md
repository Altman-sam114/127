## 1. 当前架构：四层数据模型

```
Hex（战术层）
  ↓ hexToRegion 映射
Region（战略层 / 省份，v0.2 引入）
  ↓ regionToTheater 映射
Theater（战区层，v0.31 引入）
  ↓ 邻接边推导
FrontLine（前线层，v0.32 引入，战区间接触边界，非寻路）
```

外加两条横向系统：

- **Deployment（部署/编队层，约 v0.33 引入）**：把每个单位归类为 `frontUnit`（前线作战部队）或 `garrisonUnit`（驻军），决定它是否进入某个 `FrontZone` 的可调度兵力池。这一层是本轮（v0.353~v0.355）绝大多数"AI 看起来不动"类 bug 的实际病灶所在。
- **War Directive 指令协议（v0.351 引入）**：`MockAICommander`（未来可替换为真 LLM 或更高级 agent）输出 `ZoneDirective`（`attack`/`defend`），`WarCommandExecutor` 把它翻译成底层 `Command`（move/attack/hold/allowRetreat），最终统一交给原有的 `RuleEngine` 校验执行——这条链路保证"AI 指令"和"玩家操作"最终都经过同一套合法性校验，理论上不应该出现两套规则打架（但实际过程中出现过，见第 5 节）。

```
CommandCategory（命令层）
    ├── offense（进攻类）
    │   └── standardAttack（普通进攻）   ← 当前实现
    │   [后续: blitzkrieg, fireSupression, infiltration, breakthrough]
    └── defense（防御类）
        └── holdPosition（普通防御）     ← 当前实现
        [后续: elasticDefense, depthDefense]
    [后续类别: retreat, support]
```

## 2. 版本演进一览

| 版本 | 主题 | 关键交付 |
|---|---|---|
| v0 | 六角格测试板 | Ardennes 测试场景，地形/移动/战斗/补给/包围/胜利条件，MockAI（guderian 风格） |
| v0.1 | strength 战斗模型 | 移除 organization，只看兵力；撤退模式（HOLD/RETREATABLE） |
| v0.2 | Region 战略层叠加 | `RegionGraph`/`RegionNode`/`hexToRegion` 模型与阿登 17 省数据，省份叠加 hex、不替换 hex |
| v0.31 | Theater 战区系统 | 固定四战区生成、控制比例/胜利点聚合、70% 阈值扩张/退役规则、战区互助接口（预留未实现调用方） |
| v0.32 | FrontLine 前线系统 | 战区边界邻接边、dirty-event 局部更新、简化包围识别、多敌战区合并为单一主前线 |
| v0.33 | 编队/部署底层 | `frontUnit`/`garrisonUnit` 角色分类、`WarDeploymentState` |
| v0.34 | 地图编辑器 | 自建网页/本地地图编辑工具，直接导出项目自有 schema，放弃了引入 Tiled 的方案（评估过 Tiled+多边形画省界的可行性，但用户已自行实现更贴合需求的编辑器） |
| v0.351 | 初级战争指令系统 | `DirectiveEnvelope`/`ZoneDirective`（attack/defend）、`WarCommandExecutor`、`MockAICommander`（兵力比阈值判断 attack/defend） |
| v0.352 | 管线统一 + 观察者模式 + 分层 UI | `WarPipelineMode`（新管线默认，旧 Agent D 管线保留不删）、双方可由 AI 自动对战的观察者模式、`WarDirectiveRecord`、hex/province/theater/frontLine 图层切换、阈值从 1.5 调到 1.2 |
| v0.353 | 归属判定地基重构 | hex controller 确立为唯一权威归属源，region/theater/补给站归属全部改为从 hex controller 派生，不再用静态阵营标签 |
| v0.354 | 真实联动修复（分两轮） | 修复占领-视野-战区不同回合同步的断链；修复 ZOC 误判（友军互相阻挡）；定位并修复"AI 看起来不动"的真实病灶——部队推进过深后被部署层误判为 garrison，从前线兵力池消失；统一玩家与 AI 占领判定逻辑（修复"AI 能占玩家地，玩家占不了 AI 地"的不对称 bug） |
| v0.355 | 动态/初始战区分离 + 前线可视化 + UI 收尾 | `TheaterState.initialSnapshot`（只读初始划分）与运行时 `theaters`（动态战区）正式分离；修复战区阵营身份不能从动态控制比例反推的根因；前线 overlay 改为按 segment 连线绘制；图层拆分为 hex/province/initialTheater/dynamicTheater/frontLine；观察者模式开关接入主界面 UI |

---

## 3. 后续计划

0.35 继续优化前线、动态战区ui、seg前线ui
0.3 整合命令层、优化ui、~~撤退类等命令扩展~~(扔0.7)
0.4 将军养成初步设定、将军ui、将军命令整合、玩家操控ui
0.5 元帅引入、决策链规范化（后续加入统治者）、llm接入测试、json输入输出、解码器
0.6 优化数据统计、真实阿登大地图简单推演测试、补给、后勤优化
0.7 战术大升级，命令大扩展，定点突破高级决策，阿登闪击
0.8 回合制初级经济系统、生产、城市、地形
0.9 统治者agent、多国家大测试、初步外交状态
1.0 简易ui美观化、性能优化、mockai完善、初版游玩测试