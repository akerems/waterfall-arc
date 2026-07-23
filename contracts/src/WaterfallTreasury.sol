// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title WaterfallTreasury
/// @notice Routes the full USDC treasury balance through owner-defined,
/// prioritized payment rules. This is a hackathon prototype for testnet use.
contract WaterfallTreasury is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant MAX_RULES = 6;
    uint256 public constant BASIS_POINTS = 10_000;

    enum RuleType {
        PERCENT_OF_REMAINING,
        FIXED_AMOUNT,
        TARGET_BALANCE,
        REMAINDER
    }

    struct Rule {
        string name;
        address recipient;
        RuleType ruleType;
        uint256 value;
    }

    error ZeroAddress();
    error EmptyRules();
    error TooManyRules(uint256 supplied, uint256 maximum);
    error EmptyRuleName(uint256 ruleIndex);
    error ZeroRecipient(uint256 ruleIndex);
    error DuplicateRecipient(address recipient);
    error InvalidPercentage(uint256 ruleIndex, uint256 value);
    error InvalidRemainderValue(uint256 ruleIndex, uint256 value);
    error InvalidRemainderCount(uint256 count);
    error RemainderMustBeLast(uint256 ruleIndex);
    error RulesNotConfigured();
    error EmptyTreasury();

    IERC20 public immutable usdc;
    uint256 public distributionCounter;
    uint256 public totalAmountDistributed;
    uint256 public lastExecutionTimestamp;

    Rule[] private rules;

    event RulesUpdated(uint256 ruleCount);
    event RulePayment(
        uint256 indexed executionId,
        uint256 indexed ruleIndex,
        string ruleName,
        address indexed recipient,
        uint256 amount
    );
    event WaterfallExecuted(
        uint256 indexed executionId,
        address indexed executor,
        uint256 startingBalance,
        uint256 distributedAmount,
        uint256 timestamp
    );
    event EmergencyWithdrawal(address indexed recipient, uint256 amount);

    constructor(address usdcAddress) Ownable(msg.sender) {
        if (usdcAddress == address(0)) revert ZeroAddress();
        usdc = IERC20(usdcAddress);
    }

    function setRules(Rule[] calldata newRules) external onlyOwner {
        uint256 ruleCount = newRules.length;
        if (ruleCount == 0) revert EmptyRules();
        if (ruleCount > MAX_RULES) revert TooManyRules(ruleCount, MAX_RULES);

        uint256 remainderCount;
        for (uint256 i; i < ruleCount; ++i) {
            Rule calldata rule = newRules[i];
            if (bytes(rule.name).length == 0) revert EmptyRuleName(i);
            if (rule.recipient == address(0)) revert ZeroRecipient(i);

            for (uint256 j; j < i; ++j) {
                if (newRules[j].recipient == rule.recipient) {
                    revert DuplicateRecipient(rule.recipient);
                }
            }

            if (rule.ruleType == RuleType.PERCENT_OF_REMAINING && rule.value > BASIS_POINTS) {
                revert InvalidPercentage(i, rule.value);
            }

            if (rule.ruleType == RuleType.REMAINDER) {
                ++remainderCount;
                if (rule.value != 0) revert InvalidRemainderValue(i, rule.value);
                if (i != ruleCount - 1) revert RemainderMustBeLast(i);
            }
        }

        if (remainderCount != 1) revert InvalidRemainderCount(remainderCount);

        delete rules;
        for (uint256 i; i < ruleCount; ++i) {
            rules.push(newRules[i]);
        }

        emit RulesUpdated(ruleCount);
    }

    function getRules() external view returns (Rule[] memory) {
        return rules;
    }

    function previewDistribution() external view returns (uint256 treasuryBalance, uint256[] memory amounts) {
        treasuryBalance = usdc.balanceOf(address(this));
        amounts = _calculateDistribution(treasuryBalance);
    }

    function executeWaterfall() external nonReentrant whenNotPaused {
        if (rules.length == 0) revert RulesNotConfigured();
        uint256 startingBalance = usdc.balanceOf(address(this));
        if (startingBalance == 0) revert EmptyTreasury();

        uint256[] memory amounts = _calculateDistribution(startingBalance);
        uint256 executionId = distributionCounter + 1;

        distributionCounter = executionId;
        totalAmountDistributed += startingBalance;
        lastExecutionTimestamp = block.timestamp;

        uint256 ruleCount = rules.length;
        for (uint256 i; i < ruleCount; ++i) {
            uint256 amount = amounts[i];
            if (amount == 0) continue;

            Rule storage rule = rules[i];
            usdc.safeTransfer(rule.recipient, amount);
            emit RulePayment(executionId, i, rule.name, rule.recipient, amount);
        }

        emit WaterfallExecuted(executionId, msg.sender, startingBalance, startingBalance, block.timestamp);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function emergencyWithdraw(address recipient) external onlyOwner whenPaused {
        if (recipient == address(0)) revert ZeroAddress();
        uint256 amount = usdc.balanceOf(address(this));
        if (amount != 0) usdc.safeTransfer(recipient, amount);
        emit EmergencyWithdrawal(recipient, amount);
    }

    function _calculateDistribution(uint256 treasuryBalance) private view returns (uint256[] memory amounts) {
        uint256 ruleCount = rules.length;
        amounts = new uint256[](ruleCount);
        uint256 remaining = treasuryBalance;

        for (uint256 i; i < ruleCount; ++i) {
            Rule storage rule = rules[i];
            uint256 amount;

            if (rule.ruleType == RuleType.PERCENT_OF_REMAINING) {
                amount = remaining * rule.value / BASIS_POINTS;
            } else if (rule.ruleType == RuleType.FIXED_AMOUNT) {
                amount = _min(remaining, rule.value);
            } else if (rule.ruleType == RuleType.TARGET_BALANCE) {
                uint256 recipientBalance = usdc.balanceOf(rule.recipient);
                if (recipientBalance < rule.value) {
                    amount = _min(remaining, rule.value - recipientBalance);
                }
            } else {
                amount = remaining;
            }

            amounts[i] = amount;
            remaining -= amount;
        }
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
}
