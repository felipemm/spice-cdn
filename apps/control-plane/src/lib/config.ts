export function requireEnv(name: string): string {
  const v = process.env[name];
  if (!v) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return v;
}

/** `github` → GitHub REST (Octokit). `gitea` → in-cluster Gitea (Kind lab); requires GITOPS_GITEA_API_BASE_URL. */
export function getGitopsBackend(): "github" | "gitea" {
  const b = (process.env.GITOPS_BACKEND ?? "github").toLowerCase().trim();
  if (b === "gitea") return "gitea";
  return "github";
}

/** e.g. http://gitea-http.gitea.svc.cluster.local:3000/api/v1 (no trailing slash) */
export function getGiteaApiBaseUrl(): string {
  return (process.env.GITOPS_GITEA_API_BASE_URL ?? "").trim().replace(/\/$/, "");
}

/** GitOps repository (where `instances/*` live) — GitHub API / Octokit or Gitea REST. */
export function getGitopsRepoConfig() {
  const token = process.env.GITOPS_TOKEN ?? process.env.GITHUB_TOKEN ?? "";
  const owner = process.env.GITOPS_REPO_OWNER ?? process.env.GITHUB_OWNER ?? "";
  const repo = process.env.GITOPS_REPO_NAME ?? process.env.GITHUB_REPO ?? "";
  const branch = process.env.GITOPS_REPO_BRANCH ?? process.env.GITHUB_BRANCH ?? "main";
  return { token, owner, repo, branch };
}

export function assertGitopsRepoConfigured() {
  const c = getGitopsRepoConfig();
  if (!c.token || !c.owner || !c.repo) {
    throw new Error(
      "GitOps repo is not configured (GITOPS_TOKEN, GITOPS_REPO_OWNER, GITOPS_REPO_NAME). Legacy GITHUB_* vars are still accepted.",
    );
  }
  if (getGitopsBackend() === "gitea" && !getGiteaApiBaseUrl()) {
    throw new Error(
      "GITOPS_GITEA_API_BASE_URL is required when GITOPS_BACKEND=gitea (e.g. http://gitea-http.gitea.svc.cluster.local:3000/api/v1).",
    );
  }
  return c;
}

/** @deprecated use getGitopsRepoConfig */
export function getGithubConfig() {
  return getGitopsRepoConfig();
}

/** @deprecated use assertGitopsRepoConfigured */
export function assertGithubConfigured() {
  return assertGitopsRepoConfigured();
}

export function getVaultConfig() {
  return {
    addr: process.env.VAULT_ADDR ?? "http://127.0.0.1:8200",
    token: process.env.VAULT_TOKEN ?? "",
    role: process.env.VAULT_ROLE ?? "",
  };
}

export function getArgoNamespace() {
  return process.env.ARGOCD_NAMESPACE ?? "argocd";
}

export function getSpiceNamespace() {
  return process.env.SPICE_NAMESPACE ?? "spice-instances";
}

export function getAdminApiKey() {
  return process.env.ADMIN_API_KEY ?? "";
}
