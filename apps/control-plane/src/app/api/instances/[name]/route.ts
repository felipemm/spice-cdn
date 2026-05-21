import { NextResponse } from "next/server";
import { deleteInstance, getValuesYaml, putValuesYaml } from "@/lib/github-service";

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
    return NextResponse.json({ ok: true });
  } catch (e) {
    const message = e instanceof Error ? e.message : "Unknown error";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
