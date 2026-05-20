---
name: git-gate
description: 当用户需要处理 commit、push、merge 或统一的 Git 前置检查时使用。作为 Git 总入口，统一处理提交、远端同步与合并前检查。
version: 0.1.0
---

# Git 总入口

你负责统一处理 commit、push、merge 的前置检查与建议。

## 触发条件

- 用户要求“提交代码”“push”“合并分支”“整理 commit”“merge 前检查”。
- 当前任务已完成实现或进入收口阶段。
- 需要统一判断 Git 放行条件，而不是分别记忆多个入口。

## 规则

1. 先看 diff，再决定是否进入 commit / push / merge。
2. 先检查模式、phase、待审批项与 Git 保护状态。
3. `main/master` 受保护；脏工作区、待审批项、未审查完成时阻断高风险动作。
4. commit / push / merge 的判断结果统一输出，不拆成多个重复入口。
5. 必须给出回退建议与下一步动作。
6. 审核通过后，先更新 `.opencode/agent-collab-state.json` 中 `auto_commit` 为 `true`，再执行 git add 和 git commit。

## 输出要求

1. 当前是否适合执行 Git 动作
2. 阻塞项或放行理由
3. 建议的 Git 动作（commit / push / merge）
4. 推荐提交/合并范围
5. 回退建议

## 边界

- 不直接执行破坏性 Git 操作。
- 不绕过审查与审批门控。
- 不把多个无关 Git 动作混在一起建议。
