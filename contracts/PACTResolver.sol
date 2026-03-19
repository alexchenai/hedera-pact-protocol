// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IPACTEscrow.sol";
import "./interfaces/IPACTRegistry.sol";

/**
 * @title PACTResolver
 * @notice Dispute resolution engine for PACT Protocol.
 *         Evaluates commitment breaches and produces binding rulings
 *         based on HCS evidence logs.
 *
 * @dev Two-tier resolution:
 *      Tier 1: Automated — clear breaches (missing checkpoints, timeouts)
 *      Tier 2: Arbiter — ambiguous cases requiring human/agent judgment
 */
contract PACTResolver {
    // ---------------------------------------------------------------
    //  Constants
    // ---------------------------------------------------------------

    uint256 constant BPS_DENOMINATOR = 10_000;

    /// @notice Minimum PACT stake to become an arbiter
    uint256 constant MIN_ARBITER_STAKE = 1000 * 1e8; // 1000 PACT

    /// @notice Number of arbiters per dispute panel
    uint256 constant PANEL_SIZE = 5;

    /// @notice Required majority for ruling (3 of 5)
    uint256 constant REQUIRED_MAJORITY = 3;

    /// @notice Dispute filing fee in PACT tokens
    uint256 constant DISPUTE_FEE = 50 * 1e8; // 50 PACT

    /// @notice Voting period duration in seconds
    uint256 constant VOTING_PERIOD = 86_400; // 24 hours

    /// @notice Appeal bond (2x dispute fee)
    uint256 constant APPEAL_BOND = 100 * 1e8; // 100 PACT

    // ---------------------------------------------------------------
    //  State
    // ---------------------------------------------------------------

    IPACTEscrow public escrow;
    IPACTRegistry public registry;
    address public pactToken;
    address public admin;

    enum DisputeState {
        NONE,
        FILED,
        AUTOMATED_RESOLVED,
        ARBITER_ASSIGNED,
        VOTING,
        RESOLVED,
        APPEALED,
        APPEAL_RESOLVED
    }

    enum RulingOutcome {
        NONE,
        PROVIDER_WINS,      // No breach — release remaining funds
        CONSUMER_WINS,      // Breach confirmed — slash + refund
        PARTIAL             // Partial breach — proportional resolution
    }

    struct Dispute {
        bytes32 commitmentId;
        address filer;           // Who filed the dispute
        address respondent;      // Other party
        DisputeState state;
        RulingOutcome ruling;
        uint256 severityBps;     // Slash severity if consumer wins
        uint256 filedAt;
        uint256 votingEndsAt;
        uint256 totalVotes;
        uint256 providerVotes;   // Votes in favor of provider
        uint256 consumerVotes;   // Votes in favor of consumer
    }

    struct Arbiter {
        uint256 stakedAmount;
        uint256 activeDisputes;
        uint256 totalResolved;
        uint256 correctVotes;    // Votes aligned with majority
        bool isActive;
    }

    /// @notice Dispute ID => Dispute details
    mapping(bytes32 => Dispute) public disputes;

    /// @notice Arbiter address => Arbiter details
    mapping(address => Arbiter) public arbiters;

    /// @notice Dispute ID => arbiter address => has voted
    mapping(bytes32 => mapping(address => bool)) public hasVoted;

    /// @notice Dispute ID => arbiter address => vote (true = provider wins)
    mapping(bytes32 => mapping(address => bool)) public arbiterVotes;

    /// @notice Dispute ID => assigned panel members
    mapping(bytes32 => address[]) public disputePanels;

    /// @notice Total active arbiters
    uint256 public totalArbiters;

    /// @notice All arbiter addresses (for random selection)
    address[] public arbiterList;

    // ---------------------------------------------------------------
    //  Events
    // ---------------------------------------------------------------

    event DisputeFiled(
        bytes32 indexed disputeId,
        bytes32 indexed commitmentId,
        address indexed filer,
        uint256 timestamp
    );

    event AutomatedRuling(
        bytes32 indexed disputeId,
        RulingOutcome outcome,
        uint256 severityBps
    );

    event PanelAssigned(
        bytes32 indexed disputeId,
        address[5] panel
    );

    event VoteCast(
        bytes32 indexed disputeId,
        address indexed arbiter,
        bool providerWins
    );

    event DisputeResolved(
        bytes32 indexed disputeId,
        RulingOutcome outcome,
        uint256 severityBps
    );

    event ArbiterJoined(address indexed arbiter, uint256 stakedAmount);
    event ArbiterLeft(address indexed arbiter);

    // ---------------------------------------------------------------
    //  Modifiers
    // ---------------------------------------------------------------

    modifier onlyAdmin() {
        require(msg.sender == admin, "PACTResolver: not admin");
        _;
    }

    // ---------------------------------------------------------------
    //  Constructor
    // ---------------------------------------------------------------

    constructor(
        address _escrow,
        address _registry,
        address _pactToken
    ) {
        escrow = IPACTEscrow(_escrow);
        registry = IPACTRegistry(_registry);
        pactToken = _pactToken;
        admin = msg.sender;
    }

    // ---------------------------------------------------------------
    //  Arbiter Management
    // ---------------------------------------------------------------

    /**
     * @notice Join the arbiter pool by staking PACT tokens.
     * @param amount Amount of PACT to stake (must be >= MIN_ARBITER_STAKE)
     */
    function joinArbiterPool(uint256 amount) external {
        require(amount >= MIN_ARBITER_STAKE, "PACTResolver: insufficient stake");
        require(!arbiters[msg.sender].isActive, "PACTResolver: already arbiter");

        // Transfer stake (would use HTS precompile in production)
        arbiters[msg.sender] = Arbiter({
            stakedAmount: amount,
            activeDisputes: 0,
            totalResolved: 0,
            correctVotes: 0,
            isActive: true
        });

        arbiterList.push(msg.sender);
        totalArbiters++;

        emit ArbiterJoined(msg.sender, amount);
    }

    // ---------------------------------------------------------------
    //  Dispute Filing
    // ---------------------------------------------------------------

    /**
     * @notice File a dispute for a commitment.
     * @param commitmentId The commitment being disputed
     * @param disputeId    Unique dispute identifier
     */
    function fileDispute(
        bytes32 commitmentId,
        bytes32 disputeId
    ) external {
        require(
            disputes[disputeId].state == DisputeState.NONE,
            "PACTResolver: dispute exists"
        );

        // Determine filer and respondent roles
        // In production, this would check the escrow contract
        disputes[disputeId] = Dispute({
            commitmentId: commitmentId,
            filer: msg.sender,
            respondent: address(0), // Set by escrow lookup
            state: DisputeState.FILED,
            ruling: RulingOutcome.NONE,
            severityBps: 0,
            filedAt: block.timestamp,
            votingEndsAt: 0,
            totalVotes: 0,
            providerVotes: 0,
            consumerVotes: 0
        });

        emit DisputeFiled(disputeId, commitmentId, msg.sender, block.timestamp);
    }

    // ---------------------------------------------------------------
    //  Automated Resolution (Tier 1)
    // ---------------------------------------------------------------

    /**
     * @notice Attempt automated resolution based on clear evidence.
     * @dev Called after dispute filing. If evidence is unambiguous,
     *      produces a ruling without arbiter involvement.
     *
     * @param disputeId          The dispute to resolve
     * @param checkpointsExpected Total expected checkpoints
     * @param checkpointsVerified Verified checkpoints (from escrow)
     * @param deadlineExceeded   Whether the execution deadline passed
     */
    function automatedResolve(
        bytes32 disputeId,
        uint256 checkpointsExpected,
        uint256 checkpointsVerified,
        bool deadlineExceeded
    ) external onlyAdmin {
        Dispute storage d = disputes[disputeId];
        require(
            d.state == DisputeState.FILED,
            "PACTResolver: not filed"
        );

        // Case 1: All checkpoints verified => provider wins
        if (checkpointsVerified == checkpointsExpected && !deadlineExceeded) {
            d.state = DisputeState.AUTOMATED_RESOLVED;
            d.ruling = RulingOutcome.PROVIDER_WINS;
            d.severityBps = 0;

            emit AutomatedRuling(disputeId, RulingOutcome.PROVIDER_WINS, 0);
            return;
        }

        // Case 2: Zero checkpoints and deadline exceeded => consumer wins
        if (checkpointsVerified == 0 && deadlineExceeded) {
            d.state = DisputeState.AUTOMATED_RESOLVED;
            d.ruling = RulingOutcome.CONSUMER_WINS;
            d.severityBps = BPS_DENOMINATOR; // Full severity

            escrow.slash(d.commitmentId, BPS_DENOMINATOR);

            emit AutomatedRuling(
                disputeId,
                RulingOutcome.CONSUMER_WINS,
                BPS_DENOMINATOR
            );
            return;
        }

        // Case 3: Partial completion — escalate to arbiters
        // Ambiguous cases require human judgment
        _escalateToArbiters(disputeId);
    }

    // ---------------------------------------------------------------
    //  Arbiter Resolution (Tier 2)
    // ---------------------------------------------------------------

    /**
     * @notice Cast a vote on a dispute (arbiter only).
     * @param disputeId    The dispute being voted on
     * @param providerWins True if voting in favor of provider
     */
    function castVote(bytes32 disputeId, bool providerWins) external {
        Dispute storage d = disputes[disputeId];
        require(
            d.state == DisputeState.VOTING,
            "PACTResolver: not in voting"
        );
        require(
            block.timestamp <= d.votingEndsAt,
            "PACTResolver: voting ended"
        );
        require(
            arbiters[msg.sender].isActive,
            "PACTResolver: not arbiter"
        );
        require(
            !hasVoted[disputeId][msg.sender],
            "PACTResolver: already voted"
        );

        // Verify arbiter is on the panel
        bool onPanel = false;
        address[] storage panel = disputePanels[disputeId];
        for (uint256 i = 0; i < panel.length; i++) {
            if (panel[i] == msg.sender) {
                onPanel = true;
                break;
            }
        }
        require(onPanel, "PACTResolver: not on panel");

        hasVoted[disputeId][msg.sender] = true;
        arbiterVotes[disputeId][msg.sender] = providerWins;
        d.totalVotes++;

        if (providerWins) {
            d.providerVotes++;
        } else {
            d.consumerVotes++;
        }

        emit VoteCast(disputeId, msg.sender, providerWins);

        // Check if we have enough votes for a ruling
        if (d.providerVotes >= REQUIRED_MAJORITY) {
            _finalizeRuling(disputeId, RulingOutcome.PROVIDER_WINS, 0);
        } else if (d.consumerVotes >= REQUIRED_MAJORITY) {
            // Default to 50% severity for arbiter-decided consumer wins
            _finalizeRuling(disputeId, RulingOutcome.CONSUMER_WINS, 5_000);
        }
    }

    /**
     * @notice Finalize a dispute after voting period ends.
     * @param disputeId The dispute to finalize
     */
    function finalizeDispute(bytes32 disputeId) external {
        Dispute storage d = disputes[disputeId];
        require(
            d.state == DisputeState.VOTING,
            "PACTResolver: not in voting"
        );
        require(
            block.timestamp > d.votingEndsAt,
            "PACTResolver: voting not ended"
        );

        if (d.providerVotes > d.consumerVotes) {
            _finalizeRuling(disputeId, RulingOutcome.PROVIDER_WINS, 0);
        } else if (d.consumerVotes > d.providerVotes) {
            _finalizeRuling(disputeId, RulingOutcome.CONSUMER_WINS, 5_000);
        } else {
            // Tie: partial ruling
            _finalizeRuling(disputeId, RulingOutcome.PARTIAL, 2_500);
        }
    }

    // ---------------------------------------------------------------
    //  Checkpoint Verification
    // ---------------------------------------------------------------

    /**
     * @notice Verify a checkpoint and release the corresponding tranche.
     * @dev In production, this would validate the HCS message signature
     *      and content against the PSL specification.
     *
     * @param commitmentId      The commitment identifier
     * @param checkpointIndex   The checkpoint to verify
     * @param hcsSequenceNumber The HCS sequence number of the checkpoint message
     * @param messageHash       Hash of the HCS message content
     * @param providerSig       Provider's signature on the message
     */
    function verifyAndRelease(
        bytes32 commitmentId,
        uint256 checkpointIndex,
        uint64 hcsSequenceNumber,
        bytes32 messageHash,
        bytes calldata providerSig
    ) external {
        // In production:
        // 1. Query Mirror Node for HCS message at hcsSequenceNumber
        // 2. Verify message hash matches
        // 3. Verify provider signature
        // 4. Validate checkpoint content against PSL schema
        // 5. Call escrow to release tranche

        // For MVP, trust the caller (to be replaced with oracle verification)
        escrow.releaseTranche(commitmentId, checkpointIndex, hcsSequenceNumber);
    }

    // ---------------------------------------------------------------
    //  Internal
    // ---------------------------------------------------------------

    function _escalateToArbiters(bytes32 disputeId) internal {
        Dispute storage d = disputes[disputeId];
        require(
            totalArbiters >= PANEL_SIZE,
            "PACTResolver: insufficient arbiters"
        );

        d.state = DisputeState.VOTING;
        d.votingEndsAt = block.timestamp + VOTING_PERIOD;

        // Select panel (simplified — production would use VRF)
        // Using block hash as pseudo-random seed
        uint256 seed = uint256(
            keccak256(abi.encodePacked(block.timestamp, disputeId))
        );

        address[] storage panel = disputePanels[disputeId];
        uint256 selected = 0;
        uint256 attempts = 0;

        while (selected < PANEL_SIZE && attempts < arbiterList.length * 2) {
            uint256 idx = (seed + attempts) % arbiterList.length;
            address candidate = arbiterList[idx];

            if (
                arbiters[candidate].isActive &&
                arbiters[candidate].activeDisputes < 10 &&
                candidate != d.filer &&
                candidate != d.respondent
            ) {
                panel.push(candidate);
                arbiters[candidate].activeDisputes++;
                selected++;
            }
            attempts++;
        }

        require(selected == PANEL_SIZE, "PACTResolver: panel incomplete");
    }

    function _finalizeRuling(
        bytes32 disputeId,
        RulingOutcome outcome,
        uint256 severityBps
    ) internal {
        Dispute storage d = disputes[disputeId];
        d.state = DisputeState.RESOLVED;
        d.ruling = outcome;
        d.severityBps = severityBps;

        // Execute ruling
        if (outcome == RulingOutcome.CONSUMER_WINS || outcome == RulingOutcome.PARTIAL) {
            escrow.slash(d.commitmentId, severityBps);
            registry.recordBreach(d.respondent, d.commitmentId, severityBps);
        }

        // Update arbiter stats
        address[] storage panel = disputePanels[disputeId];
        for (uint256 i = 0; i < panel.length; i++) {
            address arb = panel[i];
            arbiters[arb].activeDisputes--;
            arbiters[arb].totalResolved++;

            bool votedWithMajority = arbiterVotes[disputeId][arb] ==
                (outcome == RulingOutcome.PROVIDER_WINS);
            if (votedWithMajority) {
                arbiters[arb].correctVotes++;
            }
        }

        emit DisputeResolved(disputeId, outcome, severityBps);
    }
}
