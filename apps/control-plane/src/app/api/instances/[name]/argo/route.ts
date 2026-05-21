import { NextResponse } from "next/server";
import { getArgoApplication } from "@/lib/k8s";

type Ctx = { params: Promise<{ name: string }> };

export async function GET(_request: Request, ctx: Ctx) {
  const { name } = await ctx.params;
  try {
    const appName = `spice-${name}`;
    const app = await getArgoApplication(appName);
    return NextResponse.json({ application: app });
  } catch (e) {
    const message = e instanceof Error ? e.message : "Unknown error";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
