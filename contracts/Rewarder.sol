// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IRewarder.sol";
import "./libraries/TransferHelper.sol";

contract Rewarder is IRewarder, Ownable {
    address public immutable SB;
    address public immutable SB_MASTER_CHEF;

    constructor(address _SB, address _SB_MASTER_CHEF) {
        SB = _SB;
        SB_MASTER_CHEF = _SB_MASTER_CHEF;
    }

    modifier onlyMasterChef() {
        require(msg.sender == SB_MASTER_CHEF, "Only SBMasterChef can call this function.");
        _;
    }

    function onSBReward(address to, uint256 amount) external override onlyMasterChef returns (uint256) {
        uint256 rewardBal = IERC20(SB).balanceOf(address(this));
        if (amount > rewardBal) {
            amount = rewardBal;
        }

        TransferHelper.safeTransfer(SB, to, amount);
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
