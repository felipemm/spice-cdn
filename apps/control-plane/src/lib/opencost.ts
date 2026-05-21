/**
 * Optional OpenCost allocation (see https://www.opencost.io/).
 * Base URL example: http://opencost.opencost.svc.cluster.local:9003
 */

export type OpenCostAllocationRow = {
  ownerLayerSlug?: string;
  totalCost?: number;
  cpuCost?: number;
  ramCost?: number;
  raw?: unknown;
};

function tryParseAllocationJson(data: unknown): OpenCostAllocationRow[] {
  if (!data || typeof data !== "object") return [];
  const d = data as Record<string, unknown>;
  /** OpenCost / Kubecost variants */
  const sets = (d.data ?? d.items ?? d) as unknown;
  if (!Array.isArray(sets)) return [];
  const rows: OpenCostAllocationRow[] = [];
  for (const entry of sets) {
    if (!entry || typeof entry !== "object") continue;
    const e = entry as Record<string, unknown>;
    const name = typeof e.name === "string" ? e.name : undefined;
    const total =
      typeof e.totalCost === "number"
        ? e.totalCost
        : typeof e.totalAmortizedCost === "number"
          ? e.totalAmortizedCost
          : typeof e.cost === "number"
            ? e.cost
            : undefined;
    rows.push({
      ownerLayerSlug: name,
      totalCost: total,
      cpuCost: typeof e.cpuCost === "number" ? e.cpuCost : undefined,
      ramCost: typeof e.ramCost === "number" ? e.ramCost : undefined,
      raw: entry,
    });
  }
  return rows;
}

export async function fetchOpenCostAllocationBySlug(
  baseUrl: string,
  window = "30d",
): Promise<{ rows: OpenCostAllocationRow[]; source: string } | null> {
  const base = baseUrl.replace(/\/$/, "");
  const paths = [
    `/model/allocation?window=${encodeURIComponent(window)}&aggregate=owner-layer-slug&accumulate=true`,
    `/allocation?window=${encodeURIComponent(window)}&aggregate=owner-layer-slug&accumulate=true`,
    `/allocation/compute?window=${encodeURIComponent(window)}&aggregate=owner-layer-slug&accumulate=true`,
  ];
  for (const p of paths) {
    try {
      const res = await fetch(`${base}${p}`, { cache: "no-store" });
      if (!res.ok) continue;
      const json = (await res.json()) as unknown;
      const rows = tryParseAllocationJson(json);
      if (rows.length > 0) {
        return { rows, source: `${base}${p}` };
      }
    } catch {
      /* try next path */
    }
  }
  return null;
}
