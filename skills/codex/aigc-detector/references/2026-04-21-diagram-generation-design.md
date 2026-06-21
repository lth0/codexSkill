# Diagram Generation Feature Design

**Date:** 2026-04-21
**Status:** Approved
**Scope:** Add diagram/chart generation and insertion to the AIGC-Detector Skill's thesis writing mode (W3)

---

## Background

The thesis writing mode (W3-W4) currently generates `[图 X-X 描述]` text placeholders for figures. Users must manually create diagrams and insert them into the .docx. The `formatted_write_docx` function already has `<!-- figure-placeholder -->` regex matching but only skips these markers without rendering.

python-docx supports `doc.add_picture()` for image insertion, providing the technical foundation.

---

## Architecture

Three changes, each with a single responsibility:

1. **`scripts/diagram_gen.py`** — Receives Mermaid text, calls `mmdc` CLI, outputs PNG
2. **`docx_io.py insert_figure`** — Inserts image + caption paragraph at a specified position in .docx
3. **SKILL.md / thesis_writing_guide.md** — Modified W3 workflow: LLM identifies diagram positions, generates Mermaid, asks user to confirm, then calls both scripts

Data flow:
```
LLM identifies diagram opportunity during W3 chapter writing
  → Generates Mermaid text description
  → User confirms or edits
  → diagram_gen.py generate (Mermaid → PNG)
  → docx_io.py insert_figure (PNG + caption → .docx)
```

---

## 1. diagram_gen.py

**Location:** `.claude/skills/aigc-detector/scripts/diagram_gen.py`

**CLI interface:**
```bash
# From stdin
echo "graph TD\n  A --> B" | python3 diagram_gen.py generate --output ./figures/fig1.png

# From file
python3 diagram_gen.py generate --input diagram.mmd --output fig2.png --theme default --bg white
```

**Behavior:**
1. Read Mermaid text from stdin or `--input` file
2. Write to temporary `.mmd` file
3. Call `mmdc -i temp.mmd -o output.png -w 1600 -b white -t default`
4. Verify output file exists and is non-empty
5. Print output path to stdout

**mmdc detection:**
- On first run, check if `mmdc` is in PATH
- If missing, print install instruction: `npm install -g @mermaid-js/mermaid-cli`
- Installation is one-time

**Error handling:**
- Mermaid syntax error → capture mmdc stderr, return to LLM for correction
- mmdc not installed → print install prompt, exit gracefully
- Output directory missing → auto-create with `os.makedirs`

**Supported diagram types (LLM chooses, script doesn't restrict):**
- `graph` — flowcharts, architecture diagrams
- `classDiagram` — UML class diagrams
- `erDiagram` — database ER diagrams
- `sequenceDiagram` — sequence diagrams
- `stateDiagram-v2` — state diagrams

---

## 2. docx_io.py insert_figure

**New subcommand added to existing `docx_io.py`.**

**CLI interface:**
```bash
python3 docx_io.py insert_figure <docx_path> <paragraph_index> <image_path> \
  --caption "图 3-1 系统架构图" \
  --output thesis_with_fig.docx
```

**Behavior:**
1. Open docx, locate paragraph N (1-based, consistent with existing read/replace)
2. Insert two new paragraphs after paragraph N:
   - **Image paragraph:** centered alignment, image width = page width - margins (from analyze data, default 14cm), preserves aspect ratio
   - **Caption paragraph:** centered alignment, 五号宋体 (10.5pt SimSun), content from `--caption`
3. Save to `--output` path or overwrite original

**Multiple insertions:**
- LLM must insert from last to first (e.g., insert at paragraph 20 first, then paragraph 10) to avoid index shifting
- Alternative: chain `--output` to different files for each insertion

**Constraints:**
- Does not modify existing `replace`, `read`, `formatted_write` commands
- `<!-- figure-placeholder -->` markers in `formatted_write` remain unchanged (no modification to existing logic)
- Image insertion is a separate step called by LLM during W3, not embedded in formatted_write

---

## 3. W3 Workflow Changes

**Modified in:** `SKILL.md` and `references/thesis_writing_guide.md`

**Current flow:**
```
W3: Write chapter → User confirms → Next chapter
```

**New flow:**
```
W3: Write chapter content
  → LLM identifies positions where diagrams would be appropriate
  → If diagrams are appropriate:
     1. Keep [图 X-X 描述] placeholder in text
     2. Output diagram suggestion list:
        "建议在以下位置插入图表：
         ① 第3段后：系统架构流程图（Mermaid: graph TD ...）
         ② 第7段后：数据库ER图（Mermaid: erDiagram ...）"
     3. Ask user: "是否生成以上图表？可以修改图表内容或跳过"
  → User confirms:
     4. Call diagram_gen.py generate → PNG
     5. Call docx_io.py insert_figure → .docx
  → Next chapter
```

**Diagram position identification rules (written into thesis_writing_guide.md):**

| Chapter type | Typical diagrams |
|---|---|
| Requirements analysis | Use case diagram, functional structure diagram |
| System design | Architecture diagram, module flowchart |
| Database design | ER diagram |
| Detailed design | Class diagram, sequence diagram, state diagram |
| Implementation | Flowchart |
| Testing | Test flowchart |

**Mermaid text quality requirements:**
- Node labels in Chinese
- Max 20 nodes per diagram (readability at print scale)
- Content must be consistent with paper context — no fabricated modules or relationships

**Scope limitation:** Diagram feature only activates in thesis writing mode (W3). Detection & rewrite mode is unaffected.

---

## 4. Multi-Agent Adaptation

Identical to existing SKILL.md pattern:

| Platform | Script invocation | User interaction |
|---|---|---|
| Claude Code | `python3 ~/.claude/skills/aigc-detector/scripts/diagram_gen.py` | AskUserQuestion tool |
| Codex/Cursor/Windsurf | Same scripts, `~/.claude/skills/` global path | Output option numbers, wait for input |
| Gemini | Same | Same |

Scripts are pure CLI — no platform-specific code needed. Only the interaction mechanism differs, which is already handled in SKILL.md's existing agent adaptation table.

---

## 5. New Dependencies

- `npm install -g @mermaid-js/mermaid-cli` — install on first use, one-time
- No new Python dependencies

**install.sh update:** Add mmdc availability check and install prompt.
