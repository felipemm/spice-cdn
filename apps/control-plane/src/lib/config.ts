export function requireEnv(name: string): string {
  const v = process.env[name];
  if (!v) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return v;
}

export function getGithubConfig() {
  return {
    token: process.env.GITHUB_TOKEN ?? "",
    owner: process.env.GITHUB_OWNER ?? "",
    repo: process.env.GITHUB_REPO ?? "",
    branch: process.env.GITHUB_BRANCH ?? "main",
  };
}

export function assertGithubConfigured() {
  const c = getGithubConfig();
  if (!c.token || !c.owner || !c.repo) {
    throw new Error("GitHub is not configured (GITHUB_TOKEN, GITHUB_OWNER, GITHUB_REPO).");
  }
  return c;
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
