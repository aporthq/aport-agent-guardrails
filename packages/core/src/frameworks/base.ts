/**
 * Base adapter interface for framework-specific integrations.
 * Each framework implements detect(), install(), verify(), test().
 * Used by framework adapter modules (langchain, openclaw, n8n); CLI uses bin/agent-guardrails.
 */

export interface BaseAdapter {
  readonly name: string;

  detect(): Promise<boolean>;

  install(): Promise<void>;

  verify(): Promise<boolean>;

  test(): Promise<boolean>;
}

export abstract class BaseAdapterImpl implements BaseAdapter {
  abstract readonly name: string;

  abstract detect(): Promise<boolean>;
  abstract install(): Promise<void>;
  abstract verify(): Promise<boolean>;
  abstract test(): Promise<boolean>;
}
