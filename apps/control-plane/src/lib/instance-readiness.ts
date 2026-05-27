import { getArgoApplication } from "@/lib/k8s";

export type ArgoApplicationStatus = {
  syncStatus?: string;
  healthStatus?: string;
};

export function parseArgoApplicationStatus(app: unknown): ArgoApplicationStatus {
  if (!app || typeof app !== "object") return {};
  const status = (app as { status?: unknown }).status;
  if (!status || typeof status !== "object") return {};
  const sync = (status as { sync?: unknown }).sync;
  const health = (status as { health?: unknown }).health;
  return {
    syncStatus:
      sync && typeof sync === "object"
        ? ((sync as { status?: string }).status ?? undefined)
        : undefined,
    healthStatus:
      health && typeof health === "object"
        ? ((health as { status?: string }).status ?? undefined)
        : undefined,
  };
}

export function isInstanceDeployReady(status: ArgoApplicationStatus): boolean {
  return status.syncStatus === "Synced" && status.healthStatus === "Healthy";
}

export type WaitForDeployReadyOutcome =
  | { ready: true; status: ArgoApplicationStatus }
  | { ready: false; status: ArgoApplicationStatus; timedOut: true };

export type WaitForDeployReadyOptions = {
  pollIntervalMs?: number;
  maxWaitMs?: number;
};

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

/**
 * Polls Argo CD until spice-<instanceName> is Synced + Healthy or maxWaitMs elapses.
 */
export async function waitForInstanceDeployReady(
  instanceName: string,
  opts?: WaitForDeployReadyOptions,
): Promise<WaitForDeployReadyOutcome> {
  const pollIntervalMs = opts?.pollIntervalMs ?? 10_000;
  const maxWaitMs = opts?.maxWaitMs ?? 15 * 60 * 1000;
  const appName = `spice-${instanceName}`;
  const deadline = Date.now() + maxWaitMs;
  let lastStatus: ArgoApplicationStatus = {};

  while (Date.now() < deadline) {
    try {
      const app = await getArgoApplication(appName);
      lastStatus = parseArgoApplicationStatus(app);
      if (isInstanceDeployReady(lastStatus)) {
        return { ready: true, status: lastStatus };
      }
    } catch {
      lastStatus = {};
    }
    await sleep(pollIntervalMs);
  }

  return { ready: false, status: lastStatus, timedOut: true };
}
