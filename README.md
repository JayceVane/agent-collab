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

**Windows（PowerShell）：**
```powershell
Copy-Item -Recurse agent-collab\.opencode\agents\* $env:USERPROFILE\.config\opencode\agents\
Copy-Item -Recurse agent-collab\.opencode\skills\* $env:USERPROFILE\.config\opencode\skills\
```

**macOS / Linux：**
```bash
cp -r agent-collab/.opencode/agents/* ~/.config/opencode/agents/
cp -r agent-collab/.opencode/skills/* ~/.config/opencode/skills/
```

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

- `.opencode/agents/` — 6 个中文角色提示词（coordinator / planner / executor / reviewer / arbiter / reflector）
- `.opencode/skills/` — 3 个技能入口（collaboration / git-gate / retrospective）
- `scripts/` — 状态与模式控制辅助脚本（需 Bash，Windows 下用 Git Bash 或 WSL）
- `docs/` — 工程规范与使用文档

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
