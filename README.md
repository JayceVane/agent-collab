# agent-collab

OpenCode 智能体协作插件：中文提示词、模式 A/B/C、审批门控、复盘沉淀。

> v1.0.0 — 开箱即跑

## 环境要求

- **OpenCode** CLI（[opencode](https://github.com/opencode-ai/opencode)）
- 智能体与技能为纯 Markdown 文件，跨平台兼容

## 安装

### 方式一：安装到当前项目

**Windows（PowerShell）：**
```powershell
git clone git@github.com:JayceVane/agent-collab.git
cd your-project
.\agent-collab\install.ps1
```

**macOS / Linux：**
```bash
git clone git@github.com:JayceVane/agent-collab.git
cd your-project
bash agent-collab/install.sh
```

### 方式二：全局安装（适用于所有项目）

一键安装全部组件（Agents + Skills + JS 插件 + 配置 + 脚本），所有项目通用。

**Windows（PowerShell）：**
```powershell
cd agent-collab
.\install-global.ps1          # 执行安装
.\install-global.ps1 -WhatIf  # 预览操作，不实际执行
```

**macOS / Linux：**
```bash
cd agent-collab
bash install-global.sh              # 执行安装
bash install-global.sh /custom/dir  # 指定全局目录
```

> **说明：** 全局安装后，JS 插件的审批门控和 Git 保护在所有项目中生效。
> 每个项目的协作状态和自定义配置仍按项目独立（在项目的 `.opencode/agent-collab.config.json` 中配置）。

### 方式三：在当前仓库内直接使用

此仓库本身就是 OpenCode 可识别结构，直接在该目录下启动 OpenCode 即可。

## 使用

安装后重启 OpenCode，在会话中输入中文触发词：

| 触发词 | 效果 |
|---|---|
| "启动协作"、"帮我拆任务" | 触发协作总入口技能 |
| "检查提交"、"合并前检查" | 触发 Git 总入口技能 |
| "复盘一下"、"总结一下" | 触发复盘技能 |
| "审批一下"、"看看能不能合" | 触发协作总入口的审批判断 |

## 目录

- `agent-collab.config.json` — 插件独立配置文件
- `.opencode/agents/` — 6 个中文角色提示词（coordinator / planner / executor / reviewer / arbiter / reflector）
- `.opencode/skills/` — 3 个技能入口（collaboration / git-gate / retrospective）
- `plugin/` — OpenCode 原生 JS 插件（审批门控 + Git 保护自动拦截）
- `scripts/` — 状态与模式控制辅助脚本（需 Bash）
- `docs/` — 工程规范与使用文档

## 配置文件

安装后编辑项目目录下的 `.opencode/agent-collab.config.json`，可配置：

### 智能体模型

```json
{
  "agents": {
    "coordinator": { "model": "deepseek-v4-pro" },
    "executor": { "model": "gpt-5.4-mini" }
  }
}
```

填好 `model` 值后，该信息会注入到系统提示词中供 OpenCode 参考。

### 工作流与 Git 规则

```json
{
  "workflow": {
    "default_mode": "A",
    "default_approval_policy": "hybrid"
  },
  "git": {
    "main_branch_protection": true,
    "require_clean_checkout": true,
    "block_on_pending_approvals": true,
    "require_review_before_merge": true
  }
}
```

## 工作流程

1. 选择模式 A/B/C
2. 协调者/规划者拆解任务
3. 执行者实现变更
4. 审查者/仲裁者审批
5. 通过后再进入下一步或收口
6. 反思者沉淀经验

## 约束

- 智能体提示词全部使用中文
- 默认先方案后执行
- 设计上遵循高内聚、低耦合
- 代码注释应保持必要且清晰
