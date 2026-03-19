// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPACTEscrow
 * @notice Interface for the PACT Protocol graduated escrow system.
 */
interface IPACTEscrow {
    /// @notice Lock payment for a new commitment
    function lockFunds(
        bytes32 commitmentId,
        address provider,
        address paymentToken,
        uint256 paymentAmount,
        uint256 collateralAmount,
        uint256 totalCheckpoints,
        uint256[] calldata checkpointWeights,
        uint256 expiresAt
    ) external;

    /// @notice Release a tranche upon checkpoint verification
    function releaseTranche(
        bytes32 commitmentId,
        uint256 checkpointIndex,
        uint64 hcsSequenceNumber
    ) external;

    /// @notice Slash provider collateral upon confirmed breach
    function slash(bytes32 commitmentId, uint256 severityBps) external;

    /// @notice Refund consumer upon commitment expiry
    function refund(bytes32 commitmentId) external;
}
