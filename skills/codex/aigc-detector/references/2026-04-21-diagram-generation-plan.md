# Diagram Generation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Mermaid-based diagram generation and .docx insertion to the AIGC-Detector Skill's thesis writing mode.

**Architecture:** New `diagram_gen.py` generates PNG from Mermaid text via `mmdc` CLI. Extended `docx_io.py insert_figure` inserts image + caption into .docx. SKILL.md and thesis_writing_guide.md updated so LLM identifies diagram positions during W3 chapter writing.

**Tech Stack:** Python 3, python-docx (existing), Mermaid CLI (`mmdc` via npm)

---

## File Structure

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `.claude/skills/aigc-detector/scripts/diagram_gen.py` | Mermaid text → PNG via mmdc CLI |
| Modify | `.claude/skills/aigc-detector/scripts/docx_io.py` | Add `insert_figure` subcommand |
| Modify | `.claude/skills/aigc-detector/SKILL.md` | Update W3 step with diagram workflow |
| Modify | `.claude/skills/aigc-detector/references/thesis_writing_guide.md` | Add diagram position rules + Mermaid quality guidelines |
| Modify | `install.sh` | Add mmdc download + install step |

---

### Task 1: Create diagram_gen.py

**Files:**
- Create: `.claude/skills/aigc-detector/scripts/diagram_gen.py`

- [ ] **Step 1: Write diagram_gen.py**

```python
#!/usr/bin/env python3
"""Diagram generation for AIGC-Detector Skill.

Generates PNG images from Mermaid diagram text using the mmdc CLI.

Commands:
  generate [--input <file>] --output <file> [--theme <theme>] [--bg <color>]
"""

import sys
import os
import subprocess
import tempfile


def check_mmdc() -> str:
    """Return path to mmdc or exit with install instructions."""
    result = subprocess.run(["which", "mmdc"], capture_output=True, text=True)
    if result.returncode == 0:
        return result.stdout.strip()
    # Check common locations
    for candidate in [
        os.path.expanduser("~/.npm-global/bin/mmdc"),
        os.path.expanduser("~/node_modules/.bin/mmdc"),
        "/usr/local/bin/mmdc",
    ]:
        if os.path.exists(candidate):
            return candidate
    print("Error: mmdc (Mermaid CLI) not found.", file=sys.stderr)
    print("Install with: npm install -g @mermaid-js/mermaid-cli", file=sys.stderr)
    sys.exit(1)


def generate(mermaid_text: str, output_path: str, theme: str = "default", bg: str = "white") -> str:
    """Generate PNG from Mermaid text using mmdc."""
    mmdc_path = check_mmdc()

    # Ensure output directory exists
    out_dir = os.path.dirname(output_path)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)

    # Write mermaid text to temp file (mmdc reads from file)
    tmp = tempfile.NamedTemporaryFile(mode="w", suffix=".mmd", delete=False)
    try:
        tmp.write(mermaid_text)
        tmp.close()

        cmd = [
            mmdc_path,
            "-i", tmp.name,
            "-o", output_path,
            "-w", "1600",
            "-b", bg,
            "-t", theme,
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)

        if result.returncode != 0:
            print(f"Error: mmdc failed:\n{result.stderr}", file=sys.stderr)
            sys.exit(1)

        if not os.path.exists(output_path) or os.path.getsize(output_path) == 0:
            print("Error: mmdc produced no output.", file=sys.stderr)
            sys.exit(1)

        print(output_path)
        return output_path
    finally:
        os.unlink(tmp.name)


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 diagram_gen.py generate [--input <file>] --output <file> "
              "[--theme default|dark|forest|neutral] [--bg <color>]", file=sys.stderr)
        sys.exit(1)

    command = sys.argv[1]
    if command != "generate":
        print(f"Error: unknown command '{command}'. Use 'generate'.", file=sys.stderr)
        sys.exit(1)

    # Parse args
    args = sys.argv[2:]
    input_path = None
    output_path = None
    theme = "default"
    bg = "white"

    i = 0
    while i < len(args):
        if args[i] == "--input" and i + 1 < len(args):
            input_path = args[i + 1]
            i += 2
        elif args[i] == "--output" and i + 1 < len(args):
            output_path = args[i + 1]
            i += 2
        elif args[i] == "--theme" and i + 1 < len(args):
            theme = args[i + 1]
            i += 2
        elif args[i] == "--bg" and i + 1 < len(args):
            bg = args[i + 1]
            i += 2
        else:
            print(f"Error: unknown argument '{args[i]}'", file=sys.stderr)
            sys.exit(1)

    if not output_path:
        print("Error: --output is required.", file=sys.stderr)
        sys.exit(1)

    # Read mermaid text
    if input_path:
        with open(input_path, "r", encoding="utf-8") as f:
            mermaid_text = f.read()
    else:
        mermaid_text = sys.stdin.read()

    if not mermaid_text.strip():
        print("Error: empty mermaid text.", file=sys.stderr)
        sys.exit(1)

    generate(mermaid_text, output_path, theme, bg)


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x .claude/skills/aigc-detector/scripts/diagram_gen.py`

- [ ] **Step 3: Test with a simple flowchart**

First install mmdc if not present: `npm install -g @mermaid-js/mermaid-cli`

Then test:
```bash
echo 'graph TD
    A[用户输入] --> B{数据验证}
    B -->|有效| C[处理请求]
    B -->|无效| D[返回错误]
    C --> E[输出结果]' | python3 .claude/skills/aigc-detector/scripts/diagram_gen.py generate --output /tmp/test_diagram.png
```
Expected: `/tmp/test_diagram.png` printed to stdout, file exists and is a valid PNG.

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/aigc-detector/scripts/diagram_gen.py
git commit -m "feat: add diagram_gen.py for Mermaid-to-PNG generation"
```

---

### Task 2: Add insert_figure to docx_io.py

**Files:**
- Modify: `.claude/skills/aigc-detector/scripts/docx_io.py`

- [ ] **Step 1: Add insert_figure function**

Add this function after the `formatted_write_docx` function (before `main()`), around line 568:

```python
def insert_figure(file_path: str, paragraph_index: int, image_path: str,
                  caption: str = "", output_path: str = None) -> str:
    """Insert an image + caption paragraph after the specified paragraph index."""
    from docx import Document
    from docx.shared import Cm
    from docx.enum.text import WD_ALIGN_PARAGRAPH

    doc = Document(file_path)
    paragraphs = doc.paragraphs

    if paragraph_index < 1 or paragraph_index > len(paragraphs):
        print(f"Error: paragraph index {paragraph_index} out of range (1-{len(paragraphs)})",
              file=sys.stderr)
        sys.exit(1)

    target_para = paragraphs[paragraph_index - 1]

    # Calculate image width from page layout (default 14cm if unknown)
    image_width = Cm(14)
    try:
        section = doc.sections[0]
        page_width = section.page_width
        left_margin = section.left_margin
        right_margin = section.right_margin
        if page_width and left_margin and right_margin:
            image_width = page_width - left_margin - right_margin
    except Exception:
        pass

    # Create image paragraph after target
    img_para = doc.add_paragraph()
    img_para.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = img_para.add_run()
    run.add_picture(image_path, width=image_width)

    # Move image paragraph to after target
    target_element = target_para._element
    img_element = img_para._element
    target_element.addnext(img_element)

    # Create caption paragraph if provided
    if caption:
        cap_para = doc.add_paragraph()
        cap_para.alignment = WD_ALIGN_PARAGRAPH.CENTER
        cap_run = cap_para.add_run(caption)
        cap_run.font.size = Pt(10.5)
        cap_run.font.name = "宋体"
        from docx.oxml.ns import qn
        cap_run._element.rPr.rFonts.set(qn('w:eastAsia'), "宋体")

        # Move caption to after image
        img_element.addnext(cap_para._element)

    # Save
    out = output_path or file_path
    out_dir = os.path.dirname(out)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    doc.save(out)

    result = out
    print(result)
    return result
```

- [ ] **Step 2: Add import for Pt at the top of file**

Add `from docx.shared import Pt` to the existing imports inside the functions that already use `from docx.shared import ...`. Actually, `Pt` is already imported inside several functions. For `insert_figure`, add it inside the function body.

Check if `Pt` is already imported somewhere. It's used in `_apply_format` and `_add_markdown_runs`. Since we use `from docx.shared import Cm, Pt` inside the new function, no top-level import needed.

- [ ] **Step 3: Add insert_figure to the main() CLI dispatcher**

In the `main()` function, after the `formatted_write` elif block (around line 617), add:

```python
    elif command == "insert_figure":
        if len(sys.argv) < 5:
            print("Usage: python3 docx_io.py insert_figure <file_path> <paragraph_index> "
                  "<image_path> [--caption <text>] [--output <path>]", file=sys.stderr)
            sys.exit(1)
        index = int(sys.argv[3])
        image = sys.argv[4]
        caption = ""
        out_path = None
        if "--caption" in sys.argv:
            cidx = sys.argv.index("--caption")
            if cidx + 1 < len(sys.argv):
                caption = sys.argv[cidx + 1]
        if "--output" in sys.argv:
            oidx = sys.argv.index("--output")
            if oidx + 1 < len(sys.argv):
                out_path = sys.argv[oidx + 1]
        if not os.path.exists(image):
            print(f"Error: image not found: {image}", file=sys.stderr)
            sys.exit(1)
        output = insert_figure(file_path, index, image, caption, output_path=out_path)
        print(f"Figure inserted: {output}", file=sys.stderr)
```

- [ ] **Step 4: Update docstring at top of file**

Change line 6 from:
```python
  formatted_write <file>         Write formatted Markdown to .docx (--template for format source)
```
to:
```python
  formatted_write <file>         Write formatted Markdown to .docx (--template for format source)
  insert_figure <file> <idx> <img>  Insert image + caption after paragraph <idx>
```

And update line 571 usage string from:
```python
        print("Usage: python3 docx_io.py <read|replace|write|analyze|formatted_write> "
```
to:
```python
        print("Usage: python3 docx_io.py <read|replace|write|analyze|formatted_write|insert_figure> "
```

- [ ] **Step 5: Test insert_figure**

Create a test .docx and insert the diagram from Task 1:
```bash
# Create a simple test doc
echo -e "第一段文字\n\n第二段文字\n\n第三段文字" | python3 .claude/skills/aigc-detector/scripts/docx_io.py write /tmp/test_insert.docx

# Insert figure after paragraph 2
python3 .claude/skills/aigc-detector/scripts/docx_io.py insert_figure /tmp/test_insert.docx 2 /tmp/test_diagram.png --caption "图 1-1 测试流程图" --output /tmp/test_with_fig.docx
```
Expected: "Figure inserted" message, `/tmp/test_with_fig.docx` exists and contains the image + caption.

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/aigc-detector/scripts/docx_io.py
git commit -m "feat: add insert_figure command to docx_io.py"
```

---

### Task 3: Update SKILL.md W3 step with diagram workflow

**Files:**
- Modify: `.claude/skills/aigc-detector/SKILL.md`

- [ ] **Step 1: Add diagram script path note to Agent 适配说明 table**

After the existing table (around line 42), add a row or note. Find the line:
```
| 读取文档 | Bash + python3 | 相同 |
```
Add after it:
```
| 生成图表 | Bash + python3 diagram_gen.py | 相同 |
| 插入图片 | Bash + python3 docx_io.py insert_figure | 相同 |
```

- [ ] **Step 2: Expand Step W3 description**

Replace the current W3 line (line 419):
```
- **Step W3: 逐章撰写** — 按大纲逐章生成内容。代码相关章节基于实际代码分析。全程应用 AIGC 安全写作技法（参考 `references/rewrite_methods.md`）。每章生成后暂停，让用户确认或修改后再继续。维护全局上下文摘要确保跨章节一致性。
```

With:
```
- **Step W3: 逐章撰写** — 按大纲逐章生成内容。代码相关章节基于实际代码分析。全程应用 AIGC 安全写作技法（参考 `references/rewrite_methods.md`）。**图表识别与插入：**写每章时自动判断适合插入图表的位置（参考 `references/thesis_writing_guide.md` 中的图表规则），输出建议列表供用户确认。用户确认后：
  1. 生成 Mermaid 文本描述
  2. 调用 `diagram_gen.py generate` 渲染 PNG
  3. 调用 `docx_io.py insert_figure` 插入图片 + 题注到 docx
  每章生成后暂停，让用户确认或修改后再继续。维护全局上下文摘要确保跨章节一致性。
```

- [ ] **Step 3: Add diagram command usage section**

After the Step W5 description (line 421), add a new section before 论文写作模式约束:

```
**图表生成命令：**
```bash
# 生成图表（Mermaid 文本 → PNG）
echo "graph TD\n  A --> B" | python3 ~/.claude/skills/aigc-detector/scripts/diagram_gen.py generate --output ./figures/fig1.png

# 插入图片到 docx（在第5段后插入）
python3 ~/.claude/skills/aigc-detector/scripts/docx_io.py insert_figure thesis.docx 5 ./figures/fig1.png --caption "图 3-1 系统架构图" --output thesis_with_fig.docx
```

如果全局路径不存在，回退到项目级路径：
```bash
python3 .claude/skills/aigc-detector/scripts/diagram_gen.py generate --output ./figures/fig1.png
python3 .claude/skills/aigc-detector/scripts/docx_io.py insert_figure thesis.docx 5 ./figures/fig1.png --caption "图 3-1 系统架构图"
```

**注意：** 多张图片需从后往前插入（先插索引大的段落），避免段落索引偏移。
```

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/aigc-detector/SKILL.md
git commit -m "feat: add diagram generation workflow to SKILL.md W3 step"
```

---

### Task 4: Update thesis_writing_guide.md with diagram rules

**Files:**
- Modify: `.claude/skills/aigc-detector/references/thesis_writing_guide.md`

- [ ] **Step 1: Add diagram identification rules section**

At the end of the file, append:

```markdown

---

## 图表自动识别与生成规则

### 各章节推荐图表类型

| 章节类型 | 推荐图表 | Mermaid 类型 |
|---------|---------|-------------|
| 需求分析 | 用例图、功能结构图 | `graph TD` |
| 系统设计 | 系统架构图、模块关系图 | `graph TD` 或 `graph LR` |
| 数据库设计 | ER 关系图 | `erDiagram` |
| 详细设计 | 类图、时序图、状态图 | `classDiagram` / `sequenceDiagram` / `stateDiagram-v2` |
| 系统实现 | 功能流程图 | `graph TD` |
| 测试分析 | 测试流程图、结果对比 | `graph TD` |

### 图表生成工作流

写每章内容时，LLM 应按以下步骤处理图表：

1. **识别位置**：分析章节内容，判断哪些位置适合用图表辅助说明
2. **保留占位符**：在正文中保留 `[图 X-X 描述]` 占位符
3. **输出建议**：在章节末尾列出图表建议，包含：
   - 插入位置（段落编号）
   - 图表类型和描述
   - 完整的 Mermaid 代码
4. **用户确认**：询问用户是否生成以上图表，允许修改或跳过
5. **生成并插入**：用户确认后调用 `diagram_gen.py` 和 `docx_io.py insert_figure`

### Mermaid 质量要求

- **节点标签用中文**，类名/方法名保持英文（如代码中有）
- **单图不超过 20 个节点**，过大则拆分为多张子图
- **内容必须与论文上下文一致**，不得编造不存在的模块、类或关系
- **类图需基于实际代码分析**，从 About/ 代码中提取真实的类名、属性和方法
- **ER 图需基于实际数据库设计**，表名和字段名应与代码一致
```

- [ ] **Step 2: Commit**

```bash
git add .claude/skills/aigc-detector/references/thesis_writing_guide.md
git commit -m "feat: add diagram identification rules to thesis writing guide"
```

---

### Task 5: Update install.sh for mmdc

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: Add mmdc check after python-docx check**

After the python-docx check block (around line 45), add:

```bash

# --- Step 2.5: Check mmdc (optional, for diagram generation) ---
echo "==> Checking mmdc (Mermaid CLI)..."
if ! command -v mmdc &>/dev/null; then
    echo "    mmdc not found. Diagram generation requires Mermaid CLI."
    echo "    Install later with: npm install -g @mermaid-js/mermaid-cli"
    echo "    (Diagram feature will be unavailable until mmdc is installed)"
else
    echo "    mmdc found: $(command -v mmdc)"
fi
```

- [ ] **Step 2: Add diagram_gen.py to download list**

In the download section (around line 35), after the `curl -fsSL ... thesis_writing_guide.md` line, add:

```bash
curl -fsSL "$REPO_URL/scripts/diagram_gen.py" -o "$INSTALL_DIR/scripts/diagram_gen.py"
```

- [ ] **Step 3: Commit**

```bash
git add install.sh
git commit -m "feat: add mmdc check and diagram_gen.py download to install.sh"
```

---

## Self-Review

**Spec coverage:**
- diagram_gen.py → Task 1 ✓
- docx_io.py insert_figure → Task 2 ✓
- SKILL.md W3 workflow → Task 3 ✓
- thesis_writing_guide.md rules → Task 4 ✓
- Multi-agent adaptation → covered by existing SKILL.md pattern, no new code needed ✓
- install.sh → Task 5 ✓

**Placeholder scan:** No TBD/TODO found. All steps have complete code.

**Type consistency:** All CLI commands use 1-based paragraph index consistent with existing `read` and `replace` commands. Script paths use `~/.claude/skills/aigc-detector/scripts/` consistent with existing pattern.
