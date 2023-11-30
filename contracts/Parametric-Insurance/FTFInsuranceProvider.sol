// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "@chainlink/contracts/src/v0.8/Chainlink.sol";
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";

contract FtfInsuranceProvider is ChainlinkClient {

    address public insurer = msg.sender;
    AggregatorV3Interface internal priceFeed;
    uint public constant DAY_IN_SECONDS = 60; //How many seconds in a day. 60 for testing, 86400 for Production
    uint256 constant private ORACLE_PAYMENT = 0.1 * 10**18;
    address public constant LINK_KOVAN = 0xa36085F69e2889c224210F603D836748e7dC0088;
    mapping(address => InsuranceContract) contracts;

    event ContractCreated(address indexed insuranceContract, uint premium, uint totalCover);

    constructor() payable {
        priceFeed = AggregatorV3Interface(0x9326BFA02ADD2366b30bacB125260Af641031331);
    }

        modifier onlyInsuranceProviderOwner() {
        require(insurer == msg.sender, "Only Insurance provider can do this");
        _;
    }

    event contractCreated(address _insuranceContract, uint _premium, uint _totalCover);

    function newContract(
        address _client,
        uint _duration,
        uint _premium,
        uint _payoutValue,
        string memory _cropLocation
    ) public payable onlyInsuranceProviderOwner returns(address) {

        InsuranceContract i = new InsuranceContract{
            value: (_payoutValue * 1 ether) / uint(getLatestPrice())
        }(
            _client,
            _duration,
            _premium,
            _payoutValue,
            _cropLocation,
            LINK_KOVAN,
            ORACLE_PAYMENT
        );

        contracts[address(i)] = i;
        emit contractCreated(address(i), msg.value, _payoutValue);

        LinkTokenInterface link = LinkTokenInterface(i.getChainlinkToken());
        link.transfer(address(i), ((_duration / DAY_IN_SECONDS) + 2) * ORACLE_PAYMENT * 2);

        return address(i);
    }

}