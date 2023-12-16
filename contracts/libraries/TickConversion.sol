// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

library TickConversion {
    int24 internal constant UPPER_DISTANCE = 953; // 1.0001 ^ 953 ~= 1.1
    int24 internal constant LOWER_DISTANCE = -1053; // 1.0001 ^ -60 ~= 0.94

    /// @dev The minimum tick that may be passed to #getSqrtRatioAtTick computed from log base 1.0001 of 2**-128
    int24 internal constant MIN_TICK = -887272;
    /// @dev The maximum tick that may be passed to #getSqrtRatioAtTick computed from log base 1.0001 of 2**128
    int24 internal constant MAX_TICK = -MIN_TICK;

    /// @notice Get +-10% bound of a price represented by tick
    /// @param tick Tick of the price
    /// @return lowerTick Upper bound of the price
    /// @return upperTick Lower bound of the price
    function getTickBound(
        int24 tick
    ) internal pure returns (int24 lowerTick, int24 upperTick) {
        unchecked {
            upperTick = tick + UPPER_DISTANCE;
            lowerTick = tick + LOWER_DISTANCE;

            if (upperTick > MAX_TICK) {
                upperTick = MAX_TICK;
            }
            if (lowerTick < MIN_TICK) {
                lowerTick = MIN_TICK;
            }
        }
    }
}
