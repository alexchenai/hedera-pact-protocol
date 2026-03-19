# PACT Protocol: Programmable Agent Commitment Tracking on Hedera

**Version 1.0 — March 2026**

**Authors:** Jhon, Alex Chen

**Abstract:** As autonomous AI agents transition from isolated tools to economic participants capable of transacting, delegating, and collaborating, a critical infrastructure gap emerges: there is no standardized mechanism for agents to form binding service commitments with verifiable performance guarantees and automated economic consequences. PACT Protocol addresses this by introducing a Programmable Agent Commitment Tracking layer built on Hedera, leveraging the Hedera Consensus Service (HCS) for tamper-proof performance attestations, the Hedera Token Service (HTS) for collateral escrow and incentive alignment, and Hedera Smart Contracts for automated dispute resolution. PACT enables a trust-minimized environment where AI agents can make, monitor, and enforce service-level agreements (SLAs) without human intermediation, unlocking the next phase of autonomous agent commerce.

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Problem Statement](#2-problem-statement)
3. [Related Work](#3-related-work)
4. [System Architecture](#4-system-architecture)
5. [PACT Lifecycle](#5-pact-lifecycle)
6. [Hedera Service Integration](#6-hedera-service-integration)
7. [Commitment Specification Language](#7-commitment-specification-language)
8. [Escrow and Staking Mechanics](#8-escrow-and-staking-mechanics)
9. [Performance Monitoring via HCS](#9-performance-monitoring-via-hcs)
10. [Dispute Resolution Engine](#10-dispute-resolution-engine)
11. [Economic Model](#11-economic-model)
12. [Security Analysis](#12-security-analysis)
13. [Implementation](#13-implementation)
14. [Use Cases](#14-use-cases)
15. [Roadmap](#15-roadmap)
16. [Conclusion](#16-conclusion)
17. [References](#17-references)

---

## 1. Introduction

The rise of autonomous AI agents marks a paradigm shift in software architecture. Agents no longer simply respond to user queries — they negotiate, transact, delegate tasks, and collaborate with other agents to accomplish complex objectives. Frameworks like LangChain, CrewAI, AutoGen, and OpenClaw have demonstrated that multi-agent systems can coordinate effectively, but they operate in a trust vacuum: there is no mechanism to enforce that an agent will deliver on its promises.

Consider a scenario where Agent A (a data analysis agent) contracts Agent B (a web scraping agent) to collect pricing data from 500 e-commerce sites within 2 hours, paying 50 USDC upon completion. Today, this interaction requires either:

1. **Blind trust** — Agent A pays upfront and hopes Agent B delivers.
2. **Human oversight** — A human monitors the interaction and mediates disputes.
3. **Centralized platforms** — A trusted third party holds escrow and adjudicates.

None of these approaches scale to the millions of agent-to-agent transactions that agentic commerce will produce. PACT Protocol provides the fourth option: **trustless, automated commitment enforcement** built on Hedera's enterprise-grade distributed ledger.

### 1.1 Why Hedera

Hedera offers a unique combination of properties that make it the ideal substrate for agent commitment tracking:

- **Hedera Consensus Service (HCS):** Provides ordered, timestamped, and immutable message logs with 3-5 second finality — perfect for recording performance attestations that cannot be disputed.
- **Hedera Token Service (HTS):** Native token creation with built-in compliance controls (KYC, freeze, supply management) — ideal for escrow tokens and staking mechanisms.
- **Low and predictable fees:** HCS message submission costs ~$0.0001, making it economically viable for agents to log thousands of performance checkpoints per commitment.
- **High throughput:** 10,000+ TPS ensures the network can handle an entire ecosystem of agents forming and monitoring commitments simultaneously.
- **EVM compatibility:** Solidity smart contracts for complex escrow logic while leveraging native HTS performance.
- **Fair ordering:** Hashgraph consensus provides fair transaction ordering, preventing front-running in commitment markets.

### 1.2 Contributions

This paper makes the following contributions:

1. **PACT Specification Language (PSL):** A formal language for expressing agent commitments with measurable, verifiable conditions.
2. **HCS Performance Oracle:** A novel use of HCS topics as tamper-proof performance monitoring channels.
3. **Graduated Escrow Model:** An economic mechanism that releases funds proportionally to verified progress, reducing risk for both parties.
4. **Automated Dispute Resolution:** A smart-contract-based arbitration system that resolves disputes using on-chain evidence from HCS logs.
5. **Reputation Staking:** A mechanism where agents stake tokens proportional to their commitment value, creating economic skin-in-the-game.

---

## 2. Problem Statement

### 2.1 The Agent Accountability Gap

Current multi-agent frameworks assume cooperative behavior. When Agent A delegates a task to Agent B, the implicit assumption is that B will perform the task competently and honestly. This assumption fails in open, permissionless agent ecosystems for several reasons:

**P1: No Enforceable Commitments.** An agent can promise to deliver a service and fail to do so without consequence. There is no on-chain record of what was promised versus what was delivered.

**P2: No Verifiable Performance.** Even when agents attempt to track performance, the monitoring data is stored off-chain and can be fabricated or selectively omitted.

**P3: No Automated Consequences.** When a commitment is breached, there is no automated mechanism to compensate the harmed party or penalize the offender.

**P4: No Proportional Risk Management.** An agent contracting for a $10,000 service faces the same trust model as one contracting for $0.01 — there is no mechanism to require higher guarantees for higher-value commitments.

**P5: No Historical Accountability.** An agent that consistently underperforms can simply change its identity and start fresh, with no reputation consequences.

### 2.2 Requirements

A commitment tracking protocol for autonomous agents must satisfy the following requirements:

| Requirement | Description |
|---|---|
| **R1: Expressiveness** | Support arbitrary commitment conditions including latency bounds, accuracy thresholds, data freshness, and composite metrics. |
| **R2: Verifiability** | All performance data must be tamper-proof and independently auditable. |
| **R3: Automation** | Commitment creation, monitoring, enforcement, and settlement must operate without human intervention. |
| **R4: Economic Alignment** | The protocol must create economic incentives for agents to honor commitments and economic penalties for breaches. |
| **R5: Scalability** | Support millions of concurrent commitments with sub-dollar costs per commitment lifecycle. |
| **R6: Composability** | Commitments must be composable — an agent fulfilling one commitment should be able to sub-contract portions to other agents. |
| **R7: Privacy** | Sensitive commitment details should be concealable while maintaining verifiability. |

---

## 3. Related Work

### 3.1 Smart Contract SLAs

Traditional SLA systems in cloud computing (AWS CloudWatch, Azure SLAs) operate within centralized trust boundaries. Decentralized SLA systems have been explored in projects like Chainlink's Service Level Agreements for oracle networks, but these are specific to oracle data delivery and do not generalize to arbitrary agent services.

### 3.2 Agent Identity and Trust

The Hedera Agent Identity Plugin (ERC-8004 inspired) provides agent registration and authentication but does not address commitment enforcement. EQTY Lab's Verifiable Compute anchors AI pipeline attestations on Hedera but focuses on compute verification rather than service-level agreements.

### 3.3 Escrow Protocols

Existing escrow protocols (OpenZeppelin Escrow, Kleros) provide basic hold-and-release functionality but lack the graduated release model and automated performance verification that agent commitments require.

### 3.4 Multi-Agent Coordination

Frameworks like SWORN Protocol (Solana) implement trust scoring and penalty systems for agent networks but operate on different chains and focus on node-level trust rather than task-level commitments. PACT is complementary — it could use SWORN trust scores as inputs to commitment risk assessment.

### 3.5 Gap Analysis

| Feature | Cloud SLAs | Chainlink SLAs | Agent Identity | SWORN | **PACT** |
|---|---|---|---|---|---|
| Decentralized | No | Partial | Yes | Yes | **Yes** |
| Agent-native | No | No | Yes | Yes | **Yes** |
| Arbitrary services | Yes | No | N/A | Partial | **Yes** |
| Escrow/staking | No | Yes | No | Yes | **Yes** |
| Performance proofs | Centralized | On-chain | N/A | On-chain | **HCS** |
| Dispute resolution | Manual | Oracle-based | N/A | Slashing | **Automated** |
| Graduated release | No | No | No | No | **Yes** |
| Composable | No | No | N/A | No | **Yes** |

---

## 4. System Architecture

### 4.1 Overview

PACT Protocol consists of five layers:

```
+------------------------------------------------------------------+
|                     APPLICATION LAYER                             |
|  Agent SDK  |  Dashboard  |  CLI Tools  |  Hedera Agent Kit      |
+------------------------------------------------------------------+
|                     PROTOCOL LAYER                                |
|  Commitment  |  Escrow     |  Dispute    |  Reputation            |
|  Manager     |  Engine     |  Resolver   |  Registry              |
+------------------------------------------------------------------+
|                     MONITORING LAYER                              |
|  HCS Performance Oracle  |  Checkpoint Verifier  |  Alert Engine |
+------------------------------------------------------------------+
|                     SETTLEMENT LAYER                              |
|  HTS Token Manager  |  Smart Contract Escrow  |  Fee Distributor |
+------------------------------------------------------------------+
|                     HEDERA NETWORK                                |
|  HCS Topics  |  HTS Tokens  |  Smart Contracts  |  Mirror Node  |
+------------------------------------------------------------------+
```

### 4.2 Core Components

**Commitment Manager:** Handles the lifecycle of PACTs — creation, activation, monitoring, completion, and termination. Stores commitment specifications as HCS topic messages and manages state transitions via smart contracts.

**Escrow Engine:** Manages fund locking, graduated release, and refund operations using HTS tokens held in smart contract accounts. Supports multiple payment tokens (HBAR, USDC, custom HTS tokens).

**HCS Performance Oracle:** A novel component that uses dedicated HCS topics as tamper-proof performance monitoring channels. Each active commitment has an associated HCS topic where both parties (and optional third-party monitors) publish performance attestations.

**Dispute Resolver:** A smart contract that evaluates HCS evidence logs against commitment specifications and produces binding rulings. Supports both automated resolution (based on clear evidence) and escalated resolution (using a staked arbiter pool).

**Reputation Registry:** Maintains on-chain reputation scores derived from commitment history. Agents build reputation by successfully fulfilling commitments, and lose reputation (and staked tokens) when they breach commitments.

### 4.3 Data Flow

```
Agent A                    PACT Protocol                    Agent B
  |                            |                              |
  |--- 1. Create Commitment -->|                              |
  |                            |--- 2. Notify & Terms ------->|
  |                            |<-- 3. Accept & Stake --------|
  |<-- 4. Confirm & Lock ------|                              |
  |                            |                              |
  |                     [Execution Phase]                      |
  |                            |                              |
  |                            |<-- 5. Checkpoint Logs --------|
  |                            |--- 6. Progress Updates ----->|
  |--- 7. Verify Checkpoint -->|                              |
  |                            |--- 8. Release Tranche ------>|
  |                            |                              |
  |                     [Completion / Dispute]                 |
  |                            |                              |
  |--- 9. Confirm Delivery --->|                              |
  |                            |--- 10. Final Settlement ---->|
  |                            |--- 11. Update Reputation --->|
```

---

## 5. PACT Lifecycle

A PACT (Programmable Agent Commitment Transaction) progresses through the following states:

```
DRAFT --> PROPOSED --> ACCEPTED --> ACTIVE --> {COMPLETED | DISPUTED | EXPIRED}
                                                    |
                                              ARBITRATED
                                                    |
                                           {RESOLVED | SLASHED}
```

### 5.1 State Definitions

**DRAFT:** Agent A creates a commitment specification locally. No on-chain activity.

**PROPOSED:** Agent A publishes the commitment to an HCS topic and locks their payment into the escrow contract. The commitment becomes discoverable by Agent B (or is sent directly via agent-to-agent messaging).

**ACCEPTED:** Agent B reviews the terms, stakes their collateral (proportional to commitment value), and confirms acceptance. Both parties' funds are now locked.

**ACTIVE:** The commitment period begins. Agent B performs the contracted service. Performance checkpoints are logged to the commitment's HCS topic. The escrow engine releases tranches as checkpoints are verified.

**COMPLETED:** All commitment conditions are met. The escrow releases remaining payment to Agent B, and Agent B's collateral is returned. Both agents' reputations are updated positively.

**DISPUTED:** One party claims a breach. The dispute resolver examines HCS evidence and produces a ruling.

**EXPIRED:** The commitment period elapsed without completion or dispute. Predefined expiry rules determine fund distribution.

**ARBITRATED:** A dispute has been escalated to the arbiter pool for resolution.

**RESOLVED:** A dispute has been settled. Funds are distributed according to the ruling.

**SLASHED:** An agent's collateral has been partially or fully seized due to a confirmed breach.

### 5.2 State Transition Rules

Each state transition is recorded as an HCS message on the commitment topic and enforced by the PACT smart contract:

| Transition | Trigger | On-Chain Action |
|---|---|---|
| DRAFT -> PROPOSED | Agent A submits | HCS message + escrow lock |
| PROPOSED -> ACCEPTED | Agent B accepts | HCS message + collateral lock |
| ACCEPTED -> ACTIVE | Time condition met | Contract state update |
| ACTIVE -> COMPLETED | All conditions verified | Escrow release + reputation update |
| ACTIVE -> DISPUTED | Either party files | Dispute contract activated |
| ACTIVE -> EXPIRED | Timeout reached | Expiry rule execution |
| DISPUTED -> RESOLVED | Automated ruling | Fund distribution per ruling |
| DISPUTED -> ARBITRATED | Evidence inconclusive | Arbiter pool notified |
| ARBITRATED -> RESOLVED | Arbiter consensus | Fund distribution + arbiter rewards |
| RESOLVED -> SLASHED | Breach confirmed | Collateral seizure + reputation penalty |

---

## 6. Hedera Service Integration

### 6.1 HCS Topic Architecture

PACT uses a hierarchical HCS topic structure:

```
PACT_REGISTRY_TOPIC (public, submit-key controlled)
├── Commitment announcements
├── Protocol governance messages
└── Global reputation updates

PACT_COMMITMENT_TOPIC_{id} (per-commitment, party-controlled)
├── Commitment specification
├── Acceptance confirmation
├── Performance checkpoints
├── Completion attestations
└── Dispute evidence

PACT_ARBITER_TOPIC (public, stake-gated)
├── Dispute escalations
├── Arbiter votes
└── Ruling announcements
```

**Topic Creation Parameters:**

```javascript
// Commitment-specific topic
const topicCreateTx = new TopicCreateTransaction()
  .setTopicMemo(`PACT:v1:${commitmentId}`)
  .setSubmitKey(new KeyList([agentAKey, agentBKey, protocolKey]))
  .setAdminKey(protocolKey);
```

Each commitment topic uses a `submitKey` that is a KeyList requiring signatures from both parties, ensuring that neither party can unilaterally post fabricated evidence.

### 6.2 HTS Token Integration

PACT Protocol uses HTS for three token types:

**1. PACT Governance Token (PACT)**
- Fungible HTS token
- Used for protocol governance, arbiter staking, and fee payment
- Supply: 100,000,000 PACT
- Minted at protocol launch, distributed via ecosystem incentives

**2. Escrow Wrapper Tokens**
- Temporary HTS tokens minted 1:1 against locked collateral
- Represent locked positions in active commitments
- Burned upon commitment resolution
- Enable secondary market liquidity for locked positions (future feature)

**3. Reputation Soulbound Tokens (RSTs)**
- Non-fungible, non-transferable HTS tokens
- Encode an agent's commitment history: completions, breaches, dispute outcomes
- Updated via authorized supply key operations

**Token Creation:**

```javascript
const pactToken = new TokenCreateTransaction()
  .setTokenName("PACT Protocol")
  .setTokenSymbol("PACT")
  .setTokenType(TokenType.FungibleCommon)
  .setDecimals(8)
  .setInitialSupply(10_000_000_000_000_000) // 100M with 8 decimals
  .setSupplyKey(protocolKey)
  .setFreezeKey(protocolKey)
  .setPauseKey(protocolKey)
  .setCustomFees([
    new CustomFixedFee()
      .setAmount(1000) // 0.00001 PACT per transfer
      .setFeeCollectorAccountId(treasuryAccount)
  ]);
```

### 6.3 Smart Contract Architecture

PACT deploys three core Solidity contracts on Hedera:

**PACTEscrow.sol** — Manages fund locking, graduated release, and refund operations.

**PACTResolver.sol** — Evaluates dispute evidence from HCS logs and produces rulings.

**PACTRegistry.sol** — Maintains agent registration, reputation scores, and commitment indexes.

These contracts interact with HTS via the HTS System Contract precompile (address `0x167`), enabling native token operations from within Solidity.

---

## 7. Commitment Specification Language

### 7.1 PSL Overview

The PACT Specification Language (PSL) is a JSON-based format for expressing commitment terms that can be automatically verified against HCS performance logs.

```json
{
  "pact_version": "1.0",
  "commitment_id": "pact_7f3a2b1c",
  "created_at": "2026-03-19T10:00:00Z",
  "parties": {
    "provider": {
      "agent_id": "hedera:0.0.12345",
      "did": "did:hedera:mainnet:0.0.12345"
    },
    "consumer": {
      "agent_id": "hedera:0.0.67890",
      "did": "did:hedera:mainnet:0.0.67890"
    }
  },
  "service": {
    "type": "data_collection",
    "description": "Collect pricing data from 500 e-commerce sites",
    "deliverable": {
      "format": "json",
      "schema_hash": "sha256:abc123..."
    }
  },
  "conditions": [
    {
      "metric": "completion_rate",
      "operator": ">=",
      "threshold": 0.95,
      "unit": "ratio",
      "verification": "checkpoint_count"
    },
    {
      "metric": "latency",
      "operator": "<=",
      "threshold": 7200,
      "unit": "seconds",
      "verification": "hcs_timestamp_delta"
    },
    {
      "metric": "data_accuracy",
      "operator": ">=",
      "threshold": 0.98,
      "unit": "ratio",
      "verification": "sample_audit"
    }
  ],
  "checkpoints": {
    "interval": 600,
    "required_count": 12,
    "schema": {
      "sites_processed": "uint",
      "errors_encountered": "uint",
      "sample_hash": "bytes32"
    }
  },
  "payment": {
    "token": "0.0.456789",
    "amount": 5000000000,
    "decimals": 8,
    "release_schedule": "graduated"
  },
  "collateral": {
    "provider_stake": 1000000000,
    "consumer_stake": 5000000000,
    "slash_percentage": 50
  },
  "timing": {
    "acceptance_window": 3600,
    "execution_window": 7200,
    "dispute_window": 1800,
    "expiry": "2026-03-19T12:00:00Z"
  }
}
```

### 7.2 Condition Types

PSL supports the following condition verification methods:

| Verification Method | Description | Data Source |
|---|---|---|
| `checkpoint_count` | Counts completed checkpoints on HCS topic | HCS messages |
| `hcs_timestamp_delta` | Measures time between first and last HCS checkpoint | HCS timestamps |
| `sample_audit` | Verifies random samples of deliverable against specification | HCS + off-chain oracle |
| `binary_delivery` | Checks for a delivery confirmation message | HCS message |
| `external_oracle` | Queries an external data source for verification | Oracle contract |
| `multi_party_attestation` | Requires N-of-M parties to confirm | HCS signed messages |

### 7.3 Formal Verification

A commitment `C` is considered **fulfilled** if and only if all conditions `c_i` evaluate to `true`:

```
fulfilled(C) = ∀ c_i ∈ C.conditions : evaluate(c_i, evidence(C.topic_id)) = true
```

where `evidence(topic_id)` is the complete, ordered set of HCS messages on the commitment's topic, and `evaluate` is a deterministic function mapping condition specifications to boolean outcomes based on the evidence.

A commitment is **breached** if any mandatory condition evaluates to `false` after the execution window has elapsed:

```
breached(C) = ∃ c_i ∈ C.conditions : (c_i.mandatory = true) ∧ (evaluate(c_i, evidence(C.topic_id)) = false) ∧ (now > C.timing.expiry)
```

---

## 8. Escrow and Staking Mechanics

### 8.1 Graduated Escrow Release

Unlike traditional escrow (all-or-nothing), PACT implements a graduated release model that reduces risk for both parties by releasing funds proportionally to verified progress.

Given a commitment with payment amount `P`, collateral `S`, and `n` required checkpoints, the release schedule is:

```
tranche_k = P × w_k / Σ(w_i)  for k = 1, 2, ..., n
```

where `w_k` is the weight of checkpoint `k`. By default, weights are uniform (`w_k = 1/n`), but PSL supports custom weight distributions for commitments where later stages are more valuable.

**Example:** For a 50 USDC commitment with 10 checkpoints:
- Each checkpoint verification releases 5 USDC
- If the provider completes 7/10 checkpoints before timeout, they receive 35 USDC
- The remaining 15 USDC is returned to the consumer
- Collateral is returned proportionally: `S_returned = S × (checkpoints_completed / n)`

### 8.2 Collateral Requirements

The required collateral for a commitment is determined by the provider's reputation score and the commitment value:

```
collateral_required = base_rate × commitment_value × risk_multiplier(reputation)
```

where:
- `base_rate` = 0.20 (20% of commitment value)
- `risk_multiplier(r)` = max(0.5, 2.0 - r/100) for reputation score `r ∈ [0, 100]`

| Reputation Score | Risk Multiplier | Effective Collateral Rate |
|---|---|---|
| 0 (new agent) | 2.00 | 40% |
| 25 | 1.75 | 35% |
| 50 | 1.50 | 30% |
| 75 | 1.25 | 25% |
| 100 (perfect) | 1.00 | 20% |

This creates a virtuous cycle: agents with strong track records are required to lock less capital, incentivizing consistent performance.

### 8.3 Slashing Conditions

When a commitment is breached, the provider's collateral is slashed according to the breach severity:

```
slash_amount = collateral × severity_factor × (1 - partial_completion_rate)
```

where:
- `severity_factor` is defined per condition in the PSL (default: 0.5)
- `partial_completion_rate` = checkpoints_completed / total_checkpoints

Slashed funds are distributed as follows:
- 70% to the harmed consumer (compensation)
- 20% to the protocol treasury (sustainability)
- 10% to arbiters who resolved the dispute (incentive)

### 8.4 Escrow Contract

```solidity
// Simplified PACTEscrow interface
interface IPACTEscrow {
    /// @notice Lock payment for a new commitment
    /// @param commitmentId The unique commitment identifier
    /// @param providerAccount The provider's Hedera account
    /// @param tokenId The HTS token used for payment
    /// @param paymentAmount The total payment amount
    /// @param collateralAmount The required collateral from provider
    function lockFunds(
        bytes32 commitmentId,
        address providerAccount,
        address tokenId,
        uint256 paymentAmount,
        uint256 collateralAmount
    ) external;

    /// @notice Release a tranche upon checkpoint verification
    /// @param commitmentId The commitment identifier
    /// @param checkpointIndex The verified checkpoint index
    /// @param hcsSequenceNumber The HCS message sequence proving completion
    function releaseTranche(
        bytes32 commitmentId,
        uint256 checkpointIndex,
        uint64 hcsSequenceNumber
    ) external;

    /// @notice Slash provider collateral upon confirmed breach
    /// @param commitmentId The commitment identifier
    /// @param severityBps The severity in basis points (0-10000)
    function slash(
        bytes32 commitmentId,
        uint256 severityBps
    ) external;

    /// @notice Refund consumer upon commitment expiry
    /// @param commitmentId The commitment identifier
    function refund(bytes32 commitmentId) external;
}
```

---

## 9. Performance Monitoring via HCS

### 9.1 HCS as a Performance Oracle

PACT introduces a novel use of HCS topics as tamper-proof performance monitoring channels. Each active commitment has a dedicated HCS topic where performance data is published as structured messages.

The key insight is that HCS provides three properties essential for performance monitoring:

1. **Immutability:** Once a checkpoint message is submitted, it cannot be altered or deleted.
2. **Ordering:** Messages receive a consensus timestamp, establishing an indisputable chronological record.
3. **Availability:** Messages are available via the Hedera Mirror Node, enabling any party to independently verify performance.

### 9.2 Checkpoint Message Format

```json
{
  "type": "CHECKPOINT",
  "commitment_id": "pact_7f3a2b1c",
  "checkpoint_index": 5,
  "timestamp": "2026-03-19T10:50:00Z",
  "reporter": "0.0.12345",
  "metrics": {
    "sites_processed": 250,
    "errors_encountered": 3,
    "sample_hash": "0xabc123...",
    "cpu_seconds_used": 1847
  },
  "evidence_hash": "sha256:def456...",
  "signature": "0x..."
}
```

### 9.3 Verification Pipeline

The checkpoint verification pipeline operates as follows:

```
1. Provider submits checkpoint to HCS topic
        ↓
2. HCS assigns consensus timestamp (3-5 second finality)
        ↓
3. Mirror Node indexes the message
        ↓
4. PACT Verifier reads the checkpoint:
   a. Validate message signature matches provider's key
   b. Validate checkpoint_index is sequential
   c. Validate metrics conform to PSL schema
   d. Validate timing (within execution window)
        ↓
5. If valid: call PACTEscrow.releaseTranche()
        ↓
6. Escrow releases proportional payment to provider
```

### 9.4 Anti-Gaming Measures

**Fake Checkpoint Prevention:** Checkpoints include an `evidence_hash` — the hash of the actual deliverable data at that point. The consumer can challenge any checkpoint by requesting the pre-image. If the provider cannot produce data matching the hash, the checkpoint is invalidated.

**Timestamp Manipulation:** HCS timestamps are assigned by Hedera's hashgraph consensus, making them tamper-proof. An agent cannot backdate or pre-date a checkpoint.

**Replay Prevention:** Each checkpoint must have a strictly incrementing `checkpoint_index`. The smart contract tracks the last verified index and rejects duplicates.

**Collusion Prevention:** For high-value commitments, the protocol can require third-party monitor attestations. Monitors are randomly selected from the arbiter pool and must independently verify checkpoint claims.

### 9.5 Cost Analysis

At HCS's current fee structure (~$0.0001 per message), the monitoring cost for a typical commitment is minimal:

| Scenario | Checkpoints | HCS Messages | Cost |
|---|---|---|---|
| Quick task (1 hour) | 6 | ~8 (6 + setup/close) | ~$0.0008 |
| Standard task (24 hours) | 24 | ~28 | ~$0.0028 |
| Long-running task (7 days) | 168 | ~175 | ~$0.0175 |
| High-frequency monitoring | 1,000 | ~1,010 | ~$0.101 |

Even the most intensive monitoring scenario costs under $0.11, making PACT economically viable for micro-commitments.

---

## 10. Dispute Resolution Engine

### 10.1 Overview

Disputes arise when one party believes a commitment has been breached. The PACT dispute resolution engine operates in two tiers:

**Tier 1: Automated Resolution** — The dispute resolver smart contract evaluates the HCS evidence logs against the commitment specification. If the evidence is unambiguous (e.g., required checkpoints are missing, or deadline was exceeded), the contract produces an automated ruling.

**Tier 2: Arbiter Resolution** — When evidence is ambiguous (e.g., quality disputes, partial completion claims), the dispute is escalated to a pool of staked arbiters who review the evidence and vote on a ruling.

### 10.2 Automated Resolution Logic

```
function resolve(commitmentId) -> Ruling:
    spec = getCommitmentSpec(commitmentId)
    evidence = getHCSMessages(spec.topicId)

    for each condition in spec.conditions:
        result = evaluate(condition, evidence)
        if result == UNAMBIGUOUS_PASS:
            markConditionPassed(condition)
        elif result == UNAMBIGUOUS_FAIL:
            markConditionFailed(condition)
        elif result == AMBIGUOUS:
            return escalateToArbiters(commitmentId)

    if allConditionsPassed():
        return Ruling(FULFILLED, releaseAll=true)
    else:
        failedRatio = failedConditions / totalConditions
        return Ruling(BREACHED, slashPercent=failedRatio * severityFactor)
```

### 10.3 Arbiter Pool

Arbiters are agents or humans who stake PACT tokens to join the arbiter pool. When a dispute is escalated:

1. **Selection:** 5 arbiters are randomly selected (weighted by stake) from the pool, excluding any with conflicts of interest (prior commitments with either party).
2. **Evidence Review:** Arbiters receive the full HCS log, the commitment specification, and any additional evidence submitted by the parties.
3. **Voting:** Each arbiter submits a signed vote to the arbiter HCS topic. Votes are hidden until the voting period ends (commit-reveal scheme).
4. **Resolution:** A 3-of-5 majority determines the ruling. The ruling specifies the fund distribution.
5. **Rewards:** Arbiters who voted with the majority receive a share of the dispute resolution fee. Arbiters who voted against the majority receive nothing.

**Arbiter Staking Requirements:**

```
minimum_arbiter_stake = 1000 PACT
maximum_disputes_per_arbiter = 10 concurrent
arbiter_lock_period = 30 days after last ruling
```

### 10.4 Appeal Mechanism

Either party may appeal an automated or arbiter ruling within the appeal window (default: 24 hours) by posting an appeal bond of 2x the dispute resolution fee. Appeals are heard by 9 arbiters (none from the original panel) and require a 6-of-9 majority to overturn.

---

## 11. Economic Model

### 11.1 Fee Structure

| Fee Type | Amount | Recipient |
|---|---|---|
| Commitment creation | 10 PACT | Protocol treasury |
| Checkpoint verification | 1 PACT | Protocol treasury |
| Successful completion | 0.5% of payment | Protocol treasury |
| Dispute filing | 50 PACT | Arbiter pool + treasury |
| Appeal bond | 100 PACT | Returned if appeal succeeds |

### 11.2 Token Economics

**Supply:** 100,000,000 PACT (fixed supply)

**Distribution:**

| Allocation | Percentage | Tokens | Vesting |
|---|---|---|---|
| Ecosystem Incentives | 40% | 40,000,000 | 4-year linear |
| Team & Contributors | 20% | 20,000,000 | 2-year cliff, 3-year linear |
| Protocol Treasury | 15% | 15,000,000 | Governance-controlled |
| Arbiter Bootstrap | 10% | 10,000,000 | Released as arbiters join |
| Liquidity & Partnerships | 10% | 10,000,000 | 1-year linear |
| Community Grants | 5% | 5,000,000 | On-demand |

### 11.3 Value Accrual

PACT token derives value from three sources:

1. **Fee Revenue:** All protocol fees are collected in PACT, creating natural buy pressure as the ecosystem grows.
2. **Staking Demand:** Arbiters and providers must hold and stake PACT, reducing circulating supply.
3. **Governance Rights:** PACT holders vote on protocol parameters (fee rates, collateral requirements, supported tokens).

### 11.4 Flywheel Effect

```
More agents → More commitments → More fees → Higher PACT value
      ↑                                              |
      |         More arbiters ← More staking demand ←|
      |              |
      +-- Better dispute resolution → More trust → More agents
```

---

## 12. Security Analysis

### 12.1 Threat Model

We consider the following adversaries:

**A1: Malicious Provider** — An agent that accepts commitments but intentionally underdelivers or delivers fabricated results.

**Mitigation:** Collateral staking ensures economic loss for breach. Checkpoint evidence hashes prevent data fabrication. Reputation system makes serial fraud increasingly expensive.

**A2: Malicious Consumer** — An agent that receives a valid deliverable but disputes to avoid payment.

**Mitigation:** HCS evidence logs provide tamper-proof delivery proof. Automated resolution based on checkpoint data limits false dispute success. Consumers who file frivolous disputes lose their dispute filing fee and reputation.

**A3: Colluding Arbiters** — A subset of arbiters who coordinate to produce biased rulings.

**Mitigation:** Random arbiter selection weighted by stake. Commit-reveal voting prevents coordination. Appeal mechanism with fresh arbiter panel. Collusion requires controlling 3 of 5 randomly selected arbiters — economically infeasible at scale.

**A4: Sybil Agent** — An agent that creates multiple identities to escape reputation consequences.

**Mitigation:** Collateral requirements for new agents (high risk multiplier). Integration with Hedera Agent Identity Plugin (DID-based). Minimum account age and activity requirements.

**A5: Network-Level Attacks** — Attempts to manipulate HCS message ordering or smart contract execution.

**Mitigation:** Hedera's aBFT hashgraph consensus is resilient to 1/3 Byzantine nodes. HCS message ordering is deterministic and tamper-proof. Smart contracts execute deterministically on Hedera's EVM.

### 12.2 Economic Security Bounds

The cost of attacking the protocol scales with commitment value:

```
attack_cost = collateral_at_risk + reputation_loss_value + opportunity_cost

For a new agent (reputation = 0):
  collateral_at_risk = 0.40 × commitment_value
  reputation_loss_value ≈ 0  (new agent has nothing to lose)

For an established agent (reputation = 80):
  collateral_at_risk = 0.22 × commitment_value
  reputation_loss_value ≈ present_value(future_commitment_discounts)
```

The protocol is economically secure when `attack_cost > attack_profit` for rational adversaries. For new agents, the 40% collateral requirement ensures this property holds for any commitment where the provider expects to gain less than 40% of the commitment value from cheating.

### 12.3 Formal Properties

**Safety:** No honest agent can lose funds without a verified breach or valid dispute ruling.

*Proof sketch:* Funds are locked in the escrow contract and can only be released via (a) verified checkpoints, (b) successful completion, (c) dispute ruling, or (d) expiry timeout. Each path requires either the provider's verified performance (a, b), arbiter consensus (c), or contract-enforced timeout logic (d). An honest agent who fulfills all conditions will have verifiable HCS evidence supporting their case.

**Liveness:** Every commitment eventually reaches a terminal state (COMPLETED, RESOLVED, or EXPIRED).

*Proof sketch:* Each state has a bounded timeout. ACTIVE commitments expire after the execution window. DISPUTED commitments have a bounded voting period. ARBITRATED commitments have a bounded appeal window. The composition of bounded timeouts guarantees termination.

**Fairness:** Honest agents are compensated proportionally to their verified performance.

*Proof sketch:* The graduated escrow model releases funds per verified checkpoint. An agent who completes K of N checkpoints receives K/N of the payment (assuming uniform weights). The verification is based on tamper-proof HCS evidence, so honest agents' checkpoints cannot be denied.

---

## 13. Implementation

### 13.1 Technology Stack

| Component | Technology |
|---|---|
| Smart Contracts | Solidity 0.8.x on Hedera EVM |
| Agent SDK | TypeScript (Hedera Agent Kit plugin) |
| HCS Integration | @hashgraph/sdk |
| Mirror Node Queries | Hedera Mirror Node REST API |
| Off-chain Indexer | Node.js + PostgreSQL |
| Frontend Dashboard | Next.js 15 + React |
| Testing | Hardhat + Hedera Local Node |

### 13.2 Hedera Agent Kit Plugin

PACT is implemented as a Hedera Agent Kit plugin, enabling any agent built with the Agent Kit to form and manage commitments:

```typescript
import { PACTPlugin } from '@pact-protocol/hedera-agent-plugin';

const agent = new HederaAgentKit({
  accountId: '0.0.12345',
  privateKey: process.env.HEDERA_PRIVATE_KEY,
  network: 'mainnet',
  plugins: [
    new PACTPlugin({
      registryTopicId: '0.0.999999',
      escrowContractId: '0.0.888888',
      defaultCollateralToken: '0.0.777777',
    }),
  ],
});

// Create a commitment
const commitment = await agent.pact.createCommitment({
  service: 'data_collection',
  conditions: [
    { metric: 'completion_rate', operator: '>=', threshold: 0.95 },
    { metric: 'latency', operator: '<=', threshold: 7200, unit: 'seconds' },
  ],
  payment: { token: '0.0.456789', amount: 50_00000000 },
  checkpoints: { interval: 600, count: 12 },
});

// Accept a commitment (as provider)
await agent.pact.acceptCommitment(commitment.id, {
  collateral: { token: '0.0.456789', amount: 10_00000000 },
});

// Submit a checkpoint (during execution)
await agent.pact.submitCheckpoint(commitment.id, {
  metrics: { sites_processed: 250, errors: 3 },
  evidenceHash: '0xabc123...',
});

// File a dispute
await agent.pact.dispute(commitment.id, {
  reason: 'Data quality below threshold',
  evidence: [{ type: 'sample_audit', data: '...' }],
});
```

### 13.3 Smart Contract Deployment

```
PACTRegistry.sol  → Deployed at 0.0.REGISTRY
PACTEscrow.sol    → Deployed at 0.0.ESCROW
PACTResolver.sol  → Deployed at 0.0.RESOLVER

Dependencies:
  - HTS System Contract (0x167 precompile)
  - Hedera Mirror Node REST API
  - PACT HCS Topics (created at deployment)
```

### 13.4 Development Status

| Component | Status |
|---|---|
| PSL Specification | Complete |
| PACTEscrow.sol | In development |
| PACTResolver.sol | In development |
| PACTRegistry.sol | In development |
| Agent Kit Plugin | In development |
| HCS Performance Oracle | In development |
| Dashboard UI | Design phase |
| Documentation | This whitepaper |

---

## 14. Use Cases

### 14.1 AI Agent Task Marketplace

A marketplace where AI agents list their capabilities and form PACT commitments for task execution. A research agent needs data from 1,000 academic papers — it creates a PACT commitment offering 100 HBAR for extraction with 95% accuracy. A specialized scraping agent accepts, stakes collateral, and delivers results with checkpoint-verified progress.

### 14.2 Multi-Agent Pipeline SLAs

Complex workflows involving chains of agents (data collection -> processing -> analysis -> reporting) use nested PACTs. Each link in the chain has its own commitment with appropriate conditions. If any agent in the pipeline breaches their commitment, the upstream agents are automatically compensated from the breaching agent's collateral.

### 14.3 Autonomous DeFi Agent Guarantees

DeFi agents that manage funds on behalf of users can form PACT commitments specifying performance bounds (maximum drawdown, minimum yield, rebalancing frequency). If the agent violates these bounds, the user is automatically compensated.

### 14.4 Enterprise AI Service Agreements

Enterprises deploying AI agents can use PACT to formalize service-level expectations. An enterprise's customer service agent commits to 95th-percentile response times under 2 seconds, resolution rates above 80%, and escalation protocols. PACT provides the audit trail regulators require.

### 14.5 Cross-Agent Data Licensing

Agents that generate valuable data (market analysis, sentiment signals, research summaries) can license it to other agents via PACT commitments. The commitment specifies data freshness, update frequency, and accuracy guarantees. Payment is released per verified data delivery.

---

## 15. Roadmap

### Phase 1: Foundation (Q1 2026)
- [x] Whitepaper and specification
- [ ] Core smart contracts (Escrow, Registry, Resolver)
- [ ] HCS topic management library
- [ ] Hedera testnet deployment
- [ ] Basic Agent Kit plugin

### Phase 2: Core Protocol (Q2 2026)
- [ ] PSL v1.0 specification finalization
- [ ] Graduated escrow implementation
- [ ] Automated dispute resolution
- [ ] Mirror Node indexer
- [ ] Agent reputation system

### Phase 3: Ecosystem (Q3 2026)
- [ ] Arbiter pool launch
- [ ] Dashboard UI
- [ ] Multi-token support (HBAR, USDC, custom HTS)
- [ ] Third-party integrations (OpenClaw, ElizaOS)
- [ ] Mainnet deployment

### Phase 4: Scale (Q4 2026)
- [ ] Commitment composability (nested PACTs)
- [ ] Cross-chain commitment bridging (Solana via SWORN)
- [ ] Advanced PSL conditions (ML-based verification)
- [ ] Governance decentralization
- [ ] Enterprise features (private commitments, custom resolvers)

---

## 16. Conclusion

PACT Protocol addresses the critical gap between AI agents' growing transactional capabilities and the trust infrastructure needed to support them. By leveraging Hedera's unique combination of tamper-proof consensus logging (HCS), native token management (HTS), and EVM-compatible smart contracts, PACT creates a trustless environment where autonomous agents can form, monitor, and enforce service commitments with real economic consequences.

The protocol's graduated escrow model, HCS-based performance monitoring, and tiered dispute resolution system provide a comprehensive accountability framework that scales from micro-tasks costing fractions of a cent to enterprise-grade service agreements worth thousands of dollars.

As autonomous AI agents become primary economic actors, the infrastructure for verifiable commitments between them will be as fundamental as smart contracts were for DeFi. PACT Protocol aims to be that infrastructure, built on Hedera's enterprise-grade foundation.

---

## 17. References

1. Hedera. "Hedera Consensus Service." https://hedera.com/service/consensus-service/
2. Hedera. "Hedera Token Service." https://hedera.com/service/token-service/
3. Hedera. "Smart Contract Service." https://hedera.com/service/smart-contract-service/
4. Hedera. "Hedera AI Agent Kit." https://docs.hedera.com/hedera/open-source-solutions/ai-studio-on-hedera/hedera-ai-agent-kit
5. Hedera. "Leading the Charge in Agentic AI." https://hedera.com/blog/hedera-leading-the-charge-in-agentic-ai/
6. EQTY Lab. "Verifiable Compute Brings Trust to AI with Hedera." https://hedera.com/blog/eqty-labs-verifiable-compute-brings-trust-to-ai-with-hedera/
7. Hashgraph. "hedera-agent-kit-js." https://github.com/hashgraph/hedera-agent-kit-js
8. Hedera. "HIP-991: Permissionless Revenue-Generating Topic IDs." https://hedera.com/blog/introducing-hip-991-permissionless-revenue-generating-topic-ids-for-topic-operators/
9. Baird, L. "The Swirlds Hashgraph Consensus Algorithm." 2016.
10. Hedera. "Hedera AI Studio." https://hedera.com/product/ai-studio/

---

*PACT Protocol is an open-source project. All code, specifications, and documentation are available under the MIT License.*

*For inquiries: https://github.com/alexchenai/hedera-pact-protocol*
