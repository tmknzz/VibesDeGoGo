import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, rmSync, symlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import vdgg from '../../pi/extensions/vdgg.mjs';

const skill = resolve('.agents/skills/vibesdegogo');
function fixture(t, phase = 'investigating', step = 3) {
  const root = mkdtempSync(join(tmpdir(), 'vdgg-pi-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  spawnSync('git', ['init', '-q', root]);
  mkdirSync(join(root, '.codex'));
  mkdirSync(join(root, 'tasks/vdgg/test-id'), { recursive: true });
  writeFileSync(join(root, '.codex/.vdgg-active'), 'test-id\n');
  writeFileSync(join(root, '.codex/.vdgg-state-test-id'), `step=${step}\nphase=${phase}\nloop_count=0\ncurrent_task=T1: fixture\ntask_allowlist_file=\ntask_base_ref=\nformation=\nvdgg_id=test-id\nlast_updated=2026-10-02T00:00:00Z\n`);
  writeFileSync(join(root, 'source.txt'), 'first\nsecond\n');
  const handlers = {}, sent = [], notices = [];
  const ctx = { cwd: root, ui: { notify: (...args) => notices.push(args) } };
  const previous = process.env.VDGG_CODEX_SKILL_DIR;
  process.env.VDGG_CODEX_SKILL_DIR = skill;
  vdgg({ on: (name, fn) => { handlers[name] = fn; }, sendMessage: (...args) => sent.push(args) });
  t.after(() => { if (previous === undefined) delete process.env.VDGG_CODEX_SKILL_DIR; else process.env.VDGG_CODEX_SKILL_DIR = previous; });
  const call = (name, input, id = 'call-1') => {
    const event = { toolName: name, input, toolCallId: id };
    return { event, result: handlers.tool_call(event, ctx) };
  };
  const result = (event, isError = false) => handlers.tool_result({ ...event, isError, content: [{ type: 'text', text: 'fixture output' }] }, ctx);
  return { root, handlers, sent, notices, ctx, call, result, log: join(root, '.codex/.vdgg-read-test-id') };
}

test('native read becomes evidence only after success', t => {
  const f = fixture(t), c = f.call('read', { path: 'source.txt' });
  assert.equal(c.result, undefined);
  assert.equal(existsSync(f.log), false);
  f.result(c.event);
  assert.equal(readFileSync(f.log, 'utf8'), 'source.txt\n');
});
test('failed native and Bash reads do not become evidence', t => {
  const f = fixture(t);
  f.result(f.call('read', { path: 'source.txt' }).event, true);
  assert.equal(existsSync(f.log), false);
  writeFileSync(f.log, 'prior.txt\n');
  const c = f.call('bash', { command: 'cat source.txt' });
  assert.match(readFileSync(f.log, 'utf8'), /source.txt/);
  f.result(c.event, true);
  assert.equal(readFileSync(f.log, 'utf8'), 'prior.txt\n');
});
test('blocked sibling does not release an in-flight call', t => {
  const f = fixture(t), a = f.call('read', { path: 'source.txt' }, 'a');
  const b = f.call('bash', { command: 'vdgg_state_advance 4 planning' }, 'b');
  assert.equal(b.result.block, true);
  f.result(b.event, true);
  assert.equal(f.call('read', { path: 'source.txt' }, 'c').result.block, true);
  f.result(a.event);
  assert.equal(f.call('read', { path: 'source.txt' }, 'd').result, undefined);
});
test('native edits preserve patch-first and canonical sidecar guards', t => {
  const f = fixture(t, 'implementing', 6);
  assert.match(f.call('write', { path: 'source.txt', content: 'bad' }).result.reason, /patch first/i);
  assert.match(f.call('edit', { path: 'tasks/../.codex/.vdgg-active' }).result.reason, /sidecar/i);
  symlinkSync(join(f.root, '.codex'), join(f.root, 'alias'));
  assert.match(f.call('write', { path: 'alias/.vdgg-active' }).result.reason, /sidecar/i);
  const note = f.call('write', { path: 'tasks/vdgg/test-id/note.md', content: 'note' });
  assert.equal(note.result, undefined);
  f.result(note.event);
});
test('entry gate, early commit, unknown tool and missing hook stay closed', t => {
  const f = fixture(t, 'implementing', 6);
  assert.match(f.call('bash', { command: 'git commit -m early' }).result.reason, /Commit is blocked/);
  assert.equal(f.call('custom_write', {}).result.block, true);
  rmSync(join(f.root, '.codex/.vdgg-active'));
  writeFileSync(join(f.root, '.vdgg-target'), 'VDGG_REQUIRED=on\n');
  assert.equal(f.call('write', { path: 'source.txt', content: 'bad' }).result.block, true);
  process.env.VDGG_CODEX_SKILL_DIR = join(f.root, 'missing-skill');
  let gate;
  vdgg({ on: (name, fn) => { if (name === 'tool_call') gate = fn; } });
  assert.equal(gate({ toolName: 'bash', input: { command: 'pwd' }, toolCallId: 'z' }, f.ctx).block, true);
});
test('Bash failure sets acknowledgement; success never sniffs output text', t => {
  const f = fixture(t, 'implementing', 6), c = f.call('bash', { command: 'false' });
  f.result(c.event, true);
  assert.match(f.call('bash', { command: 'pwd' }).result.reason, /Acknowledge/);
  const ack = f.call('bash', { command: '# [Error Acknowledged]\npwd' });
  assert.equal(ack.result, undefined);
  f.handlers.tool_result({ ...ack.event, isError: false, content: [{ type: 'text', text: 'ERROR is literal text' }] }, f.ctx);
  assert.equal(existsSync(join(f.root, '.codex/.vdgg-error-pending')), false);
});
test('unread and nonliteral transitions are refused', t => {
  const f = fixture(t);
  assert.equal(f.call('bash', { command: 'vdgg_state_advance 4 planning' }).result.block, true);
  assert.match(f.call('bash', { command: 'vdgg_state_advance "$step" planning' }).result.reason, /literal/);
});
test('context refreshes state without accumulating old instructions', t => {
  const f = fixture(t), first = f.handlers.context({ messages: [{ role: 'user', content: [] }] }, f.ctx);
  assert.match(first.messages.at(-1).content, /phase=investigating/);
  const state = join(f.root, '.codex/.vdgg-state-test-id');
  writeFileSync(state, readFileSync(state, 'utf8').replace('phase=investigating', 'phase=planning'));
  const next = f.handlers.context(first, f.ctx);
  assert.equal(next.messages.filter(m => m.customType === 'vdgg-state').length, 1);
  assert.match(next.messages.at(-1).content, /phase=planning/);
});
test('stop continues active work, bounds no-progress, preserves state', t => {
  const f = fixture(t), event = { messages: [{ role: 'assistant', content: [{ type: 'text', text: 'Done' }] }] };
  for (let i = 0; i < 4; i++) f.handlers.agent_end(event, f.ctx);
  assert.equal(f.sent.length, 4);
  assert.equal(f.sent[0][1].triggerTurn, true);
  assert.match(f.sent[3][0].content, /\[Intentional Stop\]/);
  assert.equal(f.sent[3][1].deliverAs, 'nextTurn');
  assert.equal(f.sent[3][1].triggerTurn, undefined);
  assert.equal(existsSync(join(f.root, '.codex/.vdgg-active')), true);
});
test('intentional stop and inactive workflows do not auto-continue', t => {
  const f = fixture(t);
  f.handlers.agent_end({ messages: [{ role: 'assistant', content: [{ type: 'text', text: '[Intentional Stop] waiting for login' }] }] }, f.ctx);
  assert.equal(f.sent.length, 0);
  rmSync(join(f.root, '.codex/.vdgg-active'));
  f.handlers.agent_end({ messages: [] }, f.ctx);
  assert.equal(f.sent.length, 0);
});


test('successful same-phase work resets no-progress count', t => {
  const f = fixture(t), end = { messages: [{ role: 'assistant', content: [{ type: 'text', text: 'More research' }] }] };
  for (let i = 0; i < 6; i++) {
    f.result(f.call('read', { path: 'source.txt' }, 'read-' + i).event);
    f.handlers.agent_end(end, f.ctx);
  }
  assert.equal(f.sent.length, 6);
  assert.ok(f.sent.every(message => message[1]?.triggerTurn));
});
test('posttool failure latches closed until reload', t => {
  const f = fixture(t, 'implementing', 6);
  const broken = join(f.root, 'broken-core'); mkdirSync(join(broken, 'scripts'), { recursive: true });
  writeFileSync(join(broken, 'scripts/vdgg-hook-pretool.sh'), '#!/bin/sh\nexit 0\n');
  process.env.VDGG_CODEX_SKILL_DIR = broken;
  const handlers = {};
  vdgg({ on: (name, fn) => { handlers[name] = fn; } });
  const event = { toolName: 'bash', input: { command: 'pwd' }, toolCallId: 'bad-post' };
  assert.equal(handlers.tool_call(event, f.ctx), undefined);
  assert.equal(handlers.tool_result({ ...event, isError: false, content: [] }, f.ctx).isError, true);
  assert.match(handlers.tool_call({ ...event, toolCallId: 'next' }, f.ctx).reason, /reload pi/);
});
test('real search errors and unknown failures require acknowledgement', t => {
  const f = fixture(t, 'implementing', 6);
  for (const output of ['Command exited with code 2', 'Timed out']) {
    const call = f.call('bash', { command: 'rg pattern source.txt' });
    f.handlers.tool_result({ ...call.event, isError: true, content: [{ type: 'text', text: output }] }, f.ctx);
    assert.match(f.call('bash', { command: 'pwd' }).result.reason, /Acknowledge/);
    f.result(f.call('bash', { command: '# [Error Acknowledged]\npwd' }).event);
  }
  const noMatch = f.call('bash', { command: 'rg missing source.txt' });
  f.handlers.tool_result({ ...noMatch.event, isError: true, content: [{ type: 'text', text: 'Command exited with code 1' }] }, f.ctx);
  assert.equal(existsSync(join(f.root, '.codex/.vdgg-error-pending')), false);
});


test('unacknowledged Bash failure blocks native tools before execution without a fault latch', t => {
  const f = fixture(t);
  f.result(f.call('bash', { command: 'false' }).event, true);
  assert.match(f.call('read', { path: 'source.txt' }).result.reason, /Acknowledge/);
  assert.equal(existsSync(f.log), false);
  f.result(f.call('bash', { command: '# [Error Acknowledged]\npwd' }).event);
  const read = f.call('read', { path: 'source.txt' });
  assert.equal(read.result, undefined);
  assert.equal(f.result(read.event), undefined);
  assert.equal(readFileSync(f.log, 'utf8'), 'source.txt\n');
});


test('explicit abort never auto-resumes an active workflow', t => {
  const f = fixture(t);
  f.handlers.agent_end({ messages: [{ role: 'assistant', stopReason: 'aborted', content: [] }] }, f.ctx);
  f.handlers.agent_end({ messages: [] }, { ...f.ctx, signal: { aborted: true } });
  assert.equal(f.sent.length, 0);
  assert.equal(existsSync(join(f.root, '.codex/.vdgg-active')), true);
});
