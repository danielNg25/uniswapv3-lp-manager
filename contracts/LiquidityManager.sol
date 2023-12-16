// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../wido-contracts/contracts/core/zapper/WidoZapperUniswapV3.sol";
import "../v3-core/contracts/libraries/SqrtPriceMath.sol";
import "./SimpleNFTVault.sol";
import "./interfaces/IWETH.sol";
import "./libraries/TickConversion.sol";

error EIncompatibleAddresses();
error EWrongMSGValue();
error EVaultWithdrawed();
error ENotPositionOwner();

contract LiquidityManager is
    WidoZapperUniswapV3,
    Ownable2Step,
    ReentrancyGuard,
    Pausable
{
    using SafeERC20 for IERC20;
    using SafeCast for int256;

    ISwapRouter02 public swapRouter;
    INonfungiblePositionManager public nonfungiblePositionManager;
    IUniswapV3Pool public WETH_GMX_Pool;
    SimpleNFTVault public nonfungiblePositionVault;

    mapping(uint256 => address) public userPositionTokenIds;

    event Deposit(
        address indexed user,
        uint256 tokenId,
        uint256 amountEth,
        uint256 liquidity
    );

    event Withdraw(
        address indexed user,
        uint256 tokenId,
        uint256 amount0,
        uint256 amount1
    );

    constructor(address _swapRouter, address _positionManager, address _pool) {
        if (
            IUniswapV3Pool(_pool).factory() ==
            INonfungiblePositionManager(_positionManager).factory()
        ) {
            revert EIncompatibleAddresses();
        }

        swapRouter = ISwapRouter02(_swapRouter);
        WETH_GMX_Pool = IUniswapV3Pool(_pool);
        nonfungiblePositionManager = INonfungiblePositionManager(
            _positionManager
        );
        nonfungiblePositionVault = new SimpleNFTVault(_positionManager);
    }

    /**
     * @notice deposit ETH and zap in to wETH-GMX pool
     * @param amountEth Amount ETH to deposit to pool
     * @param minLiquidity minimum liquidity receive
     */
    function deposit(
        uint256 amountEth,
        uint256 minLiquidity
    ) external payable nonReentrant whenNotPaused {
        if (msg.value == amountEth) {
            revert EWrongMSGValue();
        }

        // Cache the pool address
        IUniswapV3Pool _WETH_GMX_Pool = WETH_GMX_Pool;

        (address wETH, ) = _tokens(_WETH_GMX_Pool);

        (, int24 currentTick, , , , , ) = _WETH_GMX_Pool.slot0();

        (int24 lowerTick, int24 upperTick) = _getTickRangeToAddLiquidity(
            currentTick
        );

        IWETH(wETH).deposit{value: amountEth}();
        // Zap in liquidity to the pool
        (uint256 tokenId, uint256 liquidity) = zapIn(
            swapRouter,
            nonfungiblePositionManager,
            ZapInOrder({
                pool: _WETH_GMX_Pool,
                fromToken: wETH,
                amount: amountEth,
                lowerTick: lowerTick,
                upperTick: upperTick,
                minToToken: minLiquidity,
                recipient: address(nonfungiblePositionVault),
                dustRecipient: msg.sender
            })
        );

        // Store the LP NFT amount to userLP[msg.sender]
        userPositionTokenIds[tokenId] = msg.sender;

        emit Deposit(msg.sender, tokenId, amountEth, liquidity);
    }

    /**
     * @notice withdraw lp and fee from wETH-GMX pool and burn LP NFT
     * @param tokenId LP NFT token id
     */
    function withdraw(uint256 tokenId) external nonReentrant whenNotPaused {
        if (userPositionTokenIds[tokenId] != msg.sender) {
            revert ENotPositionOwner();
        }
        userPositionTokenIds[tokenId] = address(0);

        // Remove liquidity from the pool
        nonfungiblePositionVault.transfer(address(this), tokenId);

        (, , , , , , , uint128 liquidity, , , , ) = nonfungiblePositionManager
            .positions(tokenId);

        (uint256 amount0, uint256 amount1) = nonfungiblePositionManager
            .decreaseLiquidity(
                INonfungiblePositionManager.DecreaseLiquidityParams({
                    tokenId: tokenId,
                    liquidity: liquidity,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp
                })
            );
        (uint256 amountFee0, uint256 amountFee1) = nonfungiblePositionManager
            .collect(
                INonfungiblePositionManager.CollectParams({
                    tokenId: tokenId,
                    recipient: msg.sender,
                    amount0Max: type(uint128).max,
                    amount1Max: type(uint128).max
                })
            );

        nonfungiblePositionManager.burn(tokenId);

        emit Withdraw(
            msg.sender,
            tokenId,
            amount0 + amountFee0,
            amount1 + amountFee1
        );
    }

    /**
     * @notice emergency withdraw all LP NFT from the vault
     * @param treasury address of treasury to receive ownership of vault
     */
    function emergencyWithdraw(address treasury) external onlyOwner {
        if (nonfungiblePositionVault.owner() != address(this)) {
            revert EVaultWithdrawed();
        }
        // Withdraw all LP NFT into the treasury
        nonfungiblePositionVault.transferOwnership(treasury);
    }

    /**
     * @notice Read deposit data
     * @param tokenId LP NFT token id
     * @return amount0 amount of token0 (wETH) in position
     * @return amount1 amount of token1 (GMX) in position
     * @return lpShare LP share of user
     * @return feeReceivingShare fee receiving share of user
     */
    function getDepositData(
        uint256 tokenId
    )
        external
        view
        returns (
            uint256 amount0,
            uint256 amount1,
            uint256 lpShare,
            uint256 feeReceivingShare
        )
    {
        (
            ,
            ,
            ,
            ,
            ,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            ,
            ,
            ,

        ) = nonfungiblePositionManager.positions(tokenId);

        // Cache the pool address
        IUniswapV3Pool _WETH_GMX_Pool = WETH_GMX_Pool;

        (
            uint160 currentSqrtPriceX96,
            int24 currentTick,
            ,
            ,
            ,
            ,

        ) = _WETH_GMX_Pool.slot0();

        (amount0, amount1, feeReceivingShare) = _getLiquidityValue(
            -int256(uint256(liquidity)).toInt128(),
            currentSqrtPriceX96,
            currentTick,
            tickLower,
            tickUpper
        );

        (address wETH, address GMX) = _tokens(_WETH_GMX_Pool);
        (uint256 poolBalance0, uint256 poolBalance1) = (
            IERC20(wETH).balanceOf(address(_WETH_GMX_Pool)),
            IERC20(GMX).balanceOf(address(_WETH_GMX_Pool))
        );

        // calculate pool TVL
        uint256 token0Price = FullMath.mulDiv(
            currentSqrtPriceX96 * 1e18,
            currentSqrtPriceX96,
            2 ** 192
        );

        uint256 poolTVL = FullMath.mulDiv(poolBalance0, token0Price, 1e18) +
            poolBalance1;

        // calculate user LP value
        uint256 lpValue = FullMath.mulDiv(amount0, token0Price, 1e18) + amount1;

        // calculate user LP share
        lpShare = FullMath.mulDiv(lpValue, 1e18, poolTVL); // 1e18 = 100%
    }

    function _getLiquidityValue(
        int128 liquidity,
        uint160 currentSqrtPriceX96,
        int24 currentTick,
        int24 tickLower,
        int24 tickUpper
    )
        internal
        view
        returns (uint256 amount0, uint256 amount1, uint256 feeReceivingShare)
    {
        if (currentTick < tickLower) {
            // current tick is below the passed range; liquidity can only become in range by crossing from left to
            // right, when we'll need _more_ token0 (it's becoming more valuable) so user must provide it
            amount0 = uint256(
                -SqrtPriceMath.getAmount0Delta(
                    TickMath.getSqrtRatioAtTick(tickLower),
                    TickMath.getSqrtRatioAtTick(tickUpper),
                    liquidity
                )
            );
        } else if (currentTick < tickUpper) {
            amount0 = uint256(
                -SqrtPriceMath.getAmount0Delta(
                    currentSqrtPriceX96,
                    TickMath.getSqrtRatioAtTick(tickUpper),
                    liquidity
                )
            );
            amount1 = uint256(
                -SqrtPriceMath.getAmount1Delta(
                    TickMath.getSqrtRatioAtTick(tickLower),
                    currentSqrtPriceX96,
                    liquidity
                )
            );

            // calculate fee receiving share
            uint128 currentLiquidity = WETH_GMX_Pool.liquidity();

            feeReceivingShare = FullMath.mulDiv(
                uint256(-int256(liquidity)),
                1e18,
                currentLiquidity
            );
        } else {
            // current tick is above the passed range; liquidity can only become in range by crossing from right to
            // left, when we'll need _more_ token1 (it's becoming more valuable) so user must provide it
            amount1 = uint256(
                -SqrtPriceMath.getAmount1Delta(
                    TickMath.getSqrtRatioAtTick(tickLower),
                    TickMath.getSqrtRatioAtTick(tickUpper),
                    liquidity
                )
            );
        }
    }

    function _getTickRangeToAddLiquidity(
        int24 currentTick
    ) internal pure returns (int24 lowerTick, int24 upperTick) {
        (lowerTick, upperTick) = TickConversion.getTickBound(currentTick);
    }

    function _tokens(
        IUniswapV3Pool pool
    ) internal view returns (address token0, address token1) {
        // Get the token0 and token1 address from the pool
        token0 = pool.token0();
        token1 = pool.token1();
    }
}
