---
description: 初始化 agent-collab 协作环境 — 从全局配置拷贝到项目级，供二次定制
---

# /init-collab

初始化 agent-collab 协作环境，将全局角色配置拷贝到当前项目目录，供用户按需定制模型和权限。

## 功能

1. 将全局 `agent-collab.config.json` 拷贝到 `.opencode/agent-collab.config.json`
2. 创建 `.opencode/agents/` 目录（用户可放入同名 .md 文件覆盖角色 prompt）
3. 初始化 `.opencode/agent-collab-state.json` 状态文件（由插件自动处理）
4. 输出当前协作配置摘要

## 使用场景

- 新项目首次启用 agent-collab 协作
- 需要从全局默认切换为项目级定制（如更换模型、调整权限）
- 检查当前项目的协作状态

## 执行步骤

1. 确认当前工作目录
2. 检查 `.opencode/agent-collab.config.json` 是否已存在
   - 若存在：提示"项目级配置已存在，如需覆盖请先手动删除"
   - 若不存在：从全局配置 `~/.config/opencode/agent-collab.config.json` 复制
3. 创建 `.opencode/agents/` 目录（如不存在）
4. 确认插件状态文件 `.opencode/agent-collab-state.json` 已初始化
5. 输出配置摘要

## 项目级定制方式

拷贝完成后，用户可以：

1. **修改 `.opencode/agent-collab.config.json`** — 更换模型、调整权限
   - 例如将 executor 的模型改为 `openai/gpt-5.2`
   - 例如将 planner 的 permission 改为允许 bash

2. **创建 `.opencode/agents/<角色名>.md`** — 覆盖角色的 prompt
   - 例如创建 `.opencode/agents/coordinator.md` 来自定义协调者行为
   - 只需写正文即可（无需 frontmatter，配置从 JSON 读取）

3. **两者配合** — JSON 控制模型/权限，md 控制 prompt 内容

## 配置优先级

```
项目级 .opencode/agent-collab.config.json  →  覆盖全局配置
项目级 .opencode/agents/*.md               →  覆盖全局 prompt
全局 ~/.config/opencode/agent-collab.config.json  →  默认
全局 ~/.config/opencode/agents/*.md               →  默认 prompt
```

## 输出示例

```
✅ agent-collab 已初始化

📋 协作配置（来自 .opencode/agent-collab.config.json）
   模式：A（先方案后执行）
   审批策略：hybrid
   状态文件：.opencode/agent-collab-state.json

🤖 已注册角色
   coordinator  → zhipuai-coding-plan/glm-5.1     (primary)
   planner      → opencode-go/qwen3.6-plus         (subagent)
   executor     → zhipuai-coding-plan/glm-5.1     (subagent)
   reviewer     → zhipuai-coding-plan/glm-5-turbo  (subagent)
   arbiter      → zhipuai-coding-plan/glm-4.7     (subagent, hidden)
   reflector    → opencode-go/kimi-k2.6            (subagent)
   learner      → zhipuai-coding-plan/glm-5.1     (primary)

💡 定制提示
   - 编辑 .opencode/agent-collab.config.json 更换模型或权限
   - 在 .opencode/agents/ 中创建同名 .md 文件自定义角色 prompt
```
