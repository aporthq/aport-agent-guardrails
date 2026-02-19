# OpenClaw feedback summary and fixes

This doc summarizes external OpenClaw feedback on launch readiness and the **two fixes** needed so the guardrail is “ready for prime time” in a real OpenClaw environment.

---

## What the feedback said

**Plan and messaging:** Strong. Strategy, checklist, and guardrail post content are sufficient for a shot at reach and developer adoption—**provided the product experience matches the promises.**

**Guardrail readiness:** Not yet. The guardrail **logic** is correct (repo tests are green; ALLOW/DENY work across verification paths). The blockage is in the **OpenClaw environment** on the machine where you run OpenClaw:

1. **Passport allowlist:** The guardrail script (or the `bash` invocation that runs it) was **not** in the passport’s **allowed_commands**. So every attempt to run the guardrail via `exec` got denied **before** APort could respond (“command must be in allowed list”). The tests pass because they use a temp OpenClaw dir with an allowlisted guardrail; the real `~/.openclaw` passport may have a narrower list.
2. **Capability alignment:** Messaging checks were failing with “missing capability: messaging.send.” The passport must include the capabilities the plugin needs (e.g. **messaging.send** for messaging.message.send.v1). There was also a **400 Bad Request** from the APort API when config (local vs API) or request shape didn’t match.

**Until you can run:**

```bash
~/.openclaw/.skills/aport-guardrail.sh system.command.execute '{"command":"mkdir","args":["/tmp/test"]}'
# -> ✅ ALLOW

~/.openclaw/.skills/aport-guardrail.sh system.command.execute '{"command":"rm","args":["-rf","/"]}'
# -> ❌ DENY (blocked pattern)
```

—and capture that output for the launch post—you can’t truthfully say “5-minute setup, works today.”

---

## Fix 1: Passport allowlist (allowed_commands)

**Problem:** OpenClaw uses **exec** for both (a) running the guardrail script and (b) running real shell commands. The policy **system.command.execute.v1** checks the **command** string against **passport.limits.system.command.execute.allowed_commands** (prefix match). If the guardrail is invoked via `exec` (e.g. `bash ~/.openclaw/.skills/aport-guardrail.sh ...`), that **command** must be allowed. And every **real** command you need (e.g. `mkdir`, `ls`, `npm`) must be in the same list.

**Fix:**

The **installer (`./bin/openclaw`) now does this for you:** after it installs the guardrail wrappers, it updates the passport so that the guardrail script paths and `bash`/`sh` are in **allowed_commands** (idempotent merge). It then runs a self-check and exits with a clear error if the guardrail is denied. You only need to edit the passport manually if you didn’t use the installer or you use a different config dir.

If you do edit by hand:

1. Open your passport (e.g. `~/.openclaw/passport.json`).
2. Ensure **limits.system.command.execute.allowed_commands** includes:
   - **`bash`** (so any `bash .../aport-guardrail.sh ...` invocation is allowed), and
   - Every **real** command the agent may run: **mkdir**, **ls**, **npm**, **git**, **node**, **npx**, **cp**, **cat**, **echo**, **pwd**, **mv**, **touch**, **open**, etc.
3. Alternatively use **`["*"]`** to allow any command (blocked_patterns still apply). Re-run the passport wizard and choose “allow all commands” for the broad default, or edit the JSON.

**Where it’s set:** The wizard (`bin/aport-create-passport.sh` or `./bin/openclaw`) writes this when you create the passport. To change it later, edit the passport file or re-run the wizard.

**Quick fix (allow any command):** Run once to set `allowed_commands` to `["*"]` (blocked_patterns still apply):

```bash
jq '.limits["system.command.execute"].allowed_commands = ["*"]' ~/.openclaw/passport.json > ~/.openclaw/passport.json.tmp && mv ~/.openclaw/passport.json.tmp ~/.openclaw/passport.json
```

**References:** [OPENCLAW_TOOLS_AND_POLICIES.md](../OPENCLAW_TOOLS_AND_POLICIES.md), [QUICK_LAUNCH_CHECKLIST.md](QUICK_LAUNCH_CHECKLIST.md).

---

## Fix 2: Capability alignment (messaging.send and API config)

**Problem:** The policy **messaging.message.send.v1** requires the passport to have capability **messaging.send** (per OAP and the policy pack). If the passport was created with an old or different capability id (e.g. `messaging.message.send`), you get “missing capability: messaging.send.” Also, **400 Bad Request** from the APort API usually means wrong endpoint, missing/invalid body, or local vs API mode mismatch.

**Fix:**

1. **Passport capabilities:** In **passport.capabilities**, include an object with **`"id": "messaging.send"`** (not only `messaging.message.send`) if you use messaging. The wizard adds this when you answer “Send messages?” with yes.
2. **Local vs API:** For **local** mode the plugin runs the guardrail script and does **not** call the APort API. Set **mode: local** and **guardrailScript** to your `~/.openclaw/.skills/aport-guardrail-bash.sh` (or equivalent). For **API** mode set **apiUrl** and optionally **apiKey**; ensure the passport and request format match what the API expects.
3. **Limits for messaging:** Under **limits.messaging** include at least **msgs_per_min**, **msgs_per_day**, and any **allowed_recipients** / **approval_required** your policy uses.

**References:** [QUICKSTART.md](../QUICKSTART.md) (“Missing required capabilities: messaging.send”), [extensions/openclaw-aport/README.md](../../extensions/openclaw-aport/README.md) (config).

---

## After the two fixes

1. **Test a full flow:** Run a benign command through the guardrail → ALLOW; run a blocked command → DENY. Then run the same via OpenClaw (e.g. “create a folder and list it”) to confirm enforcement.
2. **Capture the screenshot** (terminal ALLOW/DENY) for the launch post.
3. **Re-run the Quick Launch Checklist** so repo, docs, and screenshots are ready.
4. **Then** run the launch sequence (Valentine post → engagement → guardrail post).

**TL;DR:** The launch plan and story are in good shape. The product needs **allowed_commands** (including `bash` and the commands you use) and **capability alignment** (e.g. **messaging.send**) in the passport so the guardrail runs and passes in your real OpenClaw environment. Once the ALLOW/DENY demo works and is captured, you're clear to execute the plan.

---

## Status: action items complete

The **exec mapping bug is fixed** and **messaging now honors L0** by default. The installer sets `allowed_commands: ["*"]` automatically, so the action items above (allowlist + capabilities) are complete. New installs get a working guardrail with no manual passport edits for normal use.
