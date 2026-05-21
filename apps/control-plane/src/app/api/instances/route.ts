import { NextResponse } from "next/server";
import { createInstance, listInstancesWithUrls } from "@/lib/github-service";
import { renderInstanceTemplate } from "@/lib/instance-template";

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
    const body = (await request.json()) as { name?: string };
    const name = body.name?.trim();
    if (!name || !/^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/.test(name)) {
      return NextResponse.json(
        { error: "Invalid instance name (lowercase DNS label)." },
        { status: 400 },
      );
    }
    const yaml = renderInstanceTemplate(name);
    await createInstance(name, yaml);
    return NextResponse.json({ ok: true, name });
  } catch (e) {
    const message = e instanceof Error ? e.message : "Unknown error";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
