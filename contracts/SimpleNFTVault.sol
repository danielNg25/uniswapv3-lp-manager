// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./interfaces/ISimpleNFTVault.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract SimpleNFTVault is
    ISimpleNFTVault,
    ERC721Holder,
    Ownable,
    ReentrancyGuard
{
    address public positionNFT;

    constructor(address _positionNFT) {
        positionNFT = _positionNFT;
    }

    function transfer(
        address to,
        uint256 tokenId
    ) external nonReentrant onlyOwner {
        IERC721(positionNFT).safeTransferFrom(address(this), to, tokenId);
    }
}
