# fable-5 重构优化总提示词草案

你接手的是 `WWIIHexV0`，一个iOS 二战（计划接入llm）回合制战棋项目。希望你做一次较大的“重构 + 优化 + 体验提升”，具体参考“大目标”，你可以发挥判断力，但是底层逻辑大改的话，必须先向我确认。

## 先读

请先阅读这些文件，再看相关源码：

- `update_log.md`
- `md/flow/flow.md`
- `md/flow/flowchart.md`
- `md/test/test.md`
- `WWIIHexV0/Core/*`
- `WWIIHexV0/Rules/TheaterSystem.swift`
- `WWIIHexV0/Rules/FrontLineManager.swift`
- `WWIIHexV0/Rules/WarDeploymentManager.swift`
- `WWIIHexV0/Rules/CommandValidator.swift`
- `WWIIHexV0/Rules/CommandExecutor.swift`
- `WWIIHexV0/Commands/WarDirective.swift`
- `WWIIHexV0/Commands/WarCommandExecutor.swift`
- `WWIIHexV0/Agents/ZoneCommanderAgent.swift`
- `WWIIHexV0/Agents/MockAICommander.swift`
- `WWIIHexV0/Turn/TurnManager.swift`
- `WWIIHexV0/SpriteKit/*`
- `WWIIHexV0/UI/*`
- 相关历史测试文件 `WWIIHexV0/Probes/WWIIHexV0ProbeTests.swift`、`Stage0355DynamicTheaterTests.swift`、`CommandSystemTests.swift`、`WarSystemsIntegrationTests.swift`、`LayeredMapUIStateTests.swift`。这些文件只作语义参考，默认不执行。

若文档和源码冲突，以当前源码和轻量检查结果为准；需要重测试确认的风险要记录，不能擅自跑。

## 大目标

请整体重构和优化这些方向：

1. `hex -> region -> 动态战区 -> 前线 -> 部署层`整个体系代码优化，你自己判断优化代码。
2. UI优化：目前主游戏地图太简陋了，我希望你帮我彻底重构优化主游戏的界面，让整个游戏界面看起来高端上档次，很有那种战棋二战史实风味，像统一指挥2/钢铁雄心那样，且新地图依然可以使用mac版地图编辑器编辑，以及重构动态前线的UI线显示
3. 优化ai命令算法，比如自动填线、攻击、防御算法，使ai更加智能，运行速度更快，此外也可以优化下游戏的链路算法，也是更加智能、运行速度更快，后续llm接入后也是依靠底层命令算法操作的，所以这个很重要

## 轻量检查要求

做完一整节的优化后按照 `md/test/test.md` 做轻量检查。默认不要跑 Xcode / XCTest / 模拟器 / 性能测试，也不要跑 Probe、Stage Regression 或 Full。

如果正确性必须依赖重测试确认，在交付里写清楚“按当前规范未跑重测试，风险未验证”。

## 最终交付格式

最终回复请简洁说明：

1. 修改优化了哪些方向。
2. 按方向分，改了哪些关键文件、跑了哪些轻量检查。
3. 还剩什么风险或下一步。

重点：你可以发挥，但要守住 hex 权威、动态战区权威、部署权威和统一命令管线。大方向变化先确认；重测试默认不跑，只记录风险和轻量检查结果。
