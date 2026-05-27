import { headers } from "next/headers";
import Link from "next/link";
import { listInstancesWithUrls } from "@/lib/github-service";
import { staticKindClusterUrlSections } from "@/lib/kind-lab-urls";

export const dynamic = "force-dynamic";

async function requestOrigin(): Promise<string | null> {
  const h = await headers();
  const hostRaw = h.get("x-forwarded-host") ?? h.get("host");
  const host = hostRaw?.split(",")[0]?.trim() ?? null;
  if (!host) return null;
  const rawProto = h.get("x-forwarded-proto");
  const proto =
    rawProto?.split(",")[0]?.trim() ||
    (process.env.NODE_ENV === "production" ? "https" : "http");
  return `${proto}://${host}`;
}

export default async function ClusterUrlsPage() {
  const origin = await requestOrigin();
  const sections = staticKindClusterUrlSections();

  let instances: Awaited<ReturnType<typeof listInstancesWithUrls>> = [];
  let instancesError: string | null = null;
  try {
    instances = await listInstancesWithUrls();
  } catch (e) {
    instancesError = e instanceof Error ? e.message : "Unknown error";
  }

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-semibold">Cluster access URLs</h1>
        <p className="mt-1 max-w-2xl text-sm text-neutral-400">
          Quick links for the Kind lab: services fronted by ingress-nginx on{" "}
          <span className="text-neutral-300">127.0.0.1:80</span> (see{" "}
          <code className="text-neutral-200">hack/kind-config.yaml</code>). Spice instances use each
          folder&apos;s <code className="text-neutral-200">ingress.host</code> from Git.
        </p>
      </div>

      {origin && (
        <section className="space-y-3">
          <h2 className="text-lg font-medium text-neutral-200">This control plane</h2>
          <p className="text-sm text-neutral-500">Resolved from your current request (Host / forwarded headers).</p>
          <ul className="divide-y divide-neutral-800 rounded border border-neutral-800">
            <li className="flex flex-col gap-1 px-3 py-3 sm:flex-row sm:items-start sm:justify-between">
              <div className="min-w-0 space-y-1">
                <span className="text-sm font-medium text-neutral-200">App &amp; admin</span>
                <p className="text-xs text-neutral-500">Instances UI, instance editor, cost admin.</p>
              </div>
              <a
                href={origin}
                target="_blank"
                rel="noopener noreferrer"
                className="shrink-0 break-all text-sm text-emerald-400/90 hover:text-emerald-300"
              >
                {origin}
              </a>
            </li>
            <li className="flex flex-col gap-1 px-3 py-3 sm:flex-row sm:items-start sm:justify-between">
              <div className="min-w-0 space-y-1">
                <span className="text-sm font-medium text-neutral-200">Remote MCP (Streamable HTTP)</span>
                <p className="text-xs text-neutral-500">Same ingress path when the MCP sidecar is enabled.</p>
              </div>
              <a
                href={`${origin.replace(/\/$/, "")}/mcp`}
                target="_blank"
                rel="noopener noreferrer"
                className="shrink-0 break-all text-sm text-emerald-400/90 hover:text-emerald-300"
              >
                {`${origin.replace(/\/$/, "")}/mcp`}
              </a>
            </li>
          </ul>
        </section>
      )}

      {sections.map((sec) => (
        <section key={sec.id} className="space-y-3">
          <div>
            <h2 className="text-lg font-medium text-neutral-200">{sec.heading}</h2>
            {sec.description && <p className="mt-1 text-sm text-neutral-500">{sec.description}</p>}
          </div>
          <ul className="divide-y divide-neutral-800 rounded border border-neutral-800">
            {sec.rows.map((row) => (
              <li key={row.id} className="flex flex-col gap-2 px-3 py-3 sm:flex-row sm:items-start sm:justify-between">
                <div className="min-w-0 space-y-1">
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="text-sm font-medium text-neutral-200">{row.title}</span>
                    {row.optional && (
                      <span className="rounded bg-neutral-800 px-1.5 py-0.5 text-[10px] font-medium uppercase tracking-wide text-neutral-400">
                        Optional addon
                      </span>
                    )}
                  </div>
                  {row.detail && <p className="text-xs text-neutral-500">{row.detail}</p>}
                  {row.note && <p className="font-mono text-[11px] text-neutral-600">{row.note}</p>}
                </div>
                {row.href ? (
                  <a
                    href={row.href}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="shrink-0 break-all text-sm text-emerald-400/90 hover:text-emerald-300"
                  >
                    {row.href}
                  </a>
                ) : (
                  <span className="shrink-0 text-sm text-neutral-600">—</span>
                )}
              </li>
            ))}
          </ul>
        </section>
      ))}

      <section className="space-y-3">
        <div>
          <h2 className="text-lg font-medium text-neutral-200">Spice instances</h2>
          <p className="mt-1 text-sm text-neutral-500">
            From Git <code className="text-neutral-300">instances/*/values.yaml</code> — same list as the{" "}
            <Link href="/" className="text-sky-400 hover:text-sky-300">
              home page
            </Link>
            .
          </p>
        </div>
        {instancesError && (
          <div className="rounded border border-red-900 bg-red-950/50 p-3 text-sm text-red-200">
            Could not list instances: {instancesError}
          </div>
        )}
        <ul className="divide-y divide-neutral-800 rounded border border-neutral-800">
          {instances.length === 0 && !instancesError && (
            <li className="px-3 py-4 text-sm text-neutral-500">No instances yet.</li>
          )}
          {instances.map(({ name, url }) => (
            <li
              key={name}
              className="flex flex-col gap-1 px-3 py-3 sm:flex-row sm:items-center sm:justify-between"
            >
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
                Edit
              </Link>
            </li>
          ))}
        </ul>
      </section>
    </div>
  );
}
