# 轻量检查规范

> 当前规则：不主动做 Xcode / XCTest / 模拟器 / 性能类测试。默认只做轻量语法、格式和配置文件检查。历史 Probe、Smoke、Stage Regression、Dynamic Theater Regression、Full 记录只作回归参考，不再是每轮任务的默认要求。

## 0. 总原则

- 每轮实现或验收前仍要读本文件，但目的从“选择测试层级”改为“确认哪些检查允许执行、哪些检查禁止执行”。
- 默认不跑任何耗费性能的测试、构建、模拟器启动或 app 启动。
- 默认不新增或修改测试文件；可以阅读既有测试理解历史语义。
- 若某风险必须依靠重测试才能确认，只在交付中明确记录“按当前规范未跑重测试，风险未验证”，不要擅自扩大验证范围。
- 不得用“已验证”代替具体命令和结果；不得伪造测试、构建或模拟器结果。

## 1. 禁止主动执行

除非人工在当前任务中明确授权，否则 Agent 不得主动执行以下操作：

- `xcodebuild test`
- `xcodebuild build`
- `xcodebuild build-for-testing`
- `xcrun simctl ...`
- Probe / Smoke / Stage Regression / Dynamic Theater Regression / Full
- XCTest、UI test、性能测试、快照测试
- 启动 iOS Simulator
- 启动 app 做人工烟测
- 全项目 Swift 编译、全量 lint、全量格式化
- 会长时间占用 CPU、内存、磁盘或 DerivedData 的命令

如果旧文档、历史 prompt 或 README 仍要求跑这些命令，以本文件和 `AGENTS.md` 的当前规则为准。

## 2. 默认允许的轻量检查

### 2.1 Markdown / 文本

检查改动文档是否存在尾随空白：

```sh
rg -n "[[:blank:]]+$" AGENTS.md README.md update_log.md md/test/test.md md/flow/flow.md
```

检查当前规范中是否仍残留旧默认测试口径：

```sh
rg -n "默认先跑|默认 Probe|Probe -> Smoke|Stage Regression -> Full|代码改动按 .*Probe" AGENTS.md md/flow/flow.md
```

### 2.2 Xcode project / plist

仅当修改了 `WWIIHexV0.xcodeproj/project.pbxproj` 时运行：

```sh
plutil -lint WWIIHexV0.xcodeproj/project.pbxproj
```

仅当修改了 scheme 或 XML 文件时运行：

```sh
xmllint --noout WWIIHexV0.xcodeproj/xcshareddata/xcschemes/WWIIHexV0.xcscheme
xmllint --noout WWIIHexV0.xcodeproj/xcshareddata/xcschemes/WWIIHexV0Probes.xcscheme
```

### 2.3 JSON

仅当修改了 JSON 数据时运行对应文件的解析检查，优先只查改动文件：

```sh
jq empty WWIIHexV0/Data/ardennes_v0_scenario.json
jq empty WWIIHexV0/Data/ardennes_v02_regions.json
jq empty WWIIHexV0/Data/general_agents.json
jq empty WWIIHexV0/Data/terrain_rules.json
jq empty WWIIHexV0/Data/unit_templates.json
```

### 2.4 Swift 单文件语法

默认不做全项目编译。若只改了少量纯 Swift 文件，并且单文件语法检查不会触发项目构建，可以只针对改动文件做轻量 parse；如果命令需要 SDK、SwiftUI/SpriteKit 依赖或变慢，立即停止并记录未检查。

示例：

```sh
swiftc -parse path/to/ChangedFile.swift
```

## 3. 多分支 / 并发后的整合检查

多分支或多子 Agent 并发完成后，主 Agent 必须做轻量整合检查。即使不跑测试，也不能跳过冲突审查。

必查项：

- 同一文件是否被多个分支或子 Agent 修改。
- 同一 public API、类型名、枚举 case、JSON key 是否出现分叉。
- `WWIIHexV0.xcodeproj/project.pbxproj` 是否存在重复文件引用、缺失文件引用或 UUID 冲突。
- `Data/*.json` 与 `ScenarioDefinition` / `RegionDataSet` 是否同时变化但文档未同步。
- `Command` / `ZoneDirective` / `WarCommandExecutor` / `RuleEngine` 管线是否仍保持统一入口。
- `hexToTheater`、`hexToFrontZone`、`regionToTheater` 的权威边界是否被不同分支写成不同口径。
- README、`md/flow/*`、阶段 prompt、`update_log.md` 是否描述同一版本状态。

建议命令：

```sh
rg -n "struct |enum |class |protocol |case |func " WWIIHexV0 MapEditor
rg -n "hexToTheater|hexToFrontZone|regionToTheater|ZoneDirective|WarCommandExecutor|RuleEngine" WWIIHexV0 md README.md AGENTS.md
```

这些命令只用于定位冲突线索，不等于功能测试。

## 4. 历史测试基线

以下记录只用于理解历史状态，不作为当前任务的默认执行要求：

- v0.37 Probe：18 tests, 0 failures。
- v0.37 CommandSystemTests：15 tests, 0 failures。
- v0.37 Stage Regression：69 tests, 0 failures。
- v0.37 Full Regression：226 tests, 0 failures。

当前交付中若没有人工授权，统一写明：

```text
未跑 Xcode / XCTest / 模拟器 / 性能测试；按当前规范仅做轻量检查。
```

## 5. 决策表

| 场景 | 默认允许做什么 | 禁止默认做什么 |
|---|---|---|
| 文档改动 | 尾随空白、旧口径残留、必要的 Markdown 人工阅读检查 | Xcode / XCTest |
| JSON 改动 | `jq empty` 查改动文件 | 启动游戏加载全场景 |
| project / scheme 改动 | `plutil` / `xmllint` | build-for-testing |
| 少量 Swift 改动 | 必要时单文件 `swiftc -parse` | 全项目 build / test |
| 大任务并发 | 文件/API/schema/文档冲突检查 | 以测试通过代替冲突检查 |
| 版本分支候选 | 分支差异和风险说明 | 未检查冲突就合并 |

## 6. 交付写法

最终回复必须区分“轻量检查”和“未跑重测试”：

- 已跑：写具体命令和结果。
- 未跑：明确说明禁止或未授权的重测试类型。
- 风险：说明哪些功能正确性仍未通过运行时测试确认。
