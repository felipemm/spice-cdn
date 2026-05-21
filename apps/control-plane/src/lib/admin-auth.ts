import { getAdminApiKey } from "@/lib/config";

export function assertAdmin(request: Request) {
  const expected = getAdminApiKey();
  if (!expected) {
    return new Response("Admin API key is not configured on the server.", { status: 503 });
  }
  const header =
    request.headers.get("x-admin-key") ??
    request.headers.get("authorization")?.replace(/^Bearer\s+/i, "") ??
    "";
  if (header !== expected) {
    return new Response("Unauthorized", { status: 401 });
  }
  return null;
}
