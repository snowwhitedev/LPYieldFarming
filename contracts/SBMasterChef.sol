// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IRewarder.sol";
import "./libraries/TransferHelper.sol";

contract SBMasterChef is Ownable, ReentrancyGuard {
    /// `amount` LP token amount the user has provided.
    /// `rewardDebt` The amount of SB entitled to the user.
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 pendingRewards;
    }

    /// `allocPoint` The amount of allocation points assigned to the pool.
    /// Also known as the amount of SB to distribute per block.
    struct PoolInfo {
        uint128 accSBPerShare;
        uint128 allocPoint;
        uint256 lastRewardBlock;
        uint256 depositedAmount;
        address lpToken;
    }

    PoolInfo[] public poolInfo;
    IRewarder public rewarder;

    /// @notice Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo; // poolId => user_address => userInfo
    mapping(address => bool) private poolExistence; // lp address => bool

    /// @dev Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;
    uint256 private constant ACC_SB_PRECISION = 1e12;

    uint256 public sbPerBlock;
    uint256 public immutable rewardStartTimestamp;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
    event Withdraw(address indexed to, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
    event Harvest(address indexed user, uint256 indexed pid, uint256 pending, uint256 harvested);
    event LogPoolAddition(uint256 indexed pid, uint256 allocPoint, address indexed lpToken);
    event LogSetPool(uint256 indexed pid, uint256 allocPoint);
    event LogUpdatePool(uint256 indexed pid, uint256 lastRewardBlock, uint256 lpSupply, uint256 accSBPerShare);
    event LogInit();
    event LogSetRewarder(address indexed _user, address indexed _rewarder);
    event LogSetSBPerBlock(address indexed user, uint256 amount);

    constructor(uint256 _sbPerBlock, uint256 _rewardTimestamp) {
        require(_rewardTimestamp >= block.timestamp, "SBMasterChef: Invalid reward start timestamp");
        sbPerBlock = _sbPerBlock;
        rewardStartTimestamp = _rewardTimestamp;
    }

    function poolLength() external view returns (uint256 pools) {
        pools = poolInfo.length;
    }

    function setRewarder(IRewarder _rewarder) external onlyOwner {
        require(address(_rewarder) != address(rewarder), "It is old rewader");
        require(address(_rewarder) != address(0), "SBMasterChef: ZERO address");
        rewarder = _rewarder;

        emit LogSetRewarder(msg.sender, address(_rewarder));
    }

    function setSBPerBlock(uint256 _sbPerBlock) external onlyOwner {
        require(_sbPerBlock != sbPerBlock, "It is old value");
        massUpdatePools();

        sbPerBlock = _sbPerBlock;
        emit LogSetSBPerBlock(msg.sender, _sbPerBlock);
    }

    /// @notice Add a new LP to the pool. Can only be called by the owner.
    /// DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    /// @param allocPoint AP of the new pool. 100 - 1 point
    /// @param _lpToken Address of the LP ERC-20 token.
    function add(
        uint256 allocPoint,
        address _lpToken,
        bool _withUpdate
    ) external onlyOwner nonReentrant {
        require(!poolExistence[_lpToken], "SBMasterChef: Pool already exists");
        require(_lpToken != address(0), "SBMasterChef: ZERO address");

        if (_withUpdate) {
            massUpdatePools();
        }

        totalAllocPoint = totalAllocPoint + allocPoint;
        poolExistence[_lpToken] = true;

        poolInfo.push(
            PoolInfo({
                accSBPerShare: 0,
                allocPoint: uint128(allocPoint),
                lastRewardBlock: block.number,
                depositedAmount: 0,
                lpToken: _lpToken
            })
        );
        emit LogPoolAddition(poolInfo.length - 1, allocPoint, _lpToken);
    }

    /// @notice Update the given pool's SB allocation point and `IRewarder` contract.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _allocPoint New AP of the pool.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) external onlyOwner {
        require(_pid < poolInfo.length, "SBMasterChef: Pool does not exist");
        require(poolInfo[_pid].allocPoint != _allocPoint, "It is old alloc point");
        if (_withUpdate) {
            massUpdatePools();
        }

        totalAllocPoint = totalAllocPoint - poolInfo[_pid].allocPoint + _allocPoint;
        poolInfo[_pid].allocPoint = uint128(_allocPoint);
        emit LogSetPool(_pid, _allocPoint);
    }

    /// @notice View function to see pending SB on frontend.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _user Address of user.
    /// @return pending SB reward for a given user.
    function pendingRewards(uint256 _pid, address _user) external view returns (uint256 pending) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        uint256 accSBPerShare = pool.accSBPerShare;
        uint256 lpSupply = pool.depositedAmount;

        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 blocks = block.number - pool.lastRewardBlock;
            uint256 sbReward = (blocks * sbPerBlock * pool.allocPoint) / totalAllocPoint;
            accSBPerShare = accSBPerShare + ((sbReward * ACC_SB_PRECISION) / lpSupply);
        }
        pending = user.pendingRewards + (user.amount * accSBPerShare) / ACC_SB_PRECISION - uint256(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            _updatePool(pid);
        }
    }

    /// @notice Update reward variables for pool.
    /// @param pid Pool ID to be updated.
    function updatePool(uint256 pid) external nonReentrant {
        _updatePool(pid);
    }

    /// @notice Update reward variables of the given pool.
    /// @param pid The index of the pool. See `poolInfo`.
    function _updatePool(uint256 pid) private {
        PoolInfo storage pool = poolInfo[pid];
        if (block.number > pool.lastRewardBlock) {
            uint256 lpSupply = pool.depositedAmount;
            if (lpSupply > 0) {
                uint256 blocks = block.number - pool.lastRewardBlock;
                uint256 sbReward = (blocks * sbPerBlock * pool.allocPoint) / totalAllocPoint;
                pool.accSBPerShare = pool.accSBPerShare + uint128((sbReward * ACC_SB_PRECISION) / lpSupply);
            }
            pool.lastRewardBlock = block.number;
            emit LogUpdatePool(pid, pool.lastRewardBlock, lpSupply, pool.accSBPerShare);
        }
    }

    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to deposit. If amount = 0, it means user wants to harvest
    /// @param to The receiver of `amount` deposit benefit.
    function deposit(
        uint256 pid,
        uint256 amount,
        address to
    ) external nonReentrant {
        require(pid < poolInfo.length, "SBMasterChef: Pool does not exist");
        require(block.timestamp > rewardStartTimestamp, "SBMasterChef: Deposit is not started yet");
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][to];
        _updatePool(pid);

        // harvest current reward
        if (user.amount > 0) {
            harvest(pid, to);
        }

        if (amount > 0) {
            TransferHelper.safeTransferFrom(pool.lpToken, msg.sender, address(this), amount);
            user.amount = user.amount + amount;
        }

        pool.depositedAmount += amount;
        user.rewardDebt = (user.amount * pool.accSBPerShare) / ACC_SB_PRECISION;
        emit Deposit(msg.sender, pid, amount, to);
    }

    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to withdraw.
    function withdraw(uint256 pid, uint256 amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];
        require(user.amount >= amount, "SBMasterChef: Invalid amount");
        _updatePool(pid);
        harvest(pid, msg.sender);

        if (amount > 0) {
            user.amount = user.amount - amount;
            TransferHelper.safeTransfer(pool.lpToken, msg.sender, amount);
        }

        pool.depositedAmount -= amount;
        user.rewardDebt = (user.amount * pool.accSBPerShare) / ACC_SB_PRECISION;

        emit Withdraw(msg.sender, pid, amount);
    }

    /// @notice Harvest proceeds for transaction sender to `to`.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param to Receiver of SB rewards.
    function harvest(uint256 pid, address to) private {
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][to];

        // harvest current reward
        uint256 pending = user.pendingRewards + (user.amount * pool.accSBPerShare) / ACC_SB_PRECISION - user.rewardDebt;
        user.pendingRewards = pending;

        uint256 harvested;
        if (pending > 0) {
            harvested = IRewarder(rewarder).onSBReward(to, pending);
            // We assume harvested amount is less than pendingRewards
            user.pendingRewards -= harvested;
        }

        emit Harvest(to, pid, pending, harvested);
    }

    /// @notice Withdraw without caring about rewards. EMERGENCY ONLY.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param to Receiver of the LP tokens.
    function emergencyWithdraw(uint256 pid, address to) external nonReentrant {
        UserInfo storage user = userInfo[pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;

        // Note: transfer can fail or succeed if `amount` is zero.
        TransferHelper.safeTransfer(poolInfo[pid].lpToken, to, amount);

        poolInfo[pid].depositedAmount -= amount;
        emit EmergencyWithdraw(msg.sender, pid, amount, to);
    }
}
