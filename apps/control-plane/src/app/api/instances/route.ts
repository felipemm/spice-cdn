import { NextResponse } from "next/server";
import { assertGitopsRepoConfigured } from "@/lib/config";
import {
  createInstance,
  createOctokit,
  listInstanceNames,
  listInstancesWithUrls,
} from "@/lib/github-service";
import { renderInstanceTemplate } from "@/lib/instance-template";
import { assertValidOwnerLayerSlug, parseInstanceValuesYaml } from "@/lib/instance-values";
import { getBudgetForSlug, loadBudgetsFromFile } from "@/lib/budgets";
import { estimateMonthlyUsd, loadPricingFactorsFromEnv } from "@/lib/aws-pricing";
import { listInstanceSlugSummaries } from "@/lib/cost-summary";

function budgetsPath(): string {
  return process.env.BUDGETS_FILE ?? "/config/budgets.yaml";
}

async function declaredMonthlyForSlug(slug: string): Promise<number> {
  const octokit = createOctokit();
  const { owner, repo, branch } = assertGitopsRepoConfigured();
  const names = await listInstanceNames();
  const pricing = loadPricingFactorsFromEnv();
  let sum = 0;
  for (const name of names) {
    const path = `instances/${name}/values.yaml`;
    const res = await octokit.repos.getContent({ owner, repo, path, ref: branch });
    if (Array.isArray(res.data) || res.data.type !== "file" || !("content" in res.data)) continue;
    const content = Buffer.from(res.data.content, "base64").toString("utf8");
    const p = parseInstanceValuesYaml(content);
    if (p.ownerLayerSlug !== slug) continue;
    sum += estimateMonthlyUsd(p.cpuCores, p.memoryGiB, pricing);
  }
  return sum;
}

export async function GET() {
  try {
    const instances = await listInstancesWithUrls();
    return NextResponse.json({ instances });
  } catch (e) {
    const message = e instanceof Error ? e.message : "Unknown error";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}

export async function POST(request: Request) {
  try {
    const body = (await request.json()) as { name?: string; ownerLayerSlug?: string };
    const name = body.name?.trim();
    const ownerLayerSlug = body.ownerLayerSlug?.trim();
    if (!name || !/^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/.test(name)) {
      return NextResponse.json(
        { error: "Invalid instance name (lowercase DNS label)." },
        { status: 400 },
      );
    }
    if (!ownerLayerSlug) {
      return NextResponse.json(
        { error: "ownerLayerSlug is required for cost attribution and cluster policy." },
        { status: 400 },
      );
    }
    try {
      assertValidOwnerLayerSlug(ownerLayerSlug);
    } catch (e) {
      const message = e instanceof Error ? e.message : "Invalid ownerLayerSlug";
      return NextResponse.json({ error: message }, { status: 400 });
    }

    const budgets = loadBudgetsFromFile(budgetsPath());
    const b = getBudgetForSlug(budgets, ownerLayerSlug);
    const summaries = await listInstanceSlugSummaries();
    const count = summaries.filter((s) => s.slug === ownerLayerSlug).length;
    const maxInst = b.maxInstancesPerSlug ?? 100;
    if (count >= maxInst) {
      return NextResponse.json(
        { error: `Budget exceeded: slug "${ownerLayerSlug}" already has ${count} instances (max ${maxInst}).` },
        { status: 409 },
      );
    }

    if (b.maxEstimatedMonthlyUsdPerSlug != null) {
      const currentUsd = await declaredMonthlyForSlug(ownerLayerSlug);
      const pricing = loadPricingFactorsFromEnv();
      const newYaml = renderInstanceTemplate(name, ownerLayerSlug);
      const newParsed = parseInstanceValuesYaml(newYaml);
      const addUsd = estimateMonthlyUsd(newParsed.cpuCores, newParsed.memoryGiB, pricing);
      if (currentUsd + addUsd > b.maxEstimatedMonthlyUsdPerSlug) {
        return NextResponse.json(
          {
            error: `Estimated monthly spend for slug "${ownerLayerSlug}" would exceed maxEstimatedMonthlyUsdPerSlug (${b.maxEstimatedMonthlyUsdPerSlug}).`,
          },
          { status: 409 },
        );
      }
    }

    const yaml = renderInstanceTemplate(name, ownerLayerSlug);
    await createInstance(name, yaml);
    return NextResponse.json({ ok: true, name, ownerLayerSlug });
  } catch (e) {
    const message = e instanceof Error ? e.message : "Unknown error";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
