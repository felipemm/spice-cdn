/**
 * Browser URLs for the Kind + ingress-nginx lab (see templates/gitops and docs/tutorial.md).
 * Override with KIND_LAB_INGRESS_ROOT (e.g. 127.0.0.1.nip.io) and KIND_LAB_INGRESS_SCHEME (http|https).
 */

export function getKindLabIngressRoot(): string {
  return (process.env.KIND_LAB_INGRESS_ROOT ?? "127.0.0.1.nip.io").replace(/^\.+/, "").trim() || "127.0.0.1.nip.io";
}

export function getKindLabIngressScheme(): string {
  const s = (process.env.KIND_LAB_INGRESS_SCHEME ?? "http").replace(/:$/, "").trim().toLowerCase();
  return s === "https" ? "https" : "http";
}

export function kindLabPublicUrl(hostnamePrefix: string, path = "/"): string {
  const scheme = getKindLabIngressScheme();
  const root = getKindLabIngressRoot();
  const host = `${hostnamePrefix}.${root}`;
  const p = path.startsWith("/") ? path : `/${path}`;
  return `${scheme}://${host}${p}`;
}

export type ClusterUrlRow = {
  id: string;
  title: string;
  href: string | null;
  /** Shown under the title */
  detail?: string;
  /** Shown as muted note */
  note?: string;
  optional?: boolean;
};

export type ClusterUrlSection = {
  id: string;
  heading: string;
  description?: string;
  rows: ClusterUrlRow[];
};

export function staticKindClusterUrlSections(): ClusterUrlSection[] {
  return [
    {
      id: "core",
      heading: "GitOps & source",
      description:
        "Defaults match this repo’s Helm values (ingress-nginx host port 80 → 127.0.0.1). Change KIND_LAB_INGRESS_* if you use another DNS root.",
      rows: [
        {
          id: "argocd",
          title: "Argo CD",
          href: kindLabPublicUrl("argocd"),
          detail: "Continuous delivery UI — sync Applications, logs, diffs.",
          note: "Initial admin password: kubectl -n argocd get secret argocd-initial-admin-secret …",
        },
        {
          id: "gitea",
          title: "Gitea",
          href: kindLabPublicUrl("gitea"),
          detail: "In-cluster Git + registry when the Gitea Application is installed (GITOPS_BACKEND=gitea).",
          optional: true,
        },
      ],
    },
    {
      id: "observability",
      heading: "Metrics & cost",
      description: "Optional addons from templates/gitops/addons/.",
      rows: [
        {
          id: "grafana",
          title: "Grafana",
          href: kindLabPublicUrl("grafana"),
          detail: "kube-prometheus-stack dashboards (Kind values: admin / admin).",
          optional: true,
        },
        {
          id: "prometheus",
          title: "Prometheus (TSDB UI)",
          href: null,
          detail:
            "No ingress in Kind values — reach the UI with port-forward, or open targets in Grafana.",
          note:
            "kubectl -n monitoring port-forward svc/kps-kube-prometheus-stack-prometheus 9090:9090 → http://127.0.0.1:9090/",
          optional: true,
        },
        {
          id: "opencost",
          title: "OpenCost",
          href: kindLabPublicUrl("opencost"),
          detail: "Allocation / cost UI (install after kube-prometheus-stack for full data).",
          optional: true,
        },
      ],
    },
    {
      id: "bi",
      heading: "Analytics",
      rows: [
        {
          id: "superset",
          title: "Apache Superset",
          href: kindLabPublicUrl("superset"),
          detail: "Optional BI stack (see templates/gitops/addons/superset/).",
          optional: true,
        },
      ],
    },
    {
      id: "platform",
      heading: "Platform (no browser UI in defaults)",
      rows: [
        {
          id: "vault",
          title: "Vault",
          href: null,
          detail: "Lab chart keeps the UI disabled; API is in-cluster for ESO and workloads.",
          note: "Example: kubectl -n vault port-forward svc/vault 8200:8200 → http://127.0.0.1:8200/ui/",
        },
      ],
    },
  ];
}
