import fs from 'fs';
import path from 'path';
import os from 'os';

const PLUGIN_NAME = 'agent-collab';
const STATE_FILE = '.opencode/agent-collab-state.json';
const CONFIG_FILE = '.opencode/agent-collab.config.json';
const GLOBAL_DIR = path.join(os.homedir(), '.config', 'opencode');
const GLOBAL_CONFIG_FILE = 'agent-collab.config.json';

// ── 读配置（项目级优先，全局级回退） ────────────────────────
function readConfig(cwd) {
  // 1. 项目级配置（优先）
  try {
    const raw = fs.readFileSync(path.join(cwd, CONFIG_FILE), 'utf-8');
    return JSON.parse(raw);
  } catch { /* 项目级不存在，继续尝试全局 */ }

  // 2. 全局配置（回退）
  try {
    const raw = fs.readFileSync(path.join(GLOBAL_DIR, GLOBAL_CONFIG_FILE), 'utf-8');
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
    changed_files: [],
    auto_commit: false,
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

// ── 读取 agents/*.md 的 prompt 正文（项目级优先 → 全局级回退）──────────
function parseAgentMd(filePath) {
  try {
    const raw = fs.readFileSync(filePath, 'utf-8');
    const match = raw.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n([\s\S]*)$/);
    if (!match) {
      // 无 frontmatter，整个文件就是 prompt
      return { frontmatter: {}, body: raw.trim() };
    }
    const body = match[2].trim();

    // 简易 YAML 解析（仅支持 key: value 单层）
    const frontmatter = {};
    const fmText = match[1];
    for (const line of fmText.split('\n')) {
      const kv = line.match(/^(\w[\w-]*):\s*(.+)$/);
      if (kv) {
        let val = kv[2].trim();
        if ((val.startsWith('"') && val.endsWith('"')) ||
            (val.startsWith("'") && val.endsWith("'"))) {
          val = val.slice(1, -1);
        }
        frontmatter[kv[1]] = val;
      }
    }

    return { frontmatter, body };
  } catch {
    return null;
  }
}

function resolveAgentPrompt(cwd, agentName) {
  // 1. 项目级
  const projectMd = path.join(cwd, '.opencode', 'agents', `${agentName}.md`);
  const projectParsed = parseAgentMd(projectMd);
  if (projectParsed?.body) return projectParsed;

  // 2. 全局级
  const globalMd = path.join(GLOBAL_DIR, 'agents', `${agentName}.md`);
  const globalParsed = parseAgentMd(globalMd);
  if (globalParsed?.body) return globalParsed;

  return null;
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
//   "config":              (config) => void
//                          读取 agent-collab.config.json + agents/*.md → 注入 config.agent

export default async ({ directory, $ }) => {
  return {
    // ── config 钩子：动态注册 agent 角色 ─────────────────────────────
    // 读取 agent-collab.config.json + agents/*.md → 注入 config.agent
    config: async (config) => {
      try {
        const cfg = readConfig(directory);
        if (!cfg?.agents) return;

        if (!config.agent) config.agent = {};

        for (const [name, agentDef] of Object.entries(cfg.agents)) {
          // 读取 prompt（项目级优先，全局级回退）
          const promptInfo = resolveAgentPrompt(directory, name);

          // 注入到 OpenCode 配置
          config.agent[name] = {
            ...(agentDef.description ? { description: agentDef.description } : {}),
            ...(agentDef.mode ? { mode: agentDef.mode } : {}),
            ...(agentDef.model ? { model: agentDef.model } : {}),
            ...(agentDef.color ? { color: agentDef.color } : {}),
            ...(agentDef.hidden ? { hidden: agentDef.hidden } : {}),
            ...(agentDef.permission ? { permission: agentDef.permission } : {}),
            ...(promptInfo?.body ? { prompt: promptInfo.body } : {}),
          };
        }
      } catch (err) {
        // config 钩子失败不应阻塞插件加载
        console.warn(`[${PLUGIN_NAME}] config hook error:`, err.message);
      }
    },

    // ── 执行前门控 ──────────────────────────────────────────────
    // SDK: input.tool (非 tool_name), output.args
    // 通过 throw new Error() 来阻断工具执行（OpenCode 官方支持的拦截方式）
    'tool.execute.before': async (input, output) => {
      const state = ensureState(directory);
      if (!state.enabled) return;

      // FIX #1: input.tool_name → input.tool
      const toolName = input.tool;
      if (!['write', 'edit', 'bash'].includes(toolName)) return;

      const { mode, phase, approval_policy, pending_approvals } = state;
      const pending = pending_approvals.length;

      // ── write/edit 审批门控 ──
      if (toolName === 'write' || toolName === 'edit') {
        // 模式 L（学习模式）：拦截 AI 直接写代码，引导用户自己写
        if (mode === 'L') {
          throw new Error(`[${PLUGIN_NAME}] 模式 L（学习模式）：AI 不应直接写代码。请改为提供思路提示、API 参考或代码框架引导用户自己实现。`);
        }
        if (mode === 'A' && phase === 'planning' && approval_policy !== 'auto' && pending > 0) {
          throw new Error(`[${PLUGIN_NAME}] 模式 A（先方案后代码）：规划阶段存在 ${pending} 项待审批，请先处理。`);
        }
        if (mode === 'C') {
          const blocked = approval_policy === 'manual' || (approval_policy === 'hybrid' && pending > 0);
          if (blocked) {
            throw new Error(`[${PLUGIN_NAME}] 模式 C（全流程审批）：存在 ${pending} 项待审批，请先 approve 或 reject。`);
          }
        }
        return;
      }

      // ── bash Git 门控 ──
      if (toolName === 'bash') {
        // FIX #1: 从 output.args 提取命令（非 input.tool_input）
        const cmd = extractCommand(output.args);
        if (!isGitCmd(cmd)) return;

        let isRepo = false;
        try {
          const r = await $`git rev-parse --is-inside-work-tree`.quiet();
          isRepo = r.exitCode === 0;
        } catch { /* 非 Git 目录 */ }

        if (!isRepo) {
          throw new Error(`[${PLUGIN_NAME}] 检测到 Git 命令，但不是 Git 仓库。`);
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
            throw new Error(`[${PLUGIN_NAME}] Git 保护：当前位于 ${branch}，禁止直接执行高风险操作。请切换到任务分支。`);
          }
        }

        if (state.git_require_clean_checkout && dirty > 0) {
          if (/^git\s+(checkout|switch|merge|rebase|pull)/.test(cmd)) {
            throw new Error(`[${PLUGIN_NAME}] Git 检查：脏工作区（${dirty} 个文件），请先提交或暂存。`);
          }
        }

        if (state.git_block_on_pending_approvals && pending > 0 && isHighRiskGit(cmd)) {
          throw new Error(`[${PLUGIN_NAME}] Git 检查：存在 ${pending} 项待审批，已阻断高风险 Git 动作。`);
        }

        if (state.git_require_review_before_merge && mode !== 'B') {
          if (/^git\s+(merge|push)/.test(cmd) && phase !== 'reviewing' && phase !== 'completed') {
            throw new Error(`[${PLUGIN_NAME}] Git 检查：当前阶段 ${phase}，不允许合并/推送。请先完成审查。`);
          }
        }

        // auto_commit 模式下放行 git add/commit
        if (state.auto_commit && /^git\s+(add|commit)\b/.test(cmd.trim())) {
          return; // 放行
        }
      }
    },

    // ── 执行后记录 ───────────────────────────────────────────────
    // SDK: input.tool (非 tool_name)
    'tool.execute.after': async (input) => {
      const state = readState(directory);
      if (!state?.enabled) return;

      const toolName = input.tool;

      // 变更文件追踪
      if (toolName === 'write' || toolName === 'edit') {
        const filePath = input.args?.file_path || input.args?.filePath || input.args?.path;
        if (filePath) {
          if (!state.changed_files) state.changed_files = [];
          // 去重
          if (!state.changed_files.includes(filePath)) {
            state.changed_files.push(filePath);
          }
          writeState(directory, state);
        }

        // 模式 C 的审批追踪（保留原有逻辑）
        if (state.mode === 'C') {
          state.pending_approvals.push({
            desc: `${toolName} 操作等待审查确认`,
            status: 'pending',
            ts: new Date().toISOString(),
          });
          writeState(directory, state);
        }
      }

      // Git commit 后清除变更记录
      if (toolName === 'bash') {
        const cmd = extractCommand(input.args);
        if (/^git\s+commit/.test(cmd.trim()) && state.changed_files?.length > 0) {
          state.changed_files = [];
          state.auto_commit = false;
          writeState(directory, state);
        }
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

      // Git 自动提交规则
      if (state.changed_files?.length > 0) {
        lines.push('');
        lines.push('## Git 自动提交');
        if (state.auto_commit) {
          lines.push('**审核已通过，请立即执行以下操作：**');
          lines.push('1. `git add` 以下变更文件');
          lines.push('2. `git commit -m "<简洁描述本次变更的 message>"`');
          lines.push('');
          lines.push('变更文件清单：');
          state.changed_files.forEach(f => lines.push(`  - ${f}`));
        } else {
          lines.push('以下文件已变更，等待审核：');
          state.changed_files.forEach(f => lines.push(`  - ${f}`));
        }
      }

      // 通用 Git 提交规则（始终注入）
      lines.push('');
      lines.push('## Git 提交规则');
      lines.push('- 审核通过后（auto_commit = true），必须立即 git commit 变更文件');
      lines.push('- 每完成一个独立任务后，即使未显式审核，也应 commit');
      lines.push('- commit message 用中文，简洁描述变更内容');
      lines.push('- 不要在一个 commit 中混合多个不相关的变更');

      // FIX #3: 通过 output.system 数组追加，而非 return 拼接
      output.system.push(lines.join('\n'));
    },
  };
};
