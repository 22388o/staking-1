// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.7.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract Staker is Ownable {
    using SafeMath for uint256;

    struct UserInfo {
        uint256 deposited;
        uint256 rewardsAlreadyConsidered;
    }

    uint256 public rewardPeriodEndTimestamp;
    uint256 public rewardPerSecond; // multiplied by 1e6

    uint256 public lastRewardTimestamp;
    uint256 public accumulatedRewardPerShare; // multiplied by 1e12

    IERC20 public depositToken;
    IERC20 public rewardToken;

    mapping (address => UserInfo) users;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    

    constructor(address _depositToken, address _rewardToken) {
        depositToken = IERC20(_depositToken);
        rewardToken = IERC20(_rewardToken);
    }

    // User should have allowed transfer before.
    function addRewards(uint256 _rewardsAmount, uint256 _lengthInDays)
    external onlyOwner {
        require(block.timestamp > rewardPeriodEndTimestamp, "Staker: can't add rewards before period finished"); // TODO: might be not necessary, need to check
        rewardPeriodEndTimestamp = block.timestamp.add(_lengthInDays.mul(24*60*60));
        rewardPerSecond = _rewardsAmount.mul(1e6).div(_lengthInDays).div(24*60*60);
        require(rewardToken.transferFrom(msg.sender, address(this), _rewardsAmount), "Staker: transfer failed");
    }

    function updateRewards()
    public {
        if (block.timestamp <= lastRewardTimestamp) {
            return;
        }
        uint256 totalStaked = depositToken.balanceOf(address(this));
        if (totalStaked == 0) {
            lastRewardTimestamp = block.timestamp;
            return;
        }
        //uint256 multiplier
        uint256 endingTime;
        if (block.timestamp > rewardPeriodEndTimestamp) {
            endingTime = rewardPeriodEndTimestamp;
        } else {
            endingTime = block.timestamp;
        }
        uint256 secondsSinceLastRewardUpdate = endingTime.sub(lastRewardTimestamp);
        uint256 totalNewReward = secondsSinceLastRewardUpdate.mul(rewardPerSecond);
        accumulatedRewardPerShare = accumulatedRewardPerShare.add(totalNewReward.mul(1e12).div(totalStaked));
        lastRewardTimestamp = block.timestamp;
    }

    // User should have allowed transfer before.
    function deposit(uint256 _amount)
    public {
        UserInfo storage user = users[msg.sender];
        updateRewards();
        // Send reward for previous deposits
        if (user.deposited > 0) {
            uint256 pending = user.deposited.mul(accumulatedRewardPerShare).div(1e12).div(1e6).sub(user.rewardsAlreadyConsidered);
            require(rewardToken.transfer(msg.sender, pending), "Staker: transfer failed");
        }
        require(depositToken.transferFrom(msg.sender, address(this), _amount), "Staker: transferFrom failed");
        user.deposited = user.deposited.add(_amount);
        user.rewardsAlreadyConsidered = user.deposited.mul(accumulatedRewardPerShare).div(1e12).div(1e6);
        emit Deposit(msg.sender, _amount);
    }

    function withdraw(uint256 _amount)
    public {
        UserInfo storage user = users[msg.sender];
        require(user.deposited > _amount, "Staker: balance not enough");
        updateRewards();
        uint256 pending = user.deposited.mul(accumulatedRewardPerShare).div(1e12).div(1e6).sub(user.rewardsAlreadyConsidered);
        require(rewardToken.transfer(msg.sender, pending), "Staker: reward transfer failed");
        user.deposited = user.deposited.sub(_amount);
        user.rewardsAlreadyConsidered = user.deposited.mul(accumulatedRewardPerShare).div(1e12).div(1e6);
        require(depositToken.transfer(msg.sender, _amount), "Staker: deposit withdrawal failed");
        emit Withdraw(msg.sender, _amount);
    }
    
    // For testing
    function getTime()
    public view returns (uint256) {
        return block.timestamp;
    }
}