// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IFOToken} from "../src/IFOToken.sol";

/// @dev A closed set of actors lets the invariant account for every token and allowance.
///      The expected ledger is maintained independently of the token's reported balances.
contract TokenHandler is Test {
    IFOToken public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(IFOToken token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
        expectedBalance[actors_[0]] = 1_000_000_000 * 10 ** 18;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = bound(rawAmount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAmount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 amount = rawAmount % 5 == 0 ? type(uint256).max : bound(rawAmount, 0, 1_000_000_000 * 10 ** 18);
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawAmount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 available = expectedBalance[owner];
        uint256 amount = bound(rawAmount, 0, allowed < available ? allowed : available);

        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        if (allowed != type(uint256).max) {
            expectedAllowance[owner][spender] -= amount;
        }
    }

    function attemptOverspend(uint256 fromSeed, uint256 toSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = expectedBalance[from] + 1;
        _expectFailure(
            from,
            abi.encodeCall(token.transfer, (to, amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, expectedBalance[from], amount)
        );
        // The model is unchanged. The invariant also detects partial state changes on failure.
    }

    function revoke(uint256 ownerSeed, uint256 spenderSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, 0));
        expectedAllowance[owner][spender] = 0;

        _expectFailure(
            spender,
            abi.encodeCall(token.transferFrom, (owner, spender, 1)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
    }

    function attemptAllowanceOverrun(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAllowance) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        // Establish a finite allowance even if this pair previously had unlimited approval.
        uint256 allowed = bound(rawAllowance, 0, 1_000_000_000 * 10 ** 18);
        vm.prank(owner);
        assertTrue(token.approve(spender, allowed));
        expectedAllowance[owner][spender] = allowed;

        _expectFailure(
            spender,
            abi.encodeCall(token.transferFrom, (owner, spender, allowed + 1)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, allowed + 1)
        );
    }

    function attemptApprovedOverspend(uint256 ownerSeed, uint256 spenderSeed, bool infinite) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 amount = expectedBalance[owner] + 1;
        uint256 allowed = infinite ? type(uint256).max : amount;
        vm.prank(owner);
        assertTrue(token.approve(spender, allowed));
        expectedAllowance[owner][spender] = allowed;

        _expectFailure(
            spender,
            abi.encodeCall(token.transferFrom, (owner, spender, amount)),
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, owner, expectedBalance[owner], amount
            )
        );
    }

    function attemptZeroRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAmount, bool delegated) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 limit = expectedBalance[owner];
        if (delegated && expectedAllowance[owner][spender] < limit) {
            limit = expectedAllowance[owner][spender];
        }
        uint256 amount = bound(rawAmount, 0, limit);
        bytes memory data = delegated
            ? abi.encodeCall(token.transferFrom, (owner, address(0), amount))
            : abi.encodeCall(token.transfer, (address(0), amount));
        _expectFailure(
            delegated ? spender : owner,
            data,
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
    }

    function attemptZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        _expectFailure(
            owner,
            abi.encodeCall(token.approve, (address(0), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
    }

    function _expectFailure(address caller, bytes memory data, bytes memory expectedError) internal {
        vm.prank(caller);
        (bool success, bytes memory result) = address(token).call(data);
        assertFalse(success, "invalid operation succeeded");
        assertEq(result, expectedError, "unexpected failure reason");
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract IFOTokenInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    IFOToken internal token;
    TokenHandler internal handler;
    address[4] internal actors;

    function setUp() public {
        actors = [makeAddr("actor 0"), makeAddr("actor 1"), makeAddr("actor 2"), makeAddr("actor 3")];
        token = new IFOToken();
        token.transfer(actors[0], SUPPLY);
        handler = new TokenHandler(token, actors);

        // Reach funded, approved states from the start through real token operations.
        // Other pairs remain unapproved, and random revocations can remove the seeded approvals.
        for (uint256 i = 1; i < actors.length; ++i) {
            handler.transfer(0, i, SUPPLY / actors.length);
        }
        for (uint256 i; i < actors.length; ++i) {
            handler.approve(i, (i + 1) % actors.length, SUPPLY / actors.length + 1);
        }

        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        selectors[3] = TokenHandler.attemptOverspend.selector;
        selectors[4] = TokenHandler.revoke.selector;
        selectors[5] = TokenHandler.attemptAllowanceOverrun.selector;
        selectors[6] = TokenHandler.attemptApprovedOverspend.selector;
        selectors[7] = TokenHandler.attemptZeroRecipient.selector;
        selectors[8] = TokenHandler.attemptZeroSpender.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_FixedSupplyAndIndependentLedgerMatch() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            address actor = actors[i];
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.expectedBalance(actor), "balance differs from independent model");
            sum += balance;
            assertEq(token.allowance(actor, address(0)), 0, "zero address was approved");
            assertEq(token.allowance(address(0), actor), 0, "zero address granted approval");
            for (uint256 j; j < actors.length; ++j) {
                assertEq(
                    token.allowance(actor, actors[j]),
                    handler.expectedAllowance(actor, actors[j]),
                    "allowance differs from independent model"
                );
            }
        }
        assertEq(sum, SUPPLY, "tokens created, lost, or diverted");
        assertEq(token.totalSupply(), SUPPLY, "supply changed");
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.name(), "Initial Fee Offering");
        assertEq(token.symbol(), "IFO");
        assertEq(token.decimals(), 18);
    }

    /// @dev A valid balance must remain transferable after every generated sequence.
    ///      Each round trip restores the independent ledger before checking the next actor.
    function afterInvariant() public {
        for (uint256 i; i < actors.length; ++i) {
            address from = actors[i];
            address to = actors[(i + 1) % actors.length];
            uint256 amount = handler.expectedBalance(from);
            uint256 recipientBefore = handler.expectedBalance(to);
            vm.prank(from);
            assertTrue(token.transfer(to, amount));
            assertEq(token.balanceOf(from), 0);
            assertEq(token.balanceOf(to), recipientBefore + amount);
            vm.prank(to);
            assertTrue(token.transfer(from, amount));
            invariant_FixedSupplyAndIndependentLedgerMatch();
        }
    }
}
