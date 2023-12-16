import * as hre from "hardhat";
import { expect } from "chai";
import { ethers } from "hardhat";

import {
    LiquidityManager__factory,
    LiquidityManager,
    TotalSupply__factory,
    TotalSupply,
} from "../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

import { parseEther } from "ethers";

const CONFIG = {
    ROUTER: "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45",
    NFT_POSITION_MANAGER: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
    WETH_GMX_POOL: "0x80A9ae39310abf666A87C743d6ebBD0E8C42158E",
};

describe("Greater", () => {
    let owner: SignerWithAddress;
    let user: SignerWithAddress;
    let liquidityManager: LiquidityManager;
    let nonfungiblePositionManager: TotalSupply;

    beforeEach(async () => {
        owner = await ethers.getImpersonatedSigner(
            "0x9894d1564D4DBF111AC372CbB0c7df17027535fa",
        );
        user = await ethers.getImpersonatedSigner(
            "0x2487cb1A359c942312259BBc64a01CEe32E9f539",
        );

        const LiquidityManager: LiquidityManager__factory =
            await ethers.getContractFactory("LiquidityManager");

        const TotalSupply = await ethers.getContractFactory("TotalSupply");

        nonfungiblePositionManager = <TotalSupply>(
            TotalSupply.attach("0xC36442b4a4522E871399CD717aBDD847Ab11FE88")
        );
        liquidityManager = await LiquidityManager.connect(owner).deploy(
            CONFIG.ROUTER,
            CONFIG.NFT_POSITION_MANAGER,
            CONFIG.WETH_GMX_POOL,
        );

        hre.tracer.nameTags[await liquidityManager.getAddress()] =
            "LiquidityManager";
    });

    describe("Liquidity Manager Happy Case", () => {
        it("Should deploy successfully", async () => {
            expect(await liquidityManager.swapRouter()).to.equal(CONFIG.ROUTER);
            expect(
                await liquidityManager.nonfungiblePositionManager(),
            ).to.equal(CONFIG.NFT_POSITION_MANAGER);
            expect(await liquidityManager.WETH_GMX_Pool()).to.equal(
                CONFIG.WETH_GMX_POOL,
            );
        });

        it("Should deposit successfully", async () => {
            await liquidityManager
                .connect(user)
                .deposit(parseEther("10"), 0, { value: parseEther("10") });

            const tokenId = await nonfungiblePositionManager.totalSupply();

            const depositData = await liquidityManager.getDepositData(tokenId);
            console.log("wethAmount: ", depositData.amount0.toString());
            console.log("gmxAmount: ", depositData.amount1.toString());
            console.log("lpShare:", depositData.lpShare.toString());
            console.log(
                "feeReceivingShare:",
                depositData.feeReceivingShare.toString(),
            );
        });

        it("Should withdraw successfully", async () => {
            const tokenId = await nonfungiblePositionManager.totalSupply();
            await liquidityManager.connect(user).withdraw(tokenId);
        });

        it("Should emergency withdraw successfully", async () => {
            await liquidityManager
                .connect(owner)
                .emergencyWithdraw(owner.address);
        });
    });
});
