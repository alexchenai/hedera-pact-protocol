// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IPACTRegistry.sol";

/**
 * @title PACTRegistry
 * @notice Agent registration and reputation management for PACT Protocol.
 *         Tracks agent performance history and computes collateral requirements
 *         based on reputation scores.
 */
contract PACTRegistry is IPACTRegistry {
    // ---------------------------------------------------------------
    //  Constants
    // ---------------------------------------------------------------

    uint256 constant BPS_DENOMINATOR = 10_000;

    /// @notice Base collateral rate: 20% (2000 bps)
    uint256 constant BASE_COLLATERAL_RATE = 2_000;

    /// @notice Maximum reputation score
    uint256 constant MAX_REPUTATION = 100;

    /// @notice Initial reputation for new agents
    uint256 constant INITIAL_REPUTATION = 0;

    /// @notice Reputation gain per successful completion (scaled by value)
    uint256 constant REPUTATION_GAIN_BASE = 5;

    /// @notice Reputation loss per breach (scaled by severity)
    uint256 constant REPUTATION_LOSS_BASE = 15;

    // ---------------------------------------------------------------
    //  State
    // ---------------------------------------------------------------

    struct Agent {
        string did;                    // Decentralized Identifier
        uint256 reputation;            // 0-100 score
        uint256 totalCommitments;      // Total commitments participated in
        uint256 completedCommitments;  // Successfully completed
        uint256 breachedCommitments;   // Breached / slashed
        uint256 totalValueCompleted;   // Sum of completed commitment values
        uint256 totalValueSlashed;     // Sum of slashed collateral
        uint256 registeredAt;          // Registration timestamp
        bool isActive;                 // Whether agent is registered
    }

    /// @notice Agent address => Agent details
    mapping(address => Agent) public agents;

    /// @notice Authorized callers (escrow contract, resolver)
    mapping(address => bool) public authorized;

    /// @notice Protocol admin
    address public admin;

    /// @notice Total registered agents
    uint256 public totalAgents;

    // ---------------------------------------------------------------
    //  Events
    // ---------------------------------------------------------------

    event AgentRegistered(
        address indexed agent,
        string did,
        uint256 timestamp
    );

    event ReputationUpdated(
        address indexed agent,
        uint256 oldScore,
        uint256 newScore,
        bytes32 indexed commitmentId,
        string reason
    );

    event AgentDeactivated(address indexed agent);

    // ---------------------------------------------------------------
    //  Modifiers
    // ---------------------------------------------------------------

    modifier onlyAuthorized() {
        require(
            authorized[msg.sender] || msg.sender == admin,
            "PACTRegistry: unauthorized"
        );
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "PACTRegistry: not admin");
        _;
    }

    // ---------------------------------------------------------------
    //  Constructor
    // ---------------------------------------------------------------

    constructor() {
        admin = msg.sender;
    }

    // ---------------------------------------------------------------
    //  Admin
    // ---------------------------------------------------------------

    function setAuthorized(address addr, bool status) external onlyAdmin {
        authorized[addr] = status;
    }

    // ---------------------------------------------------------------
    //  Registration
    // ---------------------------------------------------------------

    /**
     * @notice Register a new agent with the protocol.
     * @param agent The agent's EVM address
     * @param did   The agent's Decentralized Identifier (did:hedera:...)
     */
    function registerAgent(
        address agent,
        string calldata did
    ) external override {
        require(!agents[agent].isActive, "PACTRegistry: already registered");
        require(bytes(did).length > 0, "PACTRegistry: empty DID");

        agents[agent] = Agent({
            did: did,
            reputation: INITIAL_REPUTATION,
            totalCommitments: 0,
            completedCommitments: 0,
            breachedCommitments: 0,
            totalValueCompleted: 0,
            totalValueSlashed: 0,
            registeredAt: block.timestamp,
            isActive: true
        });

        totalAgents++;

        emit AgentRegistered(agent, did, block.timestamp);
    }

    // ---------------------------------------------------------------
    //  Reputation Updates
    // ---------------------------------------------------------------

    /**
     * @notice Record a successful commitment completion.
     *         Increases the agent's reputation score.
     * @param agent          The provider agent's address
     * @param commitmentId   The completed commitment
     * @param commitmentValue The value of the completed commitment
     */
    function recordCompletion(
        address agent,
        bytes32 commitmentId,
        uint256 commitmentValue
    ) external override onlyAuthorized {
        require(agents[agent].isActive, "PACTRegistry: not registered");

        Agent storage a = agents[agent];
        uint256 oldRep = a.reputation;

        a.totalCommitments++;
        a.completedCommitments++;
        a.totalValueCompleted += commitmentValue;

        // Reputation gain: base gain, diminishing as reputation increases
        // gain = BASE * (1 - currentRep/MAX_REP)
        uint256 gain = (REPUTATION_GAIN_BASE *
            (MAX_REPUTATION - a.reputation)) / MAX_REPUTATION;

        if (gain == 0) gain = 1; // minimum 1 point gain

        a.reputation = _min(a.reputation + gain, MAX_REPUTATION);

        emit ReputationUpdated(
            agent,
            oldRep,
            a.reputation,
            commitmentId,
            "completion"
        );
    }

    /**
     * @notice Record a breach/slash event.
     *         Decreases the agent's reputation score.
     * @param agent          The breaching agent's address
     * @param commitmentId   The breached commitment
     * @param slashedAmount  The amount of collateral slashed
     */
    function recordBreach(
        address agent,
        bytes32 commitmentId,
        uint256 slashedAmount
    ) external override onlyAuthorized {
        require(agents[agent].isActive, "PACTRegistry: not registered");

        Agent storage a = agents[agent];
        uint256 oldRep = a.reputation;

        a.totalCommitments++;
        a.breachedCommitments++;
        a.totalValueSlashed += slashedAmount;

        // Reputation loss: larger than gain to discourage breaches
        uint256 loss = REPUTATION_LOSS_BASE;

        if (loss >= a.reputation) {
            a.reputation = 0;
        } else {
            a.reputation -= loss;
        }

        emit ReputationUpdated(
            agent,
            oldRep,
            a.reputation,
            commitmentId,
            "breach"
        );
    }

    // ---------------------------------------------------------------
    //  View Functions
    // ---------------------------------------------------------------

    /**
     * @notice Get agent reputation score (0-100).
     */
    function getReputation(
        address agent
    ) external view override returns (uint256) {
        return agents[agent].reputation;
    }

    /**
     * @notice Calculate required collateral rate for an agent.
     *         Rate decreases as reputation increases.
     *
     *         collateral_rate = base_rate * risk_multiplier(reputation)
     *         risk_multiplier = max(0.5, 2.0 - reputation/100)
     *
     * @return Collateral rate in basis points
     */
    function getCollateralRate(
        address agent
    ) external view override returns (uint256) {
        uint256 rep = agents[agent].reputation;

        // risk_multiplier = max(5000, 20000 - rep * 150) (in bps, scaled by 10000)
        // For rep=0:   multiplier = 20000 => rate = 2000 * 20000 / 10000 = 4000 bps (40%)
        // For rep=50:  multiplier = 12500 => rate = 2000 * 12500 / 10000 = 2500 bps (25%)
        // For rep=100: multiplier = 5000  => rate = 2000 * 5000 / 10000  = 1000 bps (10%)
        uint256 multiplier = 20_000 - (rep * 150);
        if (multiplier < 5_000) multiplier = 5_000;

        return (BASE_COLLATERAL_RATE * multiplier) / BPS_DENOMINATOR;
    }

    /**
     * @notice Check if an agent is registered and active.
     */
    function isRegistered(
        address agent
    ) external view override returns (bool) {
        return agents[agent].isActive;
    }

    /**
     * @notice Get full agent statistics.
     */
    function getAgentStats(
        address agent
    )
        external
        view
        returns (
            uint256 reputation,
            uint256 totalCommitments,
            uint256 completedCommitments,
            uint256 breachedCommitments,
            uint256 totalValueCompleted,
            uint256 totalValueSlashed
        )
    {
        Agent storage a = agents[agent];
        return (
            a.reputation,
            a.totalCommitments,
            a.completedCommitments,
            a.breachedCommitments,
            a.totalValueCompleted,
            a.totalValueSlashed
        );
    }

    // ---------------------------------------------------------------
    //  Internal
    // ---------------------------------------------------------------

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
