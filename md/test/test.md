# 轻量检查与云端验证规范

> 当前规则：默认云端重验证，本机不主动运行测试或检查命令。GitHub Actions 默认执行静态检查、通用 iOS build 和 `WWIIHexV0Probes` simulator probe；该 probe 覆盖灰潮默认剧本数据启动、战略派生层、既有 directive 执行探针、10 个 AI 半回合轻量运行时链路、Playtest 红/蓝新局、Action Gate、主目标摘要、本地快照状态链路、neutral 主目标地面占领到即时胜利阈值的闭环、Modern Mission Recon 经 `AppContainer -> CommandValidator -> RuleEngine / VisibilityRules` 的容器链路、Modern Command Chain 的 ISR Recon Area 受限执行桥经 `ModernSubDirectiveCommandCompiler -> Command.recon -> RuleEngine / VisibilityRules` 的规则链路、Observer AI 容器入口自动推进 2 个 AI 半回合、restricted / civilian fire ROE 规则入口，以及 direct attack contact gate。完整 XCTest、Smoke、Stage Regression、Dynamic Theater Regression、Full、真实 App UI 点击 / 截图、真实 App 10-20 回合 observer 长跑和性能验证仍不在默认本机范围内。

## 0. 总原则

- 每轮实现或验收前仍要读本文件，确认云端重验证和禁止本机执行项。
- 默认不在本机跑任何测试、检查、构建、模拟器启动或 app 启动。
- 默认不新增或修改测试文件；可以阅读既有测试理解历史语义。
- 若某风险必须依靠检查或重测试才能确认，默认通过 `main` push 触发 GitHub Actions；本机只在人工明确授权时运行检查、build 或 test。
- 若云端环境缺依赖或 workflow 失败，必须记录哪个检查没跑、缺什么依赖、是否影响验收、需要人工提供什么。
- 不得用“已验证”代替具体命令和结果；不得伪造测试、构建或模拟器结果。

## 1. 默认云端重验证

本项目当前唯一默认验证分支是 `main`。Agent B 完成实现后：

```sh
git fetch origin
git switch main
git pull --ff-only origin main
git status --short
git add 相关文件
git commit -m "chore: 简要说明本轮制度或功能变化"
git push origin main
```

`origin/main` push 会触发 `.github/workflows/ci-results.yml`。该 workflow 默认执行：

- `git diff --check HEAD^ HEAD`；仅根提交 fallback 到 `git diff-tree --check --no-commit-id --root -r HEAD`
- `plutil -lint WWIIHexV0.xcodeproj/project.pbxproj`
- `xmllint --noout` 检查两个共享 scheme
- `ruby -c scripts/check_grey_tide_data.rb` 与 `ruby scripts/check_grey_tide_data.rb`
- `ruby -c scripts/check_modern_visible_text.rb` 与 `ruby scripts/check_modern_visible_text.rb`
- 云端 `xcodebuild build`
- 云端 simulator 上执行 `WWIIHexV0Probes` probe target，其中包含灰潮默认剧本的 10 个 AI 半回合轻量运行时 probe、Playtest 红/蓝新局、Action Gate、主目标摘要、本地快照状态 probe、neutral 主目标地面占领到即时胜利阈值 probe、Modern Mission Recon 容器链路 probe、Modern Command Chain ISR Recon Area 受限执行桥 probe、Observer AI 容器入口自动推进 probe、restricted / civilian fire ROE probe，以及 direct attack contact gate probe

云端 build 命令：

```sh
xcodebuild \
  -project WWIIHexV0.xcodeproj \
  -scheme WWIIHexV0 \
  -configuration Debug \
  -destination "generic/platform=iOS" \
  -derivedDataPath .derivedData-ci \
  -resultBundlePath ci-results/WWIIHexV0.xcresult \
CODE_SIGNING_ALLOWED=NO \
build
```

云端 Probe 命令由 workflow 自动选择可用 iPhone simulator 后执行：

```sh
xcodebuild \
  -project WWIIHexV0.xcodeproj \
  -scheme WWIIHexV0Probes \
  -configuration Debug \
  -destination "id=<cloud_simulator_udid>" \
  -derivedDataPath .derivedData-ci-probes \
  -resultBundlePath ci-results/WWIIHexV0Probes.xcresult \
  CODE_SIGNING_ALLOWED=NO \
  test
```

当前默认云端 workflow 只跑 `WWIIHexV0Probes` 作为轻量运行时 probe。该 probe 可作为默认灰潮数据加载、AI 半回合推进、`end_turn` 规则链路、战略派生层刷新、Playtest 红/蓝新局状态、Action Gate / 主目标摘要、本地快照 envelope 恢复、neutral 主目标地面占领到即时胜利阈值、Modern Command Chain ISR Recon Area 受限执行桥、Observer AI 容器入口自动推进、restricted / civilian fire ROE 规则入口和 direct attack contact gate 的 cloud Probe 证据；它不等于真实 App observer 模式长跑，也不跑完整 `WWIIHexV0Tests`、Smoke、Stage Regression、Dynamic Theater Regression、Full、UI test、截图或性能检查；这些结果统一通过 JUnit `ci.tests` skipped 摘要说明，或不列入默认结果。

## 2. Agent C 结果包验收

Agent C 验收时必须下载最新 `origin/main` commit 对应的未加密 artifact，不只阅读 Agent B 文字汇报。

前置：

```sh
gh auth login
```

下载缓存位置：

```sh
/private/tmp/wwiihexv0-c-review-<run_id>/
```

必须核对：

- `ci-artifact-manifest.json`：`branch=main`、`commitSha`、`runId`、`runAttempt` 与 `origin/main` 最新 run 一致，并核对 `staticChecksOutcome`、`buildOutcome`、`probeOutcome`、`simulatorOutcome`、`testOutcome`。
- `ci-failure-summary.md`：成功时应写明无失败；失败时应包含失败命令和日志路径。
- `junit.xml`：至少含静态检查、build、cloud probe、默认 skipped 的完整测试摘要。
- `xcodebuild.log`：主构建日志。
- `probe-xctest.log`：`WWIIHexV0Probes` 云端 simulator probe 日志，需核对灰潮 10 个 AI 半回合 probe、Playtest 状态 probe、neutral 主目标地面占领到即时胜利阈值 probe、Modern Command Chain ISR Recon Area 受限执行桥 probe、Observer AI 容器入口 probe、restricted / civilian fire ROE probe 和 direct attack contact gate probe 用例执行并通过。
- `simulator.log`：云端 simulator 发现和启动日志。
- `grey-tide-data.log` 与 `modern-visible-text.log`：项目静态脚本检查日志。
- `WWIIHexV0.xcresult`：若 Xcode 成功产出或失败时仍生成，则保留在结果包内。
- `WWIIHexV0Probes.xcresult`：若 cloud probe 成功产出或失败时仍生成，则保留在结果包内。

## 3. 禁止主动在本机执行

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
- `git diff --check`、`plutil -lint`、`xmllint --noout`、`jq empty`、Ruby 项目脚本、workflow YAML 解析等本地检查命令，除非人工明确授权
- 会长时间占用 CPU、内存、磁盘或 DerivedData 的命令

如果旧文档、历史 prompt 或 README 仍要求跑这些命令，以本文件和 `AGENTS.md` 的当前规则为准。

## 4. 云端静态检查与人工授权本机参考命令

以下命令默认由 `.github/workflows/ci-results.yml` 在云端执行，并写入 artifact。Agent 本机默认不主动运行；只有人工明确授权本机检查时，才可按对应场景运行这些参考命令。

### 4.1 Markdown / 文本

检查改动文档是否存在尾随空白：

```sh
rg -n "[[:blank:]]+$" AGENTS.md README.md update_log.md md/test/test.md md/flow/flow.md
```

检查当前规范中是否仍残留旧默认测试口径：

```sh
rg -n "默认先跑|默认 Probe|Probe -> Smoke|Stage Regression -> Full|代码改动按 .*Probe" AGENTS.md md/flow/flow.md
```

检查 diff 空白：

```sh
git diff --check
```

### 4.2 Xcode project / plist

仅当修改了 `WWIIHexV0.xcodeproj/project.pbxproj` 时运行：

```sh
plutil -lint WWIIHexV0.xcodeproj/project.pbxproj
```

仅当修改了 scheme 或 XML 文件时运行：

```sh
xmllint --noout WWIIHexV0.xcodeproj/xcshareddata/xcschemes/WWIIHexV0.xcscheme
xmllint --noout WWIIHexV0.xcodeproj/xcshareddata/xcschemes/WWIIHexV0Probes.xcscheme
```

仅当修改 workflow 时运行 YAML 解析：

```sh
ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci-results.yml"); puts "yaml ok"'
```

### 4.3 JSON

仅当修改了 JSON 数据时运行对应文件的解析检查，优先只查改动文件：

```sh
jq empty WWIIHexV0/Data/ardennes_v0_scenario.json
jq empty WWIIHexV0/Data/ardennes_v02_regions.json
jq empty WWIIHexV0/Data/general_agents.json
jq empty WWIIHexV0/Data/grey_tide_2030_scenario.json
jq empty WWIIHexV0/Data/grey_tide_2030_regions.json
jq empty WWIIHexV0/Data/terrain_rules.json
jq empty WWIIHexV0/Data/unit_templates.json
jq empty WWIIHexV0/Data/modern_unit_templates.json
```

当修改 `grey_tide_2030_scenario.json`、`grey_tide_2030_regions.json`、`modern_unit_templates.json`、`WWIIHexV0/Rules/VictoryRules.swift` 或 `scripts/check_grey_tide_data.rb`，或交付中声明灰潮数据一致性已核对时，运行：

该脚本会核对灰潮默认 `initialPhase=blueCommand` 现代 phase alias、tile / region / objective / key location / initial unit / unit template / supply source / victory condition 引用、十个主目标三源一致性、objective 与 key location 映射、region edge / neighbor、补给源和初始单位落点语义。

```sh
ruby -c scripts/check_grey_tide_data.rb
ruby scripts/check_grey_tide_data.rb
```

### 4.4 现代玩家可见文案

当修改主应用玩家可见文案、默认现代剧本显示字段、默认 commander 数据、现代模板显示名、UI 面板、SpriteKit 标记、AppContainer 反馈文案、Core displayName 映射或 `scripts/check_modern_visible_text.rb`，或交付中声明“主路径无主要二战文案残留”时，运行：

```sh
ruby -c scripts/check_modern_visible_text.rb
ruby scripts/check_modern_visible_text.rb
```

该脚本只做静态文本扫描，不启动 app，不跑 Xcode。扫描范围限定为主应用 `App` / `UI` / `SpriteKit` Swift 字符串、会进入命令结果 / 日志 / diagnostics / legacy prompt 的 `Commands`、`Rules`、`Turn`、`Agents` 字符串、若干 Core 可见 displayName 映射，以及 `grey_tide_2030_*`、`modern_unit_templates.json`、`generals.json` 中的显示字段和地图 `cityName` / `fortressName`；`AgentConfiguration.swift` 和 `AgentPromptBuilder.swift` 不再整文件排除，只对保留的 legacy id / legacy prompt schema key 做精确 allowlist；旧阿登数据、历史文档、测试 fixture、target/module 名和源码兼容 raw value 不作为默认 hard fail。

### 4.5 Swift 单文件语法

默认不做全项目编译。若只改了少量纯 Swift 文件，并且单文件语法检查不会触发项目构建，可以只针对改动文件做轻量 parse；如果命令需要 SDK、SwiftUI/SpriteKit 依赖或变慢，立即停止并记录未检查。

示例：

```sh
swiftc -parse path/to/ChangedFile.swift
```

## 5. 人工授权时的本机构建命令

只有人工在当前任务中明确说“本机测试”“本地 build”“本地跑 xcodebuild”等，才可在本机运行完整构建。建议命令与云端保持一致，但 DerivedData 放到临时目录：

```sh
xcodebuild \
  -project WWIIHexV0.xcodeproj \
  -scheme WWIIHexV0 \
  -configuration Debug \
  -destination "generic/platform=iOS" \
  -derivedDataPath /private/tmp/wwiihexv0-derived-data \
  CODE_SIGNING_ALLOWED=NO \
  build
```

未获授权时，交付统一写明：

```text
未在本机跑测试或检查命令；验证由 GitHub Actions 结果包承担。
```

## 6. 多分支 / 并发后的整合检查

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

## 7. 历史测试基线

以下记录只用于理解历史状态，不作为当前任务的默认执行要求：

- v0.37 Probe：18 tests, 0 failures。
- v0.37 CommandSystemTests：15 tests, 0 failures。
- v0.37 Stage Regression：69 tests, 0 failures。
- v0.37 Full Regression：226 tests, 0 failures。

当前交付中若没有人工授权，统一写明：

```text
未在本机跑测试或检查命令；按当前规范重验证看 GitHub Actions artifact。
```

## 8. 决策表

| 场景 | 默认允许做什么 | 禁止默认做什么 |
|---|---|---|
| 文档改动 | push 后核对云端 artifact；人工授权时可跑尾随空白、旧口径残留、`git diff --check` | 本机 Xcode / XCTest / 未授权本地检查 |
| JSON 改动 | push 后核对云端 artifact；人工授权时可跑 `jq empty` 或项目脚本 | 启动游戏加载全场景 |
| project / scheme 改动 | push 后核对云端 artifact；人工授权时可跑 `plutil` / `xmllint` | 本机 build-for-testing |
| 少量 Swift 改动 | push 后核对云端 build；人工授权时可跑单文件 `swiftc -parse` | 全项目 build / test |
| workflow 改动 | push 后核对 artifact 中 workflow 产物；人工授权时可跑 YAML 解析 | 伪造旧 artifact |
| 大任务并发 | 文件/API/schema/文档冲突审查，push 后看云端结果 | 以测试通过代替冲突检查 |
| main 直推 | commit 后 push 到 `origin/main` 触发 Actions | PR / 候选分支作为默认流程 |

## 9. 交付写法

最终回复必须区分“本机是否跑过检查”“云端 workflow”“未跑本机重测试”：

- 已跑：写具体命令和结果。
- 云端：写 commit SHA、run id、run attempt、artifact 名称、manifest 核对结果。
- 未跑：明确说明本机禁止或未授权的重测试类型。
- 风险：说明哪些功能正确性仍未通过运行时测试确认。
