// SPDX-License-Identifier: UNLICENSED
//Copyright Ebisusbay.com 2021
pragma solidity 0.8.4;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PullPaymentUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";

import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

import "./SafePct.sol";
import "./IterableMapping.sol";
import "./IMembershipStaker.sol";

contract Marketplace is 
    Initializable, 
    AccessControlUpgradeable, 
    UUPSUpgradeable, 
    PullPaymentUpgradeable,
    ReentrancyGuardUpgradeable {

    using SafeMathLite for uint256;
    using SafePct for uint256;
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using AddressUpgradeable for address payable;
    using ERC165Checker for address;
 
    using IterableMapping for IterableMapping.Map;
    using IterableMapping for IterableMapping.Listing;

    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant STAFF_ROLE = keccak256("STAFF_ROLE");
    bytes32 public constant SERVER_ROLE = keccak256("SERVER_ROLE");
    uint16 constant private SCALE = 10000;
    bytes4 public constant IID_IERC1155 = type(IERC1155).interfaceId;
    bytes4 public constant IID_IERC721 = type(IERC721).interfaceId;

    
    struct Royalty {
        address ipHolder;
        uint16 percent;
    }

    event Listed(uint256 indexed listingId);
    event Sold(uint256 indexed listingId);
    event Cancelled(uint256 indexed listingId);
    event FeesUpdate(address indexed updater, uint256 reg, uint256 fm, uint256 admin);
    event AdminWithdraw(address indexed admin, uint256 amount);
    event RoyaltyChanged(address indexed staffMember, address indexed collection, address ipHolder, uint16 fee);
    event RoyaltyRemoved(address indexed staffMember, address indexed collection);
    event StakerUpdated(address indexed admin, address newStaker);

    IERC1155 private memberships;

    uint16 public vipFee;
    uint16 public memberFee;
    uint16 public regFee;

    IterableMapping.Map private activeListings;
    IterableMapping.Map private completeListings;
    IterableMapping.Map private cancelledListings;

    CountersUpgradeable.Counter private listingId;

    mapping(address => Royalty) public royalties;
    IMembershipStaker public membershipStaker;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize(IERC1155 _memberships) initializer public {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __PullPayment_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
        memberships = _memberships;
        vipFee = 150;
        memberFee = 300;
        regFee = 500;
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(UPGRADER_ROLE)
        override
    {}

    function totalActive() external view returns (uint256) {
        return activeListings.size();
    }

    function getRoyalty(address _nftContract) external view returns (Royalty memory){
        return royalties[_nftContract];
    }

    function activeListing(uint256 _listingId) external view returns (IterableMapping.Listing memory){
        return activeListings.getById(_listingId);
    } 

    function completeListing(uint256 _listingId) external view returns (IterableMapping.Listing memory){
        return completeListings.getById(_listingId);
    }

    function cancelledListing(uint256 _listingId) external view returns (IterableMapping.Listing memory){
        return cancelledListings.getById(_listingId);
    }

    function pagedActive(uint256 _page, uint16 _pageSize) external view returns ( IterableMapping.Listing[] memory){
        return activeListings.paged(_page, _pageSize);
    }

    function totalComplete() external view returns (uint256){
        return completeListings.size();
    }

    function pagedComplete(uint256 _page, uint16 _pageSize) external view returns ( IterableMapping.Listing[] memory){
        return completeListings.paged(_page, _pageSize);
    }

    function totalCancelled() external view returns (uint256){
        return cancelledListings.size();
    }

    function pagedCancelled(uint256 _page, uint16 _pageSize) external view returns ( IterableMapping.Listing[] memory){
        return cancelledListings.paged(_page, _pageSize);
    }

    function withdrawPayments(address payable payee) public virtual override nonReentrant{
        super.withdrawPayments(payee);
    }

    function makeListing(address _nft, uint256 _id, uint256 _price) external  {
        bool is1155 = _nft.supportsInterface(IID_IERC1155);
        bool is721 =_nft.supportsInterface(IID_IERC721);
        require(is1155 || is721, "unsupported type");
        if(is721){
            require(IERC721(_nft).ownerOf(_id) == msg.sender, "not owned");
            require(IERC721(_nft).isApprovedForAll(msg.sender, address(this)), "must approve transfer");
        } else {
            require(IERC1155(_nft).balanceOf(msg.sender, _id) > 0, "not owned");
            require(IERC1155(_nft).isApprovedForAll(msg.sender, address(this)), "must approve transfer");
        }

        bytes32 listingHash = keccak256(abi.encode(_nft, msg.sender, _id));
        Royalty storage royalty = royalties[_nft];

        if(activeListings.contains(listingHash)){
            IterableMapping.Listing storage listing = activeListings.get(listingHash);
            listing.price = _price;
            listing.fee = _price.mulDiv(fee(msg.sender), SCALE);
            listing.royalty = _price.mulDiv(royalty.percent, SCALE);
            emit Listed(listing.listingId);
            return;
        }

        IterableMapping.Listing memory newListing;
        newListing.listingId = listingId.current();
        newListing.nftId = _id;
        newListing.seller = msg.sender;
        newListing.nft = address(_nft);
        newListing.price = _price;
        newListing.fee = _price.mulDiv(fee(msg.sender), SCALE);
        newListing.is1155 = is1155;
        newListing.listingTime = block.timestamp;
        newListing.royalty = _price.mulDiv(royalty.percent, SCALE);
        activeListings.set(listingHash, newListing);

        listingId.increment();
        emit Listed(newListing.listingId);
    }

    function makePurchase(uint256 _id) external  payable nonReentrant {
        require(activeListings.containsId(_id), "invalid id");
        IterableMapping.Listing memory listing = activeListings.getById(_id);
        
        if(listing.is1155){
            require(IERC1155(listing.nft).isApprovedForAll(listing.seller, address(this)), "seller revoked approval");
        } else {
            require(IERC721(listing.nft).isApprovedForAll(listing.seller, address(this)), "seller revoked approval");
        }

        activeListings.remove(activeListings.keyForId(_id));
        listing.purchaser = msg.sender;
        listing.saleTime = block.timestamp;
        completeListings.set(keccak256(abi.encodePacked(_id)), listing);
        
        require(msg.value >= listing.price, "not enough funds");
        if(listing.is1155){
            IERC1155(listing.nft).safeTransferFrom(listing.seller, msg.sender, listing.nftId, 1, "");
        }else {
            IERC721(listing.nft).safeTransferFrom(listing.seller, msg.sender, listing.nftId);
        }
        
        if (address(membershipStaker) != address(0)) {
            uint256 stakingFee = listing.fee.mulDiv(1, 2);
            (bool sent, ) = address(membershipStaker).call{value: stakingFee}("");
            require(sent, "transfer fee failed");
        }

        
        address ipHolder = royalties[listing.nft].ipHolder;
        if(ipHolder != address(0)){
            _asyncTransfer(ipHolder, listing.royalty);
            _asyncTransfer(listing.seller, listing.price - listing.fee - listing.royalty);
        } else {
            //previously registered royalty revoked (rugged or abandoned project)
            _asyncTransfer(listing.seller, listing.price - listing.fee);
        }

        emit Sold(_id);
    }

    function addToEscrow(address _address) external payable {
        _asyncTransfer(_address, msg.value);
    }

    function cancelListing(uint256 _id) public {
        require(activeListings.containsId(_id), "invalid id");
        IterableMapping.Listing memory listing = activeListings.getById(_id);
        require(listing.seller == msg.sender || hasRole(STAFF_ROLE, msg.sender) || hasRole(SERVER_ROLE, msg.sender), "not lister");
        listing.saleTime = block.timestamp;
        activeListings.remove(activeListings.keyForId(_id));
        cancelledListings.set(keccak256(abi.encodePacked(_id)), listing);
        emit Cancelled(_id);
    }

    function cancelActive(address _nft, uint256 _id, address _seller) external {
        bytes32 listingHash = keccak256(abi.encode(_nft, _seller, _id));
        if(activeListings.contains(listingHash)){
            IterableMapping.Listing storage listing = activeListings.get(listingHash);
            cancelListing(listing.listingId);
        }
    }

    /**\
        uint64 public constant FOUNDER = 1;
        uint64 public constant VIP = 2;
        uint64 public constant VVIP = 3;
     */
    function fee(address user) public view returns (uint16 userFee){
        if(memberships.balanceOf(user, 3) > 0){
            userFee = 0;
        } else if(isVIP(user)) {
            userFee = vipFee;
        } else if(isFM(user)){
            userFee = memberFee;
        }else {
            userFee = regFee;
        }
    }

    function isMember(address user) public view returns (bool){
        return isFM(user) || isVIP(user);
    }

    function isFM(address user) public view returns (bool) {
        return memberships.balanceOf(user, 1) > 0;
    }

    function isVIP(address user) public view returns (bool) {
        if(memberships.balanceOf(user, 2) > 0){
            return true;
        } else if((address(membershipStaker) != address(0) && membershipStaker.amountStaked(user) > 0)){
            return true;
        }
        return false;
    }

    //=====STAFF============

    function registerRoyalty(address _nftContract, address _ipHolder, uint16 _fee) external onlyRole(STAFF_ROLE){
        royalties[_nftContract] = Royalty(_ipHolder, _fee);
        emit RoyaltyChanged(msg.sender, _nftContract, _ipHolder, _fee);
    }

    function removeRoyalty(address _nftContract) external onlyRole(STAFF_ROLE){
        delete royalties[_nftContract];
        emit RoyaltyRemoved(msg.sender, _nftContract);
    }


    //=====ADMIN============ 

    function withdraw() external payable onlyRole(DEFAULT_ADMIN_ROLE){
        emit AdminWithdraw(msg.sender, address(this).balance);
        payable(msg.sender).sendValue(address(this).balance);
    }

    function updateFees(uint16 _regFee, uint16 _memFee, uint16 _vipFee) external onlyRole(DEFAULT_ADMIN_ROLE){
        regFee = _regFee;
        memberFee = _memFee;
        vipFee = _vipFee;
        emit FeesUpdate(msg.sender, _regFee, _memFee, _vipFee);
    }

    function setMembershipStaker(address _membershipStaker) external onlyRole(DEFAULT_ADMIN_ROLE) {
        membershipStaker = IMembershipStaker(_membershipStaker);
        emit StakerUpdated(msg.sender, _membershipStaker);
    }

    receive() external payable {}
}