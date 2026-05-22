import { assertGitopsRepoConfigured, getSpiceNamespace } from "@/lib/config";
import { createOctokit, listInstanceNames } from "@/lib/github-service";
import { listPodsInNamespace, listStatefulSetsInNamespace } from "@/lib/k8s";
import { parseInstanceValuesYaml } from "@/lib/instance-values";
import { millicoresToCpuCores, parseCpuToMillicores, parseMemoryToGiB } from "@/lib/k8s-quantity";
import { estimateMonthlyUsd, loadPricingFactorsFromEnv } from "@/lib/aws-pricing";
import { loadBudgetsFromFile, getBudgetForSlug, type BudgetsFile } from "@/lib/budgets";
import { fetchOpenCostAllocationBySlug } from "@/lib/opencost";
import { fetchAccountCostLast30d } from "@/lib/aws-cost-explorer";

export type SlugCostRow = {
  slug: string;
  instanceCount: number;
  declaredCpuCores: number;
  declaredMemoryGiB: number;
  estimatedMonthlyUsdDeclared: number;
  budget?: { maxInstancesPerSlug?: number; maxEstimatedMonthlyUsdPerSlug?: number };
  remainingInstances?: number;
  /** Git-level: sum of per-instance declared estimates for this slug */
  estimatedMonthlyUsdFromGit?: number;
};

export type CostSummary = {
  generatedAt: string;
  pricingFactors: { usdPerCpuCoreMonth: number; usdPerGiBMonth: number };
  global: {
    instanceCount: number;
    declaredCpuCores: number;
    declaredMemoryGiB: number;
    estimatedMonthlyUsdDeclared: number;
    livePodsInSpiceNamespace: number;
    liveCpuCoresRequested: number;
    liveMemoryGiBRequested: number;
    estimatedMonthlyUsdLive: number;
    liveStatefulSetsWithOwnerLayerSlug: number;
    /** Echo of env used for pricing / Cost Explorer (Kind as EKS) */
    awsRegion: string | null;
    costNodeInstanceType: string | null;
  };
  bySlug: SlugCostRow[];
  legacyInstancesMissingSlug: string[];
  inconsistentLabelInstances: string[];
  opencost: { rows: unknown[]; source?: string } | null;
  awsCostExplorer: Awaited<ReturnType<typeof fetchAccountCostLast30d>>;
};

function budgetsPath(): string {
  return process.env.BUDGETS_FILE ?? "/config/budgets.yaml";
}

export function loadBudgets(): BudgetsFile {
  return loadBudgetsFromFile(budgetsPath());
}

export async function buildCostSummary(): Promise<CostSummary> {
  const pricingFactors = loadPricingFactorsFromEnv();
  const budgets = loadBudgets();
  const names = await listInstanceNames();
  const octokit = createOctokit();
  const { owner, repo, branch } = assertGitopsRepoConfigured();

  const slugMap = new Map<
    string,
    { instances: string[]; cpu: number; mem: number; declaredUsd: number }
  >();
  const legacy: string[] = [];
  const inconsistent: string[] = [];

  let globalCpu = 0;
  let globalMem = 0;
  let globalUsd = 0;

  for (const name of names) {
    const path = `instances/${name}/values.yaml`;
    const res = await octokit.repos.getContent({ owner, repo, path, ref: branch });
    if (Array.isArray(res.data) || res.data.type !== "file" || !("content" in res.data)) continue;
    const content = Buffer.from(res.data.content, "base64").toString("utf8");
    const parsed = parseInstanceValuesYaml(content);
    if (!parsed.ownerLayerSlug) {
      legacy.push(name);
      continue;
    }
    if (parsed.labelsConsistent === false) {
      inconsistent.push(name);
    }
    const slug = parsed.ownerLayerSlug;
    const instUsd = estimateMonthlyUsd(parsed.cpuCores, parsed.memoryGiB, pricingFactors);
    globalCpu += parsed.cpuCores;
    globalMem += parsed.memoryGiB;
    globalUsd += instUsd;

    const cur = slugMap.get(slug) ?? { instances: [], cpu: 0, mem: 0, declaredUsd: 0 };
    cur.instances.push(name);
    cur.cpu += parsed.cpuCores;
    cur.mem += parsed.memoryGiB;
    cur.declaredUsd += instUsd;
    slugMap.set(slug, cur);
  }

  const bySlug: SlugCostRow[] = [];
  for (const [slug, v] of [...slugMap.entries()].sort((a, b) => a[0].localeCompare(b[0]))) {
    const b = getBudgetForSlug(budgets, slug);
    const maxInst = b.maxInstancesPerSlug ?? 100;
    bySlug.push({
      slug,
      instanceCount: v.instances.length,
      declaredCpuCores: v.cpu,
      declaredMemoryGiB: v.mem,
      estimatedMonthlyUsdDeclared: v.declaredUsd,
      budget: b,
      remainingInstances: Math.max(0, maxInst - v.instances.length),
      estimatedMonthlyUsdFromGit: v.declaredUsd,
    });
  }

  const live = await collectLiveSpicePods();

  let opencost: CostSummary["opencost"] = null;
  const ocBase = process.env.OPENCOST_BASE_URL?.trim();
  if (ocBase) {
    const oc = await fetchOpenCostAllocationBySlug(ocBase);
    opencost = oc ? { rows: oc.rows, source: oc.source } : { rows: [] };
  }

  const awsCostExplorer = await fetchAccountCostLast30d();

  return {
    generatedAt: new Date().toISOString(),
    pricingFactors,
    global: {
      instanceCount: names.length - legacy.length,
      declaredCpuCores: globalCpu,
      declaredMemoryGiB: globalMem,
      estimatedMonthlyUsdDeclared: globalUsd,
      livePodsInSpiceNamespace: live.podCount,
      liveCpuCoresRequested: live.cpuCores,
      liveMemoryGiBRequested: live.memoryGiB,
      estimatedMonthlyUsdLive: estimateMonthlyUsd(live.cpuCores, live.memoryGiB, pricingFactors),
      liveStatefulSetsWithOwnerLayerSlug: live.statefulSetCount,
      awsRegion: process.env.AWS_REGION?.trim() || null,
      costNodeInstanceType: process.env.COST_NODE_INSTANCE_TYPE?.trim() || null,
    },
    bySlug,
    legacyInstancesMissingSlug: legacy,
    inconsistentLabelInstances: inconsistent,
    opencost,
    awsCostExplorer,
  };
}

async function collectLiveSpicePods(): Promise<{
  podCount: number;
  cpuCores: number;
  memoryGiB: number;
  statefulSetCount: number;
}> {
  const ns = getSpiceNamespace();
  try {
    const pods = await listPodsInNamespace(ns);
    let podCount = 0;
    let cpuMillis = 0;
    let memGiB = 0;
    for (const p of pods) {
      const labels = p.metadata?.labels ?? {};
      if (!labels["owner-layer-slug"]) continue;
      podCount++;
      for (const c of p.spec?.containers ?? []) {
        const req = c.resources?.requests;
        cpuMillis += parseCpuToMillicores(req?.cpu);
        memGiB += parseMemoryToGiB(req?.memory);
      }
    }
    const sts = await listStatefulSetsInNamespace(ns);
    const statefulSetCount = sts.filter((s) => Boolean(s.metadata?.labels?.["owner-layer-slug"])).length;
    return {
      podCount,
      cpuCores: millicoresToCpuCores(cpuMillis),
      memoryGiB: memGiB,
      statefulSetCount,
    };
  } catch {
    return { podCount: 0, cpuCores: 0, memoryGiB: 0, statefulSetCount: 0 };
  }
}

export async function listInstanceSlugSummaries(): Promise<Array<{ name: string; slug: string | null }>> {
  const octokit = createOctokit();
  const { owner, repo, branch } = assertGitopsRepoConfigured();
  const names = await listInstanceNames();
  const out: Array<{ name: string; slug: string | null }> = [];
  for (const name of names) {
    const path = `instances/${name}/values.yaml`;
    try {
      const res = await octokit.repos.getContent({ owner, repo, path, ref: branch });
      if (Array.isArray(res.data) || res.data.type !== "file" || !("content" in res.data)) {
        out.push({ name, slug: null });
        continue;
      }
      const content = Buffer.from(res.data.content, "base64").toString("utf8");
      const parsed = parseInstanceValuesYaml(content);
      out.push({ name, slug: parsed.ownerLayerSlug });
    } catch {
      out.push({ name, slug: null });
    }
  }
  return out;
}
