# agent-collab

OpenCode 智能体协作插件骨架：中文提示词、模式 A/B/C、审批门控、复盘沉淀。

> v1.0.0：开箱即跑，支持协作总入口、Git 总入口、复盘入口。

## 快速开始

1. 将 `agent-collab/` 放入 OpenCode 可加载的插件目录。
2. 重启客户端或重新加载插件。
3. 在会话中输入“启动协作”或“检查 Git 能否提交”。
4. 首次使用时可运行：`bash hooks/scripts/session-start-init.sh`

## 目录

- `.claude-plugin/`：插件清单
- `skills/`：协作入口、Git 入口、复盘技能
- `skills/collaboration/`：协作总入口
- `skills/git-gate/`：Git 总入口
- `skills/retrospective/`：复盘入口
- `agents/`：协调者、规划者、执行者、审查者、反思者、仲裁者
- `hooks/`：事件钩子与审批检查脚本
- `scripts/`：状态与模式控制辅助脚本
- `docs/git-workflow.md`：Git 工作规范
- `docs/engineering-spec.md`：总工程规范
- `docs/workflow-v2.md`：精简工作流 v2
- `docs/install-usage.md`：安装与使用指南
- `docs/coordination-plan.md`：已保存的方案文档

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
- 变更前后都要保留审批意识
- 设计上遵循高内聚、低耦合
- 代码注释应保持必要且清晰
- 只在本插件目录内扩展，不侵入现有项目代码
