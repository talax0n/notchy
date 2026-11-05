import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, readFile, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { createServer } from 'node:http';
import { spawn } from 'node:child_process';
import { normalizeEvents, syncSources, writeJSON, acquireLock } from '../core.mjs';

const event = { id: 'class-1', title: 'Algorithms', start: '2026-11-05T09:00:00+07:00', end: '2026-11-05T10:00:00+07:00' };
const source = { id: 'college', name: 'College', url: 'https://example.com/schedule' };

test('normalizes offsets, deduplicates exact rows and rejects conflicting IDs', () => {
  const events = normalizeEvents([event, event], source.url);
  assert.equal(events.length, 1);
  assert.equal(events[0].start, '2026-11-05T02:00:00.000Z');
  assert.throws(() => normalizeEvents([event, { ...event, title: 'Different' }], source.url), /Conflicting/);
  assert.equal(normalizeEvents([{ ...event, id: undefined }], source.url)[0].id, normalizeEvents([{ ...event, id: undefined }], source.url)[0].id);
});

test('rejects missing timezones, impossible dates, reverse ranges and unsafe links', () => {
  for (const start of ['2026-11-05T09:00:00', '2026-02-30T09:00:00Z', 'not-a-date', '2026-11-05T24:00:00Z']) {
    assert.throws(() => normalizeEvents([{ ...event, start }], source.url));
  }
  assert.throws(() => normalizeEvents([{ ...event, end: event.start }], source.url), /end/);
  assert.throws(() => normalizeEvents([{ ...event, url: 'javascript:alert(1)' }], source.url), /HTTP/);
});

test('a failed source keeps its events and timestamp, other sources still refresh', async () => {
  const prior = { version: 1, sources: [{ ...source, events: [event], lastSuccessAt: '2026-11-04T00:00:00Z', error: null }, { id: 'removed', events: [event] }] };
  const other = { ...source, id: 'teaching' };
  const result = await syncSources([source, other], prior, async item => {
    if (item.id === 'college') throw new Error('Login expired');
    return [event];
  }, () => '2026-11-05T00:00:00Z');
  assert.equal(result.failed, true);
  assert.deepEqual(result.cache.sources[0].events, [event]);
  assert.equal(result.cache.sources[0].lastSuccessAt, '2026-11-04T00:00:00Z');
  assert.equal(result.cache.sources[0].error, 'Login expired');
  assert.equal(result.cache.sources[1].lastSuccessAt, '2026-11-05T00:00:00Z');
  assert.equal(result.cache.sources.length, 2);
  const empty = await syncSources([source], result.cache, async () => []);
  assert.deepEqual(empty.cache.sources[0].events, []);
  assert.equal(empty.cache.sources[0].error, null);
});

test('atomic cache is private and concurrent runs are rejected', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'notchy-lock-'));
  try {
    const release = await acquireLock(directory);
    await assert.rejects(acquireLock(directory), /Another/);
    await release();
    const file = join(directory, 'schedules.json');
    await writeJSON(file, { version: 1, sources: [] });
    assert.equal((await stat(file)).mode & 0o777, 0o600);
    assert.deepEqual(JSON.parse(await readFile(file)), { version: 1, sources: [] });
  } finally { await rm(directory, { recursive: true, force: true }); }
});

async function runCLI(configPath) {
  const child = spawn(process.execPath, [resolve('cli.mjs'), 'sync', '--config', configPath], { stdio: ['ignore', 'pipe', 'pipe'] });
  let output = '';
  for (const stream of [child.stdout, child.stderr]) stream.on('data', data => { output += data; });
  const code = await new Promise((resolve_, reject) => { child.on('error', reject); child.on('exit', resolve_); });
  return { code, output };
}

test('real Chromium sync reads DOM, handles empty schedule, and retains cache on login redirect', { timeout: 120_000 }, async () => {
  const directory = await mkdtemp(join(tmpdir(), 'notchy-browser-'));
  let mode = 'events';
  const server = createServer((request, response) => {
    response.setHeader('Content-Type', 'text/html');
    if (mode === 'login') { response.end('<h1>Login required</h1>'); return; }
    response.end(`<main id="schedule">${mode === 'empty' ? '<p id="empty">No classes</p>' : '<article data-id="class-1"><h2>Algorithms</h2><time class="start" datetime="2026-11-05T09:00:00+07:00"></time><time class="end" datetime="2026-11-05T10:00:00+07:00"></time></article>'}</main>`);
  });
  await new Promise(resolve_ => server.listen(0, '127.0.0.1', resolve_));
  const url = `http://127.0.0.1:${server.address().port}`;
  const config = { stateDirectory: join(directory, 'state'), output: join(directory, 'cache.json'), sources: [{ ...source, url, selectors: { ready: '#schedule', rows: 'article', empty: '#empty', fields: { id: { selector: ':scope', attribute: 'data-id' }, title: { selector: 'h2' }, start: { selector: '.start', attribute: 'datetime' }, end: { selector: '.end', attribute: 'datetime' } } } }] };
  const configPath = join(directory, 'config.json');
  try {
    await writeJSON(configPath, config);
    assert.deepEqual(await runCLI(configPath), { code: 0, output: `College: 1 events synced\nCache: ${config.output}\n` });
    const first = JSON.parse(await readFile(config.output));
    assert.equal(first.sources[0].events[0].title, 'Algorithms');
    mode = 'login';
    const failed = await runCLI(configPath);
    assert.equal(failed.code, 1, failed.output);
    const retained = JSON.parse(await readFile(config.output));
    assert.deepEqual(retained.sources[0].events, first.sources[0].events);
    assert.equal(retained.sources[0].lastSuccessAt, first.sources[0].lastSuccessAt);
    assert.ok(retained.sources[0].error);
    mode = 'empty';
    assert.equal((await runCLI(configPath)).code, 0);
    assert.deepEqual(JSON.parse(await readFile(config.output)).sources[0].events, []);
  } finally {
    await new Promise(resolve_ => server.close(resolve_));
    await rm(directory, { recursive: true, force: true });
  }
});
