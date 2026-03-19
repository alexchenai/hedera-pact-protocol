// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPACTRegistry
 * @notice Interface for agent registration and reputation tracking.
 */
interface IPACTRegistry {
    /// @notice Register an agent with the protocol
    function registerAgent(address agent, string calldata did) external;

    /// @notice Record a successful commitment completion
    function recordCompletion(
        address agent,
        bytes32 commitmentId,
        uint256 commitmentValue
    ) external;

    /// @notice Record a breach/slash event
    function recordBreach(
        address agent,
        bytes32 commitmentId,
        uint256 slashedAmount
    ) external;

    /// @notice Get agent reputation score (0-100)
    function getReputation(address agent) external view returns (uint256);

    /// @notice Get required collateral rate for an agent (in basis points)
    function getCollateralRate(address agent) external view returns (uint256);

    /// @notice Check if an agent is registered
    function isRegistered(address agent) external view returns (bool);
}
