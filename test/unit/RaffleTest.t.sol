// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console, console2} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import "forge-std/console.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "../../test/mocks/LinkToken.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {HelperConfig, CodeConstants} from "../../script/HelperConfig.s.sol";
import {Raffle} from "../../src/Raffle.sol";

contract RaffleTest is Test, CodeConstants {
    Raffle public raffle;
    HelperConfig public helperConfig;
    LinkToken public link;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint32 callbackGasLimit;
    uint256 subscriptionId;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_PLAYER_BALANCE = 10 ether;
    uint256 public constant LINK_BALANCE = 100 ether;

    event PlayerEntered(address indexed);
    event WinnerPicked(address indexed);

    modifier enterRaffle() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        _;
    }

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.deployContract();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        entranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        gasLane = config.gasLane;
        callbackGasLimit = config.callbackGasLimit;
        subscriptionId = config.subscriptionId;

        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);
        link = LinkToken(config.linkToken);
    }

    function test_RaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    // =============================================================
    // |                        Constructor                        |
    // =============================================================

    function test_ConstructorCorrectlyAssignsEntranceFee() public view {
        assert(raffle.getEntranceFee() == entranceFee);
    }

    function test_ConstructorCorrectlyAssignsInterval() public view {
        assert(raffle.getInterval() == interval);
    }

    // =============================================================
    // |                       Enter Raffle                        |
    // =============================================================

    function test_RaffleRevertsWhenEntranceFeeIsNotMet() public {
        vm.prank(PLAYER);

        vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector);
        raffle.enterRaffle{value: entranceFee - 1}();
        assert(raffle.getNumberOfPlayers() == 0);

        vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector);
        raffle.enterRaffle();
        assert(raffle.getNumberOfPlayers() == 0);
    }

    function test_RaffleRecordsPlayersWhenTheyEnter() public enterRaffle {
        address playerRecorded = raffle.getPlayer(0);

        assert(playerRecorded == PLAYER);
        assert(raffle.getNumberOfPlayers() == 1);
    }

    function test_EnteringRaffleEmitsEvent() public {
        vm.prank(PLAYER);

        vm.expectEmit(true, false, false, false, address(raffle));
        emit PlayerEntered(PLAYER);

        raffle.enterRaffle{value: entranceFee}();
    }

    function test_DontAllowPlayersToEnterWhileRaffleIsCalculating() public enterRaffle {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        raffle.performUpkeep("");

        vm.expectRevert(Raffle.Raffle__NotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        assert(raffle.getNumberOfPlayers() == 1);
    }

    // =============================================================
    // |                       Check Upkeep                        |
    // =============================================================

    function test_CheckUpkeepReturnsFalseIfNotEnoughTimeHasPassed() public enterRaffle {
        vm.warp(block.timestamp + interval - 1);
        vm.roll(block.number + 1);

        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        assert(!upkeepNeeded);
    }

    function test_CheckUpkeepTurnsFalseIfRaffleIsntOpen() public enterRaffle {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        raffle.performUpkeep("");

        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        assert(!upkeepNeeded);
    }

    function test_CheckUpkeepReturnsFalseIfItHasNoBalance() public {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        assert(!upkeepNeeded);
    }

    function test_CheckUpkeepReturnsFalseIfItHasNoPlayers() public {
        vm.prank(PLAYER);
        address(raffle).call{value: entranceFee}("");

        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        assert(!upkeepNeeded);
    }

    function test_CheckUpkeepReturnsTrueWhenParametersAreGood() public enterRaffle {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        assert(upkeepNeeded);
    }

    // =============================================================
    // |                      Perform Upkeep                       |
    // =============================================================

    function test_PerformUpkeepReturnsFalseIfNotEnoughTimeHasPassed() public enterRaffle {
        vm.warp(block.timestamp + interval - 1);
        vm.roll(block.number + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector,
                address(raffle).balance,
                raffle.getNumberOfPlayers(),
                raffle.getRaffleState()
            )
        );
        raffle.performUpkeep("");
    }

    function test_PerformUpkeepTurnsFalseIfRaffleIsntOpen() public enterRaffle {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        raffle.performUpkeep("");

        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector, address(raffle).balance, 1, raffle.getRaffleState()
            )
        );
        raffle.performUpkeep("");
    }

    function test_PerformUpkeepReturnsFalseIfItHasNoBalance() public {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector, address(raffle).balance, 0, raffle.getRaffleState()
            )
        );
        raffle.performUpkeep("");
    }

    function test_PerformUpkeepReturnsFalseIfItHasNoPlayers() public {
        vm.prank(PLAYER);
        address(raffle).call{value: entranceFee}("");

        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector, address(raffle).balance, 0, raffle.getRaffleState()
            )
        );
        raffle.performUpkeep("");
    }

    function test_PerformUpkeepReturnsTrueWhenParametersAreGood() public enterRaffle {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        // RequestedRaffleWinner is the second event emitted and it only has 1 topic
        // besides the event signature
        uint256 requestId = uint256(entries[1].topics[1]);
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        assert(uint256(requestId) > 0);
        assert(uint256(raffleState) == 1);
    }

    // =============================================================
    // |                   Fulfill Random Words                    |
    // =============================================================
    modifier skipFork() {
        if (block.chainid != LOCAL_CHAIN_ID) {
            return;
        }
        _;
    }

    function test_FulfillRandomWordsOnlyCalledAfterPerformUpkeep(uint256 randomRequestId) public enterRaffle skipFork {
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(raffle));
    }

    function test_FulfillRandomWordsEmitsWinnerPicked() public enterRaffle skipFork {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        uint256 balanceBefore = address(PLAYER).balance;
        uint256 balanceRaffle = address(raffle).balance;

        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        // RequestedRaffleWinner is the second event emitted and it only has 1 topic
        // besides the event signature
        uint256 requestId = uint256(entries[1].topics[1]);

        vm.expectEmit(true, false, false, false, address(raffle));
        emit WinnerPicked(PLAYER);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(requestId, address(raffle));

        assert(raffle.getRecentWinner() == PLAYER);
        assert(address(PLAYER).balance == balanceBefore + balanceRaffle);
    }

    function test_FulfillRandomWordsPicksWinnerAndResets() public enterRaffle skipFork {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        uint256 additionalEntrants = 3; // 4 total
        uint256 startingIndex = 1;
        address expectedWinner = address(1);

        for (uint256 i = startingIndex; i < startingIndex + additionalEntrants; i++) {
            address newPlayer = address(uint160(i));
            hoax(newPlayer, 1 ether);
            raffle.enterRaffle{value: entranceFee}();
        }

        uint256 startingTimeStamp = raffle.getLastTimeStamp();
        uint256 winnerStartingBalance = expectedWinner.balance;

        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 requestId = uint256(entries[1].topics[1]);

        vm.expectEmit(true, false, false, false, address(raffle));
        emit WinnerPicked(expectedWinner);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(requestId, address(raffle));

        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTimeStamp = raffle.getLastTimeStamp();
        uint256 prize = entranceFee * (additionalEntrants + 1);

        assert(recentWinner == expectedWinner);
        assert(uint256(raffleState) == 0);
        assert(winnerBalance == winnerStartingBalance + prize);
        assert(endingTimeStamp > startingTimeStamp);
    }
}
