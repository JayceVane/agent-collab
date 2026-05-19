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
const MODE_LABEL = { A: '先方案后执行', B: '快速执行后审查', C: '全阶段审批' };

function getBashCmd(input) {
  return input?.command || input?.code || '';
}

function isGitCmd(cmd) {
  return /^git\s+/.test(cmd.trim());
}

function isHighRiskGit(cmd) {
  return /^git\s+(push|merge|rebase|reset|cherry-pick|checkout|switch|pull|commit)/.test(cmd.trim());
}

// ── 插件入口 ─────────────────────────────────────────────────────
export default async ({ directory, $ }) => {
  return {
    // ── 执行前门控 ──────────────────────────────────────────────
    'tool.execute.before': async (input, output) => {
      const state = ensureState(directory);
      if (!state.enabled) return;

      const toolName = input.tool_name;
      if (!['Write', 'Edit', 'Bash'].includes(toolName)) return;

      const { mode, phase, approval_policy, pending_approvals } = state;
      const pending = pending_approvals.length;

      // ── Write/Edit 审批门控 ──
      if (toolName === 'Write' || toolName === 'Edit') {
        if (mode === 'A' && phase === 'planning' && approval_policy !== 'auto' && pending > 0) {
          output.permissionDecision = 'ask';
          output.reason = `[${PLUGIN_NAME}] 模式 A（先方案后代码）：规划阶段存在 ${pending} 项待审批，请先处理。`;
          return;
        }
        if (mode === 'C') {
          const blocked = approval_policy === 'manual' || (approval_policy === 'hybrid' && pending > 0);
          if (blocked) {
            output.permissionDecision = 'ask';
            output.reason = `[${PLUGIN_NAME}] 模式 C（全流程审批）：存在 ${pending} 项待审批，请先 approve 或 reject。`;
            return;
          }
        }
        return;
      }

      // ── Bash Git 门控 ──
      if (toolName === 'Bash') {
        const cmd = getBashCmd(input.tool_input);
        if (!isGitCmd(cmd)) return;

        let isRepo = false;
        try {
          const r = await $`git rev-parse --is-inside-work-tree`.quiet();
          isRepo = r.exitCode === 0;
        } catch { /* 非 Git 目录 */ }

        if (!isRepo) {
          output.permissionDecision = 'ask';
          output.reason = `[${PLUGIN_NAME}] 检测到 Git 命令，但不是 Git 仓库。`;
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
            output.permissionDecision = 'ask';
            output.reason = `[${PLUGIN_NAME}] Git 保护：当前位于 ${branch}，禁止直接执行高风险操作。请切换到任务分支。`;
            return;
          }
        }

        if (state.git_require_clean_checkout && dirty > 0) {
          if (/^git\s+(checkout|switch|merge|rebase|pull)/.test(cmd)) {
            output.permissionDecision = 'ask';
            output.reason = `[${PLUGIN_NAME}] Git 检查：脏工作区（${dirty} 个文件），请先提交或暂存。`;
            return;
          }
        }

        if (state.git_block_on_pending_approvals && pending > 0 && isHighRiskGit(cmd)) {
          output.permissionDecision = 'ask';
          output.reason = `[${PLUGIN_NAME}] Git 检查：存在 ${pending} 项待审批，已阻断高风险 Git 动作。`;
          return;
        }

        if (state.git_require_review_before_merge && mode !== 'B') {
          if (/^git\s+(merge|push)/.test(cmd) && phase !== 'reviewing' && phase !== 'completed') {
            output.permissionDecision = 'ask';
            output.reason = `[${PLUGIN_NAME}] Git 检查：当前阶段 ${phase}，不允许合并/推送。请先完成审查。`;
            return;
          }
        }
      }
    },

    // ── 执行后记录 ───────────────────────────────────────────────
    'tool.execute.after': async (input) => {
      const state = readState(directory);
      if (!state?.enabled) return;

      const toolName = input.tool_name;
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
    'experimental.chat.system.transform': async (system) => {
      const state = readState(directory);
      if (!state?.enabled) return system;

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

      return system + lines.join('\n');
    },
  };
};
