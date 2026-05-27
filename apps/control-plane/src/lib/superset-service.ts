import { getSpiceNamespace } from "@/lib/config";
import {
  waitForInstanceDeployReady,
  type WaitForDeployReadyOptions,
} from "@/lib/instance-readiness";

/** Display name for the Superset “database” (Flight SQL → Spice). */
export function supersetSpiceDatabaseLabel(instanceName: string): string {
  return `Spice (${instanceName})`;
}

/** In-cluster Flight SQL endpoint for the Spice Helm release (see charts/spice-instance templates). */
export function spiceFlightSqlSqlalchemyUri(instanceName: string, spiceNamespace: string): string {
  const host = `${instanceName}-spiceai.${spiceNamespace}.svc.cluster.local`;
  // Spice OSS Flight SQL + DataFusion; requires flightsql-dbapi in the Superset image (see addon bootstrapScript).
  return `datafusion+flightsql://${host}:50051?insecure=true`;
}

function supersetBaseUrl(): string | null {
  const u = process.env.SUPERSET_URL?.trim();
  if (!u) return null;
  return u.replace(/\/$/, "");
}

function supersetCredentials(): { username: string; password: string } | null {
  const password = process.env.SUPERSET_PASSWORD?.trim();
  if (!password) return null;
  const username = process.env.SUPERSET_USERNAME?.trim() || "admin";
  return { username, password };
}

export function isSupersetIntegrationReady(): boolean {
  return Boolean(supersetBaseUrl() && supersetCredentials());
}

type LoginJson = { access_token?: string; message?: string };

type CsrfJson = { result?: string; message?: string };

/** Cookies + JWT + CSRF for mutating Superset API calls (POST/DELETE require X-CSRFToken). */
type SupersetSession = {
  base: string;
  token: string;
  csrfToken: string;
  cookieHeader: string;
};

function collectSetCookieHeaders(res: Response): string[] {
  if (typeof res.headers.getSetCookie === "function") {
    const cookies = res.headers.getSetCookie();
    if (cookies.length > 0) return cookies;
  }
  const raw = res.headers.get("set-cookie");
  return raw ? [raw] : [];
}

function mergeCookieHeader(existing: string, res: Response): string {
  const jar = new Map<string, string>();
  for (const part of existing.split(";")) {
    const trimmed = part.trim();
    if (!trimmed) continue;
    const eq = trimmed.indexOf("=");
    if (eq > 0) jar.set(trimmed.slice(0, eq), trimmed.slice(eq + 1));
  }
  for (const raw of collectSetCookieHeaders(res)) {
    const first = raw.split(";")[0]?.trim();
    if (!first) continue;
    const eq = first.indexOf("=");
    if (eq > 0) jar.set(first.slice(0, eq), first.slice(eq + 1));
  }
  return Array.from(jar.entries())
    .map(([k, v]) => `${k}=${v}`)
    .join("; ");
}

async function openSupersetSession(
  base: string,
  username: string,
  password: string,
): Promise<SupersetSession> {
  let cookieHeader = "";
  const loginRes = await fetch(`${base}/api/v1/security/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      username,
      password,
      provider: "db",
      refresh: true,
    }),
  });
  cookieHeader = mergeCookieHeader(cookieHeader, loginRes);
  const loginJson = (await loginRes.json().catch(() => ({}))) as LoginJson;
  if (!loginRes.ok || !loginJson.access_token) {
    const msg = loginJson.message ?? loginRes.statusText;
    throw new Error(`Superset login failed (${loginRes.status}): ${msg}`);
  }
  const token = loginJson.access_token;

  const csrfRes = await fetch(`${base}/api/v1/security/csrf_token/`, {
    headers: {
      Authorization: `Bearer ${token}`,
      ...(cookieHeader ? { Cookie: cookieHeader } : {}),
    },
  });
  cookieHeader = mergeCookieHeader(cookieHeader, csrfRes);
  const csrfJson = (await csrfRes.json().catch(() => ({}))) as CsrfJson;
  if (!csrfRes.ok || !csrfJson.result) {
    const msg = csrfJson.message ?? csrfRes.statusText;
    throw new Error(`Superset CSRF token failed (${csrfRes.status}): ${msg}`);
  }

  // POST/DELETE require the session cookie issued with the CSRF token (Bearer alone is not enough).
  if (!cookieHeader.includes("session=")) {
    throw new Error(
      "Superset did not return a session cookie after CSRF handshake (check SUPERSET_URL and admin credentials)",
    );
  }

  return { base, token, csrfToken: csrfJson.result, cookieHeader };
}

function supersetReadHeaders(session: SupersetSession): Record<string, string> {
  return {
    Authorization: `Bearer ${session.token}`,
    ...(session.cookieHeader ? { Cookie: session.cookieHeader } : {}),
  };
}

function supersetWriteHeaders(session: SupersetSession): Record<string, string> {
  return {
    ...supersetReadHeaders(session),
    "X-CSRFToken": session.csrfToken,
    Referer: `${session.base}/`,
    "Content-Type": "application/json",
  };
}

type DatabaseRow = { id: number; database_name?: string; sqlalchemy_uri?: string };

type DatabaseListJson = { result?: DatabaseRow[] };

async function listDatabases(session: SupersetSession): Promise<DatabaseRow[]> {
  // Superset FAB list uses Rison in `q` (see REST API docs). One page is enough for typical lab sizes.
  const q = encodeURIComponent("(page:0,page_size:500)");
  const res = await fetch(`${session.base}/api/v1/database/?q=${q}`, {
    headers: supersetReadHeaders(session),
  });
  if (!res.ok) {
    const t = await res.text();
    throw new Error(`Superset list databases failed (${res.status}): ${t.slice(0, 500)}`);
  }
  const data = (await res.json()) as DatabaseListJson;
  return data.result ?? [];
}

async function createDatabase(
  session: SupersetSession,
  body: Record<string, unknown>,
): Promise<{ id: number }> {
  const res = await fetch(`${session.base}/api/v1/database/`, {
    method: "POST",
    headers: supersetWriteHeaders(session),
    body: JSON.stringify(body),
  });
  const data = (await res.json().catch(() => ({}))) as {
    id?: number;
    result?: { id?: number };
    message?: string;
    errors?: unknown;
  };
  const id = data.id ?? data.result?.id;
  if (!res.ok || id == null) {
    const msg = typeof data.message === "string" ? data.message : JSON.stringify(data.errors ?? data);
    throw new Error(`Superset create database failed (${res.status}): ${msg}`);
  }
  return { id };
}

async function deleteDatabase(session: SupersetSession, id: number): Promise<void> {
  const res = await fetch(`${session.base}/api/v1/database/${id}`, {
    method: "DELETE",
    headers: supersetWriteHeaders(session),
  });
  if (!res.ok && res.status !== 404) {
    const t = await res.text();
    throw new Error(`Superset delete database failed (${res.status}): ${t.slice(0, 500)}`);
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

export type SpiceInstanceSupersetStatus =
  | {
      configured: true;
      registered: boolean;
      databaseName: string;
      sqlalchemyUri: string;
      databaseId?: number;
    }
  | { configured: false; reason: string };

/**
 * Looks up whether a Superset SQL Lab database exists for this instance.
 */
export async function getSpiceInstanceSupersetStatus(
  instanceName: string,
): Promise<SpiceInstanceSupersetStatus> {
  const base = supersetBaseUrl();
  if (!base) {
    return { configured: false, reason: "SUPERSET_URL is not set" };
  }
  const cred = supersetCredentials();
  if (!cred) {
    return { configured: false, reason: "SUPERSET_PASSWORD is not set" };
  }

  const databaseName = supersetSpiceDatabaseLabel(instanceName);
  const sqlalchemyUri = spiceFlightSqlSqlalchemyUri(instanceName, getSpiceNamespace());

  try {
    const session = await openSupersetSession(base, cred.username, cred.password);
    const existing = await listDatabases(session);
    const row = existing.find((r) => r.database_name === databaseName);
    if (row) {
      return {
        configured: true,
        registered: true,
        databaseName,
        sqlalchemyUri,
        databaseId: row.id,
      };
    }
    return {
      configured: true,
      registered: false,
      databaseName,
      sqlalchemyUri,
    };
  } catch (e) {
    const err = e instanceof Error ? e.message : String(e);
    return { configured: false, reason: err };
  }
}

export type SupersetRegisterOutcome =
  | { ok: true; databaseId: number; created: boolean }
  | { ok: false; skipped: true; reason: string }
  | { ok: false; skipped: false; error: string };

/**
 * Registers a Superset SQL Lab “database” pointing at this instance’s Flight SQL port.
 * Short retries for transient Superset API errors only (call after deploy is ready).
 */
export async function registerSpiceInstanceInSuperset(instanceName: string): Promise<SupersetRegisterOutcome> {
  const base = supersetBaseUrl();
  if (!base) {
    return { ok: false, skipped: true, reason: "SUPERSET_URL is not set" };
  }
  const cred = supersetCredentials();
  if (!cred) {
    return { ok: false, skipped: true, reason: "SUPERSET_PASSWORD is not set" };
  }

  const databaseName = supersetSpiceDatabaseLabel(instanceName);
  const sqlalchemyUri = spiceFlightSqlSqlalchemyUri(instanceName, getSpiceNamespace());
  const payload = {
    database_name: databaseName,
    sqlalchemy_uri: sqlalchemyUri,
    expose_in_sqllab: true,
    allow_ctas: false,
    allow_cvas: false,
    allow_dml: false,
    allow_file_upload: false,
    configuration_method: "sqlalchemy_form",
  };

  const maxAttempts = 3;
  let lastErr: string | undefined;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      const session = await openSupersetSession(base, cred.username, cred.password);
      const existing = await listDatabases(session);
      const row = existing.find((r) => r.database_name === databaseName);
      if (row) {
        return { ok: true, databaseId: row.id, created: false };
      }
      const { id } = await createDatabase(session, payload);
      return { ok: true, databaseId: id, created: true };
    } catch (e) {
      lastErr = e instanceof Error ? e.message : String(e);
      if (attempt < maxAttempts) await sleep(2000);
    }
  }
  return { ok: false, skipped: false, error: lastErr ?? "unknown error" };
}

export type SupersetRegisterWhenReadyOutcome =
  | SupersetRegisterOutcome
  | { ok: false; skipped: false; error: string; deployTimedOut: true };

export type RegisterWhenReadyOptions = WaitForDeployReadyOptions;

/**
 * Waits for Argo CD Synced+Healthy, then registers the Superset database.
 */
export async function registerSpiceInstanceInSupersetWhenReady(
  instanceName: string,
  opts?: RegisterWhenReadyOptions,
): Promise<SupersetRegisterWhenReadyOutcome> {
  const wait = await waitForInstanceDeployReady(instanceName, opts);
  if (!wait.ready) {
    return {
      ok: false,
      skipped: false,
      error: `Instance deploy not ready within timeout (sync=${wait.status.syncStatus ?? "unknown"}, health=${wait.status.healthStatus ?? "unknown"})`,
      deployTimedOut: true,
    };
  }
  return registerSpiceInstanceInSuperset(instanceName);
}

export type SupersetUnregisterOutcome =
  | { ok: true; deleted: boolean }
  | { ok: false; skipped: true; reason: string }
  | { ok: false; skipped: false; error: string };

export async function unregisterSpiceInstanceFromSuperset(instanceName: string): Promise<SupersetUnregisterOutcome> {
  const base = supersetBaseUrl();
  if (!base) {
    return { ok: false, skipped: true, reason: "SUPERSET_URL is not set" };
  }
  const cred = supersetCredentials();
  if (!cred) {
    return { ok: false, skipped: true, reason: "SUPERSET_PASSWORD is not set" };
  }
  const databaseName = supersetSpiceDatabaseLabel(instanceName);
  try {
    const session = await openSupersetSession(base, cred.username, cred.password);
    const existing = await listDatabases(session);
    const row = existing.find((r) => r.database_name === databaseName);
    if (!row) return { ok: true, deleted: false };
    await deleteDatabase(session, row.id);
    return { ok: true, deleted: true };
  } catch (e) {
    const err = e instanceof Error ? e.message : String(e);
    return { ok: false, skipped: false, error: err };
  }
}
