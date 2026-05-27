import { assertGitopsRepoConfigured, getGiteaApiBaseUrl } from "@/lib/config";

const instancesPrefix = "instances";

type GiteaDirItem = { name: string; type: "file" | "dir" | string; path?: string; sha?: string };
type GiteaFileResponse = {
  type: string;
  encoding?: string;
  content?: string;
  sha?: string;
};

function authHeaders(forJsonBody: boolean): HeadersInit {
  const { token, owner } = assertGitopsRepoConfigured();
  const basic = Buffer.from(`${owner}:${token}`, "utf8").toString("base64");
  const h: Record<string, string> = {
    Authorization: `Basic ${basic}`,
    Accept: "application/json",
  };
  if (forJsonBody) {
    h["Content-Type"] = "application/json";
  }
  return h;
}

function contentsUrl(filepath: string, ref?: string): string {
  const base = getGiteaApiBaseUrl();
  const { owner, repo } = assertGitopsRepoConfigured();
  const enc = encodeURIComponent(filepath);
  let url = `${base}/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/contents/${enc}`;
  if (ref) {
    url += `?ref=${encodeURIComponent(ref)}`;
  }
  return url;
}

async function giteaFetch<T>(method: string, url: string, body?: unknown): Promise<T> {
  const res = await fetch(url, {
    method,
    headers: authHeaders(body !== undefined),
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  if (!res.ok) {
    const err = new Error(
      text ? `${res.status} ${res.statusText}: ${text.slice(0, 800)}` : `${res.status} ${res.statusText}`,
    ) as Error & { status?: number };
    err.status = res.status;
    throw err;
  }
  if (!text) {
    return undefined as T;
  }
  try {
    return JSON.parse(text) as T;
  } catch {
    return undefined as T;
  }
}

export async function listInstanceNames(): Promise<string[]> {
  const { branch } = assertGitopsRepoConfigured();
  try {
    const data = await giteaFetch<GiteaDirItem[] | GiteaFileResponse>(
      "GET",
      contentsUrl(instancesPrefix, branch),
    );
    if (!Array.isArray(data)) {
      return [];
    }
    return data.filter((e) => e.type === "dir").map((e) => e.name);
  } catch (e: unknown) {
    const status = typeof e === "object" && e && "status" in e ? (e as { status?: number }).status : undefined;
    if (status === 404) {
      return [];
    }
    throw e;
  }
}

export async function getValuesYaml(name: string): Promise<{ content: string; sha: string }> {
  const { branch } = assertGitopsRepoConfigured();
  const path = `${instancesPrefix}/${name}/values.yaml`;
  const data = await giteaFetch<GiteaFileResponse>("GET", contentsUrl(path, branch));
  if (!data || data.type !== "file" || data.encoding !== "base64" || !data.content || !data.sha) {
    throw new Error(`values.yaml not found for instance ${name}`);
  }
  const content = Buffer.from(data.content, "base64").toString("utf8");
  return { content, sha: data.sha };
}

export async function putValuesYaml(
  name: string,
  content: string,
  sha: string | null,
  message: string,
): Promise<void> {
  const { branch } = assertGitopsRepoConfigured();
  const path = `${instancesPrefix}/${name}/values.yaml`;
  const contentB64 = Buffer.from(content, "utf8").toString("base64");
  const url = contentsUrl(path);
  const body: Record<string, string> = {
    branch,
    content: contentB64,
    message,
  };
  if (sha) {
    body.sha = sha;
    await giteaFetch("PUT", url, body);
  } else {
    await giteaFetch("POST", url, body);
  }
}

export async function createInstance(name: string, initialYaml: string): Promise<void> {
  const { branch } = assertGitopsRepoConfigured();
  const path = `${instancesPrefix}/${name}/values.yaml`;
  const url = contentsUrl(path);
  await giteaFetch("POST", url, {
    branch,
    message: `feat: create spice instance ${name}`,
    content: Buffer.from(initialYaml, "utf8").toString("base64"),
  });
}

export async function deleteInstance(name: string): Promise<void> {
  const { branch } = assertGitopsRepoConfigured();
  const dirPath = `${instancesPrefix}/${name}`;
  const data = await giteaFetch<GiteaDirItem[] | GiteaFileResponse>(
    "GET",
    contentsUrl(dirPath, branch),
  );
  if (!Array.isArray(data)) {
    throw new Error("Instance path is not a directory");
  }
  for (const entry of data) {
    if (entry.type !== "file" || !entry.sha || !entry.path) continue;
    await giteaFetch("DELETE", contentsUrl(entry.path), {
      branch,
      message: `chore: delete instance ${name} (${entry.name})`,
      sha: entry.sha,
    });
  }
}
