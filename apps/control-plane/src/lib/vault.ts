import { getVaultConfig } from "@/lib/config";

/** KV v2 path under mount `secret` (ESO / control-plane convention). */
export function instanceVaultPath(name: string): string {
  return `spice/instances/${name}`;
}

export function isVaultIntegrationReady(): boolean {
  return Boolean(getVaultConfig().token);
}

function vaultFetchErrorHint(err: unknown): string {
  if (err instanceof TypeError && err.message === "fetch failed") {
    const cause = "cause" in err && err.cause != null ? ` (${String(err.cause)})` : "";
    return `Vault network error${cause}. Check VAULT_ADDR from inside the cluster (e.g. http://vault.vault.svc.cluster.local:8200 for release "vault" in namespace "vault").`;
  }
  return err instanceof Error ? err.message : String(err);
}

/**
 * Vault KV v2 helpers. Mount is assumed to be `secret` (path prefix secret/data/...).
 */
export async function vaultReadData(path: string): Promise<Record<string, string>> {
  const { addr, token } = getVaultConfig();
  if (!token) {
    throw new Error("VAULT_TOKEN is not configured.");
  }
  const url = `${addr.replace(/\/$/, "")}/v1/secret/data/${path.replace(/^\/+/, "")}`;
  let res: Response;
  try {
    res = await fetch(url, {
      headers: { "X-Vault-Token": token },
      cache: "no-store",
    });
  } catch (e) {
    throw new Error(vaultFetchErrorHint(e));
  }
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Vault read failed (${res.status}): ${text}`);
  }
  const json = (await res.json()) as { data?: { data?: Record<string, string> } };
  return json.data?.data ?? {};
}

export async function vaultWriteData(path: string, data: Record<string, string>) {
  const { addr, token } = getVaultConfig();
  if (!token) {
    throw new Error("VAULT_TOKEN is not configured.");
  }
  const url = `${addr.replace(/\/$/, "")}/v1/secret/data/${path.replace(/^\/+/, "")}`;
  let res: Response;
  try {
    res = await fetch(url, {
      method: "POST",
      headers: {
        "X-Vault-Token": token,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ data }),
      cache: "no-store",
    });
  } catch (e) {
    throw new Error(vaultFetchErrorHint(e));
  }
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Vault write failed (${res.status}): ${text}`);
  }
}

/** Permanently removes all KV v2 versions at `path` (metadata delete). */
export async function vaultDeleteMetadata(path: string): Promise<boolean> {
  const { addr, token } = getVaultConfig();
  if (!token) {
    throw new Error("VAULT_TOKEN is not configured.");
  }
  const url = `${addr.replace(/\/$/, "")}/v1/secret/metadata/${path.replace(/^\/+/, "")}`;
  let res: Response;
  try {
    res = await fetch(url, {
      method: "DELETE",
      headers: { "X-Vault-Token": token },
      cache: "no-store",
    });
  } catch (e) {
    throw new Error(vaultFetchErrorHint(e));
  }
  if (res.status === 404) return false;
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Vault delete failed (${res.status}): ${text}`);
  }
  return true;
}

export type VaultDeleteOutcome =
  | { ok: true; deleted: boolean }
  | { ok: false; skipped: true; reason: string }
  | { ok: false; skipped: false; error: string };

export async function deleteInstanceVaultSecrets(instanceName: string): Promise<VaultDeleteOutcome> {
  if (!isVaultIntegrationReady()) {
    return { ok: false, skipped: true, reason: "VAULT_TOKEN is not configured" };
  }
  try {
    const deleted = await vaultDeleteMetadata(instanceVaultPath(instanceName));
    return { ok: true, deleted };
  } catch (e) {
    const err = e instanceof Error ? e.message : String(e);
    return { ok: false, skipped: false, error: err };
  }
}

export async function vaultHealth(): Promise<unknown> {
  const { addr } = getVaultConfig();
  const url = `${addr.replace(/\/$/, "")}/v1/sys/health?standbyok=true`;
  const res = await fetch(url, { cache: "no-store" });
  const text = await res.text();
  try {
    return JSON.parse(text);
  } catch {
    return { raw: text, status: res.status };
  }
}
