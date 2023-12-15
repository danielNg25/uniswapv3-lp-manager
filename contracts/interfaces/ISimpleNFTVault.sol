// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ISimpleNFTVault {
    function positionNFT() external view returns (address);

    function transfer(address to, uint256 tokenId) external;
}
