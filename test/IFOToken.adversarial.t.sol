// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IFOToken} from "src/IFOToken.sol";

/// @dev Extends the basic ERC-20 tests with adversarial approval lifecycles and arithmetic edges.
/// forge-config: default.fuzz.runs = 1000
contract IFOTokenAdversarialTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    IFOToken internal token;
    address internal alice;
    address internal bob;
    address internal spender;

    function setUp() public {
        token = new IFOToken();
        alice = makeAddr("holder");
        bob = makeAddr("recipient");
        spender = makeAddr("approved spender");
    }

    function test_OneWeiAllowanceCannotBeSpentTwice() public {
        assertTrue(token.transfer(alice, 2));
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.allowance(alice, spender), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        _assertBalances(1, 1);
    }

    function test_MaxMinusOneAllowanceIsFinite() public {
        uint256 allowed = type(uint256).max - 1;
        assertTrue(token.approve(spender, allowed));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, SUPPLY));
        assertEq(token.allowance(address(this), spender), allowed - SUPPLY);
        _assertBalances(0, SUPPLY);
    }

    function test_InfiniteApprovalCanBeReplacedAndRevokedAfterUse() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 1));
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);

        assertTrue(token.approve(spender, type(uint256).max));
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), 0);
        _assertBalances(0, 2);
    }

    function test_TransferFromByHolderRequiresSelfApproval() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), bob, 1);
        _assertBalances(0, 0);

        assertTrue(token.approve(address(this), 1));
        assertTrue(token.transferFrom(address(this), bob, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        _assertBalances(0, 1);
    }

    function test_DelegatedSelfTransferCannotExceedBalance() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        assertTrue(token.approve(spender, 2));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1, 2));
        vm.prank(spender);
        token.transferFrom(alice, alice, 2);
        assertEq(token.allowance(alice, spender), 2);
        _assertBalances(1, 0);
    }

    function test_MaximumApprovalDoesNotAllowMaximumTransfer() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), bob, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        _assertBalances(0, 0);
    }

    function test_ZeroDelegatedTransferToZeroRejectsInfiniteApproval() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 0);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        _assertBalances(0, 0);
    }

    function test_ZeroSpenderRejectsZeroAndMaximumApproval() public {
        assertTrue(token.approve(spender, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), type(uint256).max);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.allowance(address(this), spender), 1);
        _assertBalances(0, 0);
    }

    function testFuzz_ApprovalReplacementIsIsolatedByOwnerAndSpender(uint256 first, uint256 second, uint256 replacement)
        public
    {
        assertTrue(token.approve(spender, first));
        assertTrue(token.approve(bob, 1));
        vm.prank(alice);
        assertTrue(token.approve(spender, second));
        assertTrue(token.approve(spender, replacement));

        assertEq(token.allowance(address(this), spender), replacement);
        assertEq(token.allowance(alice, spender), second);
        assertEq(token.allowance(address(this), bob), 1);
        assertEq(token.allowance(alice, bob), 0);
        assertEq(token.allowance(spender, address(this)), 0);
        assertEq(token.allowance(bob, address(this)), 0);
        _assertBalances(0, 0);
    }

    function testFuzz_ApprovalDoesNotFollowTransferredTokens(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 1, SUPPLY);
        assertTrue(token.approve(spender, type(uint256).max));
        assertTrue(token.transfer(alice, amount));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.allowance(alice, spender), 0);
        _assertBalances(amount, 0);
    }

    function testFuzz_ApprovedBalanceOverrunRollsBackAllowance(
        uint256 rawBalance,
        uint256 rawAmount,
        uint256 rawAllowance,
        bool infinite
    ) public {
        uint256 held = bound(rawBalance, 0, SUPPLY);
        uint256 amount = bound(rawAmount, held + 1, type(uint256).max - 1);
        uint256 allowed = infinite ? type(uint256).max : bound(rawAllowance, amount, type(uint256).max - 1);
        assertTrue(token.transfer(alice, held));
        vm.prank(alice);
        assertTrue(token.approve(spender, allowed));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), allowed);
        _assertBalances(held, 0);
    }

    function testFuzz_ZeroRecipientFailurePreservesAnyAllowance(uint256 allowed, uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 0, allowed < SUPPLY ? allowed : SUPPLY);
        assertTrue(token.approve(spender, allowed));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.allowance(address(this), spender), allowed);
        _assertBalances(0, 0);
    }

    function testFuzz_ExhaustedApprovalCannotBeReusedAfterTokensReturn(uint256 rawAllowance, uint256 rawFirstSpend)
        public
    {
        uint256 allowed = bound(rawAllowance, 1, SUPPLY);
        uint256 firstSpend = bound(rawFirstSpend, 0, allowed);
        assertTrue(token.approve(spender, allowed));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, firstSpend));
        assertEq(token.allowance(address(this), spender), allowed - firstSpend);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, allowed - firstSpend));
        assertEq(token.allowance(address(this), spender), 0);
        _assertBalances(0, allowed);

        // Returning the funds restores balances, but cannot restore authorization to spend them.
        vm.prank(bob);
        assertTrue(token.transfer(address(this), allowed));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), 0);
        _assertBalances(0, 0);
    }

    function testFuzz_DelegatedSelfTransferPreservesBalanceAndSpendsApproval(
        uint256 rawBalance,
        uint256 allowed,
        uint256 rawAmount
    ) public {
        uint256 held = bound(rawBalance, 0, SUPPLY);
        uint256 amount = bound(rawAmount, 0, allowed < held ? allowed : held);
        assertTrue(token.transfer(alice, held));
        vm.prank(alice);
        assertTrue(token.approve(spender, allowed));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, alice, amount));
        assertEq(token.allowance(alice, spender), allowed == type(uint256).max ? allowed : allowed - amount);
        _assertBalances(held, 0);
    }

    function testFuzz_ZeroValueTransfersPreserveExistingApproval(uint256 allowed) public {
        assertTrue(token.approve(spender, allowed));
        assertTrue(token.transfer(bob, 0));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 0));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 0));
        assertEq(token.allowance(address(this), spender), allowed);
        _assertBalances(0, 0);
    }

    function _assertBalances(uint256 aliceBalance, uint256 bobBalance) internal view {
        assertEq(token.balanceOf(alice), aliceBalance);
        assertEq(token.balanceOf(bob), bobBalance);
        assertEq(token.balanceOf(address(this)), SUPPLY - aliceBalance - bobBalance);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
