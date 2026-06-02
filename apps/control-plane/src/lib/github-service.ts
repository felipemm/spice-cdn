import { Octokit } from "@octokit/rest";
import YAML from "yaml";
import { assertGitopsRepoConfigured, getGitopsBackend } from "@/lib/config";
import * as giteaGitops from "@/lib/gitea-gitops";

const instancesPrefix = "instances";

type InstanceIngress = {
  enabled?: boolean;
  host?: string;
};

type FlightSQLIngress = {
  enabled?: boolean;
  host?: string;
};

/** Matches charts/spice-instance `spice-instance.flightSqlIngressHost` helper. */
export function flightSqlIngressHostFromIngress(ingress: {
  host?: string;
  flightSQL?: FlightSQLIngress;
}): string | null {
  const httpHost = typeof ingress.host === "string" ? ingress.host.trim() : "";
  if (!httpHost) return null;
  const explicit = typeof ingress.flightSQL?.host === "string" ? ingress.flightSQL.host.trim() : "";
  if (explicit) return explicit;
  const dot = httpHost.indexOf(".");
  if (dot === -1) return null;
  const first = httpHost.slice(0, dot);
  const rest = httpHost.slice(dot + 1);
  return `${first}-flight.${rest}`;
}

/** Arrow Flight SQL URL from instance values.yaml (dedicated flight hostname on ingress :80/:443). */
export function spiceFlightSqlUrlFromValuesYaml(yamlText: string): string | null {
  let doc: unknown;
  try {
    doc = YAML.parse(yamlText);
  } catch {
    return null;
  }
  if (!doc || typeof doc !== "object") return null;
  const ingress = (doc as { ingress?: InstanceIngress & { flightSQL?: FlightSQLIngress; tls?: { enabled?: boolean } } })
    .ingress;
  if (!ingress) return null;
  if (ingress.enabled === false) return null;
  if (typeof ingress.host !== "string" || !ingress.host.trim()) return null;
  const flight = ingress.flightSQL;
  if (flight?.enabled === false) return null;
  const fh = flightSqlIngressHostFromIngress(ingress);
  if (!fh) return null;
  const tls = ingress.tls?.enabled === true;
  return tls ? `grpcs://${fh}` : `grpc://${fh}`;
}

/** Public browser URL for the Spice HTTP API from instance values.yaml (ingress.host). */
export function spicePublicUrlFromValuesYaml(yamlText: string): string | null {
  let doc: unknown;
  try {
    doc = YAML.parse(yamlText);
  } catch {
    return null;
  }
  if (!doc || typeof doc !== "object") return null;
  const ingress = (doc as { ingress?: InstanceIngress }).ingress;
  if (!ingress) return null;
  if (ingress.enabled === false) return null;
  const host = ingress.host;
  if (typeof host !== "string" || !host.trim()) return null;
  const h = host.trim();
  const scheme = h.includes("127.0.0.1") ? "http" : "https";
  return `${scheme}://${h}`;
}

export function createOctokit() {
  if (getGitopsBackend() === "gitea") {
    throw new Error("createOctokit is only for GITOPS_BACKEND=github");
  }
  const { token } = assertGitopsRepoConfigured();
  return new Octokit({ auth: token });
}

function github401Message(): string {
  return (
    "GitHub API rejected the token (GITOPS_TOKEN / GITHUB_TOKEN). Use a fine-grained or classic PAT with contents read/write " +
    "on the GitOps repo. For the Kind + in-cluster Gitea lab, set GITOPS_BACKEND=gitea and GITOPS_GITEA_API_BASE_URL to the Gitea /api/v1 base URL."
  );
}

export async function listInstanceNames(): Promise<string[]> {
  if (getGitopsBackend() === "gitea") {
    return giteaGitops.listInstanceNames();
  }
  const octokit = createOctokit();
  const { owner, repo, branch } = assertGitopsRepoConfigured();
  try {
    const res = await octokit.repos.getContent({
      owner,
      repo,
      path: instancesPrefix,
      ref: branch,
    });
    if (!Array.isArray(res.data)) {
      return [];
    }
    return res.data.filter((e) => e.type === "dir").map((e) => e.name);
  } catch (e: unknown) {
    const status = typeof e === "object" && e && "status" in e ? (e as { status?: number }).status : undefined;
    if (status === 404) {
      return [];
    }
    if (status === 401) {
      throw new Error(github401Message());
    }
    throw e;
  }
}

export type InstanceListEntry = { name: string; url: string | null };

export async function listInstancesWithUrls(): Promise<InstanceListEntry[]> {
  const names = await listInstanceNames();
  const entries = await Promise.all(
    names.map(async (name): Promise<InstanceListEntry> => {
      try {
        const { content } = await getValuesYaml(name);
        return { name, url: spicePublicUrlFromValuesYaml(content) };
      } catch {
        return { name, url: null };
      }
    }),
  );
  entries.sort((a, b) => a.name.localeCompare(b.name));
  return entries;
}

export async function getValuesYaml(name: string): Promise<{ content: string; sha: string }> {
  if (getGitopsBackend() === "gitea") {
    return giteaGitops.getValuesYaml(name);
  }
  const octokit = createOctokit();
  const { owner, repo, branch } = assertGitopsRepoConfigured();
  try {
    const path = `${instancesPrefix}/${name}/values.yaml`;
    const res = await octokit.repos.getContent({ owner, repo, path, ref: branch });
    if (Array.isArray(res.data) || res.data.type !== "file") {
      throw new Error(`values.yaml not found for instance ${name}`);
    }
    if (!("content" in res.data) || res.data.encoding !== "base64" || !res.data.sha) {
      throw new Error("Unexpected GitHub API response for values.yaml");
    }
    const content = Buffer.from(res.data.content, "base64").toString("utf8");
    return { content, sha: res.data.sha };
  } catch (e: unknown) {
    const status = typeof e === "object" && e && "status" in e ? (e as { status?: number }).status : undefined;
    if (status === 401) {
      throw new Error(github401Message());
    }
    throw e;
  }
}

export async function putValuesYaml(
  name: string,
  content: string,
  sha: string | null,
  message: string,
): Promise<void> {
  if (getGitopsBackend() === "gitea") {
    return giteaGitops.putValuesYaml(name, content, sha, message);
  }
  const octokit = createOctokit();
  const { owner, repo, branch } = assertGitopsRepoConfigured();
  const path = `${instancesPrefix}/${name}/values.yaml`;
  const contentBase64 = Buffer.from(content, "utf8").toString("base64");
  if (sha) {
    await octokit.repos.createOrUpdateFileContents({
      owner,
      repo,
      path,
      message,
      content: contentBase64,
      sha,
      branch,
    });
  } else {
    await octokit.repos.createOrUpdateFileContents({
      owner,
      repo,
      path,
      message,
      content: contentBase64,
      branch,
    });
  }
}

export async function createInstance(name: string, initialYaml: string) {
  if (getGitopsBackend() === "gitea") {
    return giteaGitops.createInstance(name, initialYaml);
  }
  const octokit = createOctokit();
  const { owner, repo, branch } = assertGitopsRepoConfigured();
  const path = `${instancesPrefix}/${name}/values.yaml`;
  await octokit.repos.createOrUpdateFileContents({
    owner,
    repo,
    path,
    message: `feat: create spice instance ${name}`,
    content: Buffer.from(initialYaml, "utf8").toString("base64"),
    branch,
  });
}

export async function deleteInstance(name: string) {
  if (getGitopsBackend() === "gitea") {
    return giteaGitops.deleteInstance(name);
  }
  const octokit = createOctokit();
  const { owner, repo, branch } = assertGitopsRepoConfigured();
  const dirPath = `${instancesPrefix}/${name}`;
  const res = await octokit.repos.getContent({ owner, repo, path: dirPath, ref: branch });
  if (!Array.isArray(res.data)) {
    throw new Error("Instance path is not a directory");
  }
  for (const entry of res.data) {
    if (entry.type !== "file" || !("sha" in entry) || !entry.sha) continue;
    await octokit.repos.deleteFile({
      owner,
      repo,
      path: entry.path,
      message: `chore: delete instance ${name} (${entry.name})`,
      sha: entry.sha,
      branch,
    });
  }
}
