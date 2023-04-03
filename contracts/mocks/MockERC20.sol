// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * This smart contract
 */

contract MockERC20 is Ownable, ERC20 {
    uint256 INITIAL_SUPPLY = 100000000000000000 * 10**18;

    mapping(address => uint256) private _faucets;
    uint256 public constant faucetLimit = 500000000 * 10**18;

    constructor(string memory __name, string memory __symbol) ERC20(__name, __symbol) {
        _mint(msg.sender, INITIAL_SUPPLY);
    }

    function faucetToken(uint256 _amount) external {
        require(
            msg.sender == owner() || _faucets[msg.sender] + _amount <= faucetLimit,
            "Uno: Faucet amount limitation"
        );
        _mint(msg.sender, _amount);
    }
}
