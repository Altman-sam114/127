#!/usr/bin/env python3
"""
Codex 代码打捞脚本
- 自动扫描本脚本所在文件夹内的所有 .jsonl 文件
- 提取 apply_patch / patch_apply_end 记录中的代码
- 输出到同目录下的 output/ 子文件夹
- 结束后打印打捞汇总表

用法：
  python3 extract_codex_patches.py
"""

import json
import re
import sys
from pathlib import Path

# ── 路径：py 所在目录 ──────────────────────────────────────────────────────
HERE       = Path(__file__).parent.resolve()
OUTPUT_DIR = HERE / "output"


# ── 解析 apply_patch 文本 ──────────────────────────────────────────────────
def parse_patch(patch_text: str) -> dict[str, str]:
    """
    解析 Codex apply_patch 格式，返回 {原始文件路径: 文件内容}
    支持 Add File / Update File（Delete File 跳过）
    """
    files: dict[str, str] = {}
    current_path = None
    current_lines: list[str] = []
    mode = None  # "add" | "update" | "delete" | None

    for raw in patch_text.splitlines():
        if re.match(r'^\*{3} Begin Patch', raw):
            continue

        m_add    = re.match(r'^\*{3} Add File: (.+)$', raw)
        m_update = re.match(r'^\*{3} Update File: (.+)$', raw)
        m_delete = re.match(r'^\*{3} Delete File: (.+)$', raw)
        m_end    = re.match(r'^\*{3} End Patch', raw)

        if m_add or m_update or m_delete:
            # 保存上一段
            if current_path and mode in ("add", "update") and current_lines:
                files[current_path] = "\n".join(current_lines)
            current_lines = []
            if m_add:
                current_path = m_add.group(1).strip()
                mode = "add"
            elif m_update:
                current_path = m_update.group(1).strip()
                mode = "update"
            else:
                current_path = m_delete.group(1).strip()
                mode = "delete"
            continue

        if m_end:
            if current_path and mode in ("add", "update") and current_lines:
                files[current_path] = "\n".join(current_lines)
            current_path, current_lines, mode = None, [], None
            continue

        # 内容行
        if current_path and mode in ("add", "update"):
            if raw.startswith("+"):
                current_lines.append(raw[1:])   # 去掉前导 +
            elif raw.startswith(" "):
                current_lines.append(raw[1:])   # 上下文行（update 用）
            # "-" 行（被删除的旧内容）跳过

    # 文件末尾无 End Patch 时收尾
    if current_path and mode in ("add", "update") and current_lines:
        files[current_path] = "\n".join(current_lines)

    return files


# ── 从单个 JSONL 文件提取 ──────────────────────────────────────────────────
def extract_from_jsonl(path: Path) -> list[tuple[str, str, str]]:
    """返回 [(timestamp, 原始文件路径, 内容), ...]"""
    results = []
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            for raw in f:
                raw = raw.strip()
                if not raw:
                    continue
                try:
                    obj = json.loads(raw)
                except json.JSONDecodeError:
                    continue

                payload = obj.get("payload", {})
                ts      = obj.get("timestamp", "")

                # 格式 A：custom_tool_call { name: apply_patch, input: "*** Begin Patch..." }
                if (payload.get("type") == "custom_tool_call"
                        and payload.get("name") == "apply_patch"):
                    patch_text = payload.get("input", "")
                    for fp, content in parse_patch(patch_text).items():
                        results.append((ts, fp, content))

                # 格式 B：response_item function_call apply_patch
                elif (payload.get("type") == "response_item"
                      and payload.get("name") == "apply_patch"):
                    args = payload.get("arguments", "")
                    try:
                        arg_obj    = json.loads(args) if isinstance(args, str) else args
                        patch_text = arg_obj.get("patch", arg_obj.get("input", ""))
                    except Exception:
                        patch_text = str(args)
                    for fp, content in parse_patch(patch_text).items():
                        results.append((ts, fp, content))

                # 格式 C：patch_apply_end → changes → content（最干净，直接是文件内容）
                elif payload.get("type") == "patch_apply_end":
                    for abs_path, info in payload.get("changes", {}).items():
                        if info.get("type") in ("add", "modify") and "content" in info:
                            results.append((ts, abs_path, info["content"]))

    except Exception as e:
        print(f"  [!] 读取失败 {path.name}: {e}")

    return results


# ── 把原始路径转成相对输出路径 ─────────────────────────────────────────────
def to_relative(fp: str) -> Path:
    """
    /Users/xxx/Desktop/codexapp/test/WWIIHexV0/Agents/GameAgent.swift
    → WWIIHexV0/Agents/GameAgent.swift

    如果本来就是相对路径（如 WWIIHexV0/Agents/GameAgent.swift）则直接用。
    """
    p = Path(fp)
    # 找项目根（第一个不以 . 或 / 开头的非系统目录段）
    # 简单策略：去掉 /Users/xxx/.../test/ 前缀，保留后面的部分
    parts = p.parts
    # 从后往前找第一个看起来像"项目名"的段（不是 Users/home/Desktop 等）
    skip = {"Users", "home", "Desktop", "Documents", "Downloads",
            "Library", "private", "var", "tmp", "opt", "usr"}
    keep_from = 0
    for i, part in enumerate(parts):
        if part not in skip and not part.startswith(".") and i > 0:
            # 如果上一段是常见路径终点词（test/src/proj等）就从这里开始
            prev = parts[i - 1].lower()
            if prev in {"test", "src", "projects", "dev", "code",
                        "workspace", "repos", "project", "app", "apps"}:
                keep_from = i
                break
            keep_from = i  # 否则就从第一个非系统目录开始
            break

    rel_parts = parts[keep_from:] if keep_from else parts[1:]  # 至少去掉根 /
    return Path(*rel_parts) if rel_parts else Path(p.name)


# ── 主流程 ────────────────────────────────────────────────────────────────
def main():
    # 1. 找 JSONL
    jsonl_files = sorted(HERE.glob("*.jsonl"))
    if not jsonl_files:
        print(f"❌ 在脚本目录下未找到任何 .jsonl 文件：{HERE}")
        sys.exit(1)

    print(f"📂 扫描目录：{HERE}")
    print(f"📄 找到 {len(jsonl_files)} 个 JSONL 文件：")
    for f in jsonl_files:
        print(f"   {f.name}")
    print()

    # 2. 提取所有 patch 记录，同路径取最新时间戳版本
    #    key = 原始路径字符串，value = (timestamp, content)
    file_versions: dict[str, tuple[str, str]] = {}

    for jf in jsonl_files:
        records = extract_from_jsonl(jf)
        for ts, fp, content in records:
            if fp not in file_versions or ts > file_versions[fp][0]:
                file_versions[fp] = (ts, content)

    if not file_versions:
        print("❌ 未找到任何代码 patch 记录。")
        print("   请确认 JSONL 文件来自 ~/.codex/sessions/ 目录。")
        sys.exit(1)

    # 3. 写出文件
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    written: list[tuple[Path, int]] = []   # (输出路径, 行数)

    for fp, (ts, content) in file_versions.items():
        rel      = to_relative(fp)
        out_path = OUTPUT_DIR / rel
        out_path.parent.mkdir(parents=True, exist_ok=True)

        # 保证换行符正常（统一用 \n，末尾加一个换行）
        clean_content = content.replace("\r\n", "\n").replace("\r", "\n")
        if clean_content and not clean_content.endswith("\n"):
            clean_content += "\n"

        out_path.write_text(clean_content, encoding="utf-8")
        line_count = clean_content.count("\n")
        written.append((rel, line_count))

    # 4. 汇总报告
    # 只统计 .swift 文件（以及 .json / .swift 等项目文件）
    swift_files = [(p, n) for p, n in written if p.suffix == ".swift"]
    other_files = [(p, n) for p, n in written if p.suffix != ".swift"]

    total_lines = sum(n for _, n in written)

    print("=" * 60)
    print(f"✅  打捞完成，共还原 {len(written)} 个文件，合计 {total_lines} 行")
    print("=" * 60)

    if swift_files:
        print(f"\n📦 Swift 文件（{len(swift_files)} 个）：")
        for rel, n in sorted(swift_files):
            print(f"   {str(rel):<55} {n:>4} 行")

    if other_files:
        print(f"\n📦 其他文件（{len(other_files)} 个）：")
        for rel, n in sorted(other_files):
            print(f"   {str(rel):<55} {n:>4} 行")

    print(f"\n📁 输出目录：{OUTPUT_DIR}")


if __name__ == "__main__":
    main()