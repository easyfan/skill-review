# skill-review

Skills/Agents 设计委员会——对 Claude Code skill/agent/command/SKILL.md 文件进行系统性多维质量审查。

## 功能

`/skill-review` 启动一个三阶段审查流水线：

**Stage 1（并行）**：4 个专项审计员同时分析目标文件
- S1 定义质量：prompt 清晰度、模型选型、工具集匹配、description 准确性
- S2 互动链路：orchestration 模式、数据契约、并行/串行正确性
- S3 外部研究：对标业界最佳实践（含 WebSearch）
- S4 可用性：UX、输出格式、错误处理、进度反馈

**Stage 2（串行）**：
- Challenger（opus）：对 P0/P1 发现做 CONFIRM/DISPUTE/UNVERIFIABLE 裁定
- Reporter：综合报告 + 直接修复已确认问题

**Stage 3（条件）**：
- Grader：description 变更后自动生成 should-trigger/should-not-trigger 断言

输出质量等级：🔴 不可用 / 🟡 可用有缺陷 / 🟢 生产可用 / ⭐ 优秀

## 安装

<!--
### Option A — npm (未发布，暂不可用)

```bash
npm install -g skill-review
npx skill-review
```

### Option B — npx 一次性安装（未发布，暂不可用）

```bash
npx skill-review
```
-->

### Option A — Claude Code 插件市场

在 Claude Code 会话中运行：

```
/plugin marketplace add easyfan/skill-review
/plugin install skill-review@skill-review
```

> ⚠️ **部分自动化测试覆盖**：底层 `claude plugin install` CLI 路径已被 looper T2b（Plan B）验证。`/plugin` REPL 入口点（交互界面）无法通过 `claude -p` 测试，需在 Claude Code 会话中手动确认。

### Option B — 本地脚本

```bash
git clone https://github.com/easyfan/skill-review.git
cd skill-review
bash install.sh
```

安装到指定目录（`CLAUDE_DIR` 优先于 `--target=`）：

```bash
CLAUDE_DIR=~/.claude bash install.sh
# 或
bash install.sh --target=~/.claude
```

> ✅ **已验证**：已通过 skill-test 流水线自动化验证（looper Stage 5）。

### Option C — 手动

```bash
cp commands/skill-review.md ~/.claude/commands/
cp agents/*.md ~/.claude/agents/
```

安装后重启 Claude Code 会话使 agent 生效。

> ✅ **已验证**：已通过 skill-test 流水线自动化验证（looper Stage 5）。

## 使用

```
/skill-review [target_list|all|all-commands|all-agents|all-skills]
```

**示例**：

```bash
# 审查所有 commands、agents 和 skills
/skill-review all

# 仅审查 agents
/skill-review all-agents

# 仅审查 skills（~/.claude/skills/*/SKILL.md）
/skill-review all-skills

# 审查指定 skill（按目录名）
/skill-review readme-i18n

# 审查多个目标（逗号分隔，不加空格）
/skill-review looper,patterns

# 轻量快检（Stage 1 完成后输入"停止"，跳过 Challenger）
/skill-review looper
# → Stage 1 完成后输入"停止"
```

> **Skills** 以 `~/.claude/skills/` 下的目录名标识（如 `readme-i18n` 对应 `~/.claude/skills/readme-i18n/SKILL.md`）。SKILL.md 不需要 `model`/`tools` 字段，审查标准会自动适配。

## 安装的文件

| 文件 | 安装位置 | 说明 |
|------|----------|------|
| `commands/skill-review.md` | `~/.claude/commands/` | 协调者 command，用户通过 `/skill-review` 触发 |
| `agents/skill-reviewer-s1.md` | `~/.claude/agents/` | S1 定义质量审计员（sonnet）|
| `agents/skill-reviewer-s2.md` | `~/.claude/agents/` | S2 互动链路审计员（sonnet）|
| `agents/skill-researcher.md` | `~/.claude/agents/` | S3 外部前沿研究专员（sonnet + WebSearch）|
| `agents/skill-reviewer-s4.md` | `~/.claude/agents/` | S4 可用性审计员（sonnet）|
| `agents/skill-challenger.md` | `~/.claude/agents/` | Challenger 挑战者（**opus**）|
| `agents/skill-reporter.md` | `~/.claude/agents/` | Reporter 汇总报告员（sonnet + **Edit**）|
| `skills/validate-plugin-manifest/` | `~/.claude/skills/` | 插件 manifest 和 install.sh 合规性验证 skill |

## 权限模型

| 场景 | 行为 |
|------|------|
| 元项目（`PROJECT_ROOT` 或其上级目录存在 `user-level-write`）| Reporter 可直接修改 `~/.claude/` 下文件 |
| 普通项目 | 用户级文件发现写入 `~/.claude/proposals/`，不直接修改 |
| 自指模式（审查委员会自身）| Reporter 仅生成建议，禁止 Edit |

`user-level-write` 检测从当前 `PROJECT_ROOT` 向上递归查找，止于 `CLAUDE_CWD`（Claude 启动时的工作目录；未设置时默认为 `$HOME`）。这意味着放在工作区根目录的元项目标记（如 `cc_manager/.claude/user-level-write`）在子目录（如 `packer/readme-i18n`）中运行 `/skill-review` 时也能被正确识别。可通过显式设置 `CLAUDE_CWD` 限制搜索上界。

## 成本提示

- Stage 1：4 个 sonnet Agent 并行，粗估 $0.1-0.5 USD
- Stage 2 Challenger：**opus 模型**，粗估 $0.5-2 USD（约为 sonnet 的 5 倍）
- 如需低成本快检：Stage 1 完成后输入"停止"，跳过 Challenger
- 目标文件数 > 15 时会触发成本警告，可选择分批执行

## 数据与隐私

| 数据 | 发往何处 |
|------|----------|
| 目标 skill/agent 文件内容 | Claude API（S1–S4、Challenger、Reporter 共 6 次调用）|
| `CLAUDE.md` 首段（项目背景）| Claude API（Stage 1 全部 4 个 Agent）|
| `~/.claude/proposals/` pending proposals | Claude API（作为历史上下文）|
| S3 搜索关键词 | **外部搜索服务**（WebSearch / Jina）—— 不含文件原文 |

**建议在 git 仓库中使用**，以便通过 `git diff` 查看/还原 Reporter 的自动修改：

```bash
git diff .claude/   # 查看 Reporter 所有改动
git checkout .claude/commands/my-skill.md  # 还原指定文件
```

工具会在 `.claude/agent_scratch/skill_review_committee/` 和 `.claude/reports/` 写入中间文件，建议加入 `.gitignore`：

```
.claude/agent_scratch/
.claude/reports/
```

**CLAUDE.md 凭证检测**：若 CLAUDE.md 中含 `api_key / token / password / secret` 等关键词，工具会在发送前弹出确认提示（Step 0e.5）。

## 注意事项

- 不支持并发运行（lockfile 保护，第二个实例会报错）
- Reporter 直接 Edit 文件前会输出修改内容，可通过 `git diff` 查看或还原
- description 语义改写需人工确认，Reporter 不直接改写（仅输出建议方向）
- ARGUMENTS 不接受路径遍历字符（`../`、绝对路径等），只允许 skill 名称

## 开发

```bash
# 本地安装到默认 ~/.claude/
bash install.sh

# 安装到指定目录（测试用）
bash install.sh --target /tmp/test-claude
```

### Evals

`evals/evals.json` 包含 15 个测试用例，覆盖协调者逻辑的主要分支：

| ID | 场景 | 验证重点 |
|----|------|---------|
| 1 | 无参数调用 | 输出使用说明，不启动任何 Agent |
| 2 | 不存在的目标名 | 输出"未找到"错误和可用名称列表 |
| 3 | `skill-review`（自身） | 进入自指模式，Reporter 仅生成建议 |
| 4 | `all-commands` | 动态发现 commands 目录，启动 Stage 1 四维审查 |
| 5 | 单目标（`looper`） | 解析映射表、格式快检、启动 Stage 1 |
| 6 | `all,looper`（混合参数）| 拒绝混合参数，输出错误并退出 |
| 7 | `looper, patterns`（逗号加空格）| 自动修正格式后继续执行 |
| 8 | `all-agents` | 动态发现 agents 目录，含 name kebab-case 快检 |
| 9 | 并发锁保护 | 检测存活进程持有的 lock.pid，拒绝第二个实例 |
| 10 | 成本警告门 | 文件数 > 15 时输出警告并等待确认/拆分 |
| 11 | 零发现快路径 | 跳过 Challenger，Reporter 输出 ⭐ 等级 |
| 12 | 元项目模式（ELEVATED） | `PROJECT_ROOT` 或其上级目录存在 `user-level-write` → Reporter 授权直接 Edit |
| 13 | 非元项目模式 | 用户级文件发现写入 proposals/ 而非直接修改 |
| 14 | Challenger 失败 | 输出选项 A/B，等待用户选择，不自动跳过 |
| 15 | Stage 3 自动触发 | modification_log.md 含 description 变更时触发断言设计 |

每个用例由 `prompt`（触发输入）、`expected_output`（预期行为描述）、`assertions`（可验证的具体检查点）三部分组成。部分用例附带 `files` 前置条件（在执行前写入 scratch 目录）。

手动测试（在 Claude Code 会话中）：
```bash
/skill-review looper        # 对应 eval 5
/skill-review all-agents    # 对应 eval 8
```

使用 skill-creator 的 eval loop 批量运行（如已安装）：
```bash
python ~/.claude/skills/skill-creator/scripts/run_loop.py \
  --skill-path ~/.claude/commands/skill-review.md \
  --evals-path evals/evals.json
```

## Changelog

### v1.6.0（2026-04-14）

质量与健壮性改进——自指委员会审查所有发现已全部应用（CONFIRMED P1×4、P2×10、P3×7）：

| 项目 | 变更 |
|------|------|
| 并行调用强制约束 | Stage 1 启动新增强制性说明：4 次 Agent 调用必须在协调者同一 turn 内以 `function_calls` 数组并发发出，防止意外串行执行 |
| Challenger 失败条件分支 | Step 2b 新增显式 `CHALLENGER_FAILED` 分支：跳过 `challenger_response.md` 预读，内联状态字符串，Reporter 传参中省略该文件 |
| 占位写入主体明确化 | `sN_findings.md` 缺失时的占位写入由被动语态改为主动：协调者在 4 个 Agent 均返回后检查并写入（Write tool）|
| 中场汇总模板 | 新增结构化 markdown 模板：审计员状态行、P0/P1/P2/P3 分层列表、确认提示；标注为"必要交互节点，不支持无人值守模式" |
| description 改进 | 改为意图描述式写法，覆盖"review 一下"、"检查"、"帮我看看"等自然语言变体；成本标注改为"约 $0.5-2+ USD（视目标数量而定）" |
| 删除死代码 | Step 0c-1 中 `TOTAL_LINES` 变量已删除；阈值常量新增注释说明理论依据 |
| grep 回退 | Step 2b grep：`-B1` 改 `-B3`；新增空匹配回退（回退为全量读取前 200 行）|
| A/B/C/D 策略内联定义 | Step 2a-pre 超标时的策略选项现已内联定义（A: 精简仅 P0/P1、B: 分批 5 个文件、C: 跳过 Challenger、D: 终止）|
| 自指检测增强 | 新增路径检测：凡目标位于 `~/.claude/skills/skill-review/` 下均触发自指模式；用户可见通知明确指出 |
| Lockfile trap | Step 0b 注册 `trap 'rm -f lock.pid' EXIT`，覆盖凭证检测中断、用户"停止"退出等所有退出路径 |
| Stage 3 工具预算 | 协调者在 Stage 2b 结束后验证剩余工具调用配额（≥3），不足时跳过 Stage 3 并标注 |
| Reporter 下一步建议规范 | 新增格式规范：最多 5 条、按优先级排序、每条附对应 skill 命令 |
| S3 表格注释 | WebSearch 权限注释改为"S3 subagent 自带 WebSearch 权限"；`skill-researcher` subagent_type 例外标注 |
| 约束日志注释 | 自指约束日志行新增注释："仅为审计日志，约束在 Reporter prompt 中实现" |

### v1.5.0（2026-04-14）

超大文件硬门控——skill-shrink 升级为必要依赖：

| 项目 | 变更 |
|------|------|
| 400 行门控 | Step 0c-1 升级：任意目标文件 >400 行触发硬退出并提示先运行 `/skill-shrink`。此前为 >440 行时的软警告。 |
| 221–400 行范围 | 继续执行，输出 ⚠️ 质量警告（流程无变化）|
| install.sh | 安装后检测 skill-shrink 是否已安装；未装时给出警告 |
| 依赖声明 | skill-shrinker（`easyfan/skill-shrinker`）现为 >400 行文件审查的必要依赖 |

### v1.4.1（2026-03-31）

权限模型修复——ELEVATED 检测改为向上递归：

| ID | 项目 | 变更 |
|----|------|------|
| FIX-09 | ELEVATED 检测 | 从精确匹配 `$PROJECT_ROOT/.claude/user-level-write` 改为从 `PROJECT_ROOT` 向上递归查找到 `CLAUDE_CWD`（环境变量，默认 `$HOME`）——修复在元项目子目录运行时误判为非元项目的问题 |

### v1.4.0（2026-03-31）

Skills 支持——`~/.claude/skills/*/SKILL.md` 文件升级为一等公民审查目标：

| 项目 | 变更 |
|------|------|
| 发现路径 | 新增扫描 `~/.claude/skills/*/SKILL.md` |
| 选择器 | 新增 `all-skills`；`all` 现在包含 skills |
| 格式快检 | SKILL.md 跳过 `model`/`tools` 字段检查；改为验证 `name` 与目录名一致性 |
| Proposal 路由 | 新增 `~/.claude/proposals/skills/` 子目录 |
| Stage 1 审计标准 | S1/S2 针对 SKILL.md 调整（不做模型选型/orchestration 链路审查，转为聚焦指令清晰度、边界覆盖、description 触发准确性）|

### v1.3.0（2026-03-27）

安全加固 — S2 委员会补充审查后修复（3 个 P1）：

| ID | 项目 | 变更 |
|----|------|------|
| SEC-05 | ARGUMENTS 白名单 | SEC-01 黑名单升级为白名单：`^(all\|all-commands\|all-agents\|[a-z][a-z0-9_-]+...)$`，完全防御路径遍历 |
| SEC-06 | 确认门 TTY 检测 | Step 0e.5 `read -r` 改为 `[ ! -t 0 ]` 非交互检测，CI/Agent 调用自动中断 |
| SEC-07 | 凭证正则扩展 | CLAUDE.md 检测正则新增值侧特征：Bearer/ghp_/sk-/eyJ（JWT）|
| SEC-08 | 自指模式跳过 | Step 0e.5 在自指模式下自动跳过（不传入 CLAUDE.md 时无需检测）|

### v1.2.0（2026-03-26）

安全与隐私加固：

| ID | 项目 | 变更 |
|----|------|------|
| SEC-01 | ARGUMENTS 路径注入 | 前置过滤 `../`、绝对路径等非法字符，拒绝执行 |
| SEC-02 | CLAUDE.md 凭证检测 | Step 0e.5：读取前检测 api_key/token/password/secret，命中时弹确认提示 |
| SEC-03 | 数据声明 | README 新增"数据与隐私"章节，说明哪些内容发往 Claude API / 外部搜索 |
| SEC-04 | .gitignore 引导 | README 建议排除 `agent_scratch/` 和 `reports/` |

### v1.1.0（2026-03-26）

skill-test pipeline 全 5 阶段通过后应用的 bug fix 批次（来源：Stage 4 回归审查 S1/S2/S4 发现 + Stage 5 looper 已知问题）：

| ID | 优先级 | 问题 | 修复 |
|----|--------|------|------|
| FIX-01 | P1 | `grep -lLE` 互斥 flag（macOS BSD grep 行为未定义）| 改为 `-LE` |
| FIX-02 | P2 | 成本警告缺量化范围 | 添加粗估 USD 区间 |
| FIX-03 | P2 | `PROPOSAL_SUBDIR` 缺 `/commands/` 显式分支，未知路径静默跳过 | 增加 elif 分支 + 警告 |
| FIX-04 | P2 | `grep -A 20` 截断长发现；`sed` 前缀污染 Markdown 结构 | 改为 `-A 50`；仅前缀标题行；全量 cat 作权威内容 |
| FIX-05 | P2 | Challenger 启动缺用户侧耗时提示 | 启动前输出"预计 1-5 分钟"提示 |
| FIX-06 | P2 | Challenger 失败选项 A 措辞含歧义，放大用户风险感知 | 简化措辞，去掉括号内触发说明 |
| FIX-07 | P3 | 正常路径不写 `pipeline_status.md`，Reporter 依赖混合判断 | Stage 2 入口写入 `STATUS: NORMAL` |
| FIX-08 | P3 | Stage 3 自指模式 `HAS_DESC_CHANGE` 无显式分支；`grep` 过宽匹配正文 | 增加自指/非自指路由；改为 `grep -q '^description'` |
