import { NextResponse } from "next/server";
import { vaultReadData, vaultWriteData } from "@/lib/vault";

type Ctx = { params: Promise<{ name: string }> };

const vaultPathForInstance = (name: string) => `spice/instances/${name}`;

export async function GET(_request: Request, ctx: Ctx) {
  const { name } = await ctx.params;
  try {
    const data = await vaultReadData(vaultPathForInstance(name));
    return NextResponse.json({ keys: Object.keys(data), data });
  } catch (e) {
    const message = e instanceof Error ? e.message : "Unknown error";
    return NextResponse.json({ error: message, keys: [], data: {} }, { status: 500 });
  }
}

export async function PUT(request: Request, ctx: Ctx) {
  const { name } = await ctx.params;
  try {
    const body = (await request.json()) as { data?: Record<string, string> };
    if (!body.data || typeof body.data !== "object") {
      return NextResponse.json({ error: "data object required" }, { status: 400 });
    }
    await vaultWriteData(vaultPathForInstance(name), body.data);
    return NextResponse.json({ ok: true });
  } catch (e) {
    const message = e instanceof Error ? e.message : "Unknown error";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
