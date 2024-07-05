// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";

contract Helperconfig is Script {
    struct NetworkConfig {
        uint256 entranceFee;
        uint256 interval;
        address vrfCoordinator;
        bytes32 gasLane;
        uint32 callbackGasLimit;
        uint256 subscriptionId;
    }

    NetworkConfig public localNetworkConfig;
    mapping(uint256 chaindId => NetworkConfig) public networkConfigs;

    constructor() {}

    function getSepoliaEthConfig() public pure returns(NetworkConfig memory) {
        return NetworkConfig({
            entrance: 0.01 ether,
            interval: 30,
            vrfCoordinator
        })
    }
}