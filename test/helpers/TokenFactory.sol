// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IFOToken} from "../../src/IFOToken.sol";

/// @dev Test-only deployment and transfer helper; not an application contract for launch.
contract TokenFactory {
    function deploy(bytes32 salt) external returns (IFOToken) {
        return new IFOToken{salt: salt}();
    }

    function move(IFOToken token, address to, uint256 amount) external {
        require(token.transfer(to, amount), "transfer failed");
    }
}
