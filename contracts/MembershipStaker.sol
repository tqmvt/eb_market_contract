// SPDX-License-Identifier: UNLICENSED
//Copyright Ebisusbay.com 2021
pragma solidity ^0.8.4;

import "./IMembershipStaker.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155ReceiverUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

import "./RewardsPool.sol";


contract MembershipStaker is Initializable, 
IMembershipStaker,
 OwnableUpgradeable, 
 ReentrancyGuardUpgradeable, 
 ERC1155ReceiverUpgradeable,
 UUPSUpgradeable{

     using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
     using CountersUpgradeable for CountersUpgradeable.Counter;

     uint64 private constant VIP_ID = 2;
     IERC1155 private membershipContract;

    uint256 private stakeCount;
    EnumerableSetUpgradeable.AddressSet private stakers;    
    mapping(address => uint) private balances;
    
    CountersUpgradeable.Counter public rewardsId;
    uint256 private epochLength;
    RewardsPool[] private pools;
    RewardsPool public curPool;
    RewardsPool private completedPool;

    struct RewardPool {
        uint256 id;
        uint256 endTime;
        uint256 totalStaked;
        uint256 totalReleased;
    }

     function initialize(IERC1155 _memberships) initializer public {
         __Ownable_init();
         __ReentrancyGuard_init();
         __ERC1155Receiver_init();
         __UUPSUpgradeable_init();
         membershipContract = _memberships;
         (address[] memory accounts, uint256[] memory amounts) = currentStaked();
         curPool = new RewardsPool(block.timestamp + 7 days, accounts, amounts);
         pools.push(curPool);

         epochLength = 30 days;
     }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyOwner
        override
    {}

    function stake(uint256 amount) override external {
        balances[msg.sender] = balances[msg.sender] + amount;
        stakeCount += amount;
        stakers.add(msg.sender);
        membershipContract.safeTransferFrom(msg.sender, address(this), VIP_ID, amount, "");
        updatePool();
        emit MembershipStaked(msg.sender, balances[msg.sender]);
    }

    function unstake(uint256 amount) override external nonReentrant {
        require(balances[msg.sender] >= amount, "invalid amount");
        membershipContract.safeTransferFrom(address(this), msg.sender, VIP_ID, amount, "");
        balances[msg.sender] = balances[msg.sender] - amount;
        stakeCount -= amount;
        if(balances[msg.sender] == 0){
            stakers.remove(msg.sender);
        }
        updatePool();
        emit MembershipUnstaked(msg.sender, balances[msg.sender]);
    }

    function amountStaked(address staker) override external view returns (uint256){
        return balances[staker];
    }

    function totalStaked() override external view returns (uint256){
        return stakeCount;
    }

    function onERC1155Received(
        address operator,
        address,
        uint256,
        uint256,
        bytes calldata
    ) public virtual override returns (bytes4) {
        require(operator == address(this), "invalid operator");
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public virtual override returns (bytes4) {
        revert("batches not accepted");
    }

    function currentStaked() override public view returns (address[] memory, uint256[] memory){
         address[] memory _stakers = stakers.values();
         uint[] memory _amounts = new uint[](stakers.length());
         for (uint i = 0; i < _stakers.length; i++){
             _amounts[i] = balances[_stakers[i]];
         }
         return (_stakers, _amounts);
    }

    //Pool
    function updatePool() private{
        if(curPool.isClosed()){
            (address[] memory accounts, uint256[] memory amounts) = currentStaked();
            RewardsPool newPool = new RewardsPool(block.timestamp + epochLength, accounts, amounts);
            pools.push(newPool);
            rewardsId.increment();
            if(address(completedPool) != address(0)){
                completedPool.forwardUnclaimed(newPool);
            }
            if(address(this).balance > 0){
                newPool.addReward{value : address(this).balance}();
            }
            completedPool = curPool;
            curPool = newPool;
        }
    }

    receive() external payable virtual{
        updatePool();
        curPool.addReward{value: msg.value}();
    }

    function currentPoolId() public view returns(uint256){
        return rewardsId.current();
    }

    function periodEnd() public view returns (uint256){
        return curPool.endTime();
    }

    function poolBalance() public view returns (uint256){
        return address(curPool).balance;
    }

    //OWNER
    function setEpochLength(uint _length) public onlyOwner {
        epochLength = _length;
    }
}