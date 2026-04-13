export async function verifyViaApi({ apiUrl, apiKey, policyName, context, passport, agentId }) {
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
  });

  if (!response.ok) {
    throw new Error(`API request failed: ${response.status} ${response.statusText}`);
  }

  const data = await response.json();
  return data.decision || data;
}
