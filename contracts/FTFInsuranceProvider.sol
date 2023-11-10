// SPDX-License-Identifier: MIT

pragma solidity 0.4.24;
pragma experimental ABIEncoderV2;

contract InsuranceProvider {
    constructor() public payable {
        priceFeed = AggregatorV3Interface(0x9326BFA02ADD2366b30bacB125260Af641031331);
    }
}

contract InsuranceContract is ChainlinkClient, Ownable  {
    constructor(address _client, uint _duration, uint _premium, uint _payoutValue, string _cropLocation, address _link, uint256 _oraclePaymentAmount)  payable Ownable() public { 
    }
}