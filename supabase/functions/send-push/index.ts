// send-push: turns new CampusLink notifications into phone alerts (Firebase Cloud Messaging).
//
// Called by the notifications_push trigger with {"ids": [...]}. It needs no
// login: claim_push_batch only ever sends a notification once, to its owner,
// within 15 minutes of it being made, so a stranger calling this can't send
// anything that wasn't already going to be sent.
//
// Secret: FCM_SERVICE_ACCOUNT = the whole Firebase service-account JSON file.

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

type Row = {
  notification_id: string;
  token: string;
  title: string;
  body: string;
  link: string | null;
  kind: string;
  urgent: boolean;
};

type ServiceAccount = { project_id: string; client_email: string; private_key: string };

let account: ServiceAccount | null = null;
let cached: { token: string; until: number } | null = null;

function serviceAccount(): ServiceAccount {
  if (account) return account;
  const raw = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (!raw) throw new Error("FCM_SERVICE_ACCOUNT is not set");
  account = JSON.parse(raw) as ServiceAccount;
  return account;
}

const b64url = (data: Uint8Array | string) => {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};

/// A Google access token for FCM, kept for 50 minutes.
async function accessToken(): Promise<string> {
  if (cached && cached.until > Date.now()) return cached.token;
  const sa = serviceAccount();
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const pem = sa.private_key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"],
  );
  const sig = new Uint8Array(
    await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claims}`)),
  );
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${header}.${claims}.${b64url(sig)}`,
    }),
  });
  if (!res.ok) throw new Error(`Google token failed: ${res.status} ${await res.text()}`);
  const j = await res.json();
  cached = { token: j.access_token, until: Date.now() + 50 * 60 * 1000 };
  return cached.token;
}

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

/// Sends one alert. Returns "dead" when Firebase says the device code is gone.
async function send(row: Row, bearer: string, project: string): Promise<"ok" | "dead" | "failed"> {
  const message = {
    token: row.token,
    notification: { title: row.title.slice(0, 120), body: row.body.slice(0, 400) },
    data: { link: row.link ?? "/notifications", id: row.notification_id, kind: row.kind },
    android: {
      priority: "high",
      collapse_key: row.notification_id,
      notification: {
        channel_id: "campuslink_updates",
        icon: "ic_stat_campuslink",
        color: "#3B2DB3",
        tag: row.notification_id,
        default_sound: true,
      },
    },
  };
  const res = await fetch(`https://fcm.googleapis.com/v1/projects/${project}/messages:send`, {
    method: "POST",
    headers: { Authorization: `Bearer ${bearer}`, "Content-Type": "application/json" },
    body: JSON.stringify({ message }),
  });
  if (res.ok) return "ok";
  const text = await res.text();
  // Only drop a device when Firebase clearly says it's gone, never on our own mistakes.
  if (res.status === 404 || text.includes("UNREGISTERED")) return "dead";
  console.error("FCM", res.status, text.slice(0, 300));
  return "failed";
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Use POST", { status: 405 });
  let ids: string[] = [];
  try {
    const body = await req.json();
    ids = Array.isArray(body?.ids) ? body.ids.filter((x: unknown) => typeof x === "string").slice(0, 300) : [];
  } catch {
    return new Response("Bad body", { status: 400 });
  }
  if (ids.length === 0) return Response.json({ sent: 0 });

  try {
    // No key yet: stop before claiming, so nothing is marked as sent.
    serviceAccount();
    const rows = await rpc<Row[]>("claim_push_batch", { p_ids: ids });
    if (!rows?.length) return Response.json({ sent: 0 });
    const bearer = await accessToken();
    const project = serviceAccount().project_id;

    // 20 at a time so a big announcement doesn't flood Firebase.
    const dead: string[] = [];
    let sent = 0, failed = 0;
    for (let i = 0; i < rows.length; i += 20) {
      const results = await Promise.all(rows.slice(i, i + 20).map((r) => send(r, bearer, project)));
      results.forEach((r, k) => {
        if (r === "ok") sent++;
        else if (r === "dead") dead.push(rows[i + k].token);
        else failed++;
      });
    }
    if (dead.length) await rpc("drop_push_tokens", { p_tokens: dead });
    return Response.json({ sent, failed, dropped: dead.length });
  } catch (e) {
    console.error(e);
    return Response.json({ error: String(e).slice(0, 200) }, { status: 500 });
  }
});
