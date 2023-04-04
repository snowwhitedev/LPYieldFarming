// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IRewarder.sol";
import "./libraries/TransferHelper.sol";

contract Insurance is Ownable, ReentrancyGuard {
    /// `amount` USDT token amount the user has provided.
    /// `rewardDebt` The amount of UNO entitled to the user.
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 pendingRewards;
    }

    /// `rewardPerBlock` The amount of UNO reward assigned to the product.
    struct ProductInfo {
        uint128 accUNOPerShare;
        uint128 rewardPerBlock;
        uint256 lastRewardBlock;
        uint256 depositedAmount;
    }

    address public immutable USDT_ADDRESS;

    mapping(uint256 => ProductInfo) public productInfo;
    IRewarder public rewarder;

    mapping(uint256 => mapping(address => UserInfo)) public userInfo; // productId => user_address => userInfo
    mapping(uint256 => bool) private productExistence; // productId => bool

    uint256 private constant ACC_UNO_PRECISION = 1e12;

    uint256 public immutable rewardStartTimestamp;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
    event Withdraw(address indexed to, uint256 indexed pid, uint256 amount);
    event Harvest(address indexed user, uint256 indexed pid, uint256 pending, uint256 harvested);
    event LogProductAddition(uint256 indexed pid, uint256 rewardPerBlock);
    event LogSetProduct(uint256 indexed pid, uint256 rewardPerBlock);
    event LogUpdateProduct(uint256 indexed pid, uint256 lastRewardBlock, uint256 supply, uint256 accUNOPerShare);
    event LogSetRewarder(address indexed _user, address indexed _rewarder);

    constructor(uint256 _rewardTimestamp, address _USDT_ADDRESS) {
        require(_rewardTimestamp >= block.timestamp, " Invalid reward start timestamp");
        rewardStartTimestamp = _rewardTimestamp;
        USDT_ADDRESS = _USDT_ADDRESS;
    }

    function setRewarder(IRewarder _rewarder) external onlyOwner {
        require(address(_rewarder) != address(rewarder), "It is old rewader");
        require(address(_rewarder) != address(0), " ZERO address");
        rewarder = _rewarder;

        emit LogSetRewarder(msg.sender, address(_rewarder));
    }

    /// @param rewardPerBlock rewardPerBlock of the new product.
    function add(
        uint256 productId,
        uint256 rewardPerBlock
    ) external onlyOwner nonReentrant {
        require(!productExistence[productId], "Product already exist");

        productExistence[productId] = true;

        productInfo[productId] =  ProductInfo({
            accUNOPerShare: 0,
            rewardPerBlock: uint128(rewardPerBlock),
            lastRewardBlock: block.number,
            depositedAmount: 0
        });
        emit LogProductAddition(productId, rewardPerBlock);
    }

    /// @notice Update the given product's 
    /// @param _pid The index of the product. See `productInfo`.
    /// @param _rewardPerBlock New reward per block of the product.
    function set(
        uint256 _pid,
        uint256 _rewardPerBlock,
        bool _withUpdate
    ) external onlyOwner {
        require(productExistence[_pid], "Product does not exist");
        require(productInfo[_pid].rewardPerBlock != _rewardPerBlock, "It is old alloc point");

        productInfo[_pid].rewardPerBlock = uint128(_rewardPerBlock);
        emit LogSetProduct(_pid, _rewardPerBlock);
    }

    /// @notice View function to see pending UNO on frontend.
    /// @param _pid The index of the product. See `productInfo`.
    /// @param _user Address of user.
    /// @return pending UNO reward for a given user.
    function pendingRewards(uint256 _pid, address _user) external view returns (uint256 pending) {
        ProductInfo storage product = productInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        uint256 accUNOPerShare = product.accUNOPerShare;
        uint256 supply = product.depositedAmount;
        uint256 rewardPerBlock = product.rewardPerBlock;

        if (block.number > product.lastRewardBlock && supply != 0) {
            uint256 blocks = block.number - product.lastRewardBlock;
            uint256 unoReward = blocks * rewardPerBlock;
            accUNOPerShare = accUNOPerShare + ((unoReward * ACC_UNO_PRECISION) / supply);
        }
        pending = user.pendingRewards + (user.amount * accUNOPerShare) / ACC_UNO_PRECISION - uint256(user.rewardDebt);
    }

    /// @notice Update reward variables for product.
    /// @param pid Product ID to be updated.
    function updateProduct(uint256 pid) external nonReentrant {
        _updateProduct(pid);
    }

    /// @notice Update reward variables of the given product.
    /// @param pid The index of the product. See `productInfo`.
    function _updateProduct(uint256 pid) private {
        ProductInfo storage product = productInfo[pid];
        uint256 rewardPerBlock = product.rewardPerBlock;
        if (block.number > product.lastRewardBlock) {
            uint256 supply = product.depositedAmount;
            if (supply > 0) {
                uint256 blocks = block.number - product.lastRewardBlock;
                uint256 unoReward = blocks * rewardPerBlock;
                product.accUNOPerShare = product.accUNOPerShare + uint128((unoReward * ACC_UNO_PRECISION) / supply);
            }
            product.lastRewardBlock = block.number;
            emit LogUpdateProduct(pid, product.lastRewardBlock, supply, product.accUNOPerShare);
        }
    }

    /// @param pid The index of the product. See `productInfo`.
    /// @param amount USDT token amount to deposit. If amount = 0, it means user wants to harvest
    /// @param to The receiver of `amount` deposit benefit.
    function deposit(
        uint256 pid,
        uint256 amount,
        address to
    ) external nonReentrant {
        require(productExistence[pid], "Product does not exist");
        require(block.timestamp > rewardStartTimestamp, "Deposit is not started yet");
        ProductInfo storage product = productInfo[pid];
        UserInfo storage user = userInfo[pid][to];
        _updateProduct(pid);

        // harvest current reward
        if (user.amount > 0) {
            _harvest(pid, to);
        }

        if (amount > 0) {
            TransferHelper.safeTransferFrom(USDT_ADDRESS, msg.sender, address(this), amount);
            user.amount = user.amount + amount;
        }

        product.depositedAmount += amount;
        user.rewardDebt = (user.amount * product.accUNOPerShare) / ACC_UNO_PRECISION;
        emit Deposit(msg.sender, pid, amount, to);
    }

    /// @param pid The index of the product. See `productInfo`.
    /// @param amount USDT token amount to withdraw.
    function withdraw(uint256 pid, uint256 amount) external nonReentrant {
        _withdraw(pid, amount);
    }

    function harvest(uint256 pid, address to) external nonReentrant {
        _updateProduct(pid);
        _harvest(pid, to);
    }

    function multiHarvest(uint256[] calldata pids, address to) external nonReentrant {
        uint256 len = pids.length;
        for (uint256 ii = 0; ii < len; ii ++) {
            _harvest(pids[ii], to);
        }
    }

    function _withdraw(uint256 pid, uint256 amount) private {
        ProductInfo storage product = productInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];
        require(user.amount >= amount, " Invalid amount");
        _updateProduct(pid);
        _harvest(pid, msg.sender);

        if (amount > 0) {
            user.amount = user.amount - amount;
            TransferHelper.safeTransfer(USDT_ADDRESS, msg.sender, amount);
        }

        product.depositedAmount -= amount;
        user.rewardDebt = (user.amount * product.accUNOPerShare) / ACC_UNO_PRECISION;

        emit Withdraw(msg.sender, pid, amount);
    }

    /// @notice Harvest proceeds for transaction sender to `to`.
    /// @param pid The index of the product. See `productInfo`.
    /// @param to Receiver of UNO rewards.
    function _harvest(uint256 pid, address to) private {
        ProductInfo storage product = productInfo[pid];
        UserInfo storage user = userInfo[pid][to];

        // harvest current reward
        uint256 pending = user.pendingRewards + (user.amount * product.accUNOPerShare) / ACC_UNO_PRECISION - user.rewardDebt;
        user.pendingRewards = pending;

        uint256 harvested;
        if (pending > 0) {
            harvested = IRewarder(rewarder).onReward(to, pending);
            // We assume harvested amount is less than pendingRewards
            user.pendingRewards -= harvested;
        }

        emit Harvest(to, pid, pending, harvested);
    }
}
