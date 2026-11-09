---
"@aporthq/aport-agent-guardrails-core": patch
"@aporthq/aport-agent-guardrails-langchain": patch
---
Provision Node and Python prerequisites before `make test` in CI, run the full
test job for staging and main, and stop unenrolled hosted Python evaluators from
launching the Node reporter on every decision, remember and post call. One shared
Python presence check now gates optional reporting; binding and schema validation
stay in the shared Node runtime.
