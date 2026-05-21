import YAML from "yaml";
import { millicoresToCpuCores, parseCpuToMillicores, parseMemoryToGiB } from "@/lib/k8s-quantity";

export type ParsedInstanceValues = {
  ownerLayerSlug: string | null;
  /** Declared spiceai.resources.requests */
  cpuCores: number;
  memoryGiB: number;
  /** True when spiceai.additionalLabels['owner-layer-slug'] matches ownerLayerSlug */
  labelsConsistent: boolean | null;
};

function asRecord(v: unknown): Record<string, unknown> | null {
  return v && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, unknown>) : null;
}

export function parseInstanceValuesYaml(yamlText: string): ParsedInstanceValues {
  let doc: unknown;
  try {
    doc = YAML.parse(yamlText);
  } catch {
    return {
      ownerLayerSlug: null,
      cpuCores: 0,
      memoryGiB: 0,
      labelsConsistent: null,
    };
  }
  const root = asRecord(doc);
  const slug =
    root && typeof root.ownerLayerSlug === "string" && root.ownerLayerSlug.trim()
      ? root.ownerLayerSlug.trim()
      : null;

  const spiceai = root ? asRecord(root.spiceai) : null;
  const resources = spiceai ? asRecord(spiceai.resources) : null;
  const requests = resources ? asRecord(resources.requests) : null;
  const cpuRaw = requests && typeof requests.cpu === "string" ? requests.cpu : undefined;
  const memRaw = requests && typeof requests.memory === "string" ? requests.memory : undefined;
  const cpuCores = millicoresToCpuCores(parseCpuToMillicores(cpuRaw));
  const memoryGiB = parseMemoryToGiB(memRaw);

  let labelsConsistent: boolean | null = null;
  const addLabels = spiceai ? asRecord(spiceai.additionalLabels) : null;
  const labelSlug =
    addLabels && typeof addLabels["owner-layer-slug"] === "string"
      ? (addLabels["owner-layer-slug"] as string).trim()
      : null;
  if (slug && labelSlug) {
    labelsConsistent = slug === labelSlug;
  }

  return { ownerLayerSlug: slug, cpuCores, memoryGiB, labelsConsistent };
}

const slugPattern = /^[a-z0-9]([-a-z0-9]*[a-z0-9])?$/;

export function assertValidOwnerLayerSlug(slug: string): void {
  const s = slug.trim();
  if (!s || s.length > 63) {
    throw new Error("ownerLayerSlug must be 1–63 characters.");
  }
  if (!slugPattern.test(s)) {
    throw new Error(
      "ownerLayerSlug must be a lowercase DNS label (letters, digits, hyphens; no leading/trailing hyphen).",
    );
  }
}
