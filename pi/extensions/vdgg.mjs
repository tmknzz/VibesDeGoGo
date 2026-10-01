import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync, realpathSync, writeFileSync, unlinkSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const edition = resolve(dirname(fileURLToPath(import.meta.url)), '../../.agents/skills/vibesdegogo');
const stepsFile = resolve(dirname(fileURLToPath(import.meta.url)), '../skills/vibesdegogo-pi/references/steps.json');
const quote = value => "'" + value.replaceAll("'", "'\\''") + "'";
const contract = 'VDGG for pi: use one tool per response. State and hook evidence decide progress. '
  + 'Source "$VDGG_CODEX_SKILL_DIR/scripts/vdgg-state.sh" in bash. '
  + 'Agree Goal/Constraints/Acceptance before vdgg_state_init. '
  + 'Implementation changes only via vdgg_patch_apply; never forge sidecars or test/review evidence. '
  + 'Council is qwenmagi. External failures never silently fall back to primary. '
  + 'Separate verified facts from assumptions. [Intentional Stop] needs a concrete reason.';

function rootFor(cwd) {
  const result = spawnSync('git', ['-C', cwd, 'rev-parse', '--show-toplevel'], { encoding: 'utf8' });
  return realpathSync(result.status === 0 ? result.stdout.trim() : cwd);
}

function stateFor(root) {
  const active = join(root, '.codex/.vdgg-active');
  if (!existsSync(active)) return null;
  const id = readFileSync(active, 'utf8').trim();
  if (!/^[a-zA-Z0-9-]+$/.test(id)) throw new Error('Invalid VDGG active id');
  const raw = readFileSync(join(root, `.codex/.vdgg-state-${id}`), 'utf8');
  const fields = Object.fromEntries(raw.trim().split('\n').map(line => {
    const i = line.indexOf('=');
    return [line.slice(0, i), line.slice(i + 1)];
  }));
  return { ...fields, raw, id, readLog: join(root, `.codex/.vdgg-read-${id}`) };
}

// Match pi's actual target, including symlinked parents and new files.
function canonicalPath(path, cwd) {
  const absolute = resolve(cwd, path);
  if (existsSync(absolute)) return realpathSync(absolute);
  const parent = dirname(absolute);
  return parent === absolute ? absolute : join(canonicalPath(parent, cwd), absolute.slice(parent.length + 1));
}

export default function vdgg(pi) {
  const skill = process.env.VDGG_CODEX_SKILL_DIR || edition;
  const pending = new Map();
  let stopState = '', continuations = 0, successfulTools = 0, fault = '';
  const env = { ...process.env, VDGG_CODEX_SKILL_DIR: skill };
  // Do not inherit another host's root/state overrides into this checkout.
  for (const key of ['VDGG_CWD', 'VDGG_STATE_DIR', 'VDGG_TASKS_DIR']) {
    delete env[key];
    delete process.env[key];
  }
  process.env.VDGG_CODEX_SKILL_DIR = skill;

  function hook(name, input, root) {
    const result = spawnSync('bash', [join(skill, 'scripts', `vdgg-hook-${name}.sh`)], {
      cwd: root, env, input: JSON.stringify(input), encoding: 'utf8', timeout: 10000, maxBuffer: 1024 * 1024,
    });
    if (result.error || result.status !== 0) throw new Error(result.stderr?.trim() || `VDGG ${name} hook failed; no gate was passed`);
    return result.stdout;
  }

  function eventFor(event, cwd) {
    const names = { bash: 'Bash', read: 'Read', edit: 'Edit', write: 'Write' };
    if (!names[event.toolName]) throw new Error(`VDGG does not guard tool ${event.toolName}; use read/bash/edit/write`);
    const tool_input = { ...event.input };
    if (event.toolName !== 'bash') {
      if (typeof tool_input.path !== 'string') throw new Error('VDGG requires a tool path');
      tool_input.file_path = canonicalPath(tool_input.path, cwd);
      event.input.path = tool_input.file_path;
    }
    return { cwd, tool_name: names[event.toolName], tool_input };
  }

  pi.on('session_start', () => { pending.clear(); stopState = ''; continuations = 0; successfulTools = 0; fault = ''; });
  pi.on('before_agent_start', event => ({ systemPrompt: event.systemPrompt + '\n\n' + contract }));
  pi.on('context', (event, ctx) => {
    const root = rootFor(ctx.cwd), state = stateFor(root);
    const steps = existsSync(stepsFile) ? JSON.parse(readFileSync(stepsFile, 'utf8')) : {};
    const text = `${contract}\nRoot: ${root}\n${state?.raw || 'Step 0: no active state.'}\n`
      + (steps[state?.phase || 'none'] || 'Read the pi skill for the current phase.');
    return { messages: [...event.messages.filter(m => m.customType !== 'vdgg-state'), {
      role: 'custom', customType: 'vdgg-state', content: text, display: false, timestamp: Date.now(),
    }] };
  });

  pi.on('tool_call', (event, ctx) => {
    try {
      if (fault) throw new Error(fault + '; repair the hook and reload pi');
      const root = rootFor(ctx.cwd);
      if (realpathSync(ctx.cwd) !== root) throw new Error(`Start VDGG pi from repository root: ${root}`);
      if (pending.size) throw new Error('VDGG runs one tool at a time; wait for the previous result');
      if (event.toolName !== 'bash' && existsSync(join(root, '.codex/.vdgg-error-pending'))) {
        throw new Error('Acknowledge the failed Bash command with [Error Acknowledged] in bash before using another tool');
      }
      const input = eventFor(event, root), state = stateFor(root);
      const readLog = state?.phase === 'investigating' ? state.readLog : null;
      const before = readLog && existsSync(readLog) ? readFileSync(readLog) : null;
      hook('pretool', input, root);
      pending.set(event.toolCallId, { input, root, readLog, before });
    } catch (error) { return { block: true, reason: error.message }; }
  });

  pi.on('tool_result', (event, ctx) => {
    const call = pending.get(event.toolCallId);
    if (!call) return; // Blocked siblings must not release another call.
    pending.delete(event.toolCallId);
    try {
      // Shared Bash hooks log before execution; failed calls prove no read.
      if (event.isError && call.readLog) {
        if (call.before === null) { if (existsSync(call.readLog)) unlinkSync(call.readLog); }
        else writeFileSync(call.readLog, call.before);
      }
      if (event.toolName === 'read' && !event.isError) hook('pretool', {
        cwd: call.root, tool_name: 'Bash', tool_input: { command: 'cat -- ' + quote(call.input.tool_input.file_path) },
      }, call.root);
      const output = event.content.filter(c => c.type === 'text').map(c => c.text).join('\n');
      // pi's Bash tool appends its real exit status to errors; unknown failures
      // must not masquerade as grep/rg's normal no-match status (1).
      const status = event.details?.exitCode ?? output.match(/(?:^|\n)Command exited with code ([0-9]+)\s*$/)?.[1];
      const exitCode = event.isError ? (Number(status) > 0 ? Number(status) : 2) : 0;
      hook('posttool', { ...call.input, tool_response: {
        exit_code: exitCode,
        output,
      } }, call.root);
      if (!event.isError) successfulTools++;
    } catch (error) {
      fault = error.message;
      ctx.ui.notify(error.message, 'error');
      return { isError: true, content: [...event.content, { type: 'text', text: error.message }] };
    }
  });

  pi.on('agent_end', (event, ctx) => {
    if (ctx.signal?.aborted) return;
    try {
      const root = rootFor(ctx.cwd), state = stateFor(root);
      if (!state) return;
      const last = [...event.messages].reverse().find(m => m.role === 'assistant');
      if (last?.stopReason === 'aborted') return;
      const text = last?.content?.filter(c => c.type === 'text').map(c => c.text).join('\n') || '';
      const verdict = JSON.parse(hook('stop', { cwd: root, last_assistant_message: text }, root) || '{}');
      if (verdict.decision !== 'block') return;
      const progress = state.raw + successfulTools;
      if (progress !== stopState) { stopState = progress; continuations = 0; }
      if (++continuations > 3) {
        pi.sendMessage({ customType: 'vdgg-stop', display: true,
          content: '[Intentional Stop] VDGG state and successful tools did not advance after 3 continuations. State is preserved; inspect the blocked gate before resuming.' }, { deliverAs: 'nextTurn' });
        ctx.ui.notify('[Intentional Stop] VDGG made no progress after 3 continuations; state is preserved.', 'warning');
        return;
      }
      pi.sendMessage({ customType: 'vdgg-continue', display: true,
        content: verdict.reason + '\nContinue the current Step. Resolve failed gates; do not claim completion or repeat failed commands without [Error Acknowledged].',
      }, { triggerTurn: true, deliverAs: 'followUp' });
    } catch (error) { ctx.ui.notify('[Intentional Stop] ' + error.message + '; state is preserved.', 'error'); }
  });
}
