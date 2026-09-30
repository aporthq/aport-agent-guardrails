import { isHardFailureDecision, shouldAllowDeniedDecision } from "./enforcement.js";

describe("enforcement helpers", () => {
  it("keeps runtime failures blocking in warn mode", () => {
    const decision = {
      allow: false,
      reasons: [{ code: "oap.api_error", message: "API unavailable" }],
    };

    expect(isHardFailureDecision(decision)).toBe(true);
    expect(shouldAllowDeniedDecision("warn", decision)).toBe(false);
    expect(shouldAllowDeniedDecision("observe", decision)).toBe(true);
  });

  it("allows policy denials in warn mode", () => {
    const decision = {
      allow: false,
      reasons: [{ code: "oap.command_not_allowed", message: "blocked" }],
    };

    expect(isHardFailureDecision(decision)).toBe(false);
    expect(shouldAllowDeniedDecision("warn", decision)).toBe(true);
  });

  it("classifies validation and passport path errors as hard failures", () => {
    for (const code of [
      "oap.context_not_serializable",
      "oap.context_too_nested",
      "oap.invalid_session_count",
      "oap.path_traversal_attempt",
      "oap.path_resolution_error",
    ]) {
      expect(isHardFailureDecision({ allow: false, reasons: [{ code }] })).toBe(true);
    }
  });
});
