---
description: 当用户明确请求审查 skill/agent 文件质量（如"/skill-review"、"委员会审查 skill/agent"、"审查这个 skill"、"审查这个 agent"、"agent 质量审查"）时触发；涉及多 subagent 并行和 opus Challenger，成本较高（$0.5-2 USD），需用户指定目标文件；在模糊场景下应优先询问用户是否确认启动完整委员会审查
allowed-tools: ["Bash", "Read", "Write", "Task"]
---
# Skills/Agents 设计委员会

## 使用方式
```
/skill-review [target_list|all|all-commands|all-agents]
```

`target_list` 格式：逗号分隔的 skill 名称，不含路径和 `.md` 后缀，不加空格（如：`mr-review,perf-tune`）

**示例**：
- `/skill-review all` — 审查所有 commands 和 agents
- `/skill-review all-agents` — 仅审查 agent 定义
- `/skill-review all-commands` — 仅审查 command 定义
- `/skill-review mr-review,perf-tune` — 审查指定 skill（逗号分隔，不加空格）

**注意**：委员会 Reporter 在 Stage 2 完成后将**直接修改**问题文件中确认无争议的改进项。请提前确认已提交当前工作区变更。

**注意**：若当前项目无 `.claude/user-level-write`（非元项目），涉及 `~/.claude/` 的修改项 Reporter 将写入 `~/.claude/proposals/` 而非直接执行。审查完成后，请**切换到元项目**处理 proposals，再执行"全部修复"。

**注意**：若审查目标包含委员会自身文件（skill-review、skill-reviewer-s* 等），自动进入自指模式：Reporter 将仅生成修改建议，不执行直接修改。

> 💡 **轻量快检模式**：如需迭代自检而非完整正式审查，可仅指定单个文件，Stage 1 中场完成后输入"停止"，仅查看 S1/S2/S3/S4 原始发现，跳过 opus Challenger 和 Reporter 直接修改，成本更低。

> ⚠️ 不支持并发运行：同时启动多个实例会导致 scratch 文件相互覆盖，建议等待上一次运行完成后再启动新的审查。

---

## 你的角色：委员会协调者（Coordinator）

你负责：
1. 解析审查目标，收集所有 skill/agent 文件路径
2. 组建并调度 4 个 Stage 1 专项审查成员（并行）
3. 汇总后向用户展示 Stage 1 摘要，等待确认
4. 依序启动 Challenger（反驳验证）→ Reporter（报告+直接修改）

---

## 审查目标（动态发现）

`/skill-review` 在启动时动态发现以下目录中的 skill 文件：

| 目录 | 说明 |
|------|------|
| `<PROJECT_ROOT>/.claude/commands/` | 项目级 commands |
| `<PROJECT_ROOT>/.claude/agents/` | 项目级 agents |
| `~/.claude/commands/` | 用户级 commands（跨项目共用）|
| `~/.claude/agents/` | 用户级 agents（跨项目共用）|

`PROJECT_ROOT` = 执行命令时的当前工作目录（`pwd`）。同名文件时项目级优先于用户级。

---

## 执行流程

### Step 0：初始化

**Step 0a：确定项目根目录，动态发现可用 skill**

首先确定 PROJECT_ROOT（不要硬编码，通过 Bash 获取）：

```bash
PROJECT_ROOT=$(pwd)
SCRATCH_DIR="$PROJECT_ROOT/.claude/agent_scratch/skill_review_committee"
REPORT_DIR="$PROJECT_ROOT/.claude/reports"
```

> **设计说明**：SCRATCH_DIR 使用固定路径（不含时间戳），因为 Reporter 会直接修改原始 skill/agent 文件，历史 findings 无需跨次保留；每次运行覆盖前次即可。（对比 research-review 使用时间戳路径，是因为 research-review 的 Reporter 不修改源文件，需要保留多次审查的历史 findings 供比较。）

动态发现所有可用 skill 文件，构建"名称 → 绝对路径"映射表：

```bash
# 项目级（优先）
ls "$PROJECT_ROOT/.claude/commands/"*.md 2>/dev/null
ls "$PROJECT_ROOT/.claude/agents/"*.md 2>/dev/null
# 用户级（补充，同名时被项目级覆盖）
ls "$HOME/.claude/commands/"*.md 2>/dev/null
ls "$HOME/.claude/agents/"*.md 2>/dev/null
```

解析 `$ARGUMENTS`：

**Step 0a-1（空值检查）**：若 `$ARGUMENTS` 为空，输出使用帮助并退出：
```
用法：/skill-review [target_list|all|all-commands|all-agents]
示例：
  /skill-review all                    — 审查所有 skills
  /skill-review all-agents             — 仅审查 agents
  /skill-review mr-review              — 审查指定 skill
  /skill-review mr-review,perf-tune   — 审查多个 skill（逗号分隔，不加空格）
请重新执行并指定审查目标。
```

**Step 0a-2（安全过滤）**：拒绝非法参数格式，防止路径遍历（前一步失败则退出，不执行此步）：

```bash
# 白名单：仅允许 all/all-commands/all-agents 或 kebab-case 名称（逗号分隔）
if ! echo "$ARGUMENTS" | grep -qE '^(all|all-commands|all-agents|[a-z][a-z0-9_-]+(,[a-z][a-z0-9_-]+)*)$'; then
  echo "错误：参数格式不合法。"
  echo "请使用 skill 名称（不含路径和 .md 后缀）："
  echo "  正确：/skill-review mr-review"
  echo "  正确：/skill-review mr-review,perf-tune"
  echo "  正确：/skill-review all"
  echo "  错误：/skill-review ~/.claude/commands/mr-review.md"
  echo "  错误：/skill-review ./mr-review"
  exit 1
fi
```

**Step 0a-3（格式修正）**：若 `$ARGUMENTS` 含逗号+空格模式（如 "mr-review, perf-tune"），这是纯语法问题、意图明确，直接用 Bash 修正后继续，无需确认（前两步通过后才执行此步）：

```bash
# 自动去除逗号后的多余空格，修正后输出提示
if echo "$ARGUMENTS" | grep -q ", "; then
  ARGUMENTS=$(echo "$ARGUMENTS" | sed 's/,[ ]*/,/g')
  echo "格式提示：已自动去除逗号后空格，解析为：$ARGUMENTS"
fi
```

- `all` → 所有发现的 commands + agents
- `all-commands` → 仅 commands
- `all-agents` → 仅 agents
- 逗号分隔名称 → 在动态发现的映射表中按名称（不含路径和 `.md`）查找；名称不存在时，输出错误信息并退出（不执行审查）
- 混合参数（如 `all,mr-review`）不合法，输出错误并退出：`错误：不支持 all/all-commands/all-agents 与具体名称混合使用，请使用具体文件列表或单独特殊值`
- 参数缺省时报错展示用法说明（见前置空值检查）：
  ```
  错误：以下名称未找到：<name1>, <name2>
  可用名称列表：
    commands: <list>
    agents: <list>
  请重新执行：/skill-review <正确名称> 或 /skill-review all
  ```

若审查目标包含 skill-review 自身或委员会成员，即进入**自指模式**。

**委员会成员文件名完整列表**（用于自指模式检测；新增审计维度时需同步更新**此处、Stage 1 分派表、委员会成员一览表**三处）：
> ⚠️ **维护提示**：新增或重命名委员会成员文件时，必须同步更新此列表，否则自指模式检测将静默失效。
- skill-reviewer-s1.md（→ Stage 1 分派表 S1 行）
- skill-reviewer-s2.md（→ Stage 1 分派表 S2 行）
- skill-reviewer-s4.md（→ Stage 1 分派表 S4 行）
- skill-researcher.md（→ Stage 1 分派表 S3 行）
- skill-challenger.md（→ Stage 2 Challenger）
- skill-reporter.md（→ Stage 2 Reporter）
- skill-review.md（command 本身，无分派表行）

可在 Step 0a 末尾执行运行时验证（可选，检测列表维护完整性）：
```bash
# 验证自指检测列表中每个文件在 ~/.claude/ 下确实存在，防止静默失效
SELF_REF_FILES=("skill-reviewer-s1.md" "skill-reviewer-s2.md" "skill-reviewer-s4.md" "skill-researcher.md" "skill-challenger.md" "skill-reporter.md" "skill-review.md")
for _sf in "${SELF_REF_FILES[@]}"; do
  ls "$HOME/.claude/agents/$_sf" "$HOME/.claude/commands/$_sf" 2>/dev/null | grep -q . || \
    echo "⚠️ 自指检测列表中的文件 '$_sf' 在 ~/.claude/ 下不存在，自指模式检测可能失效" >&2
done
```

若在动态发现的文件列表中，任意文件的 basename 与上述任一匹配，进入自指模式，**立即向用户输出**：
```
[自指模式] 检测到审查目标包含委员会自身文件（<匹配文件名>）
  - Reporter 将仅生成修改建议，不直接修改任何文件
  - 所有建议需人工审阅后手动应用
  - 流程将自动继续，无需确认
```

自指模式约束：
- **禁止传入项目 CLAUDE.md**：这些 agent 是跨项目通用工具，用特定项目背景评审会引入偏见，导致在不同项目运行时产生矛盾的修改建议
- **Reporter 禁止 Edit**：见 Step 2b 授权说明中的自指模式条款
- 在 Stage 1 传给各 Agent 的项目背景中注明："当前审查的是跨项目通用 agent，评审标准应基于通用性，而非当前项目技术栈"

**Step 0b：创建工作目录**

```bash
mkdir -p "$SCRATCH_DIR"
mkdir -p "$REPORT_DIR"
# 并发 lockfile 检查：防止多实例同时运行覆盖 scratch 文件
# lock.pid 格式：<PID> <创建时间戳epoch>，用于检测 stale lock 和排除 PID 复用
if [ -f "$SCRATCH_DIR/lock.pid" ]; then
  read lock_pid lock_ts < "$SCRATCH_DIR/lock.pid"
  now_ts=$(date +%s)
  lock_age=$((now_ts - ${lock_ts:-0}))
  if [ "$lock_age" -gt 1800 ]; then
    # 锁龄超过 30 分钟，视为孤儿锁，自动清理后继续
    echo "⚠️ 检测到孤儿 lockfile（锁龄 ${lock_age}s），已自动清理。如有疑问，手动清理：rm $SCRATCH_DIR/lock.pid" >&2
    rm -f "$SCRATCH_DIR/lock.pid"
  elif kill -0 "$lock_pid" 2>/dev/null; then
    echo "错误：已有另一个 /skill-review 实例在运行（PID $lock_pid），请等待其完成后再执行。如误报，手动清理：rm $SCRATCH_DIR/lock.pid" >&2
    exit 1
  fi
fi
echo "$$ $(date +%s)" > "$SCRATCH_DIR/lock.pid"
# 清理上次运行遗留的 scratch 文件（Write 工具要求对已存在文件先 Read，不清理会导致 Agent Write 失败）
# MUST be after lock.pid write — 先写锁再清理，避免竞态中锁文件被误删
rm -f "$SCRATCH_DIR"/*.md
# 注：lock.pid 以 echo > 写入（协调者 bash 直写），s*_findings.md 等产物由 Agent Write 工具写入，两种路径各司其职
# 初始化完成断言
ls -d "$SCRATCH_DIR" > /dev/null || { echo "FATAL: SCRATCH_DIR 初始化失败，终止。" >&2; exit 1; }
```

写入初始进度文件 `$SCRATCH_DIR/progress.md`：

> 设计说明：progress.md 使用结构化 schema（`STAGE | DIM | STATUS | FINDINGS | TIME`），便于断点排查。Stage 1 各 Agent 完成后追加写入各维度状态记录。

```
STAGE=0 | DIM=init | STATUS=STARTED | FINDINGS=- | TIME=<datetime>
PROJECT_ROOT=<PROJECT_ROOT>
TARGET=<列表>
```

**Step 0c：验证目标文件存在**

```bash
ls -la "$PROJECT_ROOT/.claude/commands/" "$PROJECT_ROOT/.claude/agents/" "$HOME/.claude/commands/" "$HOME/.claude/agents/" 2>/dev/null
```

对每个目标文件：若不存在则告知用户并输出：
  ```
  输入"继续"排除缺失文件后执行剩余目标，输入"终止"退出：
  ```
  用户选"继续"：从目标列表中移除缺失文件，继续执行后续步骤；
  用户选"终止"：终止流程，输出缺失文件路径列表。

排除缺失文件后，将已验证存在的文件更新为最终审查目标列表，后续 Step 0e（格式快检）、Step 0f 和 Stage 1 均使用此更新后的列表。若排除后无剩余有效目标，立即终止并提示："错误：无有效审查目标。请检查参数或文件路径后重试。"

若目标文件数 > ${SKILL_REVIEW_WARN_THRESHOLD:-15}，输出成本警告并询问用户：
```
⚠️  目标文件数量较多（<N> 个：commands <M> 个 / agents <K> 个），all 模式将启动 6 个 Agent（含 opus Challenger），
    预估成本偏高（粗估 $1-5 USD，具体取决于文件长度和发现数量）。建议分批审查：all-commands 和 all-agents 分两次执行。
    继续执行请输入"继续"，分批执行请输入"拆分"（将输出分批建议命令后终止，需手动执行）。
    用户选"继续"：继续执行后续步骤；
    用户选"拆分"：根据原始输入动态生成分批建议命令后终止当前流程（需用户手动执行）：
      - 原始输入为 `all`：输出 `/skill-review all-commands` 和 `/skill-review all-agents`
      - 原始输入为 `all-commands`：输出按名称前半/后半拆分的具体命令列表（前 N/2 个 / 后 N/2 个）
      - 原始输入为 `all-agents`：同上，按 agents 名称拆分
      - 原始输入为具体文件名列表：输出按前半/后半拆分的具体命令列表
```

在验证完成后，输出进度提示：
```
[审查启动] 已发现 <N> 个有效目标文件（<M> 个 commands, <K> 个 agents）
并行启动 4 个审计 Agent（S1 定义质量 / S2 链路 / S3 前沿研究 / S4 可用性）
预计等待：Stage 1 共 2-10 分钟（S3 含 Web 搜索，超过 15 分钟可视为超时）。请等待...
若 S3 超时或失败，该维度将标注 [分析失败] 后继续，不影响其他三个维度结果。
```

输出成本预估：
```
[成本预估]
- Stage 1：4 个 sonnet Agent 并行，粗估 $0.1-0.5 USD
- Stage 2 Challenger：使用 opus 模型，粗估 $0.5-2 USD（约为 sonnet 的 5 倍）
如需仅执行 Stage 1（跳过 Challenger），等 Stage 1 完成后在确认门输入"停止"即可。
```

**Step 0d：权限检测与文件分类**

```bash
# 检测 cc-config-manager 模式
[ -f "$PROJECT_ROOT/.claude/user-level-write" ] && ELEVATED=true || ELEVATED=false

# 分类目标文件（TARGET_FILES 数组由 Step 0c 验证后赋值）
USER_LEVEL_FILES=()    # ~/.claude/ 下的文件
PROJECT_LEVEL_FILES=() # $PROJECT_ROOT/ 下的文件
for f in "${TARGET_FILES[@]}"; do
  [[ "$f" == "$HOME/.claude/"* ]] && USER_LEVEL_FILES+=("$f") || PROJECT_LEVEL_FILES+=("$f")
done

# 将分类结果写入文件，供 Reporter 读取（避免依赖 prompt 内联展开）
{
  echo "USER_LEVEL_FILES:"
  printf '%s\n' "${USER_LEVEL_FILES[@]}" | sed 's/^/- /'
  echo "PROJECT_LEVEL_FILES:"
  printf '%s\n' "${PROJECT_LEVEL_FILES[@]}" | sed 's/^/- /'
} > "$SCRATCH_DIR/file_classification.md"
```

输出权限检测结果：
- 若 `ELEVATED=true`：`[权限检测] 元项目模式（user-level-write 已授权），用户级文件可直接修改`
- 若 `ELEVATED=false` 且 `USER_LEVEL_FILES` 非空：
  ```
  [权限检测] 非元项目模式（.claude/user-level-write 不存在）
    用户级文件（N 个）：仅审查，发现写入 ~/.claude/proposals/ 而非直接修改
    项目级文件（M 个）：正常审查
  ```
- 若 `ELEVATED=false` 且所有目标均为项目级：无特殊提示，正常继续

将 `ELEVATED`、`USER_LEVEL_FILES`、`PROJECT_LEVEL_FILES` 作为后续步骤的上下文变量。

---

**Step 0e：前置格式快检**

在启动委员会之前，对所有目标文件执行基础格式验证（耗时 < 5 秒），过滤可被机械检出的明显问题：

```bash
for f in <目标文件列表>; do
  echo "=== $(basename $f) ==="
  # 检查 1：YAML front-matter 是否存在
  head -1 "$f" | grep -q "^---" || echo "  ❌ 缺少 YAML front-matter"
  # 检查 2：description 字段是否存在
  grep -q "^description:" "$f" || echo "  ❌ 缺少 description 字段"
  # 检查 3：description 长度 ≤ 1024 字符
  desc=$(grep "^description:" "$f" | head -1 | sed 's/^description:[[:space:]]*//')
  [ ${#desc} -gt 1024 ] && echo "  ❌ description 超过 1024 字符（当前 ${#desc} 字符）"
  # 检查 4（仅 agents）：name 字段存在且为 kebab-case
  if echo "$f" | grep -q "/agents/"; then
    grep -q "^name:" "$f" || echo "  ❌ agent 缺少 name 字段"
    name=$(grep "^name:" "$f" | head -1 | sed 's/^name:[[:space:]]*//')
    echo "$name" | grep -qE "^[a-z][a-z0-9-]*$" || echo "  ❌ name 不符合 kebab-case: $name"
  fi
  echo ""
done
```

输出结果，并将格式快检结果写入 scratch 文件：
```bash
# 将格式快检输出写入文件，供 Reporter 纳入报告（标注 P3）
echo "$format_check_output" > "$SCRATCH_DIR/format_issues.md"
```
- 若全部通过：`✅ 格式快检通过（<N> 个文件）`，`format_issues.md` 写入"无格式问题"，继续 Step 0f
- 若有问题：列出所有问题条目后继续（格式问题不中断流程；Reporter 将从 `format_issues.md` 读取并纳入报告，标注 P3）

> **设计说明**：借鉴 skill-creator 的 `quick_validate.py` 思路，前置过滤格式问题，节省委员会算力。S1 可聚焦于更深层的设计质量问题，无需重复检查格式项；Reporter 通过读取 `format_issues.md` 跟进格式发现，确保不丢失。

---

**Step 0e.5：CLAUDE.md 敏感内容检测**

在将 CLAUDE.md 作为项目背景发送给 Stage 1 Agent 之前，检查是否含有疑似凭证：

```bash
if [ "$SELF_REF" = "true" ]; then
  echo "[自指模式] CLAUDE.md 检测跳过（自指模式下不传入项目背景）"
else
  CLAUDE_MD="$PROJECT_ROOT/CLAUDE.md"
  if [ -f "$CLAUDE_MD" ]; then
    if grep -iEq '(api[_-]?key|access[_-]?token|secret[_-]?key|password|credential|private[_-]?key)\s*[:=]|(Bearer\s+[A-Za-z0-9]|ghp_|sk-|eyJ[A-Za-z0-9])' "$CLAUDE_MD"; then
      echo "⚠️ [安全提示] 检测到 CLAUDE.md 中可能包含凭证（api_key / token / secret / JWT / GitHub PAT 等）。"
      echo "   若继续，CLAUDE.md 内容将包含在发送至 Anthropic API 的 prompt 中（Stage 1 共 4 次调用）。"
      echo "   若 CLAUDE.md 含真实密钥，这些密钥将暴露在 API 请求中。"
      echo "   非交互环境（CI/Agent 调用）下将自动中断。请清理 CLAUDE.md 中的敏感内容后重新运行。"
      # 非交互环境（无 TTY）：直接中断（fail-safe）
      if [ ! -t 0 ]; then
        echo "已中断（非交互式环境，默认拒绝继续）。"
        exit 1
      fi
      # 交互环境：等待用户明确确认
      echo "   请输入\"取消\"或其他非继续内容以中断；输入\"继续\"以明确接受此风险："
      read -r _confirm
      if ! echo "$_confirm" | grep -qi "继续\|continue\|yes\|y"; then
        echo "已中断。请清理 CLAUDE.md 中的敏感内容后重新运行。"
        exit 1
      fi
    fi
  fi
fi
```

---

**Step 0f：预读所有目标文件 YAML front-matter（防止 Agent 预算耗尽）**

**目的**：Agent 工具调用预算有限（约 25-30 次），若 Agent 自行 Read 所有目标文件，预算将耗尽于 Read 操作，无法最终 Write 发现报告。协调者在此步骤批量预读，将结果嵌入 Agent prompt。

> **大批量场景预算分配指导**：目标文件数 > 5 时，各 Agent 应按审计维度重点优先 Read 最相关文件，而非逐一读取所有文件。建议优先级：S1 优先 YAML front-matter 完整内容、S2 优先 orchestration 步骤、S3 优先外部参考相关段落、S4 优先用户接口和错误处理段落。前 5 个文件为优先级文件，超出部分仅在预算允许时读取。

使用 Bash 批量提取所有目标文件的 YAML front-matter，构建"预读内容块"：

```bash
FILE_COUNT=<目标文件数>
for f in <目标文件列表>; do
  echo "=== $f ==="
  # 读取到第二个 --- 为止（YAML front-matter 结束），完整提取不截断
  awk '/^---/{c++; if(c==2){print; exit}} {print}' "$f"
  echo ""
done
```

将上述完整输出作为 **预读内容块** 嵌入 Stage 1 Agent prompt，并附加说明：

> **Agent 工具预算说明**：上述预读内容包含所有文件的 YAML front-matter。
> **你无需再次 Read 文件头部（model/tools/description 信息均已提供）**。若某文件 front-matter 字段看起来不完整，可自行 Read 该文件补充。
> 仅在需要分析正文细节时才调用 Read，且每个 Read 应针对特定分析目标。
> **请确保保留至少 2 次工具调用用于最终 Write 步骤**（建议：先完成全部分析和草稿，最后一步统一写入 scratch 文件）。
>
> 注：Step 0e 已完成前置格式快检（YAML 字段、name kebab-case、description 长度），S1 可直接聚焦于设计质量问题，无需重复检查上述格式项。

---

**Step 0g：扫描 Pending Proposals（历史发现上下文，仅他指模式）**

> **设计说明**：自指模式下跳过此步骤。proposals/agents/ 和 proposals/commands/ 存储的是"skill-review 在他指模式下发现的、针对目标文件的历史改进建议"；自指时这些条目是关于 skill-review 自身的观察，注入会改变正在执行的审查流程，造成自我参照悖论。

```bash
if [ "$SELF_REF" = "false" ]; then
  PROPOSAL_CONTEXT=""
  for f in "${TARGET_FILES[@]}"; do
    skill_name=$(basename "$f" .md)
    # 根据路径推断 proposals 子目录
    if echo "$f" | grep -q "/agents/"; then
      PROPOSAL_SUBDIR="agents"
    elif echo "$f" | grep -q "/commands/"; then
      PROPOSAL_SUBDIR="commands"
    else
      echo "⚠️ 无法推断 proposals 子目录（非 agents/commands 路径：$f），跳过 proposal 扫描" >&2
      continue
    fi
    # 查找 pending proposals（排除已处理：status: ✅ / applied / rejected）
    PENDING=$(find "$HOME/.claude/proposals/$PROPOSAL_SUBDIR" \
      -name "*${skill_name}*.md" 2>/dev/null | \
      xargs grep -LE "status: (✅|applied|rejected)" 2>/dev/null)
    if [ -n "$PENDING" ]; then
      for p in $PENDING; do
        PROPOSAL_CONTEXT="${PROPOSAL_CONTEXT}<proposal_context>\n=== $(basename "$p") ===\n$(cat "$p")\n</proposal_context>\n\n"
      done
    fi
  done
fi
```

若发现 pending proposals，构建 **Proposal 上下文块** 并向用户输出提示：

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📬 已有 Pending Proposals（历史 /skill-review 发现，来自其他项目）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[<skill_name>]
  来源：<proposal 文件路径>
  已记录缺口：
    - <问题1>（发现于 <source-project>，<date>）
    - <问题2>
    ...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

若无 pending proposals，`PROPOSAL_CONTEXT` 为空，不输出任何内容。

---

### Stage 1：并行专项审查

**单条消息同时启动以下 4 个 Agent**（Task tool，单条消息多 tool call 并行）：

向每个 Agent 传入：
1. 审查目标文件的完整绝对路径列表（**必须按此列表读取，不得读取列表外的文件，不得根据上下文自行猜测目标**）
2. scratch 目录路径：`$SCRATCH_DIR`（即 `$PROJECT_ROOT/.claude/agent_scratch/skill_review_committee/`）
3. Step 0f 预读的**完整 YAML front-matter 内容块**（非一行摘要，而是每个文件的前20行原文）
4. 工具预算说明（嵌入 prompt 中，见 Step 0f）
5. 项目背景：
   - **非自指模式**：若 `$PROJECT_ROOT/CLAUDE.md` 存在则读取首段，否则使用通用描述
   - **自指模式**：固定使用以下通用描述，**不传入**项目 CLAUDE.md（防止项目偏见）：
   > 被审查的是跨项目通用 skill/agent，应以"在任意项目中是否都有意义"为评审标准。
   > `.claude/commands/*.md` 是用户通过 `/command-name` 触发的 skill 指令（协调者角色，Claude 主进程执行）。
   > `.claude/agents/*.md` 是 YAML front-matter 定义的子 Agent（被 Task tool 调度，独立沙箱执行）。
   > Agent 间通过 `.claude/agent_scratch/` 下的临时文件传递数据。
   > **⚠️ 反熟悉度搜索要求**：评审对象与你运行的 pipeline 结构相同，存在"自我偏好偏差"风险——你可能对自身设计的结构给出更宽松的评价。请主动寻找与你设计直觉相悖的证据，对每个"通过"判断反问：是否有反例？是否有未覆盖的边界场景？
6. **findings 格式强制要求**：每条发现必须以 `### [P0]`/`### [P1]`/`### [P2]`/`### [P3]` 开头，协调者将在 Stage 1 完成后用 grep 验证格式合规性。
7. **Proposal 上下文块**（Step 0g 产物，仅他指模式；自指模式传"无 pending proposals"）：
   - "已记录缺口"中的问题若在当前目标文件中**仍存在**，标注为"[已知，仍未修复]"作为 CONFIRMED 发现上报
   - 已被修复的问题标注为"[已知，已修复]"归入通过项
   - 审查重点放在 proposal 未覆盖的**新问题**上，不重复描述已知问题

| Agent | subagent_type | 职责 | 模型 |
|-------|--------------|------|------|
| S1 | `skill-reviewer-s1`（已加入自指白名单） | 定义质量审计（prompt 清晰度、模型选型、工具集匹配、description 准确性） | sonnet |
| S2 | `skill-reviewer-s2`（已加入自指白名单） | 互动链路审计（orchestration 模式、数据契约、并行/串行正确性） | sonnet |
| S3 | `skill-researcher`（已加入自指白名单） | 外部前沿研究（对标业界最佳实践，允许使用搜索引擎） | sonnet |
| S4 | `skill-reviewer-s4`（已加入自指白名单） | 可用性审计（用户体验、输出格式、错误处理、进度反馈） | sonnet |

**等待所有 4 个 Agent 完成。**

输出等待中状态提示：`[Stage 1 执行中] 正在等待 4 个 Agent 完成，请勿中断...`

完成后检查 findings 文件是否存在且非空，并追加各 Agent 执行状态到 progress.md：

```bash
ls "$SCRATCH_DIR"/s{1,2,3,4}_findings.md 2>&1

# 非空校验（size > 0）
for dim in s1 s2 s3 s4; do
  if [ -s "$SCRATCH_DIR/${dim}_findings.md" ]; then
    count=$(grep -c "^### " "$SCRATCH_DIR/${dim}_findings.md" 2>/dev/null || echo 0)
    # 格式合规性验证：findings 必须含 [P0/P1/P2/P3] 标记
    if ! grep -q "^### \[P[0-3]\]" "$SCRATCH_DIR/${dim}_findings.md" 2>/dev/null; then
      echo "⚠️ ${dim} findings 格式不合规（缺少 [P0/P1/P2/P3] 标记），请检查该 Agent 输出"
    fi
    # 反向检测：是否存在非标准标题（四级标题或粗体标注会导致 Reporter 遗漏发现）
    if grep -q "^#### \[P[0-3]\]\|^\*\*\[P[0-3]\]" "$SCRATCH_DIR/${dim}_findings.md" 2>/dev/null; then
      echo "⚠️ ${dim}_findings.md 存在非法标题格式（#### 或 **粗体**），Reporter 解析时可能遗漏这些发现"
    fi
    printf "STAGE=1 | DIM=${dim} | STATUS=SUCCESS | FINDINGS=${count} | TIME=$(date '+%Y-%m-%dT%H:%M:%S')\n" >> "$SCRATCH_DIR/progress.md"
  else
    printf "STAGE=1 | DIM=${dim} | STATUS=FAIL | FINDINGS=0 | TIME=$(date '+%Y-%m-%dT%H:%M:%S')\n" >> "$SCRATCH_DIR/progress.md"
    echo "[MISSING - Agent 执行失败，此维度无发现数据]" > "$SCRATCH_DIR/${dim}_findings.md"
    echo "⚠️ ${dim} findings 缺失或为空，该维度结果将被标注 [分析失败]"
  fi
done
```

Reporter 将在报告中明确标注缺失维度，不因此中断流程。

---

### Stage 1 中场汇总与暂停

读取 4 个 findings 文件（全量读取）：
- `s1_findings.md`
- `s2_findings.md`
- `s3_findings.md`
- `s4_findings.md`

**通过项统计**：读取各 findings 文件的 `## 通过项` 章节，按文件名去重后汇总（同一文件被多个审计员标注通过，计为 1 个通过项）。

向用户输出 **Stage 1 汇总报告**：

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🏛️ Skills/Agents 设计委员会 — Stage 1 完成
审查目标：N 个文件 | 发现总数：X 个
S1 发现：X 个 | S2 发现：X 个 | S3 发现：X 个 | S4 发现：X 个
其中 P0×X  P1×X  P2×X  P3×X  （最高优先级：<P0/P1/P2/P3>）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🔴 高优先级（影响功能正确性 / 可能导致 Agent 行为错误）
  [S1] <问题标题> — <一句话描述>
  ...

🟡 中优先级（影响质量 / 一致性 / 可维护性）
  [S2] <问题标题>
  ...

🟢 低优先级：X 个（见详细报告）

🟢 通过：X 个（≤5 个时列出名称：<名称列表>；>5 个时见详细报告）

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Stage 2 将启动：
  • Challenger（opus，成本约为 sonnet 的 5 倍）— 反驳性验证所有 Stage 1 发现
  • Reporter（sonnet）— 综合报告 + 直接修改已确认问题

⚠️  Reporter 将直接 Edit skill/agent 文件中无争议的改进项
    修改范围：YAML front-matter（model/tools/description）、输出路径约定
    不会修改：核心业务逻辑、工作流步骤、已有功能检查项
    如需保留现状，请在确认前说明
请输入"继续"执行 Stage 2（Challenger + Reporter），或输入"停止"保留 Stage 1 结果并退出：
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**等待用户确认进入 Stage 2。**（若本命令由上层协调者 Agent 以"无交互直接完成"方式调用，跳过此确认门，直接进入 Stage 2。）用户说"继续"/"yes"/"执行"等即可；说"停止"/"取消"/"结束"等则退出，不启动 Stage 2。

停止时输出：
```
Stage 1 已完成，结果保留在：<实际 SCRATCH_DIR 绝对路径>/
可用编辑器打开 s1_findings.md～s4_findings.md 查阅（Markdown 格式）。
注意：重新运行 /skill-review 时将清空 scratch 目录并从头执行完整流程。
```

> **条件路由**：若 Stage 1 发现总数为 0（所有 findings 文件均无任何发现），**跳过 Challenger**，先写入占位文件后直接启动 Reporter：
> ```bash
> printf "STATUS: ZERO_FINDINGS\n" > "$SCRATCH_DIR/pipeline_status.md"
> printf "# Challenger 已跳过（Stage 1 零发现）\n" > "$SCRATCH_DIR/challenger_response.md"
> ```
> 同时在 Reporter prompt 中注明"pipeline_status.md 首行为 `STATUS: ZERO_FINDINGS`，表示零发现跳过场景，请读取 pipeline_status.md 判断状态，而非解析 challenger_response.md 内容"。Reporter 生成空报告并输出质量等级 ⭐。

---

### Stage 2：深潜与修改

**串行执行**（Challenger 完成后才启动 Reporter）：

```bash
# 正常执行路径写入 STATUS: NORMAL（供 Reporter 统一按文件内容路由，而非依赖文件存在性判断）
printf "STATUS: NORMAL\n" > "$SCRATCH_DIR/pipeline_status.md"
```

**Step 2a：启动 Challenger**

向用户输出：
```
[Stage 2a - Challenger 启动中] 使用 opus 模型，预计耗时 1-5 分钟，请等待...
```

**前置：预读 findings 文件内容（节省 Challenger 工具调用预算）**

在启动 Challenger 前，协调者读取全部 findings 文件完整内容，并按 P 级别从高到低排序拼接（减少位置偏差，高优先级发现优先呈现）：

```bash
# 按 P 级别排序拼接（P0 > P1 > P2 > P3），仅在标题行注入来源前缀（不破坏正文 Markdown）
for priority in P0 P1 P2 P3; do
  for dim in s1 s2 s3 s4; do
    grep -A 50 "^### \[${priority}\]" "$SCRATCH_DIR/${dim}_findings.md" 2>/dev/null | \
      sed "s/^\(### \[P[0-3]\]\)/[$dim] \1/"
  done
done
# 全量内容（权威版本，供 Challenger 引用原文；排序提取仅作结构导航用）
for dim in s1 s2 s3 s4; do
  echo "=== ${dim}_findings.md ==="
  cat "$SCRATCH_DIR/${dim}_findings.md"
  echo ""
done
```

将上述完整内容作为 **findings 预读块** 嵌入 Challenger prompt，并注明：
> "以下 findings 内容已由协调者预读并嵌入 prompt，**你无需再 Read findings 文件**；
>  仅在需要验证原始 agent/command 文件的具体行时才调用 Read；
>  请优先保留工具调用预算用于 Read 被审查文件和最终 Write challenger_response.md；
>  建议：完成所有分析后，最后一步统一 Write 输出文件。"

Task tool，`subagent_type: "skill-challenger"`

传入：
1. Stage 1 所有 findings **完整内容**（嵌入 prompt，无需 Agent Read）
2. Stage 1 findings 文件完整绝对路径（备用，Agent 如需核对原文可自行 Read）：
   - `$SCRATCH_DIR/s1_findings.md`
   - `$SCRATCH_DIR/s2_findings.md`
   - `$SCRATCH_DIR/s3_findings.md`
   - `$SCRATCH_DIR/s4_findings.md`
3. 所有被审查文件的绝对路径列表
4. scratch 目录路径：`$SCRATCH_DIR`
5. 失败维度列表：<S? 维度失败时填入，如"S3 维度分析失败，s3_findings.md 缺失"，全部成功时填"无">
6. Step 0f 预读的**完整 YAML front-matter 内容块**（复用 Stage 1 已生成的内容，无需重新 Read 文件头部）

在 Challenger prompt 中补充说明：
> 请直接从上方嵌入的 findings 内容中提取高优先级项（严重性标记为 P0/P1 的条目），**无需 Read findings 文件**。**不要依赖协调者的摘要描述，以 findings 原文为裁定依据。**
>
> **Challenger 职责边界**：对每个 🔴 发现，必须在原始 agent/command 文件中找到直接文档证据才能 CONFIRM；仅凭文档间推断不够。Challenger **不进行运行时执行验证**（如"description 是否真的能触发"）——执行层验证属于可选 Stage 3（grader），不属于 Challenger 职责。Challenger 聚焦于：逻辑矛盾、字段缺失、引用不一致，有原文证据则 CONFIRM，有反证则 DISPUTE，证据不足则 UNVERIFIABLE。
>
> **双向验证要求（防止单向否定偏差）**：DISPUTE 每个发现时，同时给出"支持该发现的最强正向证据"，确保裁定是真正双向权衡而非单纯否定。
>
> **偏见保护声明**：假设 Stage 1 发现来自高水平人工审查员（而非 LLM），不因发现来源于同家 LLM 而更宽容或更苛刻；每个 DISPUTE 需注明反证来源（原文直引 vs 通用推断）。
>
> **Challenger 预计耗时**：1-5 分钟（取决于 P1 发现数量）。

等待 Challenger 完成后，检查 `challenger_response.md` 是否存在：

```bash
ls "$SCRATCH_DIR/challenger_response.md" 2>/dev/null
```

若文件**不存在**，向用户输出以下提示并等待用户输入 A 或 B：

```
⚠️ Challenger 执行失败（challenger_response.md 未生成）。
  选项 A（推荐）：跳过 Challenger 验证，用 Stage 1 原始发现直接生成报告（Stage 1 结果仍然有价值）
  选项 B：终止流程，Stage 1 findings 保留在 <实际 SCRATCH_DIR 绝对路径>，可稍后手动查阅；重新运行可触发完整流程
  请输入 A（推荐，跳过 Challenger 继续）或 B（终止）：
```

若文件**存在**，执行内容有效性快检：
```bash
# 检查 challenger_response.md 是否包含结构化裁定标记
if ! grep -q "CONFIRMED\|DISPUTED\|UNVERIFIABLE" "$SCRATCH_DIR/challenger_response.md"; then
  echo "⚠️ challenger_response.md 内容异常（缺少 CONFIRMED/DISPUTED/UNVERIFIABLE 标记），Challenger 可能中途中断。将按原始严重性处理。"
fi
```

- 用户选 A：写入占位文件并记录结构化状态：
  ```bash
  printf "STATUS: CHALLENGER_FAILED\n" > "$SCRATCH_DIR/pipeline_status.md"
  echo "# Challenger 执行失败，所有发现按原始严重性决策（等同于无 Challenger 裁定）" > "$SCRATCH_DIR/challenger_response.md"
  ```
  继续执行 Step 2b（Reporter）。
- 用户选 B：终止流程。Stage 1 findings 保留在 `$SCRATCH_DIR`（输出实际展开路径），可手动查阅。

若 `challenger_response.md` 存在，读取并向用户展示关键争议项（≤10条），然后询问：

```
Challenger 已完成裁定，如上所示。
Reporter 将对 CONFIRMED 项直接修改，DISPUTED 项仅生成建议。
继续执行请输入"继续"，如需调整请说明。
```

等待用户确认后启动 Step 2b。

**Step 2b：启动 Reporter**

**前置：预读 challenger_response.md 内容（减少 Reporter 工具调用压力）**

在启动 Reporter 前，协调者读取 challenger_response.md 完整内容（或若超过 200 行，提取 CONFIRMED/DISPUTED/UNVERIFIABLE 列表摘要）：

```bash
challenger_line_count=$(wc -l < "$SCRATCH_DIR/challenger_response.md" 2>/dev/null || echo 0)
if [ "$challenger_line_count" -le 200 ]; then
  # 直接嵌入完整内容
  cat "$SCRATCH_DIR/challenger_response.md"
else
  # 超长时提取结构化摘要
  grep -E "^\[CONFIRMED\]|\[DISPUTED\]|\[UNVERIFIABLE\]|^STATUS:" "$SCRATCH_DIR/challenger_response.md"
fi
```

将上述内容作为 **challenger 预读块** 嵌入 Reporter prompt，并附注："challenger_response.md 内容已预读，无需 Read"。

**自指模式 allowed-tools 日志**（若 `SELF_REF=true`）：
```bash
[ "$SELF_REF" = "true" ] && echo "[自指模式] Reporter allowed-tools 已排除 Edit，执行工具层约束（Read/Write/Bash）"
```

输出进度提示（展开实际文件列表）：
```
[Stage 2b - Reporter 启动中]
即将可能直接修改的文件（PROJECT_LEVEL_FILES）：
  <逐行展开 PROJECT_LEVEL_FILES 实际路径列表，若为空则输出"无（全部为用户级文件）">
用户级文件（~/.claude/）：非元项目时不直接修改，仅生成 proposal
如需备份，请先 Ctrl+C 中断，执行 git stash，再重新运行。
Reporter 将综合 Stage 1 发现和 Challenger 裁定，生成审查报告并直接修复已确认问题。
预计耗时：仅报告生成约 1-2 分钟；含多文件修改约 2-5 分钟。
```

输出等待中状态提示：`[Stage 2b - Reporter 执行中] 正在综合发现并修复问题，请勿中断...`

Task tool，`subagent_type: "skill-reporter"`

传入：
1. 所有 findings 文件**完整绝对路径**（逐一展开）：
   - `$SCRATCH_DIR/s1_findings.md`
   - `$SCRATCH_DIR/s2_findings.md`
   - `$SCRATCH_DIR/s3_findings.md`
   - `$SCRATCH_DIR/s4_findings.md`
   - `$SCRATCH_DIR/challenger_response.md`
   - `$SCRATCH_DIR/format_issues.md`（Step 0e 格式快检结果，标注 P3 纳入报告）
2. 审查目标列表（含绝对路径）
3. 当前日期
4. scratch 目录路径：`$SCRATCH_DIR`
5. 报告输出路径：`$REPORT_DIR`，报告文件名：`skill_review_<YYYYMMDD>.md`（日期展开后传入，如 `skill_review_20260319.md`）
6. 文件分类信息：从 `$SCRATCH_DIR/file_classification.md` 读取（Step 0d 写入，包含 USER_LEVEL_FILES 和 PROJECT_LEVEL_FILES 完整列表）
7. **直接修改授权说明**：
   > **自指模式下 Reporter 的 Edit 约束**：自指模式（`SELF_REF=true`）下，在向 Reporter 发起 Task 调用时，**协调者必须在 Task tool 的 allowed-tools 参数中显式排除 Edit 工具**，仅传入 `["Bash", "Read", "Write"]`（不含 Edit）。这是工具层强制约束，而非仅依赖 prompt 文本指令。非自指模式下，Reporter 可使用完整工具集（含 Edit）。
   > 授权范围：以 `skill-reporter` agent 定义中的"修改授权边界"为准。
   > 裁定优先级：若同一发现同时存在 CONFIRMED 和 DISPUTED 裁定，以 DISPUTED 为准（不直接修改，改为建议项）；若无 Challenger 裁定，按原始发现严重性决策。
   > 计数规则：Reporter 已直接修改 → 计入"已修复"；CONFIRMED 仅作建议未执行 → 按原严重性计入未修复；DISPUTED → 不计入未修复；UNVERIFIABLE → 不计入未修复。
   > 每次 Edit 前记录"修改原因"，修改后写入 `modification_log.md`（格式：`FIELD | FILE | BEFORE | AFTER`）。
   > **description 触发准确性问题**（如"description 措辞不精确，可能导致触发失误"）：Reporter **不直接改写 description**，改为输出修改方向建议。静态分析无法验证触发准确性，如需量化验证，建议运行 `python ~/.claude/skills/skill-creator/scripts/run_loop.py` 做迭代优化。Reporter 可修改的 description 限于：明显的拼写错误、语法问题、超长（>1024字符）截断。
   > **所有传入 Reporter 的路径必须为绝对路径（非相对路径），确保 Reporter 在沙箱中能正确访问。**
   > **权限模式**（基于 `$SCRATCH_DIR/file_classification.md`，Reporter 读取该文件获取分类，不得自行通过路径前缀推断）：
   > - `ELEVATED=true`：按上述授权范围正常 Edit
   > - `ELEVATED=false`：
   >   - 项目级文件（file_classification.md 中 PROJECT_LEVEL_FILES）：正常 Edit
   >   - 用户级文件（file_classification.md 中 USER_LEVEL_FILES）：**禁止 Edit**，改为在 `~/.claude/proposals/<target-type>/` 生成 proposal 文件
   >   - `<target-type>` 推导规则：`agents/` 目录下的文件 → `agents`；`commands/` 目录下的文件 → `commands`
   >   - Proposal 命名：`<date>_<PROJECT_ROOT最后一段路径>_<topic>.md`
   >   - Proposal schema：参照 `~/.claude/proposals/README.md` 的普通提案格式

等待 Reporter 完成后，验证报告文件是否生成：

```bash
LATEST_REPORT=$(ls "$REPORT_DIR"/skill_review_*.md 2>/dev/null | tail -1)
if [ -z "$LATEST_REPORT" ]; then
  IS_GIT=$(git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree 2>/dev/null)
  if [ "$IS_GIT" = "true" ]; then
    向用户输出：
    "⚠️ Reporter 可能执行失败，报告文件未生成。
     已修改内容可通过 git diff <PROJECT_ROOT展开路径>/.claude/ 查看。
     如需还原，执行 git checkout <PROJECT_ROOT展开路径>/.claude/<file>"
  else
    向用户输出：
    "⚠️ Reporter 可能执行失败，报告文件未生成。
     如需查看改动，请手动对比 <SCRATCH_DIR展开路径>/ 下的备份文件与目标文件。"
  fi
fi
```

---

### Stage 3（条件路由）：grader 断言设计

Reporter 完成后，**检查 `$SCRATCH_DIR/modification_log.md` 是否包含 description 字段变更**：

> **触发方**：协调者在 Stage 2b（Reporter）完成后立即执行此检查；自指模式下 modification_log.md 若仅含建议条目（无实际 Edit），也视为有变更记录（`HAS_DESC_CHANGE=true`），触发断言设计以验证建议方向正确性。产物输出到 `$SCRATCH_DIR/stage3_assertions.md`，不写入最终报告文件（仅供手动验证使用）。

```bash
if [ ! -f "$SCRATCH_DIR/modification_log.md" ]; then
  # 检查报告文件是否存在，区分"Reporter 正常无修改"与"Reporter 执行失败"
  if ! ls "$REPORT_DIR"/skill_review_*.md 2>/dev/null | grep -q .; then
    echo "⚠️ [Stage 3] Reporter 未生成报告文件，可能已失败，请检查 Stage 2b 输出。如需手动触发断言设计，请输入\"断言\"。"
  else
    echo "[Stage 3] modification_log.md 不存在（Reporter 无修改），跳过 Stage 3。"
    echo "如需手动触发断言设计，请输入\"断言\"。"
  fi
  HAS_DESC_CHANGE=false
else
  if [ "$SELF_REF" = "true" ]; then
    # 自指模式：Reporter 不执行 Edit，modification_log.md 存在即视为有变更记录（内层文件存在检查冗余，直接赋 true）
    HAS_DESC_CHANGE=true
  else
    grep -q "^description" "$SCRATCH_DIR/modification_log.md" && HAS_DESC_CHANGE=true || HAS_DESC_CHANGE=false
  fi
fi
```

- **有 description 变更**（`HAS_DESC_CHANGE=true`）：自动触发 Stage 3，告知用户：
  ```
  [Stage 3 - 自动触发] 检测到 description 字段已修改，自动执行断言设计（约 1 分钟）...
  ```
- **无 description 变更**（`HAS_DESC_CHANGE=false`）：跳过 Stage 3，告知用户：
  ```
  [Stage 3 - 已跳过] description 未变更，触发准确性无需重新验证。如需手动触发，请输入"断言"。
  ```
  用户输入"断言"则手动触发；否则直接进入最终输出。

**协调者内联执行**（不启动 Task tool）：
- 读取被修复的 skill 文件（description 文本）
- 若 `$HOME/.claude/skills/skill-creator/agents/grader.md` 存在，参考其断言格式；若不存在，使用以下通用格式：
  ```json
  {
    "should_trigger": [
      {"prompt": "<用户输入>", "expected_decision": "use_skill"}
    ],
    "should_not_trigger": [
      {"prompt": "<用户输入>", "expected_decision": "skip_skill"}
    ]
  }
  ```

协调者内联执行步骤：
1. 读取被审查 skill 的 description
2. 设计 3-5 个 **should-trigger** 场景（用户意图明确匹配 description 时）
3. 设计 3-5 个 **should-not-trigger** 场景（相关但不应触发该 skill 时）
4. 输出到 `stage3_assertions.md`，格式参照 skill-creator `evals.json` schema
5. 附上手动验证命令：
   ```bash
   [ -d "$HOME/.claude/skills/skill-creator" ] && \
     python "$HOME/.claude/skills/skill-creator/scripts/run_loop.py" \
       --skill-path <被审查 skill 路径> \
       --evals-path "$SCRATCH_DIR/stage3_assertions.md" || \
     echo "# skill-creator 目录不存在，无法运行 run_loop.py 验证"
   ```

> **说明**：Stage 3 仅设计断言，不执行 `claude -p` 子进程（需用户在 terminal 手动运行）。执行层验证填补了纯静态审查的盲点——可验证 description 修改后触发准确性是否真的改善。Stage 3 断言执行结果可作为最终质量等级评定的额外维度：断言执行失败应降低质量等级评定，断言全部通过可作为 🟢 等级的补充验证。

若用户跳过 Stage 3，直接进入最终输出。

---

### 最终输出

根据 Reporter 修复后的剩余问题，计算质量等级。

**发现计数规则**：
- Reporter 已直接修改 → 计入"已直接修复"
- CONFIRMED 但仅作为建议（未执行修改）→ 计入"建议采纳（需人工确认）"，按原严重性列出
- DISPUTED → 计入"争议项"（不要求修复）
- UNVERIFIABLE → 计入"争议项"（证据不足，不作决策）
- 质量等级评定基于"建议采纳"中剩余的 P0/P1 数量（已直接修复的不计入）

| 等级 | 条件 |
|------|------|
| 🔴 不可用 | 仍有 P0（workflow 崩溃级）未修复 |
| 🟡 可用（有缺陷）| 无 P0，仍有 P1（功能降级）未修复 |
| 🟢 生产可用 | 无 P0/P1，仅剩 P2/P3 |
| ⭐ 优秀 | 仅剩 P3（文档/风格）或无发现 |

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Skills/Agents 设计委员会执行完毕
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📄 审查报告：<此处 $REPORT_DIR 和文件名必须展开为实际绝对路径后输出，禁止输出变量符号>
   🔴 已直接修复：X 个
   🟡 建议采纳（需人工确认）：X 个
   🟢 通过：X 个

🔧 直接修改记录：
   • .claude/agents/xxx.md — <修改摘要>
   • .claude/commands/xxx.md — <修改摘要>

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
质量等级：<🔴/🟡/🟢/⭐> <等级名称>
建议采纳（需人工确认）：P0×X  P1×X  P2×X  P3×X
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

<若等级为 🟢 或 ⭐，输出：>
✅ 已达到生产可用标准。P2/P3 建议项为可选改进，无需继续迭代。

<若等级为 🟡，输出：>
⚠️ 存在功能性问题，建议修复上方 P1 项后再投入使用。

<若等级为 🔴，输出：>
🚫 存在阻塞性问题，必须修复 P0 项后才能使用。

下一步建议：
  <此处路径必须展开为实际绝对路径，禁止输出 $PROJECT_ROOT 变量符号>
  <若 PROJECT_ROOT 在 git 仓库中（git rev-parse --is-inside-work-tree 返回 true），输出：>
  1. git diff <PROJECT_ROOT实际路径>/.claude/ 查看所有自动修改内容
  2. 查阅报告 🟡 建议项，决定是否采纳
  3. 如发现误改，可通过 git checkout <PROJECT_ROOT实际路径>/.claude/<file> 还原
  <若不在 git 仓库中，输出：>
  1. 如需查看改动，请手动对比 <SCRATCH_DIR实际路径>/ 下的备份文件与目标文件
  2. 查阅报告 🟡 建议项，决定是否采纳

历史审查趋势（若 $REPORT_DIR/ 下存在同名 skill 的历史报告）：
```bash
ls "$REPORT_DIR"/skill_review_*.md 2>/dev/null | tail -3
```
若存在历史报告，读取并对比历次 🔴/🟡 计数，输出改进趋势：
  上次：🔴×N 🟡×M | 本次：🔴×X 🟡×Y → <改善/持平/退步>

<若 Reporter 本次新建了 YAML front-matter（即修改记录中含 "添加 YAML front-matter" 字样），额外输出：>
⚠️  本次修复新增了 YAML front-matter，需重启会话后该 agent 才可作为 subagent_type 使用。
    请执行 /exit 重启，再执行依赖该 agent 的后续操作。
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

输出完成后，清理 lockfile：
```bash
rm -f "$SCRATCH_DIR/lock.pid"
```

---

## 委员会成员一览

> 注：model 列与 Stage 1 分派表保持同步，修改时需同步更新两处。

| 成员 | 角色 | 模型 | 特殊能力 | 阶段 | 返回摘要限制 |
|------|------|------|---------|------|------------|
| Coordinator | 协调者（你）| 继承调用方会话模型（建议 sonnet+；在 haiku 会话中使用时汇总质量可能下降）| 全部工具 | 全程 | — |
| S1 | 定义质量审计员 | sonnet | — | Stage 1 | ≤400 token |
| S2 | 互动链路审计员 | sonnet | — | Stage 1 | ≤400 token |
| S3 | 外部前沿研究专员 | sonnet | **WebSearch（或 Jina MCP，视环境配置）** | Stage 1 | ≤500 token（含外部参考链接）|
| S4 | 可用性审计员 | sonnet | — | Stage 1 | ≤400 token |
| Challenger | 挑战者 | opus | — | Stage 2 | 无限制（输出到 scratch 文件）|
| Reporter | 汇总报告员+修改者 | sonnet | **Edit**（直接修改文件）| Stage 2 | ≤500 token（主要输出在报告文件中）|
| Grader | 断言验证员（可选）| 协调者内联执行 | — | Stage 3 | 无限制（输出到 stage3_assertions.md）|

> **摘要 token 限制设计原则**：Stage 1 各审计员返回简短摘要到协调者，详细发现写入 scratch 文件。S3（研究员）多 100 token 预算用于附加外部参考链接。Stage 2 成员直接写文件，无摘要限制。Stage 3 Grader 为可选，不影响主流程质量等级评定。
