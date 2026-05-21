import Link from "next/link";
import type { InstanceListEntry } from "@/lib/github-service";
import { listInstancesWithUrls } from "@/lib/github-service";

export const dynamic = "force-dynamic";

export default async function HomePage() {
  let instances: InstanceListEntry[] = [];
  let error: string | null = null;
  try {
    instances = await listInstancesWithUrls();
  } catch (e) {
    error = e instanceof Error ? e.message : "Unknown error";
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold">Instances</h1>
        <p className="mt-1 text-sm text-neutral-400">
          Git-backed folders under <code className="text-neutral-200">instances/&lt;name&gt;/</code>. Argo CD
          syncs each to the cluster.
        </p>
      </div>
      {error && (
        <div className="rounded border border-red-900 bg-red-950/50 p-3 text-sm text-red-200">
          Could not list instances: {error}
        </div>
      )}
      <ul className="divide-y divide-neutral-800 rounded border border-neutral-800">
        {instances.length === 0 && !error && (
          <li className="px-3 py-4 text-sm text-neutral-500">No instances yet.</li>
        )}
        {instances.map(({ name, url }) => (
          <li key={name} className="flex flex-col gap-1 px-3 py-3 sm:flex-row sm:items-center sm:justify-between">
            <div className="min-w-0 space-y-0.5">
              <span className="font-mono text-sm">{name}</span>
              {url ? (
                <a
                  href={url}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="block truncate text-xs text-emerald-400/90 hover:text-emerald-300"
                >
                  {url}
                </a>
              ) : (
                <span className="text-xs text-neutral-500">No ingress host in values.yaml</span>
              )}
            </div>
            <Link
              href={`/instances/${encodeURIComponent(name)}`}
              className="shrink-0 text-sm text-sky-400 hover:text-sky-300"
            >
              Open
            </Link>
          </li>
        ))}
      </ul>
    </div>
  );
}
