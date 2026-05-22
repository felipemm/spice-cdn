export function requireEnv(name: string): string {
  const v = process.env[name];
  if (!v) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return v;
}

/** GitOps repository (where `instances/*` live) — GitHub API / Octokit. */
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
