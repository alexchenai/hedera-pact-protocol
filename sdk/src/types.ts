/**
 * PACT Specification Language (PSL) Type Definitions
 *
 * These types define the structure of PACT commitments,
 * checkpoints, and dispute evidence.
 */

// ---------------------------------------------------------------
//  Core Types
// ---------------------------------------------------------------

export interface PACTCommitment {
  pact_version: string;
  commitment_id: string;
  created_at: string;
  parties: PACTParties;
  service: PACTService;
  conditions: PACTCondition[];
  checkpoints: PACTCheckpointConfig;
  payment: PACTPayment;
  collateral: PACTCollateral;
  timing: PACTTiming;
}

export interface PACTParties {
  provider: PACTParty;
  consumer: PACTParty;
}

export interface PACTParty {
  agent_id: string; // Hedera account ID (e.g., "0.0.12345")
  did?: string; // Decentralized Identifier
}

export interface PACTService {
  type: string;
  description: string;
  deliverable?: {
    format: string;
    schema_hash?: string;
  };
}

// ---------------------------------------------------------------
//  Conditions
// ---------------------------------------------------------------

export interface PACTCondition {
  metric: string;
  operator: ConditionOperator;
  threshold: number;
  unit?: string;
  verification: VerificationMethod;
  mandatory?: boolean; // default: true
  weight?: number; // weight in severity calculation
}

export type ConditionOperator = ">=" | "<=" | "==" | "!=" | ">" | "<";

export type VerificationMethod =
  | "checkpoint_count"
  | "hcs_timestamp_delta"
  | "sample_audit"
  | "binary_delivery"
  | "external_oracle"
  | "multi_party_attestation";

// ---------------------------------------------------------------
//  Checkpoints
// ---------------------------------------------------------------

export interface PACTCheckpointConfig {
  interval: number; // seconds between checkpoints
  required_count: number;
  schema: Record<string, CheckpointFieldType>;
}

export type CheckpointFieldType =
  | "uint"
  | "int"
  | "string"
  | "bytes32"
  | "bool"
  | "float";

export interface PACTCheckpoint {
  type: "CHECKPOINT";
  commitment_id: string;
  checkpoint_index: number;
  timestamp: string;
  reporter: string; // Hedera account ID
  metrics: Record<string, number | string | boolean>;
  evidence_hash: string;
  signature: string;
}

// ---------------------------------------------------------------
//  Payment & Collateral
// ---------------------------------------------------------------

export interface PACTPayment {
  token: string; // HTS token ID
  amount: number; // in smallest unit
  decimals: number;
  release_schedule: ReleaseSchedule;
}

export type ReleaseSchedule = "graduated" | "milestone" | "completion";

export interface PACTCollateral {
  provider_stake: number;
  consumer_stake: number;
  slash_percentage: number; // 0-100
}

// ---------------------------------------------------------------
//  Timing
// ---------------------------------------------------------------

export interface PACTTiming {
  acceptance_window: number; // seconds to accept
  execution_window: number; // seconds to complete
  dispute_window: number; // seconds to file dispute
  expiry: string; // ISO 8601 timestamp
}

// ---------------------------------------------------------------
//  Dispute Types
// ---------------------------------------------------------------

export interface PACTDispute {
  dispute_id: string;
  commitment_id: string;
  filer: string;
  reason: string;
  evidence: DisputeEvidence[];
  filed_at: string;
  state: DisputeState;
  ruling?: DisputeRuling;
}

export type DisputeState =
  | "FILED"
  | "AUTOMATED_RESOLVED"
  | "ARBITER_ASSIGNED"
  | "VOTING"
  | "RESOLVED"
  | "APPEALED"
  | "APPEAL_RESOLVED";

export interface DisputeEvidence {
  type: "hcs_log" | "sample_audit" | "external_data" | "attestation";
  data: string;
  hash: string;
}

export interface DisputeRuling {
  outcome: "PROVIDER_WINS" | "CONSUMER_WINS" | "PARTIAL";
  severity_bps: number;
  rationale?: string;
}

// ---------------------------------------------------------------
//  Reputation
// ---------------------------------------------------------------

export interface AgentReputation {
  agent_id: string;
  did: string;
  reputation_score: number; // 0-100
  total_commitments: number;
  completed_commitments: number;
  breached_commitments: number;
  total_value_completed: number;
  total_value_slashed: number;
  collateral_rate_bps: number;
}

// ---------------------------------------------------------------
//  HCS Message Types
// ---------------------------------------------------------------

export type HCSMessageType =
  | "COMMITMENT_PROPOSED"
  | "COMMITMENT_ACCEPTED"
  | "CHECKPOINT"
  | "DELIVERY_CONFIRMED"
  | "DISPUTE_FILED"
  | "DISPUTE_EVIDENCE"
  | "RULING"
  | "REPUTATION_UPDATE";

export interface HCSMessage {
  type: HCSMessageType;
  commitment_id: string;
  sender: string;
  timestamp: string;
  payload: Record<string, unknown>;
  signature: string;
}

// ---------------------------------------------------------------
//  Plugin Configuration
// ---------------------------------------------------------------

export interface PACTPluginConfig {
  registryTopicId: string;
  escrowContractId: string;
  resolverContractId: string;
  registryContractId: string;
  defaultCollateralToken?: string;
  arbiterTopicId?: string;
}

// ---------------------------------------------------------------
//  SDK Method Parameters
// ---------------------------------------------------------------

export interface CreateCommitmentParams {
  service: string;
  description?: string;
  conditions: Omit<PACTCondition, "verification">[];
  payment: {
    token: string;
    amount: number;
  };
  checkpoints: {
    interval: number;
    count: number;
  };
  timing?: Partial<PACTTiming>;
}

export interface AcceptCommitmentParams {
  collateral: {
    token: string;
    amount: number;
  };
}

export interface SubmitCheckpointParams {
  metrics: Record<string, number | string | boolean>;
  evidenceHash: string;
}

export interface FileDisputeParams {
  reason: string;
  evidence?: DisputeEvidence[];
}
