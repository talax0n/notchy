const lmsOrigin = 'https://lms.binus.ac.id';
const scheduleAPI = 'https://func-bm7-schedule-prod.azurewebsites.net';

function jakartaTime(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?$/.test(value)) {
    throw new Error('BINUS LMS returned an unrecognized local schedule timestamp.');
  }
  return `${value}+07:00`;
}

export function parseMonth(data, month) {
  if (!Array.isArray(data)) throw new Error('BINUS LMS returned an unrecognized month response.');
  return data.flatMap(day => {
    if (!Array.isArray(day?.Schedule)) throw new Error('BINUS LMS schedule entries are missing.');
    return day.Schedule.filter(event => event.isCancelled !== true).map(event => {
      if (!event.scheduleId || typeof event.content !== 'string' || !event.content.trim()) {
        throw new Error('BINUS LMS schedule is missing its event ID or course name.');
      }
      const exam = /exam/i.test(event.scheduleType ?? '');
      const detail = exam ? [event.lamType, 'exam'].filter(Boolean).join(' ') : event.title;
      const location = [event.location, event.customParam?.seatNumber ? `Seat ${event.customParam.seatNumber}` : null]
        .filter(Boolean).join(' · ');
      return {
        id: event.scheduleId,
        title: [event.content.trim(), detail].filter(Boolean).join(' · '),
        start: jakartaTime(event.dateStart),
        end: jakartaTime(event.dateEnd),
        ...(location ? { location } : {}),
        url: `${lmsOrigin}/lms/schedule/${month}`,
      };
    });
  });
}

export default async function scrape(page) {
  const today = new Date().toLocaleDateString('sv-SE', { timeZone: 'Asia/Jakarta' });
  const [year, month] = today.split('-').map(Number);
  const events = [];
  for (const offset of [-1, 0, 1]) {
    const date = new Date(Date.UTC(year, month - 1 + offset, 1));
    const key = `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, '0')}`;
    const responsePromise = page.waitForResponse(response => {
      const url = new URL(response.url());
      return url.origin === scheduleAPI && url.pathname === `/api/Schedule/Month-v1/${key}-1`;
    }, { timeout: 30_000 });
    let response;
    try {
      [response] = await Promise.all([
        responsePromise,
        page.goto(`${lmsOrigin}/lms/schedule/${key}`, { waitUntil: 'domcontentloaded', timeout: 30_000 }),
      ]);
    } catch {
      throw new Error('BINUS LMS did not load its schedule. Run login college to renew the Microsoft session.');
    }
    if (!response.ok()) throw new Error(`BINUS LMS schedule request failed (${response.status()}). Renew the college login.`);
    events.push(...parseMonth(await response.json(), key));
  }
  return events;
}
