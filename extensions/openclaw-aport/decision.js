import { createHash } from "node:crypto";

export function canonicalize(obj) {
  if (obj === null || typeof obj !== "object") return JSON.stringify(obj);
  if (Array.isArray(obj)) return `[${obj.map(canonicalize).join(",")}]`;
  const keys = Object.keys(obj).sort();
  return `{${keys.map((key) => `${JSON.stringify(key)}:${canonicalize(obj[key])}`).join(",")}}`;
}

export function verifyDecisionIntegrity(decision) {
  if (!decision || !decision.content_hash) return true;
  const { content_hash, ...rest } = decision;
  const computed = `sha256:${createHash("sha256").update(canonicalize(rest), "utf8").digest("hex")}`;
  return computed === content_hash;
}

export function formatReasons(decision) {
  const reasons = Array.isArray(decision?.reasons) ? decision.reasons : [];
  const primaryMessage = reasons[0]?.message || decision?.reason || "";
  return { reasons, primaryMessage };
}
