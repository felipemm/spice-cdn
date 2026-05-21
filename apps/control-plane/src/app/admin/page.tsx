"use client";

import { useCallback, useState } from "react";

export default function AdminPage() {
  const [key, setKey] = useState("");
  const [summary, setSummary] = useState<string>("");
  const [appName, setAppName] = useState("spice-example");
  const [msg, setMsg] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const headers = useCallback(() => {
    const h: Record<string, string> = {};
    if (key) h["x-admin-key"] = key;
    return h;
  }, [key]);

  const load = useCallback(async () => {
    setBusy(true);
    setMsg(null);
    try {
      const res = await fetch("/api/admin/summary", { headers: headers() });
      const text = await res.text();
      if (!res.ok) throw new Error(text);
      setSummary(JSON.stringify(JSON.parse(text), null, 2));
    } catch (e) {
      setMsg(e instanceof Error ? e.message : "Failed");
    } finally {
      setBusy(false);
    }
  }, [headers]);

  async function doAction(action: "sync" | "refresh") {
    setBusy(true);
    setMsg(null);
    try {
      const res = await fetch("/api/admin/summary", {
        method: "POST",
        headers: { ...headers(), "Content-Type": "application/json" },
        body: JSON.stringify({ action, application: appName }),
      });
      const text = await res.text();
      if (!res.ok) throw new Error(text);
      const j = JSON.parse(text) as { result?: unknown };
      setMsg(`${action} requested.`);
      setSummary(JSON.stringify(j.result ?? j, null, 2));
    } catch (e) {
      setMsg(e instanceof Error ? e.message : "Failed");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold text-amber-100">Admin</h1>
        <p className="mt-1 text-sm text-neutral-400">
          Paste the <code className="text-neutral-200">ADMIN_API_KEY</code> configured in the cluster Secret. Never
          share it or commit it to Git.
        </p>
      </div>
      <div className="flex flex-wrap items-end gap-3">
        <div>
          <label className="block text-xs text-neutral-500">Admin API key</label>
          <input
            type="password"
            className="mt-1 w-72 rounded border border-neutral-700 bg-neutral-900 px-2 py-1.5 font-mono text-sm"
            value={key}
            onChange={(e) => setKey(e.target.value)}
            autoComplete="off"
          />
        </div>
        <button
          type="button"
          onClick={() => void load()}
          disabled={busy}
          className="rounded bg-amber-700 px-3 py-2 text-sm text-white hover:bg-amber-600 disabled:opacity-50"
        >
          Load stack summary
        </button>
      </div>
      <div className="flex flex-wrap items-end gap-3">
        <div>
          <label className="block text-xs text-neutral-500">Argo Application name</label>
          <input
            className="mt-1 w-72 rounded border border-neutral-700 bg-neutral-900 px-2 py-1.5 font-mono text-sm"
            value={appName}
            onChange={(e) => setAppName(e.target.value)}
          />
        </div>
        <button
          type="button"
          onClick={() => void doAction("refresh")}
          disabled={busy}
          className="rounded border border-neutral-600 px-3 py-2 text-sm hover:bg-neutral-900 disabled:opacity-50"
        >
          Refresh app
        </button>
        <button
          type="button"
          onClick={() => void doAction("sync")}
          disabled={busy}
          className="rounded bg-sky-700 px-3 py-2 text-sm text-white hover:bg-sky-600 disabled:opacity-50"
        >
          Sync app
        </button>
      </div>
      {msg && <p className="text-sm text-neutral-300">{msg}</p>}
      <pre className="max-h-[600px] overflow-auto rounded border border-neutral-800 bg-neutral-900 p-3 text-xs text-neutral-200">
        {summary || "// summary appears here"}
      </pre>
    </div>
  );
}
