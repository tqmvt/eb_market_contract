// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

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

enum State {ACTIVE, SOLD, CANCELLED}

struct Listing {
    uint256 listingId;
    uint256 nftId;
    address seller;
    address nft;
    uint256 price;
    uint256 fee;
    State state;
    address purchaser;
    bool is1155;
    uint256 listingTime;
    uint256 saleTime;
    uint256 endingTime;
    uint256 royalty;
}

library IterableMapping{
    struct Map {
        bytes32[] keys;
        mapping(uint256 => bytes32) idToKey;
        mapping(bytes32 => Listing) values;
        mapping(bytes32 => uint) indexOf;
        mapping(bytes32 => bool) inserted;
    }

    function contains(Map storage map, bytes32 key) public view returns (bool){
        return map.inserted[key];
    }

    function containsId(Map storage map, uint256 id) public view returns (bool){
        return map.idToKey[id] != bytes32(0);
    }

    function get(Map storage map, bytes32 key) public view returns (Listing storage) {
        return map.values[key];
    }

    function getById(Map storage map, uint256 id) public view returns (Listing storage){
        return get(map, map.idToKey[id]);
    }

    function keyForId(Map storage map, uint256 id) public view returns (bytes32){
        return map.idToKey[id];
    }

    function size(Map storage map) public view returns (uint) {
        return map.keys.length;
    }

    function paged(Map storage map, uint256 _page, uint16 _pageSize) external view returns (Listing[] memory){
        if(size(map) == 0){
            return new Listing[](0);
        }
        Listing[] memory result = new Listing[](_pageSize);
        uint16 returnCounter = 0;
        for(uint i = _pageSize * _page - _pageSize; i < _pageSize * _page; i++ ){
            if(i < size(map) - 1){
                break;
            }
            result[returnCounter] = get(map, map.keys[i]);
            returnCounter++;
        }
        return result;
    }

    function set(
        Map storage map,
        bytes32 key,
        Listing memory val
    ) public {
        if (map.inserted[key]) {
            map.values[key] = val;
            map.idToKey[val.listingId] = key;
        } else {
            map.inserted[key] = true;
            map.values[key] = val;
            map.indexOf[key] = map.keys.length;
            map.keys.push(key);
            map.idToKey[val.listingId] = key;
        }
    }

    function remove(Map storage map, bytes32 key) public {
        if (!map.inserted[key]) {
            return;
        }

        delete map.idToKey[map.values[key].listingId];
        delete map.inserted[key];
        delete map.values[key];

        uint index = map.indexOf[key];
        uint lastIndex = map.keys.length - 1;
        bytes32 lastKey = map.keys[lastIndex];

        map.indexOf[lastKey] = index;
        delete map.indexOf[key];

        map.keys[index] = lastKey;
        map.keys.pop();
    }
}

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

    IERC1155 private memberships;

    uint16 public vipFee = 150;
    uint16 public memberFee = 300;
    uint16 public regFee = 500;

    IterableMapping.Map private activeListings;
    IterableMapping.Map private completeListings;
    IterableMapping.Map private cancelledListings;

    CountersUpgradeable.Counter private listingId;

    mapping(address => Royalty) public royalties;

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
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(UPGRADER_ROLE)
        override
    {}

    function totalActive() public view returns (uint256) {
        return activeListings.size();
    }

    function activeListing(uint256 _listingId) public view returns (Listing memory){
        return activeListings.getById(_listingId);
    } 

    function pagedActive(uint256 _page, uint16 _pageSize) external view returns (Listing[] memory){
        return activeListings.paged(_page, _pageSize);
    }

    function totalComplete() external view returns (uint256){
        return completeListings.size();
    }

    function pagedComplete(uint256 _page, uint16 _pageSize) external view returns (Listing[] memory){
        return completeListings.paged(_page, _pageSize);
    }

    function totalCancelled() external view returns (uint256){
        return cancelledListings.size();
    }

    function pagedCancelled(uint256 _page, uint16 _pageSize) external view returns (Listing[] memory){
        return cancelledListings.paged(_page, _pageSize);
    }

    function withdrawPayments(address payable payee) public virtual override nonReentrant{
        super.withdrawPayments(payee);
    }

    function makeListing(address _nft, uint256 _id, uint256 _price) public  {
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
            Listing storage listing = activeListings.get(listingHash);
            listing.price = _price;
            listing.fee = _price.mulDiv(fee(msg.sender), SCALE);
            listing.royalty = _price.mulDiv(royalty.percent, SCALE);
            emit Listed(listing.listingId);
            return;
        }

        Listing memory newListing;
        newListing.listingId = listingId.current();
        newListing.nftId = _id;
        newListing.seller = msg.sender;
        newListing.nft = address(_nft);
        newListing.price = _price;
        newListing.fee = _price.mulDiv(fee(msg.sender), SCALE);
        newListing.state = State.ACTIVE;
        newListing.is1155 = is1155;
        newListing.listingTime = block.timestamp;
        newListing.royalty = _price.mulDiv(royalty.percent, SCALE);
        activeListings.set(listingHash, newListing);

        listingId.increment();
        emit Listed(newListing.listingId);
    }

    function makePurchase(uint256 _id) public  payable {
        require(activeListings.containsId(_id), "invalid id");
        Listing memory listing = activeListings.getById(_id);
        
        if(listing.is1155){
            require(IERC1155(listing.nft).isApprovedForAll(listing.seller, address(this)), "seller revoked approval");
        } else {
            require(IERC721(listing.nft).isApprovedForAll(listing.seller, address(this)), "seller revoked approval");
        }
        
        require(msg.value >= listing.price, "not enough funds");
        if(listing.is1155){
            IERC1155(listing.nft).safeTransferFrom(listing.seller, msg.sender, listing.nftId, 1, "");
        }else {
            IERC721(listing.nft).safeTransferFrom(listing.seller, msg.sender, listing.nftId);
        }
        
        _asyncTransfer(listing.seller, listing.price - listing.fee);
        address ipHolder = royalties[listing.nft].ipHolder;
        if(ipHolder != address(0)){
            _asyncTransfer(ipHolder, listing.royalty);
        }
        activeListings.remove(activeListings.keyForId(_id));
        listing.purchaser = msg.sender;
        listing.saleTime = block.timestamp;
        listing.state = State.SOLD;
        completeListings.set(keccak256(abi.encodePacked(_id)), listing);
        emit Sold(_id);
    }

    function cancelListing(uint256 _id) public {
        require(activeListings.containsId(_id), "invalid id");
        Listing memory listing = activeListings.getById(_id);
        require(listing.seller == msg.sender || hasRole(STAFF_ROLE, msg.sender), "not lister");
        listing.state = State.CANCELLED;
        listing.saleTime = block.timestamp;
        activeListings.remove(activeListings.keyForId(_id));
        cancelledListings.set(keccak256(abi.encodePacked(_id)), listing);
        emit Cancelled(_id);
    }

    /**\
        uint64 public constant FOUNDER = 1;
        uint64 public constant VIP = 2;
        uint64 public constant VVIP = 3;
     */
    function fee(address user) public view returns (uint16 userFee){
        if(memberships.balanceOf(user, 3) > 0){
            userFee = 0;
        } else if(memberships.balanceOf(user, 2) > 0) {
            userFee = vipFee;
        } else if(memberships.balanceOf(user, 1) > 0){
            userFee = memberFee;
        }else {
            userFee = regFee;
        }
    }

    //=====STAFF============

    function registerRoyalty(address _nftContract, address _ipHolder, uint16 _fee) public onlyRole(STAFF_ROLE){
        royalties[_nftContract] = Royalty(_ipHolder, _fee);
    }

    function removeRoyalty(address _nftContract) public onlyRole(STAFF_ROLE){
        delete royalties[_nftContract];
    }


    //=====ADMIN============ 

    function withdraw() public payable onlyRole(DEFAULT_ADMIN_ROLE){
        payable(msg.sender).sendValue(address(this).balance);
    }

    function updateFees(uint16 _regFee, uint16 _memFee) public onlyRole(DEFAULT_ADMIN_ROLE){
        regFee = _regFee;
        memberFee = _memFee;
    }

}