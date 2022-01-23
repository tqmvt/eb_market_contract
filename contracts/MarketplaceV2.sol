// SPDX-License-Identifier: UNLICENSED
//Copyright Ebisusbay.com 2021
pragma solidity ^0.8.4;

import "./Marketplace.sol";

contract MarketplaceV2 is Marketplace {

    function name() public pure returns (string memory){
        return "v2";
    }
}
