// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {Test, console} from "forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract RaffleTest is Test {
    /* Events */
    event EnteredRaffle(address indexed player);
    Raffle raffle;
    HelperConfig helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callBackGasLimit;
    address link;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();

        (
            entranceFee,
            interval,
            vrfCoordinator,
            gasLane,
            subscriptionId,
            callBackGasLimit,
            link,
        ) = helperConfig.activeNetworkConfig();

        vm.deal(PLAYER, STARTING_USER_BALANCE);
    }

    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    function testRaffleRevertsWhenYouDontPayEnough() public {
        // Arrange
        vm.prank(PLAYER);
        // Act / Assert
        vm.expectRevert(Raffle.RAFFLE__NotEnoughEthSent.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayerWhenTheyEnter() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        address playerRecorded = raffle.getPlayer(0);
        assert(PLAYER == playerRecorded);
    }

    function testEmitsEventOnEntrance() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit EnteredRaffle(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCantEnterWhenRaffleIsCalculating() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCheckUpkeepReturnsFalseIfIthasNoBalance() public {
    // Arrange
    vm.warp(block.timestamp + interval +1);
    vm.roll(block.number + 1);
    
    // Act
    (bool upkeepNeeded,) = raffle.checkUpKeep("");

    // Assert
    assert(!upkeepNeeded);
}

    function testCheckUpKeepReturnsFalseIfRaffleNotOpen() public {
    // Arrange
    vm.prank(PLAYER);
    raffle.enterRaffle{value: entranceFee}();
    vm.warp(block.timestamp + interval +1);
    vm.roll(block.number + 1);
    raffle.performUpkeep("");

    // Act
    (bool upkeepNeeded,) = raffle.checkUpKeep("");
    
    // Assert
    assert(upkeepNeeded == false);
    }

    function testCheckUpkeepReturnsFalseIfEnoughTimeHasntPassed() public {
    // Arrange
    vm.prank(PLAYER);
    raffle.enterRaffle{value: entranceFee}();

    // Act
    (bool upkeepNeeded,) = raffle.checkUpKeep("");
    
    // Assert
    assert(upkeepNeeded == false);

    }

    function testCheckUpkeepReturnsTrueWhenParametersAreGood() public {
    // Arrange
    vm.prank(PLAYER);
    raffle.enterRaffle{value: entranceFee}();
    vm.warp(block.timestamp + interval +1);
    vm.roll(block.number + 1);

    // Act
    (bool upkeepNeeded,) = raffle.checkUpKeep("");
    
    // Assert
    assert(upkeepNeeded == true);
    }

    //Upkeep tests

    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public {
    // Arrange
    vm.prank(PLAYER);
    raffle.enterRaffle{value: entranceFee}();
    vm.warp(block.timestamp + interval +1);
    vm.roll(block.number + 1);

    // Act / Aseert
    raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        // Arrange
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        uint256 raffleState = 0;

        // Act / Assert
        vm.expectRevert(abi.encodeWithSelector(Raffle.Raffle__UpKeepNotNeeded.selector,currentBalance, numPlayers, raffleState));
        raffle.performUpkeep("");
    }

    modifier raffleEnteredAndTimePassed() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval +1);
        vm.roll(block.number + 1);
        _;
    }

    // What if I need to test using the output of an event
    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public raffleEnteredAndTimePassed() {
        // Arrange (Done by the modifier)

        // Act
        vm.recordLogs();
        raffle.performUpkeep(""); // emit requestId
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        Raffle.RaffleState rState = raffle.getRaffleState();

        assert(uint256(requestId) > 0);
        assert(uint256(rState) == 1);

    }


    // This modifier is because VRFCoordinatorV2Mock returns differently than the real VRFCoordinator contract on Sepolia
    // 31337 is anvil's chainid

    modifier skipFork() {
        if(block.chainid != 31337) {
            return;
        }
        _;
    }


    //fuzz tests for fulfillrandomwords

    function testFulFillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(uint256 randomRequestId) public raffleEnteredAndTimePassed skipFork{
        // Arrange
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(randomRequestId,address(raffle));
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney() public raffleEnteredAndTimePassed skipFork {
        // Arrange
        uint256 additionalEntrants = 5;
        uint256 startingIndex = 1;
        for(uint256 i = startingIndex; i < startingIndex + additionalEntrants; i++) {
            address player = address(uint160(i));
            hoax(player, STARTING_USER_BALANCE);
            raffle.enterRaffle{value: entranceFee}();
        }

       
        vm.recordLogs();
        raffle.performUpkeep(""); // emit requestId
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        uint256 prize = entranceFee * (additionalEntrants + 1);

        uint256 previousTimeStamp = raffle.getLastTimeStamp();
         // pretend to be chainlink vrf to get random number & pick winner
        
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId),address(raffle));


        // Assert
        assert(uint256(raffle.getRaffleState()) == 0);
        assert(raffle.getRecentWinner() != address(0));
        assert(raffle.getLengthOfPlayers() == 0);
        assert(previousTimeStamp < raffle.getLastTimeStamp());
        console.log("Winner's balance: ",raffle.getRecentWinner().balance);
        console.log("prize + starting_user_balance= ", prize + STARTING_USER_BALANCE);
        assert(raffle.getRecentWinner().balance == STARTING_USER_BALANCE + prize - entranceFee);

    }
}


