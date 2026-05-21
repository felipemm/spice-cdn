/**
 * Optional AWS Cost Explorer (IRSA / instance role). Account-level spend, not per K8s label.
 */

export type CostExplorerSummary = {
  start: string;
  end: string;
  totalUnblendedCost: number;
  currency: string;
};

export async function fetchAccountCostLast30d(): Promise<CostExplorerSummary | null> {
  if (process.env.AWS_COST_EXPLORER_ENABLED !== "true") {
    return null;
  }
  try {
    const { CostExplorerClient, GetCostAndUsageCommand } = await import("@aws-sdk/client-cost-explorer");
    const region = process.env.AWS_REGION || "us-east-1";
    const client = new CostExplorerClient({ region });
    const end = new Date();
    const start = new Date(end);
    start.setDate(start.getDate() - 30);
    const fmt = (d: Date) => d.toISOString().slice(0, 10);
    const res = await client.send(
      new GetCostAndUsageCommand({
        TimePeriod: { Start: fmt(start), End: fmt(end) },
        Granularity: "MONTHLY",
        Metrics: ["UnblendedCost"],
      }),
    );
    let total = 0;
    let currency = "USD";
    for (const r of res.ResultsByTime ?? []) {
      const amt = r.Total?.UnblendedCost;
      if (amt?.Amount != null) {
        total += Number(amt.Amount);
        if (amt.Unit) currency = amt.Unit;
      }
    }
    return {
      start: fmt(start),
      end: fmt(end),
      totalUnblendedCost: total,
      currency,
    };
  } catch (e) {
    console.warn("[cost-explorer]", e instanceof Error ? e.message : e);
    return null;
  }
}
