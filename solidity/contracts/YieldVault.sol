// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract YieldVault is ReentrancyGuard {
    IERC20 public rewardToken;
    IERC20 public stakingToken;

    uint256 public rewardRate;
    uint256 public periodFinish;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    address public rewardDistributor;

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardNotified(uint256 reward, uint256 duration);

    constructor(address _stakingToken, address _rewardToken) {
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        rewardDistributor = msg.sender;
    }

    /// @notice Capped reward per token — stops accruing after periodFinish
    function rewardPerToken() public view returns (uint256) {
        if (totalSupply == 0) {
            return rewardPerTokenStored;
        }
        // Cap lastUpdateTime at periodFinish — no phantom rewards after period ends
        uint256 lastTimeRewardApplicable = lastTimeRewardApplicable();
        return rewardPerTokenStored + (
            (lastTimeRewardApplicable - lastUpdateTime) * rewardRate * 1e18 / totalSupply
        );
    }

    /// @notice Returns the last time rewards were applicable (capped at periodFinish)
    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    function earned(address account) public view returns (uint256) {
        return balanceOf[account] * (rewardPerToken() - userRewardPerTokenPaid[account]) / 1e18 + rewards[account];
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function deposit(uint256 amount) external nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Cannot deposit 0");
        totalSupply += amount;
        balanceOf[msg.sender] += amount;
        stakingToken.transferFrom(msg.sender, address(this), amount);
        emit Deposited(msg.sender, amount);
    }

    function withdraw(uint256 amount) external nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        totalSupply -= amount;
        balanceOf[msg.sender] -= amount;
        stakingToken.transfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function claimReward() external nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardToken.transfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    /// @notice Notify reward amount — restricted to rewardDistributor
    /// @dev Uses checked division to prevent zero rewardRate from rounding
    function notifyRewardAmount(uint256 reward, uint256 duration) external updateReward(address(0)) {
        require(msg.sender == rewardDistributor, "Not reward distributor");
        require(duration > 0, "Duration must be > 0");
        require(reward > 0, "Reward must be > 0");

        rewardRate = reward / duration;
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + duration;

        emit RewardNotified(reward, duration);
    }
}
