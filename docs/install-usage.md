# agent-collab 安装与使用指南

本文档说明如何在 OpenCode / Claude Code 中安装、启用并使用 `agent-collab` 智能体协作插件。

---

## 目录

1. [环境准备](#环境准备)
2. [安装插件](#安装插件)
3. [启用与初始化](#启用与初始化)
4. [选择协作模式](#选择协作模式)
5. [运行工作流](#运行工作流)
6. [审批门控行为](#审批门控行为)
7. [验证插件生效](#验证插件生效)
8. [回滚与禁用](#回滚与禁用)
9. [Git 工作规范](#git-工作规范)

---

## 环境准备

- **OpenCode 或 Claude Code CLI** 已安装并可正常使用
- **Bash** 环境（用于执行插件内的状态与模式控制脚本）
- **Git**（推荐将插件纳入版本控制或作为子目录管理）

---

## 安装插件

`agent-collab` 通过目录加载。将其放入 OpenCode 的插件扫描目录即可。

### 步骤

1. 将本仓库或目录复制到 OpenCode 插件目录。例如：

   ```bash
   # 以默认插件路径为例，实际路径请按你的 OpenCode 配置调整
   cp -r agent-collab ~/.config/opencode/plugins/
   ```

2. 确认目录结构包含以下关键文件：

   ```
   agent-collab/
   ├── .claude-plugin/plugin.json   # 插件清单
   ├── skills/                      # 协作入口、审批、复盘技能
   ├── agents/                      # 六个角色提示词
   ├── hooks/                       # 事件钩子与审批脚本
   ├── scripts/                     # 状态与模式控制脚本
   └── docs/                        # 说明文档
   ```

3. 重启 OpenCode / Claude Code，或重新加载插件列表，使系统识别 `plugin.json`。

> **提示**：如果 OpenCode 支持项目级插件，也可以直接将 `agent-collab` 放在当前工作目录下，由系统按项目自动加载。

---

## 启用与初始化

插件加载后，第一次使用建议初始化协作状态文件。

### 初始化状态

在插件根目录执行：

```bash
bash scripts/mode-controller.sh init
```

这会生成 `.claude/agent-collab.local.md`，记录当前模式、阶段和审批状态。

### 状态文件示例

```yaml
---
enabled: true
mode: A
phase: planning
approval_policy: hybrid
pending_approvals: []
completed_tasks: []
active_agents: []
---
```

- `enabled`：是否启用协作流程
- `mode`：当前模式（A / B / C）
- `phase`：当前阶段（planning / executing / reviewing / completed）
- `approval_policy`：审批策略（hybrid 为混合模式）
- `git_main_branch_protection`：是否保护主分支不直接提交/推送
- `git_require_clean_checkout`：切换分支或 merge/rebase 前是否要求工作区干净
- `git_block_on_pending_approvals`：待审批项存在时是否阻断高风险 Git 动作
- `git_require_review_before_merge`：未审查完成前是否阻断 merge/push

> **建议**：将 `.claude/agent-collab.local.md` 加入 `.gitignore`，避免本地状态污染仓库。

---

## 选择协作模式

本插件支持三种协作模式，对应不同的审批强度与执行顺序。

| 模式 | 名称 | 特点 | 适用场景 |
|------|------|------|----------|
| **A** | 先方案后执行 | 先输出完整计划，审批后再编码 | 复杂功能开发、大型重构 |
| **B** | 快速实现后审查 | 直接实现，完成后统一审查 | 小型修复、简单改动 |
| **C** | 全流程分阶段审批 | 每个阶段都必须审批通过 | 高风险变更、生产热修复 |

### 切换模式

通过脚本切换：

```bash
bash scripts/mode-controller.sh mode B
```

或直接让智能体在对话中切换（协调者/仲裁者会根据上下文调整状态文件）。

### 查看当前状态

```bash
bash scripts/mode-controller.sh status
```

---

## 运行工作流

标准协作流程如下，涉及六个内置角色：

1. **协调者**（蓝色）：接收目标，判断模式，分配任务
2. **规划者**（紫色）：拆解需求，识别依赖与风险，输出执行顺序
3. **执行者**（绿色）：按已确认方案实现代码、测试与文档
4. **审查者**（橙色）：检查实现是否符合方案，指出问题
5. **仲裁者**（红色）：根据策略决定是否放行，支持阻断或人工确认
6. **反思者**（青色）：任务结束后复盘，提炼经验与改进建议

### 启动一次协作

在对话中表达协作意图，例如：

> “我要开发一个用户登录模块，请启动协作模式。”

系统会触发以下技能：

- **xie-zuo-zong-ru-kou**：统一处理协作启动、模式选择、任务拆解与审批门控
- **git-zong-ru-kou**：统一处理 commit / push / merge 前置检查
- **xie-zuo-fu-pan**：在收口阶段输出复盘总结

### 阶段推进

各阶段通常按以下顺序推进，但协调者会根据模式调整：

1. **Planning（规划）**：规划者输出方案，审查者确认
2. **Executing（执行）**：执行者按方案编码，仲裁者在高风险点介入
3. **Reviewing（审查）**：审查者检查代码与测试，列出问题或放行
4. **Completed（完成）**：反思者总结本轮得失，更新可复用规则

---

## 审批门控行为

插件通过 `hooks/hooks.json` 在以下时机自动触发审批检查：

| 触发时机 | 钩子类型 | 行为 |
|----------|----------|------|
| 执行 **Write / Edit / Bash** 前 | `PreToolUse` | 根据模式与策略决定放行或阻断（exit 2） |
| 执行 **Write / Edit** 后 | `PostToolUse` | 模式 C 下自动记录审批请求 |
| 主会话结束 | `Stop` | 检查待审批项，模式 A/C 下未清零则阻断 |
| 子智能体会话结束 | `SubagentStop` | 同上 |

### 各模式审批行为

- **模式 A**：规划阶段阻断写操作（有 pending 项时 exit 2），执行阶段放行
- **模式 B**：不阻断，仅记录提示
- **模式 C**：全流程审批，每次 Write/Edit 后自动创建审批请求，未审批则阻断

### 前置检查收敛

当前所有写入与 Git 前置检查都统一走：

```bash
bash hooks/scripts/pre-flight-check.sh
```

其内部依次执行：

1. 审批门控检查
2. Git 门控检查

### 审批策略

- **auto**：自动放行，仅记录
- **manual**：所有写操作必须人工审批通过
- **hybrid（默认）**：规划阶段有条件放行，执行阶段常规放行

### 审批结论

仲裁者与审查者只输出三种结论之一：

- **通过**：进入下一阶段
- **拒绝**：退回执行者修复
- **待确认**：需要用户人工决策

---

## 验证插件生效

可通过以下方式验证插件已正确加载：

1. **查看状态文件存在且格式正确**：
   ```bash
   cat .claude/agent-collab.local.md
   ```

2. **执行状态脚本无报错**：
   ```bash
   bash scripts/mode-controller.sh status
   ```

3. **在对话中触发协作关键词**：
   输入“启动协作”或“选择模式”，观察智能体是否以“协调者”身份回应，并引用当前模式与阶段。

4. **观察钩子提示**：
    在协作启用状态下，尝试要求写文件，应看到 `[agent-collab] 模式 A（先方案后代码）...` 或类似提示。

5. **执行 Git 状态检查**：
   ```bash
   bash scripts/mode-controller.sh git-check
   ```

---

## 回滚与禁用

### 临时禁用协作

编辑 `.claude/agent-collab.local.md`，将 `enabled` 改为 `false`：

```yaml
---
enabled: false
mode: A
---
```

禁用后，审批钩子不再弹出提示，智能体恢复默认单轮对话行为。

### 恢复默认状态

删除状态文件后重新初始化：

```bash
rm .claude/agent-collab.local.md
bash scripts/mode-controller.sh init
```

### 卸载插件

从 OpenCode 插件目录中移除 `agent-collab` 文件夹，并重启客户端即可。

---

## Git 工作规范

本插件建议配套阅读：

- `docs/git-workflow.md`

核心要求：

1. 不直接在主分支长期开发
2. 先看 diff，再决定提交范围
3. 未经审查通过，不得合并
4. 测试失败优先修复，修不了则回退给用户
5. 高风险场景下优先使用模式 C

---

## 常见问题

**Q：模式切换后为什么智能体仍然按旧模式回应？**  
A：检查 `.claude/agent-collab.local.md` 中的 `mode` 字段是否已更新。部分客户端可能需要重启会话才能重新加载状态。

**Q：审批提示太频繁怎么办？**  
A：将 `approval_policy` 改为更宽松的模式（如仅在高风险操作时触发），或直接临时禁用协作。

**Q：能否只使用部分角色？**  
A：可以。协调者会根据任务复杂度自动决定调用哪些角色。你也可以在对话中明确指定“只让执行者和审查者参与”。

---

## 参考文件

- 插件清单：`.claude-plugin/plugin.json`
- 角色提示词：`agents/*.md`
- 技能定义：`skills/*/SKILL.md`
- 钩子配置：`hooks/hooks.json`
- 状态脚本：`scripts/mode-controller.sh`、`scripts/state-persistence.sh`
- 方案文档：`docs/coordination-plan.md`
