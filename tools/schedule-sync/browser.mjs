import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';
import { readJSON, writeJSON, authPath } from './core.mjs';

export async function scrapeDOM(page, source) {
  const { selectors } = source;
  await page.locator(selectors.ready).first().waitFor({ state: 'visible' });
  await Promise.any([
    page.locator(selectors.rows).first().waitFor({ state: 'visible' }),
    page.locator(selectors.empty).first().waitFor({ state: 'visible' }),
  ]);
  if (await page.locator(selectors.empty).first().isVisible()) {
    if (await page.locator(selectors.rows).count()) throw new Error('Both event rows and an empty-state marker are present.');
    return [];
  }
  return page.locator(selectors.rows).evaluateAll((rows, fields) => rows.map(row => {
    const event = {};
    for (const [key, descriptor] of Object.entries(fields)) {
      const element = descriptor.selector === ':scope' ? row : row.querySelector(descriptor.selector);
      const value = descriptor.attribute ? element?.getAttribute(descriptor.attribute) : element?.textContent;
      if (value != null && value.trim()) event[key] = value.trim();
    }
    return event;
  }), selectors.fields);
}

export async function fetchSource(browser, source, directory, configDirectory) {
  const state = await readJSON(authPath(directory, source), null);
  const context = await browser.newContext(state ? { storageState: state } : {});
  context.setDefaultTimeout(30_000);
  try {
    const page = await context.newPage();
    await page.goto(source.url, { waitUntil: 'domcontentloaded', timeout: 45_000 });
    const scrape = source.adapter
      ? (await import(pathToFileURL(resolve(configDirectory, source.adapter)).href)).default
      : scrapeDOM;
    if (typeof scrape !== 'function') throw new Error('The custom adapter must export a default async function.');
    let timeout;
    try {
      const events = await Promise.race([
        scrape(page, source),
        new Promise((_, reject) => { timeout = setTimeout(() => reject(new Error('Schedule extraction exceeded 90 seconds.')), 90_000); }),
      ]);
      await writeJSON(authPath(directory, source), await context.storageState({ indexedDB: true }));
      return events;
    } finally { clearTimeout(timeout); }
  } finally { await context.close(); }
}
