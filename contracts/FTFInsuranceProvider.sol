// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ChainlinkClient} from "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {SafeMathChainlink} from "@chainlink/contracts/src/v0.7/vendor/SafeMathChainlink.sol";
import {Ownable} from "@chainlink/contracts/src/v0.6/vendor/Ownable.sol";

contract FTFInsuranceProvider {

    using SafeMathChainlink for uint;
    address public insurer = msg.sender;
    AggregatorV3Interface internal priceFeed;

    uint public constant DAY_IN_SECONDS = 60;

    uint256 constant private ORACLE_PAYMENT = 0.1 * 10**18;
    address public constant LINK_KOVAN = 0xa36085F69e2889c224210F603D836748e7dC0088 ;

    mapping (address => InsuranceContract) contracts;
    modifier onlyOwner() {
		require(insurer == msg.sender,'Only Insurance provider can do this');
        _;
    }
    event contractCreated(address _insuranceContract, uint _premium, uint _totalCover);

    function newContract(address _client, uint _duration, uint _premium, uint _payoutValue, string _cropLocation) public payable onlyOwner() returns(address) {
        InsuranceContract i = (new InsuranceContract).value((_payoutValue * 1 ether).div(uint(getLatestPrice())))(_client, _duration, _premium, _payoutValue, _cropLocation, LINK_KOVAN,ORACLE_PAYMENT);

        contracts[address(i)] = i;
        emit contractCreated(address(i), msg.value, _payoutValue);

        LinkTokenInterface link = LinkTokenInterface(i.getChainlinkToken());
        link.transfer(address(i), ((_duration.div(DAY_IN_SECONDS)) + 2) * ORACLE_PAYMENT.mul(2));

        return address(i);

    }

    constructor() public payable {
        priceFeed = AggregatorV3Interface(0x9326BFA02ADD2366b30bacB125260Af641031331);
    }
}

contract InsuranceContract is ChainlinkClient, Ownable  {
    constructor(address _client, uint _duration, uint _premium, uint _payoutValue,
    string _cropLocation, address _link,
    uint256 _oraclePaymentAmount)  payable Ownable() public {
    }
}