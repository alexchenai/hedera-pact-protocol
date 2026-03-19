// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IPACTEscrow.sol";
import "./interfaces/IPACTRegistry.sol";

/**
 * @title PACTEscrow
 * @notice Manages graduated escrow for PACT Protocol commitments.
 *         Funds are locked when a commitment is formed and released
 *         proportionally as performance checkpoints are verified.
 *
 * @dev Interacts with Hedera Token Service via the 0x167 precompile
 *      for native HTS token operations (transfer, approve, associate).
 */
contract PACTEscrow is IPACTEscrow {
    // ---------------------------------------------------------------
    //  Constants
    // ---------------------------------------------------------------

    /// @notice HTS precompile address on Hedera
    address constant HTS_PRECOMPILE = address(0x167);

    /// @notice Basis points denominator (100% = 10_000 bps)
    uint256 constant BPS_DENOMINATOR = 10_000;

    /// @notice Maximum slash severity (100%)
    uint256 constant MAX_SEVERITY_BPS = 10_000;

    /// @notice Compensation share for harmed party (70%)
    uint256 constant COMPENSATION_SHARE_BPS = 7_000;

    /// @notice Treasury share from slashing (20%)
    uint256 constant TREASURY_SHARE_BPS = 2_000;

    /// @notice Arbiter share from slashing (10%)
    uint256 constant ARBITER_SHARE_BPS = 1_000;

    // ---------------------------------------------------------------
    //  State
    // ---------------------------------------------------------------

    /// @notice Protocol registry contract
    IPACTRegistry public registry;

    /// @notice Protocol treasury address
    address public treasury;

    /// @notice Resolver contract (only address that can call slash/release)
    address public resolver;

    /// @notice Admin address for initial setup
    address public admin;

    struct Escrow {
        address consumer;
        address provider;
        address paymentToken;
        uint256 paymentAmount;
        uint256 collateralAmount;
        uint256 releasedAmount;
        uint256 totalCheckpoints;
        uint256 verifiedCheckpoints;
        uint256[] checkpointWeights; // basis points, must sum to 10_000
        EscrowState state;
        uint256 createdAt;
        uint256 expiresAt;
    }

    enum EscrowState {
        EMPTY,
        FUNDED,         // Consumer has locked payment
        ACTIVE,         // Provider has locked collateral
        RELEASING,      // Tranches being released
        COMPLETED,      // All funds distributed
        DISPUTED,       // Under dispute
        SLASHED,        // Provider collateral seized
        REFUNDED        // Consumer refunded (expiry)
    }

    /// @notice Commitment ID => Escrow details
    mapping(bytes32 => Escrow) public escrows;

    /// @notice Commitment ID => checkpoint index => released flag
    mapping(bytes32 => mapping(uint256 => bool)) public checkpointReleased;

    // ---------------------------------------------------------------
    //  Events
    // ---------------------------------------------------------------

    event FundsLocked(
        bytes32 indexed commitmentId,
        address indexed consumer,
        address paymentToken,
        uint256 paymentAmount
    );

    event CollateralLocked(
        bytes32 indexed commitmentId,
        address indexed provider,
        uint256 collateralAmount
    );

    event TrancheReleased(
        bytes32 indexed commitmentId,
        uint256 indexed checkpointIndex,
        uint256 amount,
        uint64 hcsSequenceNumber
    );

    event Slashed(
        bytes32 indexed commitmentId,
        uint256 slashedAmount,
        uint256 compensationAmount,
        uint256 treasuryAmount,
        uint256 arbiterAmount
    );

    event Refunded(
        bytes32 indexed commitmentId,
        address indexed consumer,
        uint256 refundedAmount
    );

    event EscrowCompleted(bytes32 indexed commitmentId);

    // ---------------------------------------------------------------
    //  Modifiers
    // ---------------------------------------------------------------

    modifier onlyResolver() {
        require(msg.sender == resolver, "PACTEscrow: caller is not resolver");
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "PACTEscrow: caller is not admin");
        _;
    }

    modifier escrowInState(bytes32 commitmentId, EscrowState expected) {
        require(
            escrows[commitmentId].state == expected,
            "PACTEscrow: invalid escrow state"
        );
        _;
    }

    // ---------------------------------------------------------------
    //  Constructor
    // ---------------------------------------------------------------

    constructor(address _registry, address _treasury, address _resolver) {
        registry = IPACTRegistry(_registry);
        treasury = _treasury;
        resolver = _resolver;
        admin = msg.sender;
    }

    // ---------------------------------------------------------------
    //  Consumer Actions
    // ---------------------------------------------------------------

    /**
     * @notice Lock payment for a new commitment. Called by the consumer.
     * @param commitmentId    Unique commitment identifier (hash of PSL spec)
     * @param provider        Provider's Hedera account (EVM address)
     * @param paymentToken    HTS token address used for payment
     * @param paymentAmount   Total payment amount (in token's smallest unit)
     * @param collateralAmount Required collateral from provider
     * @param totalCheckpoints Number of checkpoints in the commitment
     * @param checkpointWeights Weight of each checkpoint in bps (must sum to 10_000)
     * @param expiresAt       Unix timestamp when commitment expires
     */
    function lockFunds(
        bytes32 commitmentId,
        address provider,
        address paymentToken,
        uint256 paymentAmount,
        uint256 collateralAmount,
        uint256 totalCheckpoints,
        uint256[] calldata checkpointWeights,
        uint256 expiresAt
    ) external override escrowInState(commitmentId, EscrowState.EMPTY) {
        require(paymentAmount > 0, "PACTEscrow: zero payment");
        require(totalCheckpoints > 0, "PACTEscrow: zero checkpoints");
        require(
            checkpointWeights.length == totalCheckpoints,
            "PACTEscrow: weights length mismatch"
        );
        require(expiresAt > block.timestamp, "PACTEscrow: already expired");

        // Verify weights sum to BPS_DENOMINATOR
        uint256 weightSum = 0;
        for (uint256 i = 0; i < checkpointWeights.length; i++) {
            weightSum += checkpointWeights[i];
        }
        require(
            weightSum == BPS_DENOMINATOR,
            "PACTEscrow: weights must sum to 10000 bps"
        );

        // Transfer payment tokens from consumer to this contract
        // Uses HTS precompile for native token transfer
        _htsTransferFrom(paymentToken, msg.sender, address(this), paymentAmount);

        escrows[commitmentId] = Escrow({
            consumer: msg.sender,
            provider: provider,
            paymentToken: paymentToken,
            paymentAmount: paymentAmount,
            collateralAmount: collateralAmount,
            releasedAmount: 0,
            totalCheckpoints: totalCheckpoints,
            verifiedCheckpoints: 0,
            checkpointWeights: checkpointWeights,
            state: EscrowState.FUNDED,
            createdAt: block.timestamp,
            expiresAt: expiresAt
        });

        emit FundsLocked(commitmentId, msg.sender, paymentToken, paymentAmount);
    }

    // ---------------------------------------------------------------
    //  Provider Actions
    // ---------------------------------------------------------------

    /**
     * @notice Lock collateral to accept a commitment. Called by the provider.
     * @param commitmentId The commitment to accept
     */
    function lockCollateral(
        bytes32 commitmentId
    ) external escrowInState(commitmentId, EscrowState.FUNDED) {
        Escrow storage escrow = escrows[commitmentId];
        require(
            msg.sender == escrow.provider,
            "PACTEscrow: caller is not provider"
        );

        // Transfer collateral from provider to this contract
        _htsTransferFrom(
            escrow.paymentToken,
            msg.sender,
            address(this),
            escrow.collateralAmount
        );

        escrow.state = EscrowState.ACTIVE;

        emit CollateralLocked(commitmentId, msg.sender, escrow.collateralAmount);
    }

    // ---------------------------------------------------------------
    //  Resolver Actions
    // ---------------------------------------------------------------

    /**
     * @notice Release a payment tranche upon checkpoint verification.
     *         Can only be called by the resolver contract after validating
     *         the HCS checkpoint evidence.
     * @param commitmentId       The commitment identifier
     * @param checkpointIndex    The verified checkpoint index (0-based)
     * @param hcsSequenceNumber  The HCS message sequence number as proof
     */
    function releaseTranche(
        bytes32 commitmentId,
        uint256 checkpointIndex,
        uint64 hcsSequenceNumber
    )
        external
        override
        onlyResolver
    {
        Escrow storage escrow = escrows[commitmentId];
        require(
            escrow.state == EscrowState.ACTIVE ||
            escrow.state == EscrowState.RELEASING,
            "PACTEscrow: not active"
        );
        require(
            checkpointIndex < escrow.totalCheckpoints,
            "PACTEscrow: invalid checkpoint index"
        );
        require(
            !checkpointReleased[commitmentId][checkpointIndex],
            "PACTEscrow: checkpoint already released"
        );

        checkpointReleased[commitmentId][checkpointIndex] = true;
        escrow.verifiedCheckpoints++;

        if (escrow.state == EscrowState.ACTIVE) {
            escrow.state = EscrowState.RELEASING;
        }

        // Calculate tranche amount based on checkpoint weight
        uint256 trancheAmount = (escrow.paymentAmount *
            escrow.checkpointWeights[checkpointIndex]) / BPS_DENOMINATOR;

        escrow.releasedAmount += trancheAmount;

        // Transfer tranche to provider
        _htsTransfer(escrow.paymentToken, escrow.provider, trancheAmount);

        emit TrancheReleased(
            commitmentId,
            checkpointIndex,
            trancheAmount,
            hcsSequenceNumber
        );

        // Check if all checkpoints verified
        if (escrow.verifiedCheckpoints == escrow.totalCheckpoints) {
            _completeEscrow(commitmentId);
        }
    }

    /**
     * @notice Slash provider collateral upon confirmed breach.
     * @param commitmentId The commitment identifier
     * @param severityBps  Severity in basis points (0-10000)
     */
    function slash(
        bytes32 commitmentId,
        uint256 severityBps
    ) external override onlyResolver {
        require(severityBps <= MAX_SEVERITY_BPS, "PACTEscrow: invalid severity");

        Escrow storage escrow = escrows[commitmentId];
        require(
            escrow.state == EscrowState.ACTIVE ||
            escrow.state == EscrowState.RELEASING ||
            escrow.state == EscrowState.DISPUTED,
            "PACTEscrow: cannot slash"
        );

        // Calculate partial completion rate
        uint256 completionBps = (escrow.verifiedCheckpoints * BPS_DENOMINATOR) /
            escrow.totalCheckpoints;

        // slash_amount = collateral * severity * (1 - completion_rate)
        uint256 slashAmount = (escrow.collateralAmount *
            severityBps *
            (BPS_DENOMINATOR - completionBps)) / (BPS_DENOMINATOR * BPS_DENOMINATOR);

        // Distribute slashed funds
        uint256 compensationAmount = (slashAmount * COMPENSATION_SHARE_BPS) /
            BPS_DENOMINATOR;
        uint256 treasuryAmount = (slashAmount * TREASURY_SHARE_BPS) /
            BPS_DENOMINATOR;
        uint256 arbiterAmount = slashAmount - compensationAmount - treasuryAmount;

        // Transfer compensation to consumer
        _htsTransfer(escrow.paymentToken, escrow.consumer, compensationAmount);

        // Transfer treasury share
        _htsTransfer(escrow.paymentToken, treasury, treasuryAmount);

        // Arbiter share held for distribution by resolver
        _htsTransfer(escrow.paymentToken, resolver, arbiterAmount);

        // Return remaining collateral to provider
        uint256 remainingCollateral = escrow.collateralAmount - slashAmount;
        if (remainingCollateral > 0) {
            _htsTransfer(escrow.paymentToken, escrow.provider, remainingCollateral);
        }

        // Refund unreleased payment to consumer
        uint256 unreleasedPayment = escrow.paymentAmount - escrow.releasedAmount;
        if (unreleasedPayment > 0) {
            _htsTransfer(escrow.paymentToken, escrow.consumer, unreleasedPayment);
        }

        escrow.state = EscrowState.SLASHED;

        emit Slashed(
            commitmentId,
            slashAmount,
            compensationAmount,
            treasuryAmount,
            arbiterAmount
        );
    }

    // ---------------------------------------------------------------
    //  Timeout / Expiry
    // ---------------------------------------------------------------

    /**
     * @notice Refund consumer if commitment expires without completion.
     * @param commitmentId The commitment identifier
     */
    function refund(bytes32 commitmentId) external override {
        Escrow storage escrow = escrows[commitmentId];
        require(
            block.timestamp >= escrow.expiresAt,
            "PACTEscrow: not yet expired"
        );
        require(
            escrow.state == EscrowState.ACTIVE ||
            escrow.state == EscrowState.RELEASING ||
            escrow.state == EscrowState.FUNDED,
            "PACTEscrow: cannot refund"
        );

        uint256 unreleasedPayment = escrow.paymentAmount - escrow.releasedAmount;

        // Refund unreleased payment to consumer
        if (unreleasedPayment > 0) {
            _htsTransfer(escrow.paymentToken, escrow.consumer, unreleasedPayment);
        }

        // Return collateral to provider (if locked)
        if (
            escrow.state == EscrowState.ACTIVE ||
            escrow.state == EscrowState.RELEASING
        ) {
            _htsTransfer(
                escrow.paymentToken,
                escrow.provider,
                escrow.collateralAmount
            );
        }

        escrow.state = EscrowState.REFUNDED;

        emit Refunded(commitmentId, escrow.consumer, unreleasedPayment);
    }

    // ---------------------------------------------------------------
    //  View Functions
    // ---------------------------------------------------------------

    function getEscrowState(
        bytes32 commitmentId
    ) external view returns (EscrowState) {
        return escrows[commitmentId].state;
    }

    function getReleasedAmount(
        bytes32 commitmentId
    ) external view returns (uint256) {
        return escrows[commitmentId].releasedAmount;
    }

    function getVerifiedCheckpoints(
        bytes32 commitmentId
    ) external view returns (uint256) {
        return escrows[commitmentId].verifiedCheckpoints;
    }

    // ---------------------------------------------------------------
    //  Internal
    // ---------------------------------------------------------------

    function _completeEscrow(bytes32 commitmentId) internal {
        Escrow storage escrow = escrows[commitmentId];

        // Return collateral to provider
        _htsTransfer(
            escrow.paymentToken,
            escrow.provider,
            escrow.collateralAmount
        );

        escrow.state = EscrowState.COMPLETED;

        // Update reputation in registry
        registry.recordCompletion(
            escrow.provider,
            commitmentId,
            escrow.paymentAmount
        );

        emit EscrowCompleted(commitmentId);
    }

    /**
     * @dev Transfer HTS tokens using the precompile.
     *      In production, this calls the HTS system contract at 0x167.
     */
    function _htsTransfer(
        address token,
        address to,
        uint256 amount
    ) internal {
        // Hedera HTS precompile call for token transfer
        // In testnet/local development, this would use the HTS system contract
        (bool success, ) = HTS_PRECOMPILE.call(
            abi.encodeWithSignature(
                "transferToken(address,address,address,int64)",
                token,
                address(this),
                to,
                int64(int256(amount))
            )
        );
        require(success, "PACTEscrow: HTS transfer failed");
    }

    /**
     * @dev Transfer HTS tokens from a sender using the precompile.
     */
    function _htsTransferFrom(
        address token,
        address from,
        address to,
        uint256 amount
    ) internal {
        (bool success, ) = HTS_PRECOMPILE.call(
            abi.encodeWithSignature(
                "transferToken(address,address,address,int64)",
                token,
                from,
                to,
                int64(int256(amount))
            )
        );
        require(success, "PACTEscrow: HTS transferFrom failed");
    }
}
