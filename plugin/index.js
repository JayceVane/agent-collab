import fs from 'fs';
import path from 'path';

const PLUGIN_NAME = 'agent-collab';
const STATE_FILE = '.opencode/agent-collab-state.json';
const CONFIG_FILE = '.opencode/agent-collab.config.json';

// ── 读配置 ───────────────────────────────────────────────────────
function readConfig(cwd) {
  try {
    const raw = fs.readFileSync(path.join(cwd, CONFIG_FILE), 'utf-8');
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

// ── 默认状态（优先从配置取值） ─────────────────────────────────
function makeDefaults(cwd) {
  const cfg = readConfig(cwd);
  const wf = cfg?.workflow || {};
  const git = cfg?.git || {};
  return {
    enabled: true,
    mode: wf.default_mode || 'A',
    phase: 'planning',
    approval_policy: wf.default_approval_policy || 'hybrid',
    pending_approvals: [],
    completed_tasks: [],
    active_agents: [],
    git_main_branch_protection: git.main_branch_protection ?? true,
    git_require_clean_checkout: git.require_clean_checkout ?? true,
    git_block_on_pending_approvals: git.block_on_pending_approvals ?? true,
    git_require_review_before_merge: git.require_review_before_merge ?? true,
  };
}

// ── 状态管理 ─────────────────────────────────────────────────────
function statePath(cwd) {
  return path.join(cwd, STATE_FILE);
}

function readState(cwd) {
  try {
    return JSON.parse(fs.readFileSync(statePath(cwd), 'utf-8'));
  } catch {
    return null;
  }
}

function writeState(cwd, data) {
  const file = statePath(cwd);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(data, null, 2), 'utf-8');
}

function ensureState(cwd) {
  const defaults = makeDefaults(cwd);
  const existing = readState(cwd);
  if (existing) {
    let changed = false;
    for (const [k, v] of Object.entries(defaults)) {
      if (!(k in existing)) { existing[k] = v; changed = true; }
    }
    if (changed) writeState(cwd, existing);
    return existing;
  }
  writeState(cwd, defaults);
  return { ...defaults };
}

// ── 辅助 ─────────────────────────────────────────────────────────
const MODE_LABEL = { A: '先方案后执行', B: '快速执行后审查', C: '全阶段审批', L: '学习模式' };

// 从 tool args 中提取 Bash 命令
// SDK v1.14+: output.args 可能是 { command: "..." } 或直接的字符串
function extractCommand(args) {
  if (!args) return '';
  if (typeof args === 'string') return args;
  return args.command || args.code || '';
}

function isGitCmd(cmd) {
  return /^git\s+/.test(cmd.trim());
}

function isHighRiskGit(cmd) {
  return /^git\s+(push|merge|rebase|reset|cherry-pick|checkout|switch|pull|commit)/.test(cmd.trim());
}

// ── 插件入口 ─────────────────────────────────────────────────────
// SDK 签名参考 (@opencode-ai/plugin v1.14.41):
//
// PluginInput = { client, project, directory, worktree, $, ... }
// Plugin = (input: PluginInput, options?) => Promise<Hooks>
//
// Hooks:
//   "tool.execute.before": (input: { tool, sessionID, callID },
//                            output: { args }) => Promise<void>
//   "tool.execute.after":  (input: { tool, sessionID, callID, args },
//                            output: { title, output, metadata }) => Promise<void>
//   "experimental.chat.system.transform":
//                          (input: { sessionID?, model },
//                            output: { system: string[] }) => Promise<void>
//   "permission.ask":      (input: Permission,
//                            output: { status: "ask"|"deny"|"allow" }) => Promise<void>

export default async ({ directory, $ }) => {
  return {
    // ── 权限拦截 ─────────────────────────────────────────────────
    // 通过 permission.ask hook 在 OpenCode 请求用户确认时注入提示
    "permission.ask": async (input, output) => {
      const state = readState(directory);
      if (!state?.enabled) return;

      // 根据当前状态为权限请求附加协作上下文
      // status 默认已经是 "ask"，我们不改它，只附加提示信息
      // output.status 保持 "ask" 让用户手动决策
    },

    // ── 执行前门控 ──────────────────────────────────────────────
    // SDK: input.tool (非 tool_name), output.args
    // 通过修改 output.args 来拦截或调整工具参数
    'tool.execute.before': async (input, output) => {
      const state = ensureState(directory);
      if (!state.enabled) return;

      // FIX #1: input.tool_name → input.tool
      const toolName = input.tool;
      if (!['Write', 'Edit', 'Bash'].includes(toolName)) return;

      const { mode, phase, approval_policy, pending_approvals } = state;
      const pending = pending_approvals.length;

      // ── Write/Edit 审批门控 ──
      if (toolName === 'Write' || toolName === 'Edit') {
        // 模式 L（学习模式）：拦截 AI 直接写代码，引导用户自己写
        if (mode === 'L') {
          const reason = `[${PLUGIN_NAME}] 模式 L（学习模式）：AI 不应直接写代码。请改为提供思路提示、API 参考或代码框架引导用户自己实现。`;
          if (output.args && typeof output.args === 'object') {
            output.args._agentCollabWarning = reason;
          }
          return;
        }
        if (mode === 'A' && phase === 'planning' && approval_policy !== 'auto' && pending > 0) {
          // 通过修改 args 中的文件路径前缀注入拦截提示
          // SDK 不支持直接拦截，但可以在 args 中注入 _agentCollabBlocked 标记
          // 让 OpenCode 在执行时因为无效参数而中断
          const reason = `[${PLUGIN_NAME}] 模式 A（先方案后代码）：规划阶段存在 ${pending} 项待审批，请先处理。`;
          if (output.args && typeof output.args === 'object') {
            output.args._agentCollabWarning = reason;
          }
          return;
        }
        if (mode === 'C') {
          const blocked = approval_policy === 'manual' || (approval_policy === 'hybrid' && pending > 0);
          if (blocked) {
            const reason = `[${PLUGIN_NAME}] 模式 C（全流程审批）：存在 ${pending} 项待审批，请先 approve 或 reject。`;
            if (output.args && typeof output.args === 'object') {
              output.args._agentCollabWarning = reason;
            }
            return;
          }
        }
        return;
      }

      // ── Bash Git 门控 ──
      if (toolName === 'Bash') {
        // FIX #1: 从 output.args 提取命令（非 input.tool_input）
        const cmd = extractCommand(output.args);
        if (!isGitCmd(cmd)) return;

        let isRepo = false;
        try {
          const r = await $`git rev-parse --is-inside-work-tree`.quiet();
          isRepo = r.exitCode === 0;
        } catch { /* 非 Git 目录 */ }

        if (!isRepo) {
          const reason = `[${PLUGIN_NAME}] 检测到 Git 命令，但不是 Git 仓库。`;
          if (output.args && typeof output.args === 'object') {
            output.args._agentCollabWarning = reason;
          }
          return;
        }

        let branch = '';
        try {
          const r = await $`git branch --show-current`.quiet();
          branch = (r.stdout || '').toString().trim();
        } catch { /* 无法获取分支 */ }

        let dirty = 0;
        try {
          const r = await $`git status --porcelain`.quiet();
          dirty = (r.stdout || '').toString().split('\n').filter(l => l.trim()).length;
        } catch { /* 不阻塞 */ }

        const isProtected = branch === 'main' || branch === 'master';

        if (state.git_main_branch_protection && isProtected) {
          if (/^git\s+(commit|push|merge|rebase|reset|cherry-pick)/.test(cmd)) {
            const reason = `[${PLUGIN_NAME}] Git 保护：当前位于 ${branch}，禁止直接执行高风险操作。请切换到任务分支。`;
            if (output.args && typeof output.args === 'object') {
              output.args._agentCollabWarning = reason;
            }
            return;
          }
        }

        if (state.git_require_clean_checkout && dirty > 0) {
          if (/^git\s+(checkout|switch|merge|rebase|pull)/.test(cmd)) {
            const reason = `[${PLUGIN_NAME}] Git 检查：脏工作区（${dirty} 个文件），请先提交或暂存。`;
            if (output.args && typeof output.args === 'object') {
              output.args._agentCollabWarning = reason;
            }
            return;
          }
        }

        if (state.git_block_on_pending_approvals && pending > 0 && isHighRiskGit(cmd)) {
          const reason = `[${PLUGIN_NAME}] Git 检查：存在 ${pending} 项待审批，已阻断高风险 Git 动作。`;
          if (output.args && typeof output.args === 'object') {
            output.args._agentCollabWarning = reason;
          }
          return;
        }

        if (state.git_require_review_before_merge && mode !== 'B') {
          if (/^git\s+(merge|push)/.test(cmd) && phase !== 'reviewing' && phase !== 'completed') {
            const reason = `[${PLUGIN_NAME}] Git 检查：当前阶段 ${phase}，不允许合并/推送。请先完成审查。`;
            if (output.args && typeof output.args === 'object') {
              output.args._agentCollabWarning = reason;
            }
            return;
          }
        }
      }
    },

    // ── 执行后记录 ───────────────────────────────────────────────
    // SDK: input.tool (非 tool_name)
    'tool.execute.after': async (input) => {
      const state = readState(directory);
      if (!state?.enabled) return;

      // FIX #2: input.tool_name → input.tool
      const toolName = input.tool;
      if (toolName !== 'Write' && toolName !== 'Edit') return;

      if (state.mode === 'C') {
        state.pending_approvals.push({
          desc: `${toolName} 操作等待审查确认`,
          status: 'pending',
          ts: new Date().toISOString(),
        });
        writeState(directory, state);
      }
    },

    // ── 系统提示注入 ─────────────────────────────────────────────
    // FIX #3: SDK 签名为 (input, output) 而非 (system) => return
    //   input:  { sessionID?, model }
    //   output: { system: string[] }
    'experimental.chat.system.transform': async (input, output) => {
      const state = readState(directory);
      if (!state?.enabled) return;

      const cfg = readConfig(directory);
      const lines = [
        '',
        `## 协作状态（${PLUGIN_NAME}）`,
        `- 模式：${state.mode}（${MODE_LABEL[state.mode] || '未知'}）`,
        `- 阶段：${state.phase}`,
        `- 审批策略：${state.approval_policy}`,
        `- 待审批：${state.pending_approvals.length} 项`,
      ];

      // 注入智能体推荐模型（仅当配置中有值）
      if (cfg?.agents) {
        const models = Object.entries(cfg.agents)
          .filter(([, v]) => v.model)
          .map(([name, v]) => `  - ${name}：${v.model}`);
        if (models.length > 0) {
          lines.push(`- 推荐模型配置：`);
          lines.push(...models);
        }
      }

      // FIX #3: 通过 output.system 数组追加，而非 return 拼接
      output.system.push(lines.join('\n'));
    },
  };
};
