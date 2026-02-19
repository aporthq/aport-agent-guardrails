# Launch evidence

**Before publishing the guardrail launch post:**

1. **Repo public:** In GitHub repo settings, set the repository to **Public**. Verify https://github.com/aporthq/aport-agent-guardrails does not 404.

2. **Evidence captured:** Terminal ALLOW/DENY transcript is in ** [EVIDENCE_TERMINAL_CAPTURE.txt](EVIDENCE_TERMINAL_CAPTURE.txt)** (guardrail exit 0 = ALLOW, exit 1 = DENY). For the post, use a screenshot of that output—or run the same commands and capture. Save as **`evidence-allow-deny.png`** in this folder if you want a dedicated image. See **`DEMO_TERMINAL_OUTPUT.txt`** for one-liner variants.

DENY:
aport-guardrail.sh system.command.execute '{"command":"rm -rf /"}'
❌ DENY
{
   "allow":false,
   "assurance_level":"L2",
   "decision_id":"A0A4C0DE-D6AB-4F9E-A5ED-7002919C0375",
   "expires_at":"2026-02-16T18:49:22Z",
   "issued_at":"2026-02-16T17:49:22Z",
   "kid":"oap:local:dev-key",
   "owner_id":"user@example.com",
   "passport_digest":"sha256:2c8368260593935ff699b5223d4101458881e3678e9b4ef992ad522bdabe198b",
   "passport_id":"CDE60F4E-49DC-4D97-AC05-190E693C202C",
   "policy_id":"system.command.execute.v1",
   "prev_content_hash":"sha256:8bb0fd773e38bb412fa79e9857392b746d891dde929764ddbaca76235d45b0c8",
   "prev_decision_id":"3E79C583-3A42-413C-830D-DA2480AD25C9",
   "reasons":[
      {
         "code":"oap.command_not_allowed",
         "message":"Command 'rm -rf /' is not in allowed list"
      }
   ],
   "signature":"ed25519:local-unsigned",
   "content_hash":"sha256:5d61ab149eb0e86e1c1d9d5822ba6714eb7b7a6ddc823130595132cd29974270"
}


ALLOW:
aport-guardrail.sh system.command.execute '{"command":"mkdir test"}'
✅ ALLOW

{
   "allow":true,
   "assurance_level":"L2",
   "decision_id":"3E79C583-3A42-413C-830D-DA2480AD25C9",
   "expires_at":"2026-02-16T18:49:18Z",
   "issued_at":"2026-02-16T17:49:18Z",
   "kid":"oap:local:dev-key",
   "owner_id":"user@example.com",
   "passport_digest":"sha256:2c8368260593935ff699b5223d4101458881e3678e9b4ef992ad522bdabe198b",
   "passport_id":"CDE60F4E-49DC-4D97-AC05-190E693C202C",
   "policy_id":"system.command.execute.v1",
   "prev_content_hash":"sha256:9572913a7cc9595629ba07ed8cf91868889987e655d69445d52bdbfc0961b827",
   "prev_decision_id":"A5CA49E4-849D-4ED8-BB68-177F1784726C",
   "reasons":[
      {
         "code":"oap.allowed",
         "message":"All policy checks passed"
      }
   ],
   "signature":"ed25519:local-unsigned",
   "content_hash":"sha256:8bb0fd773e38bb412fa79e9857392b746d891dde929764ddbaca76235d45b0c8"
}
