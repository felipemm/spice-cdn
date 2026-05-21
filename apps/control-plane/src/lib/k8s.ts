import * as k8s from "@kubernetes/client-node";
import { getArgoNamespace, getSpiceNamespace } from "@/lib/config";

let cachedApis: {
  customObjects: k8s.CustomObjectsApi;
  core: k8s.CoreV1Api;
} | null = null;

function getApis() {
  if (cachedApis) return cachedApis;
  const kubeConfig = new k8s.KubeConfig();
  kubeConfig.loadFromDefault();
  cachedApis = {
    customObjects: kubeConfig.makeApiClient(k8s.CustomObjectsApi),
    core: kubeConfig.makeApiClient(k8s.CoreV1Api),
  };
  return cachedApis;
}

export async function listArgoApplications(): Promise<unknown[]> {
  const ns = getArgoNamespace();
  const { customObjects } = getApis();
  const res = (await customObjects.listNamespacedCustomObject({
    group: "argoproj.io",
    version: "v1alpha1",
    namespace: ns,
    plural: "applications",
  })) as { items?: unknown[] };
  return res.items ?? [];
}

export async function getArgoApplication(name: string): Promise<unknown> {
  const ns = getArgoNamespace();
  const { customObjects } = getApis();
  return customObjects.getNamespacedCustomObject({
    group: "argoproj.io",
    version: "v1alpha1",
    namespace: ns,
    plural: "applications",
    name,
  });
}

export async function syncArgoApplication(name: string): Promise<unknown> {
  const ns = getArgoNamespace();
  const { customObjects } = getApis();
  const patch = { operation: { sync: {} } };
  return customObjects.patchNamespacedCustomObject({
    group: "argoproj.io",
    version: "v1alpha1",
    namespace: ns,
    plural: "applications",
    name,
    body: patch,
  });
}

export async function refreshArgoApplication(name: string): Promise<unknown> {
  const ns = getArgoNamespace();
  const { customObjects } = getApis();
  const patch = {
    metadata: {
      annotations: {
        "argocd.argoproj.io/refresh": "hard",
      },
    },
  };
  return customObjects.patchNamespacedCustomObject({
    group: "argoproj.io",
    version: "v1alpha1",
    namespace: ns,
    plural: "applications",
    name,
    body: patch,
  });
}

export async function listExternalSecrets(): Promise<unknown[]> {
  const ns = getSpiceNamespace();
  const { customObjects } = getApis();
  try {
    const res = (await customObjects.listNamespacedCustomObject({
      group: "external-secrets.io",
      version: "v1beta1",
      namespace: ns,
      plural: "externalsecrets",
    })) as { items?: unknown[] };
    return res.items ?? [];
  } catch {
    return [];
  }
}

export async function listPodsInNamespace(namespace: string) {
  const { core } = getApis();
  const res = await core.listNamespacedPod({ namespace });
  return res.items;
}

export async function listEventsInNamespace(namespace: string) {
  const { core } = getApis();
  const res = await core.listNamespacedEvent({ namespace });
  return res.items.slice(0, 50);
}
