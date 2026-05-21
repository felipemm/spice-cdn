/** Parse Kubernetes resource quantities (subset: cpu millicores, binary SI memory). */

export function parseCpuToMillicores(q: string | undefined): number {
  if (!q || typeof q !== "string") return 0;
  const s = q.trim();
  if (!s) return 0;
  if (s.endsWith("n")) {
    return Number(s.slice(0, -1)) / 1e6 / 1000;
  }
  if (s.endsWith("u")) {
    return Number(s.slice(0, -1)) / 1000;
  }
  if (s.endsWith("m")) {
    return Number(s.slice(0, -1));
  }
  const n = Number(s);
  if (!Number.isFinite(n)) return 0;
  return n * 1000;
}

export function parseMemoryToGiB(q: string | undefined): number {
  if (!q || typeof q !== "string") return 0;
  const s = q.trim();
  if (!s) return 0;
  const units: Record<string, number> = {
    Ki: 1 / (1024 * 1024),
    Mi: 1 / 1024,
    Gi: 1,
    Ti: 1024,
    K: 1 / (1000 * 1000 * 1000),
    M: 1 / (1000 * 1000),
    G: 1 / 1000,
    T: 1000,
  };
  for (const [suffix, mult] of Object.entries(units)) {
    if (s.endsWith(suffix)) {
      const n = Number(s.slice(0, -suffix.length));
      return Number.isFinite(n) ? n * mult : 0;
    }
  }
  const n = Number(s);
  return Number.isFinite(n) ? n / (1024 * 1024 * 1024) : 0;
}

export function millicoresToCpuCores(m: number): number {
  return m / 1000;
}
