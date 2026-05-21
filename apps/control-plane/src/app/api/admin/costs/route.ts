import { NextResponse } from "next/server";
import { assertAdmin } from "@/lib/admin-auth";
import { buildCostSummary } from "@/lib/cost-summary";

export async function GET(request: Request) {
  const denied = assertAdmin(request);
  if (denied) return denied;
  try {
    const summary = await buildCostSummary();
    return NextResponse.json(summary);
  } catch (e) {
    const message = e instanceof Error ? e.message : "Unknown error";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
