//SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.20;

import {IEscrow} from "./interfaces/Quests/IEscrow.sol";
import {IRewarder} from "./interfaces/IRewarder.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IQuest} from "./interfaces/Quests/IQuest.sol";
import {ITavern} from "./interfaces/Quests/ITavern.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Quest Implementation
 * @notice Controls the quest flow
 * @author @cosmodude
 * @dev Implementation contract, instances are created as ERC1167 clones
 */

contract Quest is IQuest {
    using SafeERC20 for IERC20;

    // state variables
    bool public initialized;
    bool public started;
    bool public beingDisputed;
    bool public finished;
    bool public rewarded;
    bool public withToken;

    uint256 public MAX_EXTENSIONS;
    uint256 public extendedCount;
    address public escrowImplementation; // native or with token
    uint32 public seekerId;
    uint32 public solverId;
    address public mediator;
    string public infoURI;

    address public token;

    uint256 public paymentAmount;
    uint256 public rewardTime;

    ITavern private tavern;

    address private escrow;

    modifier onlySeeker() {
        require(tavern.ownerOf(seekerId) == msg.sender, "only Seeker");
        _;
    }

    modifier onlySolver() {
        require(tavern.ownerOf(solverId) == msg.sender, "only Solver");
        _;
    }

    modifier onlyMediator() {
        require(msg.sender == mediator, "only mediator");
        _;
    }

    function initialize(
        uint32 _seekerNftId,
        uint32 _solverNftId,
        uint256 _paymentAmount,
        string memory _infoURI,
        uint256 _maxExtensions,
        address _escrowImplementation,
        address _token
    ) external {
        tavern = ITavern(msg.sender);
        require(!initialized, "Already Initialized");
        initialized = true;

        token = _token;
        escrowImplementation = _escrowImplementation;

        seekerId = _seekerNftId;
        solverId = _solverNftId;

        paymentAmount = _paymentAmount;

        infoURI = _infoURI;
        MAX_EXTENSIONS = _maxExtensions;
    }

    function startQuest() external payable onlySeeker {
        require(initialized, "not initialized");
        require(!started, "already started");

        started = true;
        escrow = Clones.clone(escrowImplementation);

        if (token == address(0)) {
            emit QuestStarted(seekerId, solverId, token, paymentAmount, escrow);
            IEscrow(escrow).initialize{value: msg.value}(
                token,
                seekerId,
                solverId,
                paymentAmount
            );
        } else {
            (uint256 platformTax, uint256 referralTax) = IRewarder(
                getRewarder()
            ).calculateSeekerTax(paymentAmount);

            emit QuestStarted(seekerId, solverId, token, paymentAmount, escrow);

            IERC20(token).transferFrom(
                msg.sender,
                escrow,
                paymentAmount + platformTax + referralTax
            );

            IEscrow(escrow).initialize(
                token,
                seekerId,
                solverId,
                paymentAmount
            );
        }
    }

    /**
     * @dev ERC20 Tokens should be approved on rewarder
     */
    function startDispute() external payable onlySeeker {
        require(started, "quest not started");
        require(!beingDisputed, "Dispute started before");
        require(!rewarded, "Rewarded before");

        beingDisputed = true;
        mediator = tavern.mediator();

        if (token == address(0)) {
            emit DisputeStarted(seekerId, solverId);
            IEscrow(escrow).processStartDispute{value: msg.value}();
        } else {
            require(msg.value == 0, "Native token sent");
            emit DisputeStarted(seekerId, solverId);
            IEscrow(escrow).processStartDispute{value: 0}();
        }
    }

    function resolveDispute(uint32 solverShare) external onlyMediator {
        require(beingDisputed, "Dispute not started");
        require(!rewarded, "Rewarded before");
        require(solverShare <= 10000, "Share can't be more than 10000");

        rewarded = true;

        emit DisputeResolved(seekerId, solverId, solverShare);

        IEscrow(escrow).processResolution(solverShare);
    }

    function finishQuest() external onlySolver {
        require(started, "quest not started");

        finished = true;

        emit QuestFinished(seekerId, solverId);

        rewardTime = block.timestamp + tavern.reviewPeriod();
    }

    function extend() external onlySeeker {
        require(finished, "Quest not finished");
        require(
            extendedCount < MAX_EXTENSIONS,
            "Max extensions number reached"
        );
        require(!rewarded, "Was rewarded before");

        extendedCount++;

        emit QuestExtended(seekerId, solverId, extendedCount);

        rewardTime += tavern.reviewPeriod();
    }

    function receiveReward() external onlySolver {
        require(finished, "Quest not finished");
        require(!rewarded, "Rewarded before");
        require(!beingDisputed, "Is under dispute");
        require(rewardTime <= block.timestamp, "Not reward time yet");

        rewarded = true;

        emit RewardReceived(seekerId, solverId, paymentAmount);

        IEscrow(escrow).processPayment();
    }

    function getRewarder() public view returns (address) {
        return tavern.getRewarder();
    }
}
