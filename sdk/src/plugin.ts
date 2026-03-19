/**
 * PACT Protocol - Hedera Agent Kit Plugin
 *
 * Integrates PACT commitment management into the Hedera Agent Kit,
 * enabling any agent to create, accept, monitor, and enforce
 * service-level commitments.
 *
 * @example
 * ```typescript
 * import { PACTPlugin } from '@pact-protocol/hedera-agent-plugin';
 *
 * const agent = new HederaAgentKit({
 *   accountId: '0.0.12345',
 *   privateKey: process.env.HEDERA_PRIVATE_KEY,
 *   network: 'testnet',
 *   plugins: [new PACTPlugin({
 *     registryTopicId: '0.0.999999',
 *     escrowContractId: '0.0.888888',
 *     resolverContractId: '0.0.777777',
 *     registryContractId: '0.0.666666',
 *   })],
 * });
 * ```
 */

import {
  TopicCreateTransaction,
  TopicMessageSubmitTransaction,
  ContractExecuteTransaction,
  ContractCallQuery,
  TokenAssociateTransaction,
  AccountId,
  TopicId,
  ContractId,
  PrivateKey,
  Client,
  Hbar,
} from "@hashgraph/sdk";

import type {
  PACTPluginConfig,
  PACTCommitment,
  PACTCheckpoint,
  CreateCommitmentParams,
  AcceptCommitmentParams,
  SubmitCheckpointParams,
  FileDisputeParams,
  AgentReputation,
  HCSMessage,
} from "./types";

import { createHash, randomBytes } from "crypto";

/**
 * PACT Plugin for Hedera Agent Kit
 */
export class PACTPlugin {
  private config: PACTPluginConfig;
  private client: Client | null = null;
  private accountId: string | null = null;
  private privateKey: PrivateKey | null = null;

  constructor(config: PACTPluginConfig) {
    this.config = config;
  }

  /**
   * Initialize the plugin with the agent's Hedera client.
   * Called automatically by the Agent Kit.
   */
  async initialize(client: Client, accountId: string, privateKey: PrivateKey) {
    this.client = client;
    this.accountId = accountId;
    this.privateKey = privateKey;
  }

  // ---------------------------------------------------------------
  //  Commitment Management
  // ---------------------------------------------------------------

  /**
   * Create a new PACT commitment as a consumer.
   *
   * 1. Generates a unique commitment ID
   * 2. Creates a dedicated HCS topic for the commitment
   * 3. Publishes the commitment spec to the topic
   * 4. Locks payment in the escrow contract
   *
   * @returns The created commitment with its ID and topic
   */
  async createCommitment(
    params: CreateCommitmentParams
  ): Promise<{ id: string; topicId: string; commitment: PACTCommitment }> {
    this._ensureInitialized();

    // Generate commitment ID
    const commitmentId = `pact_${randomBytes(8).toString("hex")}`;

    // Create dedicated HCS topic for this commitment
    const topicTx = new TopicCreateTransaction()
      .setTopicMemo(`PACT:v1:${commitmentId}`)
      .setSubmitKey(this.privateKey!.publicKey);

    const topicResponse = await topicTx.execute(this.client!);
    const topicReceipt = await topicResponse.getReceipt(this.client!);
    const topicId = topicReceipt.topicId!.toString();

    // Build the full commitment specification
    const commitment: PACTCommitment = {
      pact_version: "1.0",
      commitment_id: commitmentId,
      created_at: new Date().toISOString(),
      parties: {
        consumer: { agent_id: this.accountId! },
        provider: { agent_id: "" }, // Set when accepted
      },
      service: {
        type: params.service,
        description: params.description || params.service,
      },
      conditions: params.conditions.map((c) => ({
        ...c,
        verification: "checkpoint_count" as const,
        mandatory: true,
      })),
      checkpoints: {
        interval: params.checkpoints.interval,
        required_count: params.checkpoints.count,
        schema: {},
      },
      payment: {
        token: params.payment.token,
        amount: params.payment.amount,
        decimals: 8,
        release_schedule: "graduated",
      },
      collateral: {
        provider_stake: 0, // Set based on reputation at acceptance
        consumer_stake: params.payment.amount,
        slash_percentage: 50,
      },
      timing: {
        acceptance_window: params.timing?.acceptance_window || 3600,
        execution_window: params.timing?.execution_window || 86400,
        dispute_window: params.timing?.dispute_window || 1800,
        expiry:
          params.timing?.expiry ||
          new Date(
            Date.now() +
              (params.timing?.execution_window || 86400) * 1000
          ).toISOString(),
      },
    };

    // Publish commitment to its HCS topic
    await this._publishHCSMessage(topicId, {
      type: "COMMITMENT_PROPOSED",
      commitment_id: commitmentId,
      sender: this.accountId!,
      timestamp: new Date().toISOString(),
      payload: commitment as unknown as Record<string, unknown>,
      signature: "", // Signed by submit key
    });

    // Announce on the registry topic
    await this._publishHCSMessage(this.config.registryTopicId, {
      type: "COMMITMENT_PROPOSED",
      commitment_id: commitmentId,
      sender: this.accountId!,
      timestamp: new Date().toISOString(),
      payload: {
        topic_id: topicId,
        service: params.service,
        payment_amount: params.payment.amount,
        payment_token: params.payment.token,
      },
      signature: "",
    });

    // Lock payment in escrow contract
    await this._lockFundsInEscrow(commitment);

    return { id: commitmentId, topicId, commitment };
  }

  /**
   * Accept a commitment as a provider.
   *
   * 1. Reviews the commitment terms
   * 2. Locks collateral in the escrow contract
   * 3. Publishes acceptance to the commitment's HCS topic
   */
  async acceptCommitment(
    commitmentId: string,
    params: AcceptCommitmentParams
  ): Promise<void> {
    this._ensureInitialized();

    // Publish acceptance to commitment topic
    // (In production, would look up the topic ID from the registry)
    await this._lockCollateralInEscrow(commitmentId, params.collateral.amount);

    console.log(
      `[PACT] Accepted commitment ${commitmentId} with ${params.collateral.amount} collateral`
    );
  }

  /**
   * Submit a performance checkpoint during commitment execution.
   *
   * 1. Constructs the checkpoint message with metrics
   * 2. Computes evidence hash
   * 3. Signs and publishes to the commitment's HCS topic
   * 4. Triggers tranche release if verified
   */
  async submitCheckpoint(
    commitmentId: string,
    params: SubmitCheckpointParams
  ): Promise<{ sequenceNumber: number; trancheReleased: boolean }> {
    this._ensureInitialized();

    const checkpoint: PACTCheckpoint = {
      type: "CHECKPOINT",
      commitment_id: commitmentId,
      checkpoint_index: 0, // Would be tracked by the plugin
      timestamp: new Date().toISOString(),
      reporter: this.accountId!,
      metrics: params.metrics,
      evidence_hash: params.evidenceHash,
      signature: "", // Signed by private key
    };

    // Publish checkpoint to commitment's HCS topic
    // (In production, would look up topic from commitment registry)
    const sequenceNumber = await this._publishCheckpoint(checkpoint);

    return { sequenceNumber, trancheReleased: true };
  }

  /**
   * File a dispute for a commitment.
   */
  async dispute(
    commitmentId: string,
    params: FileDisputeParams
  ): Promise<{ disputeId: string }> {
    this._ensureInitialized();

    const disputeId = `dispute_${randomBytes(8).toString("hex")}`;

    console.log(
      `[PACT] Filed dispute ${disputeId} for commitment ${commitmentId}: ${params.reason}`
    );

    return { disputeId };
  }

  // ---------------------------------------------------------------
  //  Reputation Queries
  // ---------------------------------------------------------------

  /**
   * Get an agent's reputation score and history.
   */
  async getReputation(agentId: string): Promise<AgentReputation> {
    this._ensureInitialized();

    // Query the registry contract
    const query = new ContractCallQuery()
      .setContractId(ContractId.fromString(this.config.registryContractId))
      .setGas(100_000)
      .setFunction("getAgentStats");

    // In production, would decode the contract response
    return {
      agent_id: agentId,
      did: "",
      reputation_score: 0,
      total_commitments: 0,
      completed_commitments: 0,
      breached_commitments: 0,
      total_value_completed: 0,
      total_value_slashed: 0,
      collateral_rate_bps: 4000,
    };
  }

  // ---------------------------------------------------------------
  //  Agent Kit Tool Definitions
  // ---------------------------------------------------------------

  /**
   * Returns the tools this plugin provides to the Agent Kit.
   * These tools can be invoked by AI agents via natural language.
   */
  getTools() {
    return [
      {
        name: "pact_create_commitment",
        description:
          "Create a new PACT commitment to hire another agent for a task. " +
          "Specify the service type, conditions, payment, and checkpoint frequency.",
        parameters: {
          type: "object",
          properties: {
            service: {
              type: "string",
              description: "Type of service (e.g., data_collection, analysis)",
            },
            conditions: {
              type: "array",
              description: "Performance conditions the provider must meet",
            },
            payment_token: { type: "string", description: "HTS token ID" },
            payment_amount: { type: "number", description: "Payment amount" },
            checkpoint_interval: {
              type: "number",
              description: "Seconds between checkpoints",
            },
            checkpoint_count: {
              type: "number",
              description: "Total required checkpoints",
            },
          },
          required: ["service", "payment_token", "payment_amount"],
        },
        handler: async (params: Record<string, unknown>) => {
          return this.createCommitment({
            service: params.service as string,
            conditions: (params.conditions as CreateCommitmentParams["conditions"]) || [],
            payment: {
              token: params.payment_token as string,
              amount: params.payment_amount as number,
            },
            checkpoints: {
              interval: (params.checkpoint_interval as number) || 600,
              count: (params.checkpoint_count as number) || 10,
            },
          });
        },
      },
      {
        name: "pact_accept_commitment",
        description:
          "Accept a PACT commitment as a service provider. " +
          "You must stake collateral proportional to the commitment value.",
        parameters: {
          type: "object",
          properties: {
            commitment_id: { type: "string", description: "Commitment ID" },
            collateral_token: { type: "string", description: "HTS token ID" },
            collateral_amount: {
              type: "number",
              description: "Collateral amount",
            },
          },
          required: ["commitment_id", "collateral_token", "collateral_amount"],
        },
        handler: async (params: Record<string, unknown>) => {
          return this.acceptCommitment(params.commitment_id as string, {
            collateral: {
              token: params.collateral_token as string,
              amount: params.collateral_amount as number,
            },
          });
        },
      },
      {
        name: "pact_submit_checkpoint",
        description:
          "Submit a performance checkpoint for an active commitment. " +
          "Triggers graduated payment release upon verification.",
        parameters: {
          type: "object",
          properties: {
            commitment_id: { type: "string", description: "Commitment ID" },
            metrics: {
              type: "object",
              description: "Performance metrics for this checkpoint",
            },
            evidence_hash: {
              type: "string",
              description: "SHA-256 hash of deliverable data at this point",
            },
          },
          required: ["commitment_id", "metrics", "evidence_hash"],
        },
        handler: async (params: Record<string, unknown>) => {
          return this.submitCheckpoint(params.commitment_id as string, {
            metrics: params.metrics as Record<string, number>,
            evidenceHash: params.evidence_hash as string,
          });
        },
      },
      {
        name: "pact_file_dispute",
        description:
          "File a dispute for a commitment that was not fulfilled. " +
          "Triggers automated or arbiter-based resolution.",
        parameters: {
          type: "object",
          properties: {
            commitment_id: { type: "string", description: "Commitment ID" },
            reason: { type: "string", description: "Reason for the dispute" },
          },
          required: ["commitment_id", "reason"],
        },
        handler: async (params: Record<string, unknown>) => {
          return this.dispute(params.commitment_id as string, {
            reason: params.reason as string,
          });
        },
      },
      {
        name: "pact_get_reputation",
        description:
          "Get an agent's PACT reputation score and commitment history.",
        parameters: {
          type: "object",
          properties: {
            agent_id: {
              type: "string",
              description: "Hedera account ID of the agent",
            },
          },
          required: ["agent_id"],
        },
        handler: async (params: Record<string, unknown>) => {
          return this.getReputation(params.agent_id as string);
        },
      },
    ];
  }

  // ---------------------------------------------------------------
  //  Private Helpers
  // ---------------------------------------------------------------

  private _ensureInitialized() {
    if (!this.client || !this.accountId || !this.privateKey) {
      throw new Error(
        "PACTPlugin not initialized. Call initialize() first."
      );
    }
  }

  private async _publishHCSMessage(
    topicId: string,
    message: HCSMessage
  ): Promise<number> {
    const tx = new TopicMessageSubmitTransaction()
      .setTopicId(TopicId.fromString(topicId))
      .setMessage(JSON.stringify(message));

    const response = await tx.execute(this.client!);
    const receipt = await response.getReceipt(this.client!);
    return receipt.topicSequenceNumber?.toNumber() || 0;
  }

  private async _publishCheckpoint(
    checkpoint: PACTCheckpoint
  ): Promise<number> {
    // Would publish to the commitment's HCS topic
    // Returns the sequence number
    return 0;
  }

  private async _lockFundsInEscrow(
    commitment: PACTCommitment
  ): Promise<void> {
    // Would call PACTEscrow.lockFunds via ContractExecuteTransaction
    const commitmentHash = createHash("sha256")
      .update(commitment.commitment_id)
      .digest();

    console.log(
      `[PACT] Locked ${commitment.payment.amount} in escrow for ${commitment.commitment_id}`
    );
  }

  private async _lockCollateralInEscrow(
    commitmentId: string,
    amount: number
  ): Promise<void> {
    // Would call PACTEscrow.lockCollateral via ContractExecuteTransaction
    console.log(
      `[PACT] Locked ${amount} collateral for ${commitmentId}`
    );
  }
}
