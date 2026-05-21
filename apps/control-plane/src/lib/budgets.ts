import fs from "node:fs";
import YAML from "yaml";

export type SlugBudget = {
  maxInstancesPerSlug?: number;
  maxEstimatedMonthlyUsdPerSlug?: number;
};

export type BudgetsFile = {
  defaults?: SlugBudget;
  bySlug?: Record<string, SlugBudget>;
};

const defaultBudgets: BudgetsFile = {
  defaults: { maxInstancesPerSlug: 100 },
  bySlug: {},
};

export function loadBudgetsFromFile(path: string): BudgetsFile {
  try {
    const raw = fs.readFileSync(path, "utf8");
    const doc = YAML.parse(raw) as BudgetsFile | null;
    if (!doc || typeof doc !== "object") return defaultBudgets;
    return {
      defaults: { ...defaultBudgets.defaults, ...doc.defaults },
      bySlug: doc.bySlug ?? {},
    };
  } catch {
    return defaultBudgets;
  }
}

export function getBudgetForSlug(budgets: BudgetsFile, slug: string): SlugBudget {
  const per = budgets.bySlug?.[slug];
  return {
    maxInstancesPerSlug:
      per?.maxInstancesPerSlug ?? budgets.defaults?.maxInstancesPerSlug ?? 100,
    maxEstimatedMonthlyUsdPerSlug:
      per?.maxEstimatedMonthlyUsdPerSlug ?? budgets.defaults?.maxEstimatedMonthlyUsdPerSlug,
  };
}
