import { NextResponse } from "next/server";
import { assertAdmin } from "@/lib/admin-auth";
import {
  listArgoApplications,
  listEventsInNamespace,
  listExternalSecrets,
  listPodsInNamespace,
  refreshArgoApplication,
  syncArgoApplication,
} from "@/lib/k8s";
import { vaultHealth } from "@/lib/vault";
import { getArgoNamespace, getGithubConfig, getSpiceNamespace } from "@/lib/config";

export async function GET(request: Request) {
  const denied = assertAdmin(request);
  if (denied) return denied;

  try {
    const argoNs = getArgoNamespace();
    const spiceNs = getSpiceNamespace();
    const [apps, eso, vault, podsArgo, podsSpice, eventsArgo, gh] = await Promise.all([
      listArgoApplications(),
      listExternalSecrets(),
      vaultHealth(),
      listPodsInNamespace(argoNs).catch(() => []),
      listPodsInNamespace(spiceNs).catch(() => []),
      listEventsInNamespace(argoNs).catch(() => []),
      Promise.resolve(getGithubConfig()),
    ]);

    return NextResponse.json({
      github: {
        configured: Boolean(gh.token && gh.owner && gh.repo),
        owner: gh.owner,
        repo: gh.repo,
        branch: gh.branch,
      },
      vault: vault,
      argocd: {
        namespace: argoNs,
        applications: apps,
        pods: podsArgo.map((p) => ({
          name: p.metadata?.name,
          phase: p.status?.phase,
        })),
        events: eventsArgo.map((e) => ({
          type: e.type,
          reason: e.reason,
          message: e.message,
          involvedObject: e.involvedObject?.name,
        })),
      },
      externalSecrets: {
        namespace: spiceNs,
        items: eso,
      },
      spice: {
        namespace: spiceNs,
        pods: podsSpice.map((p) => ({
          name: p.metadata?.name,
          phase: p.status?.phase,
        })),
      },
    });
  } catch (e) {
    const message = e instanceof Error ? e.message : "Unknown error";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}

export async function POST(request: Request) {
  const denied = assertAdmin(request);
  if (denied) return denied;
  try {
    const body = (await request.json()) as { action?: string; application?: string };
    if (!body.application) {
      return NextResponse.json({ error: "application name required" }, { status: 400 });
    }
    if (body.action === "sync") {
      const res = await syncArgoApplication(body.application);
      return NextResponse.json({ ok: true, result: res });
    }
    if (body.action === "refresh") {
      const res = await refreshArgoApplication(body.application);
      return NextResponse.json({ ok: true, result: res });
    }
    return NextResponse.json({ error: "unknown action" }, { status: 400 });
  } catch (e) {
    const message = e instanceof Error ? e.message : "Unknown error";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
