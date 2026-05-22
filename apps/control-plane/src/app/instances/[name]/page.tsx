"use client";

import { useEffect, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { ValuesEditor } from "@/components/ValuesEditor";

export default function InstanceDetailPage() {
  const params = useParams<{ name: string }>();
  const router = useRouter();
  const name = decodeURIComponent(params.name);

  const [yaml, setYaml] = useState("");
  const [sha, setSha] = useState<string | null>(null);
  const [secretsJson, setSecretsJson] = useState("{}");
  const [argo, setArgo] = useState<string>("");
  const [msg, setMsg] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

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

      <section className="space-y-2">
        <h2 className="text-sm font-medium text-neutral-400">Argo CD Application (read-only)</h2>
        <pre className="max-h-80 overflow-auto rounded border border-neutral-800 bg-neutral-900 p-3 text-xs text-neutral-200">
          {argo || "…"}
        </pre>
      </section>
    </div>
  );
}
