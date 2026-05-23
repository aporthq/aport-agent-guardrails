/**
 * Custom error classes for OAP Mastra integration.
 */

export interface OAPReceipt {
  allowed: boolean;
  tool: string;
  agent?: string;
  timestamp: string;
  reason?: string;
  receiptId: string;
}

export class OAPAuthorizationError extends Error {
  public readonly receipt: OAPReceipt;
  public readonly toolName: string;
  public readonly isOAPError = true;

  constructor(message: string, receipt: OAPReceipt) {
    super(message);
    this.name = 'OAPAuthorizationError';
    this.receipt = receipt;
    this.toolName = receipt.tool;
    Object.setPrototypeOf(this, OAPAuthorizationError.prototype);
  }

  toJSON(): Record<string, unknown> {
    return {
      error: this.name,
      message: this.message,
      tool: this.toolName,
      receipt: this.receipt,
    };
  }
}

export class OAPConfigurationError extends Error {
  public readonly isOAPError = true;

  constructor(message: string) {
    super(message);
    this.name = 'OAPConfigurationError';
    Object.setPrototypeOf(this, OAPConfigurationError.prototype);
  }
}

export class OAPPolicyError extends Error {
  public readonly isOAPError = true;

  constructor(message: string) {
    super(message);
    this.name = 'OAPPolicyError';
    Object.setPrototypeOf(this, OAPPolicyError.prototype);
  }
}