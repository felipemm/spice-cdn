import { getVaultConfig } from "@/lib/config";

/**
 * Vault KV v2 helpers. Mount is assumed to be `secret` (path prefix secret/data/...).
 */
export async function vaultReadData(path: string): Promise<Record<string, string>> {
  const { addr, token } = getVaultConfig();
  if (!token) {
    throw new Error("VAULT_TOKEN is not configured.");
  }
  const url = `${addr.replace(/\/$/, "")}/v1/secret/data/${path.replace(/^\/+/, "")}`;
  const res = await fetch(url, {
    headers: { "X-Vault-Token": token },
    cache: "no-store",
  });
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
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "X-Vault-Token": token,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ data }),
    cache: "no-store",
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Vault write failed (${res.status}): ${text}`);
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
