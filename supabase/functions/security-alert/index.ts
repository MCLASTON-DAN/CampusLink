// security-alert: emails "New sign-in to your CampusLink account" and carries
// out the "This wasn't me" button.
//
//   POST {"ids": [...]}     from process_signin_alerts (every minute). No login
//                           needed: claim_signin_emails sends each email once,
//                           only to the account owner, only for recent sign-ins.
//   POST {"secure": token}  from the app's /secure-account page (the email's
//                           link opens that page; the person taps a button
//                           there, so email scanners opening links can't
//                           trigger it). Signs out every device.
//
// Secret: BREVO_API_KEY (Brevo > SMTP & API > API keys).

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SENDER = { name: "CampusLink Security", email: "centient@campuslinks.online" };
const APP_URL = "https://campuslink.danmclaston.workers.dev";

type Claim = { event_id: string; email: string; name: string; device: string; at_text: string; ip: string | null; token: string };

async function rpc<T>(name: string, args: unknown): Promise<T> {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify(args),
  });
  if (!res.ok) throw new Error(`${name} failed: ${res.status} ${await res.text()}`);
  const text = await res.text();
  return (text ? JSON.parse(text) : null) as T;
}

const secureLink = (token: string) => `${APP_URL}/#/secure-account/${token}`;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (data: unknown, status = 200) => Response.json(data, { status, headers: CORS });

const esc = (s: string) =>
  s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));

function emailHtml(c: Claim): string {
  const link = secureLink(c.token);
  return `<!doctype html><html><body style="margin:0;background:#f4f3fb;font-family:Arial,Helvetica,sans-serif;color:#1d1b2f">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding:24px 12px">
<table role="presentation" width="100%" style="max-width:520px;background:#ffffff;border-radius:14px;padding:28px" cellpadding="0" cellspacing="0">
<tr><td style="font-size:20px;font-weight:bold;color:#3B2DB3;padding-bottom:12px">CampusLink</td></tr>
<tr><td style="font-size:18px;font-weight:bold;padding-bottom:8px">New sign-in to your account</td></tr>
<tr><td style="font-size:15px;line-height:22px;padding-bottom:16px">Hi ${esc(c.name)}, your CampusLink account was just opened on a new sign-in.</td></tr>
<tr><td style="background:#f4f3fb;border-radius:10px;padding:14px;font-size:14px;line-height:22px">
<b>Device:</b> ${esc(c.device)}<br><b>When:</b> ${esc(c.at_text)}${c.ip ? `<br><b>Network address:</b> ${esc(c.ip)}` : ""}</td></tr>
<tr><td style="font-size:15px;line-height:22px;padding:16px 0">If this was you, you don't need to do anything.</td></tr>
<tr><td style="padding-bottom:16px"><a href="${link}" style="display:inline-block;background:#B42318;color:#ffffff;text-decoration:none;font-weight:bold;padding:12px 18px;border-radius:10px">This wasn't me: sign out every device</a></td></tr>
<tr><td style="font-size:13px;line-height:20px;color:#5b5872">Then secure your Google account (turn on 2-Step Verification) or change your CampusLink password.
You can also see every device in the app under <b>Me &gt; Your devices</b>. This link works once, for 7 days.</td></tr>
</table></td></tr></table></body></html>`;
}

function emailText(c: Claim): string {
  return `New sign-in to your CampusLink account\n\nDevice: ${c.device}\nWhen: ${c.at_text}${c.ip ? `\nNetwork address: ${c.ip}` : ""}\n\n` +
    `If this was you, do nothing.\nIf it wasn't you, sign out every device: ${secureLink(c.token)}\n`;
}

async function sendEmails(ids: string[]): Promise<Response> {
  const key = Deno.env.get("BREVO_API_KEY");
  // No key yet: stop before claiming, so the emails can still go later.
  if (!key) return json({ sent: 0, note: "BREVO_API_KEY is not set" });
  const claims = await rpc<Claim[]>("claim_signin_emails", { p_ids: ids });
  let sent = 0, failed = 0;
  for (const c of claims ?? []) {
    const res = await fetch("https://api.brevo.com/v3/smtp/email", {
      method: "POST",
      headers: { "api-key": key, "Content-Type": "application/json", accept: "application/json" },
      body: JSON.stringify({
        sender: SENDER,
        to: [{ email: c.email, name: c.name }],
        subject: "New sign-in to your CampusLink account",
        htmlContent: emailHtml(c),
        textContent: emailText(c),
        tags: ["security"],
      }),
    });
    if (res.ok) sent++;
    else {
      failed++;
      console.error("Brevo", res.status, (await res.text()).slice(0, 300));
    }
  }
  return json({ sent, failed });
}

const validToken = (t: string | null): t is string => !!t && /^[0-9a-f]{48}$/.test(t);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Use POST" }, 405);
  try {
    const body = await req.json().catch(() => null);
    if (body && "secure" in body) {
      const t = typeof body.secure === "string" ? body.secure : null;
      if (!validToken(t)) return json({ result: "invalid" }, 400);
      return json({ result: await rpc<string>("secure_account", { p_token: t }) });
    }
    const ids = Array.isArray(body?.ids) ? body.ids.filter((x: unknown) => typeof x === "string").slice(0, 200) : [];
    if (ids.length === 0) return json({ sent: 0 });
    return await sendEmails(ids);
  } catch (e) {
    console.error(e);
    return json({ error: "Something went wrong" }, 500);
  }
});
