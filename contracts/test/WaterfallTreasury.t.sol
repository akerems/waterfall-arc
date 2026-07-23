// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {WaterfallTreasury} from "../src/WaterfallTreasury.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";

contract WaterfallTreasuryTest is Test {
    uint256 private constant USDC = 1e6;

    MockUSDC private usdc;
    WaterfallTreasury private treasury;

    address private taxes = makeAddr("taxes");
    address private supplier = makeAddr("supplier");
    address private reserve = makeAddr("reserve");
    address private profit = makeAddr("profit");
    address private executor = makeAddr("executor");

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

    function setUp() public {
        usdc = new MockUSDC();
        treasury = new WaterfallTreasury(address(usdc));
        treasury.setRules(_demoRules());
    }

    function test_FirstHundredUsdcFollowsExpectedWaterfall() public {
        usdc.mint(address(treasury), 100 * USDC);

        vm.prank(executor);
        treasury.executeWaterfall();

        assertEq(usdc.balanceOf(taxes), 20 * USDC);
        assertEq(usdc.balanceOf(supplier), 30 * USDC);
        assertEq(usdc.balanceOf(reserve), 25 * USDC);
        assertEq(usdc.balanceOf(profit), 25 * USDC);
        assertEq(treasury.distributionCounter(), 1);
        assertEq(treasury.totalAmountDistributed(), 100 * USDC);
    }

    function test_SecondHundredUsdcSkipsFullReserve() public {
        usdc.mint(address(treasury), 100 * USDC);
        treasury.executeWaterfall();

        usdc.mint(address(treasury), 100 * USDC);
        vm.prank(executor);
        treasury.executeWaterfall();

        assertEq(usdc.balanceOf(taxes), 40 * USDC);
        assertEq(usdc.balanceOf(supplier), 60 * USDC);
        assertEq(usdc.balanceOf(reserve), 25 * USDC);
        assertEq(usdc.balanceOf(profit), 75 * USDC);
        assertEq(treasury.distributionCounter(), 2);
        assertEq(treasury.totalAmountDistributed(), 200 * USDC);
    }

    function test_FortyUsdcPrioritizesEarlierRules() public {
        usdc.mint(address(treasury), 40 * USDC);

        vm.prank(executor);
        treasury.executeWaterfall();

        assertEq(usdc.balanceOf(taxes), 8 * USDC);
        assertEq(usdc.balanceOf(supplier), 30 * USDC);
        assertEq(usdc.balanceOf(reserve), 2 * USDC);
        assertEq(usdc.balanceOf(profit), 0);
    }

    function test_PreviewMatchesFirstHundredUsdcScenarioWithoutChangingState() public {
        usdc.mint(address(treasury), 100 * USDC);

        (uint256 balance, uint256[] memory amounts) = treasury.previewDistribution();

        assertEq(balance, 100 * USDC);
        assertEq(amounts[0], 20 * USDC);
        assertEq(amounts[1], 30 * USDC);
        assertEq(amounts[2], 25 * USDC);
        assertEq(amounts[3], 25 * USDC);
        assertEq(treasury.distributionCounter(), 0);
        assertEq(usdc.balanceOf(address(treasury)), 100 * USDC);
    }

    function test_ConstructorRejectsZeroUsdcAddress() public {
        vm.expectRevert(WaterfallTreasury.ZeroAddress.selector);
        new WaterfallTreasury(address(0));
    }

    function test_OnlyOwnerCanSetRules() public {
        vm.prank(executor);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, executor));
        treasury.setRules(_demoRules());
    }

    function test_RulesMustIncludeExactlyOneRemainder() public {
        WaterfallTreasury.Rule[] memory rules = new WaterfallTreasury.Rule[](1);
        rules[0] = _rule("Taxes", taxes, WaterfallTreasury.RuleType.PERCENT_OF_REMAINING, 2_000);

        vm.expectRevert(abi.encodeWithSelector(WaterfallTreasury.InvalidRemainderCount.selector, 0));
        treasury.setRules(rules);
    }

    function test_RemainderMustBeLast() public {
        WaterfallTreasury.Rule[] memory rules = new WaterfallTreasury.Rule[](2);
        rules[0] = _rule("Profit", profit, WaterfallTreasury.RuleType.REMAINDER, 0);
        rules[1] = _rule("Supplier", supplier, WaterfallTreasury.RuleType.FIXED_AMOUNT, USDC);

        vm.expectRevert(abi.encodeWithSelector(WaterfallTreasury.RemainderMustBeLast.selector, 0));
        treasury.setRules(rules);
    }

    function test_MaximumRuleCountIsEnforced() public {
        WaterfallTreasury.Rule[] memory rules = new WaterfallTreasury.Rule[](7);

        vm.expectRevert(abi.encodeWithSelector(WaterfallTreasury.TooManyRules.selector, 7, 6));
        treasury.setRules(rules);
    }

    function test_ZeroRecipientIsRejected() public {
        WaterfallTreasury.Rule[] memory rules = new WaterfallTreasury.Rule[](1);
        rules[0] = _rule("Profit", address(0), WaterfallTreasury.RuleType.REMAINDER, 0);

        vm.expectRevert(abi.encodeWithSelector(WaterfallTreasury.ZeroRecipient.selector, 0));
        treasury.setRules(rules);
    }

    function test_DuplicateRecipientsAreRejected() public {
        WaterfallTreasury.Rule[] memory rules = new WaterfallTreasury.Rule[](2);
        rules[0] = _rule("Supplier", profit, WaterfallTreasury.RuleType.FIXED_AMOUNT, USDC);
        rules[1] = _rule("Profit", profit, WaterfallTreasury.RuleType.REMAINDER, 0);

        vm.expectRevert(abi.encodeWithSelector(WaterfallTreasury.DuplicateRecipient.selector, profit));
        treasury.setRules(rules);
    }

    function test_InvalidBasisPointValueIsRejected() public {
        WaterfallTreasury.Rule[] memory rules = new WaterfallTreasury.Rule[](2);
        rules[0] = _rule("Taxes", taxes, WaterfallTreasury.RuleType.PERCENT_OF_REMAINING, 10_001);
        rules[1] = _rule("Profit", profit, WaterfallTreasury.RuleType.REMAINDER, 0);

        vm.expectRevert(abi.encodeWithSelector(WaterfallTreasury.InvalidPercentage.selector, 0, 10_001));
        treasury.setRules(rules);
    }

    function test_EmptyRuleNameIsRejected() public {
        WaterfallTreasury.Rule[] memory rules = new WaterfallTreasury.Rule[](1);
        rules[0] = _rule("", profit, WaterfallTreasury.RuleType.REMAINDER, 0);

        vm.expectRevert(abi.encodeWithSelector(WaterfallTreasury.EmptyRuleName.selector, 0));
        treasury.setRules(rules);
    }

    function test_RemainderValueMustBeZero() public {
        WaterfallTreasury.Rule[] memory rules = new WaterfallTreasury.Rule[](1);
        rules[0] = _rule("Profit", profit, WaterfallTreasury.RuleType.REMAINDER, 1);

        vm.expectRevert(abi.encodeWithSelector(WaterfallTreasury.InvalidRemainderValue.selector, 0, 1));
        treasury.setRules(rules);
    }

    function test_EmptyTreasuryExecutionReverts() public {
        vm.expectRevert(WaterfallTreasury.EmptyTreasury.selector);
        treasury.executeWaterfall();
    }

    function test_UnconfiguredTreasuryExecutionReverts() public {
        WaterfallTreasury unconfigured = new WaterfallTreasury(address(usdc));
        usdc.mint(address(unconfigured), USDC);

        vm.expectRevert(WaterfallTreasury.RulesNotConfigured.selector);
        unconfigured.executeWaterfall();
    }

    function test_PreviewMatchesActualExecution() public {
        usdc.mint(address(treasury), 100 * USDC);
        (, uint256[] memory preview) = treasury.previewDistribution();

        treasury.executeWaterfall();

        assertEq(usdc.balanceOf(taxes), preview[0]);
        assertEq(usdc.balanceOf(supplier), preview[1]);
        assertEq(usdc.balanceOf(reserve), preview[2]);
        assertEq(usdc.balanceOf(profit), preview[3]);
    }

    function test_FixedAmountNeverExceedsRemainingBalance() public {
        WaterfallTreasury.Rule[] memory rules = new WaterfallTreasury.Rule[](2);
        rules[0] = _rule("Supplier", supplier, WaterfallTreasury.RuleType.FIXED_AMOUNT, 30 * USDC);
        rules[1] = _rule("Profit", profit, WaterfallTreasury.RuleType.REMAINDER, 0);
        treasury.setRules(rules);
        usdc.mint(address(treasury), 10 * USDC);

        treasury.executeWaterfall();

        assertEq(usdc.balanceOf(supplier), 10 * USDC);
        assertEq(usdc.balanceOf(profit), 0);
    }

    function test_ReserveTargetNeverReceivesMoreThanRequired() public {
        usdc.mint(reserve, 24 * USDC);
        usdc.mint(address(treasury), 100 * USDC);

        treasury.executeWaterfall();

        assertEq(usdc.balanceOf(reserve), 25 * USDC);
        assertEq(usdc.balanceOf(profit), 49 * USDC);
    }

    function test_RemainderReceivesRoundingDust() public {
        WaterfallTreasury.Rule[] memory rules = new WaterfallTreasury.Rule[](2);
        rules[0] = _rule("Taxes", taxes, WaterfallTreasury.RuleType.PERCENT_OF_REMAINING, 3_333);
        rules[1] = _rule("Profit", profit, WaterfallTreasury.RuleType.REMAINDER, 0);
        treasury.setRules(rules);
        usdc.mint(address(treasury), 101);

        treasury.executeWaterfall();

        assertEq(usdc.balanceOf(taxes), 33);
        assertEq(usdc.balanceOf(profit), 68);
        assertEq(usdc.balanceOf(address(treasury)), 0);
    }

    function test_PausingPreventsExecution() public {
        treasury.pause();
        usdc.mint(address(treasury), USDC);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        treasury.executeWaterfall();
    }

    function test_OnlyOwnerCanPauseAndUnpause() public {
        vm.prank(executor);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, executor));
        treasury.pause();

        treasury.pause();

        vm.prank(executor);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, executor));
        treasury.unpause();

        treasury.unpause();
        assertFalse(treasury.paused());
    }

    function test_EmergencyWithdrawalOnlyWorksWhilePaused() public {
        usdc.mint(address(treasury), 10 * USDC);

        vm.expectRevert(Pausable.ExpectedPause.selector);
        treasury.emergencyWithdraw(profit);

        treasury.pause();
        treasury.emergencyWithdraw(profit);

        assertEq(usdc.balanceOf(profit), 10 * USDC);
        assertEq(usdc.balanceOf(address(treasury)), 0);
    }

    function test_NonOwnerEmergencyWithdrawalFails() public {
        treasury.pause();
        usdc.mint(address(treasury), 10 * USDC);

        vm.prank(executor);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, executor));
        treasury.emergencyWithdraw(profit);
    }

    function test_ExecutionCounterIncreasesCorrectly() public {
        for (uint256 expected = 1; expected <= 3; ++expected) {
            usdc.mint(address(treasury), USDC);
            treasury.executeWaterfall();
            assertEq(treasury.distributionCounter(), expected);
        }

        assertEq(treasury.totalAmountDistributed(), 3 * USDC);
        assertEq(treasury.lastExecutionTimestamp(), block.timestamp);
    }

    function test_EventsContainCorrectRecipientsAndAmounts() public {
        usdc.mint(address(treasury), 100 * USDC);

        vm.expectEmit(true, true, true, true, address(treasury));
        emit RulePayment(1, 0, "Taxes", taxes, 20 * USDC);
        vm.expectEmit(true, true, true, true, address(treasury));
        emit RulePayment(1, 1, "Supplier", supplier, 30 * USDC);
        vm.expectEmit(true, true, true, true, address(treasury));
        emit RulePayment(1, 2, "Reserve", reserve, 25 * USDC);
        vm.expectEmit(true, true, true, true, address(treasury));
        emit RulePayment(1, 3, "Profit", profit, 25 * USDC);
        vm.expectEmit(true, true, false, true, address(treasury));
        emit WaterfallExecuted(1, executor, 100 * USDC, 100 * USDC, block.timestamp);

        vm.prank(executor);
        treasury.executeWaterfall();
    }

    function _demoRules() private view returns (WaterfallTreasury.Rule[] memory rules) {
        rules = new WaterfallTreasury.Rule[](4);
        rules[0] = WaterfallTreasury.Rule({
            name: "Taxes",
            recipient: taxes,
            ruleType: WaterfallTreasury.RuleType.PERCENT_OF_REMAINING,
            value: 2_000
        });
        rules[1] = WaterfallTreasury.Rule({
            name: "Supplier",
            recipient: supplier,
            ruleType: WaterfallTreasury.RuleType.FIXED_AMOUNT,
            value: 30 * USDC
        });
        rules[2] = WaterfallTreasury.Rule({
            name: "Reserve",
            recipient: reserve,
            ruleType: WaterfallTreasury.RuleType.TARGET_BALANCE,
            value: 25 * USDC
        });
        rules[3] = WaterfallTreasury.Rule({
            name: "Profit",
            recipient: profit,
            ruleType: WaterfallTreasury.RuleType.REMAINDER,
            value: 0
        });
    }

    function _rule(string memory name, address recipient, WaterfallTreasury.RuleType ruleType, uint256 value)
        private
        pure
        returns (WaterfallTreasury.Rule memory)
    {
        return WaterfallTreasury.Rule({name: name, recipient: recipient, ruleType: ruleType, value: value});
    }
}
