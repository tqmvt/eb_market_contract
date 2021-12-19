// SPDX-License-Identifier: Unlicense 
pragma solidity ^0.8.4;

import "./IMembershipStaker.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155ReceiverUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";



contract MembershipStaker is Initializable, 
IMembershipStaker,
 OwnableUpgradeable, 
 ReentrancyGuardUpgradeable, 
 ERC1155ReceiverUpgradeable,
 UUPSUpgradeable{

     using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

     uint64 private constant VIP_ID = 2;
     IERC1155 private membershipContract;

    uint256 private stakeCount;
    EnumerableSetUpgradeable.AddressSet private stakers;    
    mapping(address => uint) private balances;

     function initialize(IERC1155 _memberships) initializer public {
         __Ownable_init();
         __ReentrancyGuard_init();
         __ERC1155Receiver_init();
         __UUPSUpgradeable_init();
         membershipContract = _memberships;
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

    function currentStaked() override external view returns (address[] memory, uint256[] memory){
         address[] memory _stakers = stakers.values();
         uint[] memory _amounts = new uint[](stakers.length());
         for (uint i = 0; i < _stakers.length; i++){
             _amounts[i] = balances[_stakers[i]];
         }
         return (_stakers, _amounts);
    }    
}