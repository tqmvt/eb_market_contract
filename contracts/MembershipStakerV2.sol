// SPDX-License-Identifier: UNLICENSED
//Copyright Ebisusbay.com 2021
pragma solidity 0.8.4;

import "./MembershipStaker.sol";

contract MembershipStakerV2 is MembershipStaker {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    uint256 private pendingAmount;
    uint256 private totalDistribution;
    mapping(address => uint256) private distributions;

    function harvest(address payable _address) external override nonReentrant {
        payRewards(_address);
    }

    function distribute() private {
        if (pendingAmount > 0) {
            totalDistribution += pendingAmount / stakeCount;
            pendingAmount = 0;
        }
    }

    function payRewards(address _address) private {
        distribute();
        if(totalDistribution > 0 && balances[_address] > 0) {
            uint256 reward = (totalDistribution - distributions[_address]) * balances[_address];
            payable(_address).call{value: reward}("");
            distributions[msg.sender] = totalDistribution;
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

    function unstake(uint256 amount) override external nonReentrant {
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

}
