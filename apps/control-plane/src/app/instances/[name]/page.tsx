"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import Link from "next/link";
import { ValuesEditor } from "@/components/ValuesEditor";

type SupersetStatusResponse = {
  integrationReady?: boolean;
  reason?: string;
  deployReady?: boolean;
  registered?: boolean;
  argo?: { syncStatus?: string; healthStatus?: string };
  superset?:
    | {
        configured: true;
        registered: boolean;
        databaseName: string;
        sqlalchemyUri: string;
        databaseId?: number;
      }
    | { configured: false; reason: string };
  error?: string;
};

export default function InstanceDetailPage() {
  const params = useParams<{ name: string }>();
  const router = useRouter();
  const name = decodeURIComponent(params.name);

  const [yaml, setYaml] = useState("");
  const [sha, setSha] = useState<string | null>(null);
  const [secretsJson, setSecretsJson] = useState("{}");
  const [argo, setArgo] = useState<string>("");
  const [supersetStatus, setSupersetStatus] = useState<SupersetStatusResponse | null>(null);
  const [msg, setMsg] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [supersetBusy, setSupersetBusy] = useState(false);
  const autoRegisterAttempted = useRef(false);

  const loadSupersetStatus = useCallback(async () => {
    const res = await fetch(`/api/instances/${encodeURIComponent(name)}/superset`);
    const data = (await res.json()) as SupersetStatusResponse;
    if (!res.ok) throw new Error(data.error ?? res.statusText);
    setSupersetStatus(data);
    return data;
  }, [name]);

  useEffect(() => {
    void (async () => {
      try {
        const [v, a, s] = await Promise.all([
          fetch(`/api/instances/${encodeURIComponent(name)}`).then((r) => r.json()),
          fetch(`/api/instances/${encodeURIComponent(name)}/argo`).then((r) => r.json()),
          fetch(`/api/instances/${encodeURIComponent(name)}/secrets`).then((r) => r.json()),
        ]);
        if (v.error) throw new Error(v.error);
        setYaml(v.content ?? "");
        setSha(v.sha ?? null);
        setArgo(JSON.stringify(a.application ?? a, null, 2));
        setSecretsJson(JSON.stringify(s.data ?? {}, null, 2));
      } catch (e) {
        setMsg(e instanceof Error ? e.message : "Load failed");
      }
    })();
  }, [name]);

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      try {
        await loadSupersetStatus();
      } catch (e) {
        if (!cancelled) {
          setSupersetStatus({ error: e instanceof Error ? e.message : "Superset status failed" });
        }
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [loadSupersetStatus]);

  const supersetPending =
    supersetStatus?.integrationReady === true &&
    supersetStatus.registered !== true;

  useEffect(() => {
    if (!supersetPending) return;
    const id = setInterval(() => {
      void loadSupersetStatus().catch(() => {});
    }, 5000);
    return () => clearInterval(id);
  }, [supersetPending, loadSupersetStatus]);

  const registerSuperset = useCallback(
    async (waitForReady: boolean) => {
      setSupersetBusy(true);
      setMsg(null);
      try {
        const res = await fetch(`/api/instances/${encodeURIComponent(name)}/superset`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ waitForReady }),
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.warning ?? data.error ?? res.statusText);
        await loadSupersetStatus();
        if (data.created) {
          setMsg(`Superset connection created (database id ${data.databaseId}).`);
        } else if (data.registered) {
          setMsg("Superset connection already exists.");
        }
      } catch (e) {
        setMsg(e instanceof Error ? e.message : "Superset registration failed");
      } finally {
        setSupersetBusy(false);
      }
    },
    [name, loadSupersetStatus],
  );

  useEffect(() => {
    if (autoRegisterAttempted.current) return;
    if (!supersetStatus?.integrationReady || !supersetStatus.deployReady) return;
    if (supersetStatus.registered) return;
    autoRegisterAttempted.current = true;
    void registerSuperset(true);
  }, [supersetStatus, registerSuperset]);

  async function save() {
    setBusy(true);
    setMsg(null);
    try {
      const res = await fetch(`/api/instances/${encodeURIComponent(name)}`, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ content: yaml, sha }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? res.statusText);
      const v = await fetch(`/api/instances/${encodeURIComponent(name)}`).then((r) => r.json());
      setSha(v.sha ?? null);
      setMsg("Saved to GitOps repository.");
    } catch (e) {
      setMsg(e instanceof Error ? e.message : "Save failed");
    } finally {
      setBusy(false);
    }
  }

  async function saveSecrets() {
    setBusy(true);
    setMsg(null);
    try {
      const data = JSON.parse(secretsJson) as Record<string, string>;
      const res = await fetch(`/api/instances/${encodeURIComponent(name)}/secrets`, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ data }),
      });
      const j = await res.json();
      if (!res.ok) throw new Error(j.error ?? res.statusText);
      setMsg("Vault KV updated.");
    } catch (e) {
      setMsg(e instanceof Error ? e.message : "Vault update failed");
    } finally {
      setBusy(false);
    }
  }

  async function remove() {
    if (!confirm(`Delete instance ${name} from Git?`)) return;
    setBusy(true);
    try {
      const res = await fetch(`/api/instances/${encodeURIComponent(name)}`, { method: "DELETE" });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? res.statusText);
      router.push("/");
    } catch (e) {
      setMsg(e instanceof Error ? e.message : "Delete failed");
    } finally {
      setBusy(false);
    }
  }

  const supersetDb =
    supersetStatus?.superset && "databaseName" in supersetStatus.superset
      ? supersetStatus.superset
      : null;

  return (
    <div className="space-y-8">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="font-mono text-xl">instances/{name}</h1>
        <div className="flex gap-2">
          <button
            type="button"
            onClick={save}
            disabled={busy}
            className="rounded bg-sky-600 px-3 py-1.5 text-sm text-white hover:bg-sky-500 disabled:opacity-50"
          >
            Save values.yaml
          </button>
          <button
            type="button"
            onClick={remove}
            disabled={busy}
            className="rounded border border-red-800 px-3 py-1.5 text-sm text-red-200 hover:bg-red-950 disabled:opacity-50"
          >
            Delete
          </button>
        </div>
      </div>
      {msg && <p className="text-sm text-neutral-300">{msg}</p>}

      <section className="space-y-2">
        <h2 className="text-sm font-medium text-neutral-400">values.yaml</h2>
        <ValuesEditor value={yaml} onChange={setYaml} />
      </section>

      <section className="space-y-2">
        <h2 className="text-sm font-medium text-neutral-400">Vault KV (JSON object of string values)</h2>
        <textarea
          className="h-40 w-full rounded border border-neutral-700 bg-neutral-900 p-2 font-mono text-xs"
          value={secretsJson}
          onChange={(e) => setSecretsJson(e.target.value)}
        />
        <button
          type="button"
          onClick={saveSecrets}
          disabled={busy}
          className="rounded bg-emerald-700 px-3 py-1.5 text-sm text-white hover:bg-emerald-600 disabled:opacity-50"
        >
          Push to Vault
        </button>
      </section>

      <section className="space-y-3 rounded border border-neutral-800 bg-neutral-950 p-4">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h2 className="text-sm font-medium text-neutral-300">Superset connection</h2>
          {supersetStatus?.integrationReady && (
            <Link href="/cluster-urls" className="text-xs text-sky-400 hover:underline">
              Open cluster URLs
            </Link>
          )}
        </div>
        {supersetStatus?.error && (
          <p className="text-sm text-red-400">{supersetStatus.error}</p>
        )}
        {supersetStatus?.integrationReady === false && (
          <p className="text-sm text-neutral-400">
            Superset integration is not configured on the control plane (
            {supersetStatus.reason ?? "SUPERSET_URL / SUPERSET_PASSWORD missing"}).
          </p>
        )}
        {supersetStatus?.integrationReady && (
          <dl className="grid gap-2 text-sm sm:grid-cols-2">
            <div>
              <dt className="text-neutral-500">Argo sync</dt>
              <dd className="font-mono text-neutral-200">
                {supersetStatus.argo?.syncStatus ?? "—"}
              </dd>
            </div>
            <div>
              <dt className="text-neutral-500">Argo health</dt>
              <dd className="font-mono text-neutral-200">
                {supersetStatus.argo?.healthStatus ?? "—"}
              </dd>
            </div>
            <div>
              <dt className="text-neutral-500">Deploy ready</dt>
              <dd className="text-neutral-200">{supersetStatus.deployReady ? "yes" : "no"}</dd>
            </div>
            <div>
              <dt className="text-neutral-500">Superset database</dt>
              <dd className="font-mono text-neutral-200">
                {supersetStatus.registered && supersetDb
                  ? `${supersetDb.databaseName} (id ${supersetDb.databaseId ?? "?"})`
                  : "not registered"}
              </dd>
            </div>
          </dl>
        )}
        {supersetStatus?.integrationReady && !supersetStatus.registered && (
          <p className="text-xs text-neutral-500">
            {supersetStatus.deployReady
              ? "Instance is ready; registering Superset connection…"
              : "Waiting for Argo CD Synced + Healthy before creating the Superset connection."}
          </p>
        )}
        {supersetStatus?.integrationReady && (
          <button
            type="button"
            onClick={() => void registerSuperset(true)}
            disabled={busy || supersetBusy || supersetStatus.registered === true}
            className="rounded bg-violet-700 px-3 py-1.5 text-sm text-white hover:bg-violet-600 disabled:opacity-50"
          >
            {supersetBusy ? "Creating…" : "Create Superset connection"}
          </button>
        )}
      </section>

      <section className="space-y-2">
        <h2 className="text-sm font-medium text-neutral-400">Argo CD Application (read-only)</h2>
        <pre className="max-h-80 overflow-auto rounded border border-neutral-800 bg-neutral-900 p-3 text-xs text-neutral-200">
          {argo || "…"}
        </pre>
      </section>
    </div>
  );
}
