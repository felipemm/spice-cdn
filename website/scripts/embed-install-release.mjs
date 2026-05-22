/**
 * Copies ../scripts/install.sh → public/install.sh and, when PUBLIC_SPICE_PACKAGED_RELEASE
 * is set (e.g. in GitHub Actions), embeds that tag into SPICE_PACKAGED_RELEASE=...
 */
import { chmodSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(__dirname, "..", "..");
const src = join(repoRoot, "scripts", "install.sh");
const publicDir = join(__dirname, "..", "public");
const dst = join(publicDir, "install.sh");

mkdirSync(publicDir, { recursive: true });

let content = readFileSync(src, "utf8");
const tag = (process.env.PUBLIC_SPICE_PACKAGED_RELEASE ?? "").trim();
if (tag) {
  const safe = tag.replace(/["\\]/g, "");
  content = content.replace(/^SPICE_PACKAGED_RELEASE=.*$/m, `SPICE_PACKAGED_RELEASE="${safe}"`);
}

writeFileSync(dst, content, "utf8");
try {
  chmodSync(dst, 0o755);
} catch {
  /* ignore on Windows */
}

console.log("public/install.sh written", tag ? `(embedded ${tag})` : "(no PUBLIC_SPICE_PACKAGED_RELEASE)");
