# PACT Protocol

**Programmable Agent Commitment Tracking on Hedera**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Hedera](https://img.shields.io/badge/Built%20on-Hedera-8259EF)](https://hedera.com)
[![Track](https://img.shields.io/badge/Hello%20Future%20Apex-AI%20%26%20Agents-green)](https://hellofuturehackathon.dev)

> Trustless service-level agreements for autonomous AI agents, powered by Hedera Consensus Service.

---

## The Problem

AI agents are becoming economic actors — they negotiate, transact, and delegate tasks. But there is no mechanism to enforce that an agent will deliver on its promises. Today's options are blind trust, human oversight, or centralized intermediaries. None scale.

## The Solution

PACT Protocol enables AI agents to form **verifiable, enforceable service commitments** with:

- **Graduated Escrow** — Funds are released proportionally to verified progress, not all-or-nothing
- **HCS Performance Monitoring** — Tamper-proof checkpoint logs on Hedera Consensus Service (~$0.0001/message)
- **Automated Dispute Resolution** — Smart contracts evaluate HCS evidence and produce binding rulings
- **Reputation Staking** — Agents stake collateral proportional to commitment value and their track record
- **Composable Commitments** — Agents can sub-contract portions of their commitments to other agents

## Architecture

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

## Why Hedera

| Feature | Why It Matters for PACT |
|---|---|
| **HCS (Consensus Service)** | Tamper-proof, ordered, timestamped performance logs — perfect for checkpoint evidence |
| **HTS (Token Service)** | Native token creation for escrow, staking, and reputation tokens with built-in compliance |
| **Low Fees** | ~$0.0001 per HCS message enables high-frequency performance monitoring at near-zero cost |
| **10,000+ TPS** | Supports millions of concurrent agent commitments |
| **EVM Compatible** | Complex escrow and dispute logic in Solidity, with native HTS integration via precompiles |
| **Fair Ordering** | Hashgraph consensus prevents front-running in commitment markets |
| **3-5s Finality** | Performance checkpoints are finalized in seconds |

## Quick Start

```typescript
import { PACTPlugin } from '@pact-protocol/hedera-agent-plugin';

const agent = new HederaAgentKit({
  accountId: '0.0.12345',
  privateKey: process.env.HEDERA_PRIVATE_KEY,
  network: 'testnet',
  plugins: [new PACTPlugin()],
});

// Create a commitment
const pact = await agent.pact.createCommitment({
  service: 'data_collection',
  conditions: [
    { metric: 'completion_rate', operator: '>=', threshold: 0.95 },
    { metric: 'latency', operator: '<=', threshold: 7200, unit: 'seconds' },
  ],
  payment: { token: '0.0.456789', amount: 50_00000000 },
  checkpoints: { interval: 600, count: 12 },
});

// Provider accepts and stakes collateral
await agent.pact.acceptCommitment(pact.id, {
  collateral: { token: '0.0.456789', amount: 10_00000000 },
});

// Submit performance checkpoints during execution
await agent.pact.submitCheckpoint(pact.id, {
  metrics: { sites_processed: 250, errors: 3 },
  evidenceHash: '0xabc123...',
});
```

## PACT Lifecycle

```
DRAFT --> PROPOSED --> ACCEPTED --> ACTIVE --> COMPLETED
                                      |
                                   DISPUTED --> ARBITRATED --> RESOLVED
```

1. **Consumer** creates a commitment spec (conditions, payment, timing)
2. **Provider** reviews terms and stakes collateral
3. **Execution** begins — provider logs checkpoints to HCS
4. **Escrow** releases payment tranches as checkpoints are verified
5. **Completion** or **Dispute** — automated resolution using HCS evidence

## Key Innovation: HCS Performance Oracle

PACT uses HCS topics as **tamper-proof performance monitoring channels**. Each checkpoint message receives an immutable consensus timestamp from Hedera's hashgraph, creating an indisputable record of what was delivered and when.

Cost for full commitment monitoring: **< $0.02** (even for week-long tasks with hourly checkpoints).

## Use Cases

- **AI Task Marketplace** — Agents list capabilities, form PACTs, deliver with accountability
- **Multi-Agent Pipeline SLAs** — Chain of agents with nested commitments and cascading guarantees
- **Autonomous DeFi Guarantees** — Fund-managing agents commit to performance bounds
- **Enterprise AI Service Agreements** — Regulatory-compliant audit trails for AI operations
- **Cross-Agent Data Licensing** — Data freshness and accuracy guarantees with automated enforcement

## Documentation

- [Whitepaper](whitepaper.md) — Full technical specification (17 sections)
- [PACT Specification Language](whitepaper.md#7-commitment-specification-language) — JSON-based commitment format
- [Economic Model](whitepaper.md#11-economic-model) — Token economics and fee structure
- [Security Analysis](whitepaper.md#12-security-analysis) — Threat model and formal properties

## Project Structure

```
hedera-pact-protocol/
├── README.md                    # This file
├── whitepaper.md                # Full whitepaper
├── contracts/                   # Solidity smart contracts
│   ├── PACTEscrow.sol          # Graduated escrow management
│   ├── PACTRegistry.sol        # Agent registration and reputation
│   └── PACTResolver.sol        # Dispute resolution engine
├── sdk/                        # TypeScript Agent Kit plugin
│   └── src/
│       ├── plugin.ts           # Hedera Agent Kit plugin
│       ├── commitment.ts       # Commitment management
│       ├── checkpoint.ts       # HCS checkpoint handling
│       └── types.ts            # PSL type definitions
└── docs/                       # Additional documentation
    └── psl-spec.md             # PSL formal specification
```

## Roadmap

| Phase | Timeline | Milestones |
|---|---|---|
| Foundation | Q1 2026 | Whitepaper, core contracts, testnet deployment |
| Core Protocol | Q2 2026 | PSL v1.0, graduated escrow, automated disputes |
| Ecosystem | Q3 2026 | Arbiter pool, dashboard UI, mainnet launch |
| Scale | Q4 2026 | Composable PACTs, cross-chain bridging, governance |

## Team

Built by the team behind [SWORN Protocol](https://github.com/alexchenai/sworn-protocol) (Solana-based trust infrastructure for AI agent networks).

## License

MIT License. See [LICENSE](LICENSE) for details.

---

**Hello Future Apex Hackathon 2026** | AI & Agents Track

*PACT Protocol: Because autonomous agents need accountable commitments.*
