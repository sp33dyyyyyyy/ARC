'use strict';
// Small natural-language time parser for reminders and schedules.
const DAYS = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'];
const UNIT_MS = { second: 1000, sec: 1000, minute: 60000, min: 60000, hour: 3600000, hr: 3600000, day: 86400000, week: 604800000 };
const WORDNUM = { a: 1, an: 1, one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, ten: 10, fifteen: 15, twenty: 20, thirty: 30, 'forty five': 45, half: 0.5 };

function parseClock(s) {
  const m = s.match(/\b(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?\b/i);
  if (!m) {
    if (/\bnoon\b/.test(s)) return { h: 12, m: 0 };
    if (/\bmidnight\b/.test(s)) return { h: 0, m: 0 };
    return null;
  }
  let h = parseInt(m[1], 10); const min = m[2] ? parseInt(m[2], 10) : 0;
  const ap = (m[3] || '').replace(/\./g, '').toLowerCase();
  if (h > 23 || min > 59) return null;
  if (ap === 'pm' && h < 12) h += 12;
  if (ap === 'am' && h === 12) h = 0;
  if (!ap && !m[2] && h <= 7) h += 12; // "at 5" → 5 pm (assistant convention)
  return { h, m: min };
}

/** Parse a one-off due time. Returns epoch ms or null if no time could be found. */
function parseDue(text, now = new Date()) {
  const s = ` ${String(text || '').toLowerCase()} `;
  // relative: in 20 minutes / in an hour / in half an hour
  let m = s.match(/\bin\s+(\d+(?:\.\d+)?|a|an|one|two|three|four|five|six|ten|fifteen|twenty|thirty|half an?)\s*(seconds?|secs?|minutes?|mins?|hours?|hrs?|days?|weeks?)\b/);
  if (m) {
    const nRaw = m[1].replace(/\s+an?$/, '');
    const n = /half/.test(m[1]) ? 0.5 : (WORDNUM[nRaw] ?? parseFloat(nRaw));
    const unit = m[2].replace(/s$/, '');
    return now.getTime() + n * (UNIT_MS[unit] || 60000);
  }
  const d = new Date(now);
  let dayShift = null;
  if (/\btomorrow\b/.test(s)) dayShift = 1;
  else if (/\btoday\b|\btonight\b|\bthis (morning|afternoon|evening)\b/.test(s)) dayShift = 0;
  const wd = DAYS.findIndex((x) => new RegExp(`\\b(on\\s+)?(next\\s+)?${x}\\b`).test(s));
  let sameWeekday = false;
  if (wd >= 0) { const diff = (wd - d.getDay() + 7) % 7; dayShift = diff; sameWeekday = diff === 0; }
  let clock = null;
  const atM = s.match(/\b(?:at|by|@)\s+([0-9: apm.]+|noon|midnight)/);
  if (atM) clock = parseClock(atM[1]);
  if (!clock) { const bare = s.match(/\b(\d{1,2}(?::\d{2})?\s*(?:am|pm|a\.m\.|p\.m\.))/); if (bare) clock = parseClock(bare[1]); }
  if (!clock) { const hm = s.match(/\b(\d{1,2}:\d{2})\b/); if (hm) clock = parseClock(hm[1]); }
  if (!clock) {
    if (/\btonight\b|\bthis evening\b/.test(s)) clock = { h: 20, m: 0 };
    else if (/\bthis afternoon\b|\bafternoon\b/.test(s)) clock = { h: 15, m: 0 };
    else if (/\bmorning\b/.test(s)) clock = { h: 9, m: 0 };
    else if (/\bevening\b/.test(s)) clock = { h: 19, m: 0 };
    else if (dayShift !== null) clock = { h: 9, m: 0 };
  }
  if (!clock) {
    const iso = Date.parse(text);
    return Number.isNaN(iso) ? null : iso;
  }
  d.setHours(clock.h, clock.m, 0, 0);
  if (dayShift !== null) { d.setDate(d.getDate() + dayShift); if (sameWeekday && d.getTime() <= now.getTime()) d.setDate(d.getDate() + 7); }
  else if (d.getTime() <= now.getTime()) d.setDate(d.getDate() + 1);
  return d.getTime();
}

/** Parse a recurring schedule phrase into a trigger. Returns null if not recurring. */
function parseSchedule(text) {
  const s = ` ${String(text || '').toLowerCase()} `;
  let m = s.match(/\bevery\s+(\d+)\s*(minutes?|mins?|hours?|hrs?)\b/);
  if (m) { const n = parseInt(m[1], 10); return { type: 'interval', minutes: /h/.test(m[2]) ? n * 60 : n }; }
  if (/\bevery\s+(an\s+)?hour\b|\bhourly\b/.test(s)) return { type: 'interval', minutes: 60 };
  if (/\bevery\s+(a\s+)?minute\b/.test(s)) return { type: 'interval', minutes: 1 };
  let clock = null;
  const atM = s.match(/\b(?:at|@)\s+([0-9: apm.]+|noon|midnight)/); if (atM) clock = parseClock(atM[1]);
  if (!clock) { const bare = s.match(/\b(\d{1,2}(?::\d{2})?\s*(?:am|pm))\b/); if (bare) clock = parseClock(bare[1]); }
  const defaultClock = /\bmorning\b/.test(s) ? { h: 8, m: 0 } : /\bevening\b|\bnight\b/.test(s) ? { h: 20, m: 0 } : /\bafternoon\b/.test(s) ? { h: 15, m: 0 } : { h: 9, m: 0 };
  const c = clock || defaultClock;
  const wd = DAYS.findIndex((x) => new RegExp(`\\bevery\\s+${x}s?\\b|\\b${x}s\\b`).test(s));
  if (wd >= 0) return { type: 'cron', cron: `${c.m} ${c.h} * * ${wd}`, description: `Every ${DAYS[wd]} at ${pad(c.h)}:${pad(c.m)}` };
  if (/\bweekdays?\b|\bevery work ?day\b/.test(s)) return { type: 'cron', cron: `${c.m} ${c.h} * * 1-5`, description: `Weekdays at ${pad(c.h)}:${pad(c.m)}` };
  if (/\bweekends?\b/.test(s)) return { type: 'cron', cron: `${c.m} ${c.h} * * 0,6`, description: `Weekends at ${pad(c.h)}:${pad(c.m)}` };
  if (/\bevery\s+(day|morning|evening|night|afternoon)\b|\bdaily\b|\beach (day|morning|evening)\b/.test(s)) return { type: 'cron', cron: `${c.m} ${c.h} * * *`, description: `Every day at ${pad(c.h)}:${pad(c.m)}` };
  return null;
}
const pad = (n) => String(n).padStart(2, '0');

module.exports = { parseDue, parseSchedule, parseClock };
