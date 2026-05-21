/**
 * Rough EC2 on-demand style monthly rates for requested CPU/memory (governance estimates, not invoices).
 * Defaults approximate m6i.large us-east-1 (~$0.096/hr, 2 vCPU, 8 GiB) split linearly.
 */
export type PricingFactors = {
  usdPerCpuCoreMonth: number;
  usdPerGiBMonth: number;
};

const HOURS_PER_MONTH = 730;

/** On-demand Linux reference hourly (us-east-1 style); split across vCPU and GiB for request-based estimates. */
const NODE_TYPE_DEFAULTS: Record<string, { vcpu: number; memGiB: number; hourlyUsd: number }> = {
  "m6i.large": { vcpu: 2, memGiB: 8, hourlyUsd: 0.096 },
  "m5.large": { vcpu: 2, memGiB: 8, hourlyUsd: 0.096 },
  "m7i.large": { vcpu: 2, memGiB: 8, hourlyUsd: 0.1008 },
  "t3.medium": { vcpu: 2, memGiB: 4, hourlyUsd: 0.0416 },
  "t3.large": { vcpu: 2, memGiB: 8, hourlyUsd: 0.0832 },
};

/** m6i.large ~$0.096/hr → ~$70.08/mo; split across 2 vCPU and 8 GiB */
export const defaultPricingFactors: PricingFactors = {
  usdPerCpuCoreMonth: (0.096 * HOURS_PER_MONTH) / 2,
  usdPerGiBMonth: (0.096 * HOURS_PER_MONTH) / 8,
};

function factorsFromInstanceType(instanceType: string): PricingFactors | null {
  const spec = NODE_TYPE_DEFAULTS[instanceType.trim()];
  if (!spec) return null;
  return {
    usdPerCpuCoreMonth: (spec.hourlyUsd * HOURS_PER_MONTH) / spec.vcpu,
    usdPerGiBMonth: (spec.hourlyUsd * HOURS_PER_MONTH) / spec.memGiB,
  };
}

export function loadPricingFactorsFromEnv(): PricingFactors {
  const raw = process.env.COST_PRICING_JSON;
  if (raw?.trim()) {
    try {
      const j = JSON.parse(raw) as Partial<PricingFactors>;
      return {
        usdPerCpuCoreMonth: Number(j.usdPerCpuCoreMonth) || defaultPricingFactors.usdPerCpuCoreMonth,
        usdPerGiBMonth: Number(j.usdPerGiBMonth) || defaultPricingFactors.usdPerGiBMonth,
      };
    } catch {
      /* fall through */
    }
  }
  const inst = process.env.COST_NODE_INSTANCE_TYPE?.trim();
  if (inst) {
    const fromType = factorsFromInstanceType(inst);
    if (fromType) return fromType;
  }
  return defaultPricingFactors;
}

export function estimateMonthlyUsd(
  cpuCores: number,
  memoryGiB: number,
  factors: PricingFactors = defaultPricingFactors,
): number {
  if (cpuCores <= 0 && memoryGiB <= 0) return 0;
  const cpuCost = Math.max(0, cpuCores) * factors.usdPerCpuCoreMonth;
  const memCost = Math.max(0, memoryGiB) * factors.usdPerGiBMonth;
  /** Conservative blend: workloads pay for the larger of CPU- or memory-priced share */
  return Math.max(cpuCost, memCost);
}
