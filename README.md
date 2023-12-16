# wETH - GMX Uniswap V3 Position Manager

Decision explaination: _The requirements seem a bit unclear and confused for me, so I try to solve the problem based on my understand. I'll explain what I thought for each requirement and how I deal with them below._

**Since 2 days is a bit too short for me for both coding and testing, the security and gas optimization factor in these contracts are ignored**

## First requirement

> User can deposit ETH into a contract and add liquidity with a range +-10% at the current
> price to GMX/ETH Uniswap Pool V3 (Store info about the amount LP NFT of the user)

### The pool is pool of wETH and GMX and user deposit native ETH:

-   First, Wrap ETH to get wETH
-   Next, `Zap in` wETH into the pool (when we want to add liquidity to a pool but we only have token from oneside, `Zap in` is a process that do a swap to get other token with an optimal amount and then add liquidity to the pool)

In the `Zap in` step, we can do the swap on Balancer then add liquidity to Uniswap pool to avoid price impact. But I'm not so familiar with Balancer, so I decide to swap on Uniswap pool instead and I was inspired by this [Wido](https://github.com/widolabs/wido-contracts) project.

### Add liquidity with a range +-10% at the current price

To make it simple, I decided to handle this +-10% range by tick to avoid dealing with Q64.96 number (the sqrtPriceX96).
Since:

$$
Price = 1.0001^{tick}
$$

I took 2 approximate numbers: 953 and -1053 which:

$$
1.0001^{953} ~= 1.1
$$

$$
1.0001^{-1053} ~= 0.9
$$

We can get the satisfy tick range easily:

$$
upperTick = currentTick + 953
$$

$$
lowerTick = currentTick + (-1053)
$$

## Second requirement

> User can withdraw exactly LP user has a deposit
> This process is simple and straight forward

-   Decrease liquidity of user's position
-   Collect all fee at that position
-   Burn the NFT

## Third requirement

> Emergency withdrawal all LP NFT into the treasury (only the owner of the smart contract
> can run this function)

Transfer a large amount of NFTs cost a significant amount of gas, I choose an other solution to not transfer all the NFT, I transfer the owner of NFT owner: I created a simple vault to hold all the NFT, only owner of the vault can transfer NFT out. When emergency withdraw is called, we simply transfer the owner of the vault to the treasury.

## Last requirement

> User can read deposit data ( deposit value, % lp share in pool)

```solidity
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
    );
```

### Deposit value

I wonder if this `deposit value` is the eth value when user deposit or the worth value of wETH and GMX user gets if they remove that position at the current time. I decided to get the worth value of the position (the `amount0` and `amount1`).

### % LP Share

I don't really get what is `LP Share` in Uniswap V3 so I decided to return 2 value

-   `lpShare`: I calculated the TVL of the pool base on the balance of both token and the price in the pool, and the value of position's liquidity => I can get the % share of that position (This value is not really accurate since the collected fee is not count as lp in Uniswap V3)
-   `feeReceivingShare`: position's active liquidity / pool's active liquidity

Both value are multiply by 1e18
