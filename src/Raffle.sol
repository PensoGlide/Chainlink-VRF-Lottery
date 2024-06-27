// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

/**
 * @title Raffle Contract
 * @author Eduardo Santiago
 * @notice This contract allows the creation of a raffle
 * @dev Implements Chainlink VRGv2
 */
contract Raffle {
    uint256 private constant REQUEST_CONFIRMATIONS = 3;
    uint256 private constant NUM_WORDS = 2;

    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval;
    address private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_gasLimit;

    address payable [] private s_players;
    uint256 private s_lastTimeStamp;

    error Raffle__NotEnoughEthSent();

    event PlayerEntered(address);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 gasLimit
    ) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_vrfCoordinator = vrfCoordinator;
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_gasLimit = gasLimit;

        s_lastTimeStamp = block.timestamp;
    }

    function enterRaffle() external payable {
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughEthSent();
        }
        s_players.push(payable(msg.sender));

        emit PlayerEntered(msg.sender);
    }

    function pickWinner() public {
        if (block.timestamp - s_lastTimeStamp < i_interval) {
            revert();
        }
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_gasLimit,
            NUM_WORDS
        );
    }

    // =============================================================
    // |                      Getter functions                     |
    // =============================================================

    function getEntranceFee() external view returns(uint256) {
        return i_entranceFee;
    }
}