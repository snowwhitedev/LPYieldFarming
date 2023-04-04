// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IRewarder.sol";
import "./libraries/TransferHelper.sol";

contract Rewarder is IRewarder, Ownable {
    address public immutable UNO;
    address public immutable UNO_MASTER_CHEF;

    constructor(address _UNO, address _UNO_MASTER_CHEF) {
        UNO = _UNO;
        UNO_MASTER_CHEF = _UNO_MASTER_CHEF;
    }

    modifier onlyMasterChef() {
        require(msg.sender == UNO_MASTER_CHEF, "Only Insurance can call this function.");
        _;
    }

    function onReward(address to, uint256 amount) external override onlyMasterChef returns (uint256) {
        uint256 rewardBal = IERC20(UNO).balanceOf(address(this));
        if (amount > rewardBal) {
            amount = rewardBal;
        }

        TransferHelper.safeTransfer(UNO, to, amount);
        return amount;
    }

    function withdrawAsset(
        address _token,
        address _to,
        uint256 _amount
    ) external onlyOwner {
        TransferHelper.safeTransfer(_token, _to, _amount);
    }
}
