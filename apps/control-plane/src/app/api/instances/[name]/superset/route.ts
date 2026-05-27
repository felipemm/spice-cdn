import { NextResponse } from "next/server";
import { getArgoApplication } from "@/lib/k8s";
import {
  isInstanceDeployReady,
  parseArgoApplicationStatus,
} from "@/lib/instance-readiness";
import {
  getSpiceInstanceSupersetStatus,
  isSupersetIntegrationReady,
  registerSpiceInstanceInSuperset,
  registerSpiceInstanceInSupersetWhenReady,
} from "@/lib/superset-service";

type Ctx = { params: Promise<{ name: string }> };

function supersetRegisterResponse(
  reg:
    | Awaited<ReturnType<typeof registerSpiceInstanceInSuperset>>
    | Awaited<ReturnType<typeof registerSpiceInstanceInSupersetWhenReady>>,
) {
  if (reg.ok) {
    return {
      registered: true as const,
      databaseId: reg.databaseId,
      created: reg.created,
    };
  }
  if (reg.skipped) {
    return { registered: false as const, warning: reg.reason };
  }
  const out: { registered: false; warning: string; deployTimedOut?: boolean } = {
    registered: false,
    warning: reg.error,
  };
  if ("deployTimedOut" in reg && reg.deployTimedOut) {
    out.deployTimedOut = true;
  }
  return out;
}

export async function GET(_request: Request, ctx: Ctx) {
  const { name } = await ctx.params;
  try {
    if (!isSupersetIntegrationReady()) {
      return NextResponse.json({
        integrationReady: false,
        reason: "SUPERSET_URL or SUPERSET_PASSWORD is not configured",
      });
    }

    let argoStatus = {};
    let deployReady = false;
    try {
      const app = await getArgoApplication(`spice-${name}`);
      argoStatus = parseArgoApplicationStatus(app);
      deployReady = isInstanceDeployReady(argoStatus);
    } catch {
      argoStatus = {};
    }

    const superset = await getSpiceInstanceSupersetStatus(name);
    const registered = superset.configured && superset.registered;

    return NextResponse.json({
      integrationReady: true,
      deployReady,
      argo: argoStatus,
      superset,
      registered,
    });
  } catch (e) {
    const message = e instanceof Error ? e.message : "Unknown error";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}

export async function POST(request: Request, ctx: Ctx) {
  const { name } = await ctx.params;
  try {
    if (!isSupersetIntegrationReady()) {
      return NextResponse.json(
        {
          error: "Superset integration is not configured (SUPERSET_URL and SUPERSET_PASSWORD required)",
        },
        { status: 503 },
      );
    }

    let waitForReady = true;
    try {
      const body = (await request.json()) as { waitForReady?: boolean };
      if (body.waitForReady === false) waitForReady = false;
    } catch {
      // empty body is fine
    }

    const reg = waitForReady
      ? await registerSpiceInstanceInSupersetWhenReady(name)
      : await registerSpiceInstanceInSuperset(name);

    const result = supersetRegisterResponse(reg);
    if (!result.registered && "warning" in result) {
      const status = "deployTimedOut" in result && result.deployTimedOut ? 504 : 502;
      return NextResponse.json({ ok: false, name, ...result }, { status });
    }

    return NextResponse.json({ ok: true, name, ...result });
  } catch (e) {
    const message = e instanceof Error ? e.message : "Unknown error";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
