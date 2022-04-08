// SPDX-License-Identifier: UNLICENSED
//Copyright Ebisusbay.com 2021
pragma solidity 0.8.4;

import "./MembershipStaker.sol";
import "./PullPaymentUpgradeable.sol";

contract MembershipStakerV2 is MembershipStaker, PullPaymentUpgradeable {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    uint256 public lastChecked;
    uint256 public pendingBalance;
    uint256 public availableBalance;
    EnumerableSetUpgradeable.AddressSet private availableStakers;
    uint256 private pendingStakeCount;
    mapping(address => uint) private availableBalances;

    function calculateRewards() private {
        if (pendingStakeCount < 0) return;

        uint256 len = availableStakers.length();
        uint256 amount;
        uint256 sum;
        for (uint i = 0; i < len; i++){
            amount = availableBalances[availableStakers.at(i)];
            sum += amount;
        }

        for (uint i = 0; i < len; i++){
             amount = availableBalance * availableBalances[availableStakers.at(i)] / sum;
             _asyncTransfer(availableStakers.at(i), amount);
        }
    }

    function concatPendingValues() private {
        uint256 len = stakers.length();
        for (uint i = 0; i < len; i++){
            availableStakers.add(stakers.at(i));
            availableBalances[stakers.at(i)] = balances[stakers.at(i)];
        }

        pendingStakeCount =stakeCount;
    }
    //Pool
    function updatePool() public override {
        if(isInitPeriod) return;

        if (lastChecked + epochLength <= block.timestamp) {
            calculateRewards();
            availableBalance = pendingBalance;
            
            pendingBalance = 0;
            
            concatPendingValues();
            lastChecked = block.timestamp;
        } 
    }

    function harvest(address payable _address) external override nonReentrant {
        super.withdrawPayments(_address);
        updatePool();
    }

    function poolBalance() public view override returns (uint256){
       return pendingBalance;
    }

    function endInitPeriod() external override onlyOwner {
        isInitPeriod = false;
        __PullPayment_init();
        lastChecked = block.timestamp;
        concatPendingValues();
        availableBalance = address(this).balance;
    }

    function periodEnd() public override view returns (uint256){
        return lastChecked + epochLength;
    }

    receive() external payable virtual override{
        updatePool();
        pendingBalance += msg.value;
    }

    function name() public pure returns (string memory){
        return "v2";
    }

}
