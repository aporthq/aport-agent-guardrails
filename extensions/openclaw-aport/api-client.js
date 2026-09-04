export async function verifyViaApi({ apiUrl, apiKey, policyName, context, passport, agentId, signal }) {
  const baseUrl = String(apiUrl || "https://api.aport.io").replace(/\/$/, "");
  const headers = { "Content-Type": "application/json" };
  if (apiKey) headers.Authorization = `Bearer ${apiKey}`;

  const body = agentId
    ? JSON.stringify({ context: { agent_id: agentId, ...context } })
    : JSON.stringify({ passport, context });

  const response = await fetch(`${baseUrl}/api/verify/policy/${policyName}`, {
    method: "POST",
    headers,
    body,
    signal,
  });

  if (!response.ok) {
    let details = "";
    try {
      const text = await response.text();
      if (text) details = text;
    } catch {
      details = "";
    }
    const suffix = details ? ` - ${sanitizeApiError(details)}` : "";
    throw new Error(`API request failed: ${response.status} ${response.statusText}${suffix}`);
  }

  const data = await response.json();
  return data.decision || data;
}

function sanitizeApiError(value) {
  return String(value ?? "")
    .replace(/[\r\n\t]+/g, " ")
    .replace(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g, "")
    .replace(/(?:apk|aprt)_[A-Za-z0-9_-]+/g, "[REDACTED_APORT_KEY]")
    .replace(/github_pat_[A-Za-z0-9_]+/g, "[REDACTED_GITHUB_TOKEN]")
    .replace(/gh[pousr]_[A-Za-z0-9_]+/g, "[REDACTED_GITHUB_TOKEN]")
    .replace(/AKIA[0-9A-Z]{16}/g, "[REDACTED_AWS_KEY]")
    .replace(/(Authorization:?\s*Bearer|Bearer)\s+[A-Za-z0-9._~+/-]+=*/gi, "$1 [REDACTED]")
    .replace(/(password|passwd|pwd|token|secret|api[_-]?key)=\S+/gi, "$1=[REDACTED]")
    .slice(0, 320);
}
