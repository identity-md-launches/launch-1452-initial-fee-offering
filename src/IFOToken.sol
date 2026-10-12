// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Initial Fee Offering
/// @notice A fixed supply ERC-20 with 18 decimals and ordinary, fee-free transfers.
/// @dev The immediate deployer receives the entire supply. At launch this is the factory.
///      No externally callable mint, burn, administrator, or upgrade functions exist.
contract IFOToken is ERC20 {
    /// @notice One billion IFO, expressed in the token's smallest units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("Initial Fee Offering", "IFO") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
