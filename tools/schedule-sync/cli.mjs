#!/usr/bin/env node
import { chromium } from 'playwright';
import { createInterface } from 'node:readline/promises';
import { stdin, stdout } from 'node:process';
import { dirname, join, resolve } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { readJSON, writeJSON, stateDirectory, defaultOutput, validateSources, syncSources, authPath, acquireLock, protectState } from './core.mjs';
import { fetchSource } from './browser.mjs';

const arguments_ = process.argv.slice(2);
const configFlag = arguments_.indexOf('--config');
let configPath = join(stateDirectory, 'config.json');
if (configFlag >= 0) {
  if (!arguments_[configFlag + 1]) throw new Error('--config requires a path.');
  configPath = resolve(arguments_[configFlag + 1]);
  arguments_.splice(configFlag, 2);
}
const [command, sourceID] = arguments_;
const ownDirectory = dirname(fileURLToPath(import.meta.url));

function xml(value) { return value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&apos;'); }

async function main() {
  if (!['init', 'login', 'sync', 'status', 'launchd'].includes(command)) {
    console.log('Usage: node cli.mjs init|login SOURCE_ID|sync|status|launchd [--config /absolute/config.json]');
    return;
  }
  if (command === 'init') {
    await mkdir(dirname(configPath), { recursive: true, mode: 0o700 });
    const initial = JSON.parse(await readFile(join(ownDirectory, 'config.example.json'), 'utf8'));
    for (const source of initial.sources) source.adapter = resolve(ownDirectory, source.adapter);
    await writeFile(configPath, `${JSON.stringify(initial, null, 2)}\n`, { flag: 'wx', mode: 0o600 });
    console.log(`Created ${configPath}. Set your portal URLs and adapters, then enable each source.`);
    return;
  }
  const config = await readJSON(configPath);
  const sources = validateSources(config);
  const directory = config.stateDirectory ? resolve(dirname(configPath), config.stateDirectory) : stateDirectory;
  const output = config.output ? resolve(dirname(configPath), config.output) : defaultOutput;
  if (command === 'status') {
    const cache = await readJSON(output, { version: 1, sources: [] });
    for (const source of cache.sources) console.log(`${source.name}: ${source.events.length} events; last success ${source.lastSuccessAt ?? 'never'}; ${source.error ?? 'OK'}`);
    if (!cache.sources.length) console.log('No schedules synced. Configure and enable a source first.');
    console.log(`Cache: ${output}`);
    return;
  }
  if (command === 'launchd') {
    const path = join(homedir(), 'Library/LaunchAgents/com.talax0n.notchy.schedule-sync.plist');
    const logs = join(stateDirectory, 'logs');
    await mkdir(dirname(path), { recursive: true });
    await mkdir(logs, { recursive: true, mode: 0o700 });
    const args = [process.execPath, fileURLToPath(import.meta.url), 'sync', '--config', configPath];
    const plist = `<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict>\n<key>Label</key><string>com.talax0n.notchy.schedule-sync</string>\n<key>ProgramArguments</key><array>${args.map(value => `<string>${xml(value)}</string>`).join('')}</array>\n<key>StartInterval</key><integer>14400</integer>\n<key>ProcessType</key><string>Background</string>\n<key>StandardOutPath</key><string>${xml(join(logs, 'sync.log'))}</string>\n<key>StandardErrorPath</key><string>${xml(join(logs, 'error.log'))}</string>\n</dict></plist>\n`;
    await writeFile(path, plist, { mode: 0o600 });
    console.log(`Wrote ${path}. Timer is not active. After a successful manual sync, activate with launchctl bootstrap gui/$(id -u) "${path}"`);
    return;
  }
  await protectState(directory);
  const unlock = await acquireLock(directory);
  let browser;
  try {
    if (command === 'login') {
      const source = sources.find(item => item.id === sourceID);
      if (!source) throw new Error('Choose an enabled source ID from your configuration.');
      browser = await chromium.launch({ headless: false });
      const existing = await readJSON(authPath(directory, source), null);
      const context = await browser.newContext(existing ? { storageState: existing } : {});
      try {
        const page = await context.newPage();
        await page.goto(source.url, { waitUntil: 'domcontentloaded' });
        const prompt = createInterface({ input: stdin, output: stdout });
        try { await prompt.question('Sign in and open the schedule page in Chromium. Press Enter here when ready. '); }
        finally { prompt.close(); }
        await writeJSON(authPath(directory, source), await context.storageState({ indexedDB: true }));
        console.log(`Saved session for ${source.name}. Run sync to verify extraction.`);
      } finally { await context.close(); }
      return;
    }
    if (!sources.length) {
      await writeJSON(output, { version: 1, sources: [] });
      console.log('No sources enabled. Cleared the schedule cache without starting Chromium.');
      return;
    }
    const previous = await readJSON(output, { version: 1, sources: [] });
    browser = await chromium.launch({ headless: true });
    const { cache, failed } = await syncSources(sources, previous,
      source => fetchSource(browser, source, directory, dirname(configPath)));
    await writeJSON(output, cache);
    for (const source of cache.sources) {
      console.log(`${source.name}: ${source.error ? `refresh failed; kept ${source.events.length} cached events. ${source.error}` : `${source.events.length} events synced`}`);
    }
    console.log(`Cache: ${output}`);
    if (failed) process.exitCode = 1;
  } finally {
    try { await browser?.close(); } finally { await unlock(); }
  }
}

main().catch(error => { console.error(error.message); process.exitCode = 1; });
