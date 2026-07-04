# Prompt 工作流说明

本文说明 `md/prompt/` 下阶段提示词的写法和云端协作要求。历史 prompt 继续保留作资料，不代表当前默认流程。

## 角色召唤

- `agenta`、`a:` 或 `A:`：召唤 Agent A。
- `agentb`、`b:` 或 `B:`：召唤 Agent B。
- `agentc`、`c:` 或 `C:`：召唤 Agent C。
- 没有上述前缀时，按普通 Codex 任务处理；若任务需要 A/B/C 边界，应提醒用户指定角色，或说明本轮按普通任务执行。

身份标识：

- Agent A 最终回复第一行必须写：`我是 Agent A。`
- Agent B 最终回复第一行必须写：`我是 Agent B。`
- Agent C 最终回复第一行必须写：`我是 Agent C。`

## 云端阶段默认流

当前默认流程固定为 `main` 直推，不使用 `smalldata_test`、`develop`、`codeb/...`、候选分支或 PR 合并流。

```text
人工提出目标
  -> Agent A 本地分析并写版本化提示词
  -> Agent B 基于最新 origin/main 在 main 上小步实现
  -> Agent B 本机只跑轻量检查
  -> Agent B commit 并 push 到 origin/main
  -> GitHub Actions 运行 ci-results workflow
  -> GitHub Actions 上传未加密 CI 结果包
  -> Agent C 下载 artifact，核对 manifest / junit / 日志 / 失败摘要
      -> 有问题：退回 Agent B 在 main 上追加修复 commit
      -> 无问题：确认 main 最新 run 通过并同步文档
```

## Agent A 提示词必写项

Agent A 写给 Agent B 的阶段提示词必须包含：

- 本轮目标、非目标、禁止项。
- 当前架构依据，尤其是 `Command` / `ZoneDirective` / `WarCommandExecutor` / `RuleEngine` 权威边界。
- 需要修改的模块和文档。
- 本机轻量检查要求，命令必须来自 `md/test/test.md`。
- `main` 分支要求：开始前同步 `origin/main`，结束后 commit 并 push 到 `origin/main`。
- GitHub Actions 要求：说明应触发 `.github/workflows/ci-results.yml`，并上传未加密结果包。
- Agent C 验收要求：下载最新 run artifact，核对 `ci-artifact-manifest.json`、`junit.xml`、`xcodebuild.log`、`ci-failure-summary.md`。
- 风险提示：哪些正确性只能靠云端 build、后续人工授权测试或运行时验收确认。

## Agent B 交付提示

Agent B 交付时必须写清：

- 当前分支是否为 `main`。
- commit SHA。
- push 是否已到 `origin/main`。
- 本地轻量检查命令和结果。
- GitHub Actions run id、run attempt、artifact 名称和当前状态。
- 本机未跑的 Xcode / XCTest / 模拟器 / 性能测试及原因。

## Agent C 验收提示

Agent C 默认缓存目录：

```text
/private/tmp/wwiihexv0-c-review-<run_id>/
```

Agent C 必须先完成 `gh auth login`，再使用 `gh run download` 下载 artifact。验收必须核对：

- `origin/main` 最新 commit 与 manifest `commitSha` 一致。
- manifest `branch` 为 `main`。
- manifest `runId` / `runAttempt` 与下载的 run 一致。
- `junit.xml`、主构建日志和失败摘要可打开。
- artifact 是本轮 CI 新生成结果，不是历史 output 或旧报告。
