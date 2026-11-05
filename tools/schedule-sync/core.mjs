import { createHash, randomUUID } from 'node:crypto';
import { mkdir, readFile, writeFile, rename, rm, stat, chmod } from 'node:fs/promises';
import { dirname, resolve, join } from 'node:path';
import { homedir } from 'node:os';

export const stateDirectory = join(homedir(), 'Library/Application Support/NotchyScheduleSync');
export const defaultOutput = join(homedir(), 'Library/Containers/com.talax0n.notchy/Data/Library/Application Support/Notchy/schedules.json');

export async function readJSON(path, fallback) {
  try { return JSON.parse(await readFile(path, 'utf8')); }
  catch (error) { if (error.code === 'ENOENT' && fallback !== undefined) return fallback; throw error; }
}

export async function writeJSON(path, value) {
  await mkdir(dirname(path), { recursive: true, mode: 0o700 });
  const temporary = `${path}.${randomUUID()}.tmp`;
  try {
    await writeFile(temporary, `${JSON.stringify(value, null, 2)}\n`, { mode: 0o600, flag: 'wx' });
    await rename(temporary, path);
  } finally { await rm(temporary, { force: true }); }
}

export async function acquireLock(directory) {
  await mkdir(directory, { recursive: true, mode: 0o700 });
  const lock = join(directory, 'sync.lock');
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      await mkdir(lock, { mode: 0o700 });
      await writeJSON(join(lock, 'owner.json'), { pid: process.pid });
      return () => rm(lock, { recursive: true, force: true });
    } catch (error) {
      if (error.code !== 'EEXIST') throw error;
      let alive = true;
      try {
        const owner = await readJSON(join(lock, 'owner.json'));
        if (!Number.isSafeInteger(owner.pid) || owner.pid <= 0) throw new Error('Invalid lock owner');
        try { process.kill(owner.pid, 0); } catch (cause) { if (cause.code === 'ESRCH') alive = false; else throw cause; }
      } catch (cause) {
        if (cause.code === 'ENOENT' && Date.now() - (await stat(lock)).mtimeMs > 30_000) alive = false;
        else if (cause.code !== 'ENOENT') throw cause;
      }
      if (alive || attempt > 0) throw new Error('Another schedule login or sync is running.');
      await rm(lock, { recursive: true, force: true });
    }
  }
}

export function validateSources(config) {
  if (!Array.isArray(config.sources)) throw new Error('Configuration needs a sources array.');
  const ids = new Set();
  for (const source of config.sources) {
    if (!/^[a-z0-9][a-z0-9_-]*$/.test(source.id ?? '') || ids.has(source.id)) throw new Error('Source IDs must be unique lowercase names.');
    ids.add(source.id);
    if (typeof source.name !== 'string' || !source.name.trim()) throw new Error(`Source ${source.id} needs a name.`);
    if (source.enabled !== undefined && typeof source.enabled !== 'boolean') throw new Error(`Source ${source.id} enabled must be boolean.`);
    if (source.enabled === false) continue;
    if (!['http:', 'https:'].includes(new URL(source.url).protocol)) throw new Error(`Source ${source.id} needs an HTTP(S) URL.`);
    if (source.adapter) {
      if (typeof source.adapter !== 'string' || !source.adapter.endsWith('.mjs')) throw new Error('Custom adapters must be .mjs files.');
    } else {
      const selectors = source.selectors;
      for (const key of ['ready', 'rows', 'empty']) {
        if (typeof selectors?.[key] !== 'string' || !selectors[key].trim()) throw new Error(`Source ${source.id} needs selectors.${key}.`);
      }
      for (const key of ['title', 'start', 'end']) {
        if (typeof selectors.fields?.[key]?.selector !== 'string') throw new Error(`Source ${source.id} needs a ${key} field selector.`);
      }
    }
  }
  return config.sources.filter(source => source.enabled !== false);
}

function parseInstant(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?(?:Z|[+-]\d{2}:\d{2})$/.test(value)) throw new Error('Dates must be ISO 8601 timestamps with seconds and an explicit timezone offset.');
  const [year, month, day] = value.slice(0, 10).split('-').map(Number);
  const daysInMonth = new Date(Date.UTC(year, month, 0)).getUTCDate();
  const milliseconds = Date.parse(value);
  if (month < 1 || month > 12 || day < 1 || day > daysInMonth || !Number.isFinite(milliseconds) || Number(value.slice(11, 13)) > 23) throw new Error('Invalid schedule timestamp.');
  return milliseconds;
}

export function normalizeEvents(events, sourceURL) {
  if (!Array.isArray(events)) throw new Error('The schedule adapter must return an array.');
  const result = new Map();
  for (const event of events) {
    if (typeof event?.title !== 'string' || !event.title.trim()) throw new Error('Every event needs a title.');
    const start = parseInstant(event.start), end = parseInstant(event.end);
    if (end <= start) throw new Error('Event end must follow its start.');
    const normalized = { title: event.title.trim(), start: new Date(start).toISOString(), end: new Date(end).toISOString() };
    if (event.location != null) {
      if (typeof event.location !== 'string') throw new Error('Event location must be text.');
      if (event.location.trim()) normalized.location = event.location.trim();
    }
    if (event.url) {
      const url = new URL(event.url, sourceURL);
      if (!['http:', 'https:'].includes(url.protocol)) throw new Error('Event URLs must use HTTP(S).');
      normalized.url = url.href;
    }
    if (event.id != null && (typeof event.id !== 'string' || !event.id.trim())) throw new Error('Event IDs must be nonempty text.');
    normalized.id = event.id?.trim() ?? createHash('sha256').update(JSON.stringify(normalized)).digest('hex').slice(0, 24);
    const prior = result.get(normalized.id);
    if (prior && JSON.stringify(prior) !== JSON.stringify(normalized)) throw new Error(`Conflicting schedule rows for event ${normalized.id}.`);
    result.set(normalized.id, normalized);
  }
  return [...result.values()].sort((a, b) => a.start.localeCompare(b.start) || a.id.localeCompare(b.id));
}

export async function syncSources(sources, previous, fetchEvents, now = () => new Date().toISOString()) {
  if (previous.version !== 1 || !Array.isArray(previous.sources)) throw new Error('Unsupported existing schedule cache.');
  let failed = false;
  const next = [];
  for (const source of sources) {
    const old = previous.sources.find(item => item.id === source.id);
    const base = { id: source.id, name: source.name, url: source.url };
    try {
      const events = normalizeEvents(await fetchEvents(source), source.url);
      next.push({ ...base, lastSuccessAt: now(), error: null, events });
    } catch (error) {
      failed = true;
      next.push({ ...base, lastSuccessAt: old?.lastSuccessAt ?? null, error: String(error.message ?? error), events: old?.events ?? [] });
    }
  }
  return { cache: { version: 1, sources: next }, failed };
}

export function authPath(directory, source) { return resolve(directory, 'sessions', `${source.id}.json`); }

export async function protectState(directory) {
  await mkdir(directory, { recursive: true, mode: 0o700 });
  await chmod(directory, 0o700);
}
