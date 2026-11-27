// CampusLink private calendar feed.
//
// Google Calendar, Outlook and Apple Calendar "subscribe by URL" to:
//   https://<project>.supabase.co/functions/v1/calendar-feed?t=<64-hex token>
// The long random token is the only key (calendar apps cannot sign in), so
// this function needs no JWT. It only uses the public anon key: the database
// function calendar_feed_data() decides what the token may see.

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const APP_URL = Deno.env.get("CAMPUSLINK_APP_URL") ?? "https://campuslinks.online";
const TZ = "Africa/Kampala";

type Feed = {
  semester_ends_on: string | null;
  events: Array<Record<string, any>>;
  classes: Array<Record<string, any>>;
  exams: Array<Record<string, any>>;
};

// ---- iCalendar helpers ----
const esc = (s: unknown) =>
  String(s ?? "").replace(/\\/g, "\\\\").replace(/;/g, "\\;").replace(/,/g, "\\,").replace(/\r?\n/g, "\\n");

/** Lines longer than 75 bytes must be folded (RFC 5545 3.1), without splitting a UTF-8 character. */
function fold(line: string): string {
  const enc = new TextEncoder();
  if (enc.encode(line).length <= 75) return line;
  const out: string[] = [];
  let cur = "";
  let curLen = 0;
  for (const ch of line) {
    const n = enc.encode(ch).length;
    const limit = out.length === 0 ? 75 : 74; // continuation lines start with a space
    if (curLen + n > limit) {
      out.push(cur);
      cur = "";
      curLen = 0;
    }
    cur += ch;
    curLen += n;
  }
  out.push(cur);
  return out.join("\r\n ");
}

const pad = (n: number) => String(n).padStart(2, "0");
const utc = (d: Date) =>
  `${d.getUTCFullYear()}${pad(d.getUTCMonth() + 1)}${pad(d.getUTCDate())}T${pad(d.getUTCHours())}${pad(d.getUTCMinutes())}${pad(d.getUTCSeconds())}Z`;
const localStamp = (date: string, time: string) => `${date.replaceAll("-", "")}T${time.replaceAll(":", "").padEnd(6, "0").slice(0, 6)}`;
const ymd = (d: Date) => `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`;

/** First date on or after `from` (YYYY-MM-DD) that falls on ISO weekday `day` (1 = Monday). */
function firstWeekday(from: string, day: number): string {
  const d = new Date(`${from}T00:00:00Z`);
  const iso = ((d.getUTCDay() + 6) % 7) + 1;
  d.setUTCDate(d.getUTCDate() + ((day - iso + 7) % 7));
  return ymd(d);
}

function alarm(trigger: string, text: string): string[] {
  return ["BEGIN:VALARM", "ACTION:DISPLAY", `TRIGGER:${trigger}`, `DESCRIPTION:${esc(text)}`, "END:VALARM"];
}

function build(feed: Feed): string {
  const now = utc(new Date());
  const L: string[] = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//CampusLink//Calendar feed//EN",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    "X-WR-CALNAME:CampusLink",
    "X-WR-CALDESC:Your classes\\, exams and campus events from CampusLink",
    `X-WR-TIMEZONE:${TZ}`,
    "REFRESH-INTERVAL;VALUE=DURATION:PT6H",
    "X-PUBLISHED-TTL:PT6H",
    // Uganda has no daylight saving: one fixed +03:00 rule.
    "BEGIN:VTIMEZONE", `TZID:${TZ}`,
    "BEGIN:STANDARD", "DTSTART:19700101T000000", "TZOFFSETFROM:+0300", "TZOFFSETTO:+0300", "TZNAME:EAT", "END:STANDARD",
    "END:VTIMEZONE",
  ];

  for (const e of feed.events ?? []) {
    const start = new Date(e.starts_at);
    const end = e.ends_at ? new Date(e.ends_at) : new Date(start.getTime() + 2 * 3600_000);
    const updated = new Date(e.updated_at ?? e.starts_at);
    const link = `${APP_URL}/#/events/${e.id}`;
    const desc = [
      e.cancelled ? `CANCELLED${e.cancel_reason ? `: ${e.cancel_reason}` : ""}` : null,
      e.description,
      e.organiser ? `Organised by ${e.organiser}` : null,
      e.online_url ? `Join online: ${e.online_url}` : null,
      e.going ? "You said you're going." : null,
      `Details and your ticket: ${link}`,
    ].filter(Boolean).join("\n\n");
    L.push(
      "BEGIN:VEVENT",
      `UID:event-${e.id}@campuslink`,
      `DTSTAMP:${now}`,
      `LAST-MODIFIED:${utc(updated)}`,
      `SEQUENCE:${Math.floor(updated.getTime() / 60000) - 29_000_000}`,
      `DTSTART:${utc(start)}`,
      `DTEND:${utc(end)}`,
      `SUMMARY:${esc((e.cancelled ? "Cancelled: " : "") + e.title)}`,
      `DESCRIPTION:${esc(desc)}`,
      ...(e.location ? [`LOCATION:${esc(e.location)}`] : []),
      `URL:${link}`,
      `STATUS:${e.cancelled ? "CANCELLED" : "CONFIRMED"}`,
      "CATEGORIES:CampusLink event",
      ...(e.cancelled ? [] : alarm("-PT1H", `${e.title} starts in 1 hour`)),
      "END:VEVENT",
    );
  }

  const fallbackEnd = (from: string) => {
    const d = new Date(`${from}T00:00:00Z`);
    d.setUTCDate(d.getUTCDate() + 16 * 7); // about one semester
    return ymd(d);
  };
  for (const c of feed.classes ?? []) {
    if (!c.start || !c.end || !c.day) continue;
    const from = c.from ?? ymd(new Date());
    const first = firstWeekday(from, Number(c.day));
    const until = (feed.semester_ends_on && feed.semester_ends_on >= first) ? feed.semester_ends_on : fallbackEnd(first);
    L.push(
      "BEGIN:VEVENT",
      `UID:class-${c.id}@campuslink`,
      `DTSTAMP:${now}`,
      `DTSTART;TZID=${TZ}:${localStamp(first, c.start)}`,
      `DTEND;TZID=${TZ}:${localStamp(first, c.end)}`,
      `RRULE:FREQ=WEEKLY;UNTIL=${until.replaceAll("-", "")}T205959Z`,
      `SUMMARY:${esc(`${c.code ?? ""} ${c.name ?? ""}`.trim())}`,
      `DESCRIPTION:${esc([c.lecturer ? `Lecturer: ${c.lecturer}` : null, "From your CampusLink timetable."].filter(Boolean).join("\n"))}`,
      ...(c.room ? [`LOCATION:${esc(c.room)}`] : []),
      "CATEGORIES:Class",
      "END:VEVENT",
    );
  }

  for (const x of feed.exams ?? []) {
    if (!x.date) continue;
    const title = `Exam: ${`${x.code ?? ""} ${x.name ?? ""}`.trim()}`;
    const timed = x.start != null;
    const nextDay = (() => { const d = new Date(`${x.date}T00:00:00Z`); d.setUTCDate(d.getUTCDate() + 1); return ymd(d); })();
    L.push(
      "BEGIN:VEVENT",
      `UID:exam-${x.id}@campuslink`,
      `DTSTAMP:${now}`,
      timed ? `DTSTART;TZID=${TZ}:${localStamp(x.date, x.start)}` : `DTSTART;VALUE=DATE:${x.date.replaceAll("-", "")}`,
      timed
        ? `DTEND;TZID=${TZ}:${localStamp(x.date, x.end ?? x.start)}`
        : `DTEND;VALUE=DATE:${nextDay.replaceAll("-", "")}`,
      `SUMMARY:${esc(title)}`,
      `DESCRIPTION:${esc("Bring your exam card and student ID. Check the official exam timetable for changes.")}`,
      ...((x.room || x.campus) ? [`LOCATION:${esc([x.room, x.campus].filter(Boolean).join(", "))}`] : []),
      "CATEGORIES:Exam",
      ...alarm("-P1D", `${title} is tomorrow`),
      ...(timed ? alarm("-PT1H", `${title} starts in 1 hour`) : []),
      "END:VEVENT",
    );
  }

  L.push("END:VCALENDAR");
  return L.map(fold).join("\r\n") + "\r\n";
}

Deno.serve(async (req) => {
  if (req.method !== "GET" && req.method !== "HEAD") return new Response("Method not allowed", { status: 405 });
  const url = new URL(req.url);
  // Accept ?t=<token> or .../calendar-feed/<token>.ics
  const last = url.pathname.split("/").pop() ?? "";
  const token = (url.searchParams.get("t") ?? last.replace(/\.ics$/, "")).toLowerCase();
  if (!/^[0-9a-f]{64}$/.test(token)) return new Response("Calendar link not found", { status: 404 });

  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/calendar_feed_data`, {
    method: "POST",
    headers: { apikey: ANON_KEY, Authorization: `Bearer ${ANON_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({ p_token: token }),
  });
  if (!res.ok) return new Response("Calendar is busy, try again later", { status: 503 });
  const feed = (await res.json()) as Feed | null;
  if (!feed) return new Response("This calendar link was turned off or replaced. Make a new one in CampusLink.", { status: 404 });

  return new Response(req.method === "HEAD" ? null : build(feed), {
    headers: {
      "Content-Type": "text/calendar; charset=utf-8",
      "Content-Disposition": 'inline; filename="campuslink.ics"',
      "Cache-Control": "private, max-age=900",
      "X-Robots-Tag": "noindex",
    },
  });
});
