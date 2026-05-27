import { NextResponse } from "next/server";
import { deleteInstance, getValuesYaml, putValuesYaml } from "@/lib/github-service";
import { isSupersetIntegrationReady, unregisterSpiceInstanceFromSuperset } from "@/lib/superset-service";

type Ctx = { params: Promise<{ name: string }> };

export async function GET(_request: Request, ctx: Ctx) {
  const { name } = await ctx.params;
  try {
    const { content, sha } = await getValuesYaml(name);
    return NextResponse.json({ name, content, sha });
  } catch (e) {
    const message = e instanceof Error ? e.message : "Unknown error";
    return NextResponse.json({ error: message }, { status: 404 });
  }
}

export async function PUT(request: Request, ctx: Ctx) {
  const { name } = await ctx.params;
  try {
    const body = (await request.json()) as { content?: string; sha?: string | null };
    if (!body.content) {
      return NextResponse.json({ error: "content required" }, { status: 400 });
    }
    const existing = await getValuesYaml(name);
    const sha = body.sha ?? existing.sha;
    await putValuesYaml(name, body.content, sha, `chore: update instance ${name} values.yaml`);
    return NextResponse.json({ ok: true });
  } catch (e) {
    const message = e instanceof Error ? e.message : "Unknown error";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}

export async function DELETE(_request: Request, ctx: Ctx) {
  const { name } = await ctx.params;
  try {
    await deleteInstance(name);

    let superset: { unregistered: boolean; warning?: string } | undefined;
    if (isSupersetIntegrationReady()) {
      const un = await unregisterSpiceInstanceFromSuperset(name);
      if (un.ok) {
        superset = { unregistered: un.deleted };
      } else if (un.skipped) {
        superset = { unregistered: false, warning: un.reason };
      } else {
        superset = { unregistered: false, warning: un.error };
      }
    }

    return NextResponse.json({ ok: true, superset });
  } catch (e) {
    const message = e instanceof Error ? e.message : "Unknown error";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
