import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { homedir } from 'node:os';

const portal = 'https://socs1.binus.ac.id/messier/';
const scheduleURL = `${portal}Home.aspx#P=Teaching%20Schedule`;
const examURL = `${portal}Home.aspx#P=Exam%20Proctor%20Schedule`;

export function teachingEvents(courses) {
  if (!Array.isArray(courses)) throw new Error('Messier returned an unrecognized teaching schedule.');
  return courses.flatMap(({ course, details }) => {
    if (!course?.Id || typeof course.Subject !== 'string' || !Array.isArray(details)) {
      throw new Error('Messier teaching course details changed format.');
    }
    return details.map(detail => {
      const shift = /^(\d{2}:\d{2})\s*-\s*(\d{2}:\d{2})$/.exec(detail.Shift ?? '');
      const date = new Date(detail.Date);
      if (!detail.Id || !detail.Date || !Number.isFinite(date.getTime()) || !shift) {
        throw new Error('Messier returned an invalid dated teaching session.');
      }
      const day = new Date(date.getTime() + 7 * 60 * 60 * 1000).toISOString().slice(0, 10);
      return {
        id: `teaching-${detail.Id}`,
        title: `${course.Subject.trim()} · ${String(course.Class ?? '').trim()}`,
        start: `${day}T${shift[1]}:00+07:00`,
        end: `${day}T${shift[2]}:00+07:00`,
        location: [detail.Room, course.Campus].filter(Boolean).join(' · '),
        url: scheduleURL,
      };
    });
  });
}

export function examEvents(rows) {
  if (!Array.isArray(rows)) throw new Error('Messier returned an unrecognized exam proctor schedule.');
  return rows.map(row => {
    const event = teachingEvents([{
      course: { Id: row.Id, Subject: row.Subject, Class: row.ClassName },
      details: [row],
    }])[0];
    return { ...event, id: `exam-${row.Id}`, title: `Exam proctor · ${event.title}`, url: examURL };
  });
}

async function authenticate(page) {
  if (!page.url().startsWith(portal)) await page.goto(portal, { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => document.querySelector('#search_menu') || window.LoginScript?._single?._user);
  if (!await page.locator('#user').isVisible()) return;
  let credentials;
  try {
    credentials = JSON.parse(await readFile(join(homedir(), 'Library/Application Support/NotchyScheduleSync/credentials/teaching.json'), 'utf8'));
  } catch {
    throw new Error('Messier session expired. Save teaching credentials locally or run login teaching.');
  }
  if (!credentials.username || !credentials.password) throw new Error('Messier local credentials need username and password.');
  await page.locator('#user').fill(credentials.username);
  await page.locator('#pass').fill(credentials.password);
  await page.locator('#rm').check();
  await page.locator('#logon').click();
  const result = await Promise.race([
    page.waitForURL('**/Home.aspx').then(() => 'accepted'),
    page.locator('#msg').filter({ hasText: /\S/ }).waitFor({ state: 'visible' }).then(() => 'rejected'),
  ]);
  if (result !== 'accepted') throw new Error('Messier rejected the saved login. Update the local teaching credentials.');
}

export default async function scrapeMessier(page) {
  await authenticate(page);
  await page.goto(scheduleURL, { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => window.EmployeeSchedule?._single?._schedule?.get_data?.()?.Items);
  const courses = await page.evaluate(async () => {
    const courses = EmployeeSchedule._single._schedule.get_data().Items;
    if (!Array.isArray(courses)) throw new Error('Messier teaching schedule did not load.');
    const result = [];
    for (const course of courses) {
      const details = await new Promise((resolve, reject) =>
        Messier.ILecturerScheduleService.GetTeachingScheduleDetails(course.Id, resolve,
          () => reject(new Error('Messier could not load teaching session details.'))));
      result.push({ course, details });
    }
    return result;
  });
  const teaching = teachingEvents(courses);
  await page.goto(examURL, { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => window.ExamProctorScheduleScript?._single?._schedule?.get_data?.()?.Message !== undefined);
  const exams = await page.evaluate(() => {
    const data = ExamProctorScheduleScript._single._schedule.get_data();
    return data.Items === null && data.Message === MGeneral.NoSchedule ? [] : data.Items;
  });
  return [...teaching, ...examEvents(exams)];
}
