// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "./SafePct.sol";

struct Royalty {
    address ipHolder;
    uint16 percent;
}
abstract contract Market {
    mapping(address => uint) public royalties;
    function getRoyalty(address _address) public virtual view returns(Royalty memory);

    //Returns fee as a percent in 10k scale (ie 300 = 3%)
    function fee(address user) public virtual view returns (uint16 userFee);
    function addToEscrow(address _address) external virtual payable;
}

enum Status {
    Created,
    Rejected,
    Cancelled,
    Accepted
}
struct Offer {
    address nft;
    address seller;
    address buyer;
    address coinAddress;
    Status status;
    uint256 id;
    uint256 amount;
    uint256 date;
}
contract OfferContract is ReentrancyGuardUpgradeable, AccessControlUpgradeable, UUPSUpgradeable {
    event OfferMade(address nft, uint256 id, address buyer, uint256 amount, address coinAddress, uint256 time); 
    event OfferCancelled(address nft, uint256 id, address buyer, uint256 time); 
    event OfferAccepted(address nft, uint256 id, address buyer, address seller, uint256 amount, address coinAddress, uint256 time); 
    event OfferRejected(address nft, uint256 id, address buyer, address seller, uint256 amount, address coinAddress, uint256 time); 

    using ERC165Checker for address;
    using SafePct for uint256;
    using SafeMathLite for uint256;
    
    uint128 constant internal SCALE = 10000;
    bytes4 public constant IID_IERC1155 = type(IERC1155).interfaceId;
    bytes4 public constant IID_IERC721 = type(IERC721).interfaceId;
    
    mapping(bytes32 => Offer[]) offers;
    bytes32[] offerHashes;

    Market marketContract;
    address payable stakerAddress;

    bytes32 public constant UPGRADER_ROLE = keccak256('UPGRADER_ROLE');
    bytes32 public constant STAFF_ROLE = keccak256('STAFF_ROLE');

    modifier onlyNFT(address _nft) {
        require(is1155(_nft) || is721(_nft), "unsupported type");
        _;
    }

    function initialize(address payable _market, address payable _stakerAddress) public initializer {
         marketContract = Market(_market);
         stakerAddress = _stakerAddress;
         __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
    }

    function _authorizeUpgrade(address newImplementation) internal onlyRole(UPGRADER_ROLE) override { }

    function generateHash(address _nft, uint256 _nftId) public pure returns(bytes32) {
        return keccak256(abi.encodePacked(_nft, _nftId));
    }

    function getOffers(address _nft, uint256 _id) public view returns(Offer[] memory) {
        bytes32 hash = generateHash(_nft, _id);

        return offers[hash];
    }

    function getOffer(bytes32 _hash, uint256 _offerIndex) public view returns(bool, Offer memory offer) {
        bool isExist;

        if (offers[_hash].length <= 0) {
            return (false, offer);
        }
        if (offers[_hash][_offerIndex].nft != address(0) ) {
            isExist = true;
        }
        return (isExist, offers[_hash][_offerIndex]);
    }

    function is721(address _nft) public view returns(bool){
        return _nft.supportsInterface(IID_IERC721);
    }
   
    function is1155(address _nft) public view returns(bool){
        return _nft.supportsInterface(IID_IERC1155);
    }

    // function makeOfferWithToken(address _nft, uint256 _id, uint256 _amount, address _coinAddress) external onlyNFT(_nft) {
    //     uint256 balance = IERC20(_coinAddress).balanceOf(msg.sender);
    //     require(_amount <= balance, "not enough funds");
    //     (bool success) = IERC20(_coinAddress).transferFrom(msg.sender, address(this), _amount);
    //     require(success == true, "transfer token failed");
        
    //     bytes32 hash = generateHash(_nft, _id);
    //     Offer memory _offer;
    //     _offer.nft = _nft;
    //     _offer.id = _id;
    //     _offer.buyer = msg.sender;
    //     _offer.amount = _amount;
    //     _offer.coinAddress = _coinAddress;
    //     _offer.date = block.timestamp;
    //     _offer.status = Status.Created;

    //     offers[hash].push(_offer);

    //     emit  OfferMade(_nft, _id, msg.sender, _amount, _coinAddress, block.timestamp); 
    // }

    function makeOffer(address _nft, uint256 _id) external payable onlyNFT(_nft) {
        bytes32 hash = generateHash(_nft, _id);

        Offer memory _offer;
        _offer.nft = _nft;
        _offer.id = _id;
        _offer.buyer = msg.sender;
        _offer.amount = msg.value;
        _offer.date = block.timestamp;
        _offer.status = Status.Created;

        offers[hash].push(_offer);

        emit  OfferMade(_nft, _id, msg.sender, msg.value, address(0), block.timestamp);
    }

    function cancelOffer(bytes32 _hash, uint256 _offerIndex) external nonReentrant{
        (bool isExist, Offer memory _offer) = getOffer(_hash, _offerIndex);
        require(isExist, "offer not exist");
        require(_offer.status == Status.Created, "offer is not opened");

        if (!hasRole(STAFF_ROLE, msg.sender)) {
            require(_offer.buyer == msg.sender, "incorrect buyer");
        }

        offers[_hash][_offerIndex].status = Status.Cancelled;
        offers[_hash][_offerIndex].date = block.timestamp;

        if (_offer.coinAddress != address(0)) {
            revert("not support crc20");
            // IERC20(_offer.coinAddress).transfer(_offer.buyer, _offer.amount);
        } else {
           (bool sent, ) = payable(_offer.buyer).call{value:_offer.amount}("");
           require(sent, "transfer failed");
        }

        emit  OfferCancelled(_offer.nft, _offer.id, _offer.buyer, block.timestamp); 
    }

    function acceptOffer(bytes32 _hash, uint256 _offerIndex) external nonReentrant {
        (bool isExist, Offer memory _offer) = getOffer(_hash, _offerIndex);
        require(isExist, "offer not exist");

        require(_offer.status == Status.Created, "offer is not opened");
        if (is721(_offer.nft)) {
            require(IERC721(_offer.nft).ownerOf(_offer.id) == msg.sender, "not nft owner");
        } else {
            require(IERC1155(_offer.nft).balanceOf(msg.sender, _offer.id) > 0 , "not enough balance for token");
        }
        
         offers[_hash][_offerIndex].status = Status.Accepted;
         offers[_hash][_offerIndex].seller = msg.sender;
         offers[_hash][_offerIndex].date = block.timestamp;

        uint256 fee = marketContract.fee(msg.sender);
        Royalty memory royalty = marketContract.getRoyalty(_offer.nft);

        uint256 amountFee = _offer.amount.mulDiv(fee, SCALE); 
        uint256 royaltyAmount = _offer.amount.mulDiv(royalty.percent, SCALE); 
        uint256 amount = _offer.amount - amountFee - royaltyAmount;

        if (_offer.coinAddress != address(0)) {
            revert("not support crc20");
            // bool sent = IERC20(_offer.coinAddress).transfer(address(marketContract), amountFee);
            // require(sent, "transfer fee failed");
            
            // sent = IERC20(_offer.coinAddress).transfer(royalty.ipHolder, royaltyAmount);
            // require(sent, "transfer royalty failed");

            // sent = IERC20(_offer.coinAddress).transfer(msg.sender, amount);
            // require(sent, "transfer failed to the seller");
        } else {
            marketContract.addToEscrow{value: royaltyAmount}(royalty.ipHolder);
            
            uint256 stakerFee = amountFee.mulDiv(1, 2);
           (bool sent, ) = (address(marketContract)).call{value: amountFee - stakerFee}("");
            require(sent, "transfer fee failed");

            (sent, ) = (stakerAddress).call{value: stakerFee}("");
            require(sent, "transfer staker fee failed");
 
            (sent, ) = payable(msg.sender).call{value: amount}("");
            require(sent, "transfer failed to the seller");
        }

         //transfer nft
        if (is721(_offer.nft)) {
            IERC721(_offer.nft).safeTransferFrom(msg.sender, _offer.buyer, _offer.id);
        } else {
            IERC1155(_offer.nft).safeTransferFrom(msg.sender, _offer.buyer, _offer.id, 1, "");
        }

        // reject other offers for this nft
        // rejectAllOffers(_hash);

        emit OfferAccepted(_offer.nft, _offer.id, _offer.buyer, msg.sender, _offer.amount, _offer.coinAddress, block.timestamp); 
    }
        
    function rejectOffer(bytes32 _hash, uint256 _offerIndex) public nonReentrant {
        (bool isExist, Offer memory _offer) = getOffer(_hash, _offerIndex);
        require(isExist, "offer not exist");

        if (is721(_offer.nft)) {
            require(IERC721(_offer.nft).ownerOf(_offer.id) == msg.sender, "not nft owner");
        } else {
            revert("shouldn't reject 1155");
        }

        require(_offer.status == Status.Created, "offer is not opened");
        
        offerRejection(offers[_hash][_offerIndex]);
        emit OfferRejected(_offer.nft, _offer.id, _offer.buyer, msg.sender, _offer.amount, _offer.coinAddress, block.timestamp); 
    }

    function offerRejection(Offer storage _offer) private {
        _offer.status = Status.Rejected;
        _offer.seller = msg.sender;
        _offer.date = block.timestamp;
        
        bool sent;
        if (_offer.coinAddress != address(0)) {
            revert("not support crc20");
            // sent = IERC20(_offer.coinAddress).transfer(_offer.buyer, _offer.amount);
        } else {
           (sent, ) = payable(_offer.buyer).call{value:_offer.amount}("");
        }

        require(sent, "transfer failed");
    }

    function rejectAllOffers(bytes32 _hash) private {
       Offer[] storage _offers = offers[_hash];
       uint256 offerLen = _offers.length;

       for(uint256 i = 0; i < offerLen; i ++) {
           if (_offers[i].status == Status.Created) {
            offerRejection(_offers[i]);
           }
       }
    }
}