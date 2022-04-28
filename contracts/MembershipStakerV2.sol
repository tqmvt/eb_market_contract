// SPDX-License-Identifier: UNLICENSED
//Copyright Ebisusbay.com 2021
pragma solidity 0.8.4;

import "./MembershipStaker.sol";

contract MembershipStakerV2 is MembershipStaker {
    event Harvest (address indexed, uint256 amount);

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    uint256 private pendingAmount;
    uint256 private totalDistribution;
    mapping(address => uint256) private distributions;

    function harvest(address payable _address) external override {
        payRewards(_address);
    }

    function distribute() private {
        if (pendingAmount > 0 && stakeCount > 0) {
            totalDistribution += pendingAmount / stakeCount;
            pendingAmount = 0;
        }
    }

    function getReward(address _address) public view returns(uint256) {
        if (pendingAmount > 0 && stakeCount > 0 && totalDistribution > 0 && balances[_address] > 0) {
            uint256 reward = (totalDistribution + pendingAmount / stakeCount - distributions[_address]) * balances[_address];
            return reward;
        } else {
            return 0;
        }
    }

    function payRewards(address _address) private nonReentrant {
        distribute();
        if(totalDistribution > 0 && balances[_address] > 0) {
            uint256 reward = (totalDistribution - distributions[_address]) * balances[_address];
            if (reward > 0) {
                (bool success, ) = payable(_address).call{value: reward}("");
                require(success, "failed to pay reward");
                distributions[_address] = totalDistribution;
                emit Harvest(_address, reward);
            }
        }
    }

    function stake(uint256 amount) override external {
        require(amount > 0, "invalid amount");
        require(getMemberShipAddress().balanceOf(msg.sender, getVIPID()) >= amount, "invalid balance");
        payRewards(msg.sender);

        balances[msg.sender] = balances[msg.sender] + amount;
        stakeCount += amount;
        stakers.add(msg.sender);
        getMemberShipAddress().safeTransferFrom(msg.sender, address(this), getVIPID(), amount, "");

        emit MembershipStaked(msg.sender, balances[msg.sender]);
    }

    function unstake(uint256 amount) override external {
        require(balances[msg.sender] >= amount, "invalid amount");
        payRewards(msg.sender);

        getMemberShipAddress().safeTransferFrom(address(this), msg.sender, getVIPID(), amount, "");
        balances[msg.sender] = balances[msg.sender] - amount;
        stakeCount -= amount;
        if(balances[msg.sender] == 0){
            stakers.remove(msg.sender);
        }

        emit MembershipUnstaked(msg.sender, balances[msg.sender]);
    }

    receive() external payable virtual override{
        pendingAmount += msg.value;
    }

    function endInitPeriod() external override onlyOwner {
        isInitPeriod = false;
        pendingAmount = address(this).balance;
        distribute();
    }

    function poolBalance() public view override returns (uint256){
       return pendingAmount;
    }

    function periodEnd() public override view returns (uint256){
        return block.timestamp;
    }

    function name() public pure returns (string memory){
        return "v2";
    }
    function updatePool() public virtual override {
    }
}
