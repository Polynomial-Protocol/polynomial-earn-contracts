// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import { ISynthetix } from "../interfaces/lyra/ISynthetix.sol";
import { MockSynth } from "./MockSynth.sol";

import { FixedPointMathLib } from "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";

contract MockSynthetix is ISynthetix {
    using FixedPointMathLib for uint256;

    mapping(bytes32 => address) synths;
    mapping(bytes32 => uint256) rates;

    address owner;
    
    constructor(
        address[] memory _synths,
        bytes32[] memory _synthKeys
    ) {
        require(_synthKeys.length == _synths.length);

        for (uint256 i = 0; i < _synthKeys.length; i++) {
            synths[_synthKeys[i]] = _synths[i];
        }

        owner = msg.sender;
    }

    function exchange(
        bytes32 sourceCurrencyKey,
        uint sourceAmount,
        bytes32 destinationCurrencyKey
    ) external override returns (uint amountReceived) {
        amountReceived = exchangeOnBehalf(msg.sender, sourceCurrencyKey, sourceAmount, destinationCurrencyKey);
    }

    function exchangeOnBehalf(
        address exchangeForAddress,
        bytes32 sourceCurrencyKey,
        uint sourceAmount,
        bytes32 destinationCurrencyKey
    ) public override returns (uint amountReceived) {
        require(exchangeForAddress == msg.sender);

        MockSynth sourceSynth = MockSynth(synths[sourceCurrencyKey]);
        MockSynth destinationSynth = MockSynth(synths[sourceCurrencyKey]);

        sourceSynth.burn(msg.sender, sourceAmount);

        if (sourceCurrencyKey == "sUSD") {
            amountReceived = sourceAmount.fdiv(rates[destinationCurrencyKey], 1e18);
        } else if (destinationCurrencyKey == "sUSD") {
            amountReceived = sourceAmount.fmul(rates[destinationCurrencyKey], 1e18);
        }

        destinationSynth.mint(msg.sender, amountReceived);
    }

    function setRate(bytes32 synthKey, uint256 rate) external {
        require(msg.sender == owner);

        if (synthKey != "sUSD") {
            rates[synthKey] = rate;
        }
    }

}