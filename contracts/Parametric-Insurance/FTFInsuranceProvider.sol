// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./FTFUserInsuranceContract.sol";

contract InsuranceProvider is ChainlinkClient {
    address public insurer = msg.sender;
    AggregatorV3Interface internal priceFeed;
    uint public constant DAY_IN_SECONDS = 60; //How many seconds in a day. 60 for testing, 86400 for Production
    uint256 constant private ORACLE_PAYMENT = 0.1 * 10**18;
    address public constant LINK_KOVAN = 0xa36085F69e2889c224210F603D836748e7dC0088;

    mapping(address => FTFUserInsuranceContract) contracts;

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
        FTFUserInsuranceContract i = new FTFUserInsuranceContract{
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

    function getContract(address contractAddress) external view returns (FTFUserInsuranceContract) {
        return contracts[contractAddress];
    }

    function updateContract(address contractAddress) external {
        FTFUserInsuranceContract i = FTFUserInsuranceContract(payable(contractAddress));
        i.updateContract();
    }

    function getContractRainfall(address contractAddress) external view returns (uint) {
        FTFUserInsuranceContract i = FTFUserInsuranceContract(payable(contractAddress));
        return i.getCurrentRainfall();
    }

    function getContractRequestCount(address contractAddress) external view returns (uint) {
        FTFUserInsuranceContract i = FTFUserInsuranceContract(payable(contractAddress));
        return i.getRequestCount();
    }

    function getInsurer() external view returns (address) {
        return insurer;
    }

    function getContractStatus(address contractAddress) external view returns (bool) {
        FTFUserInsuranceContract i = FTFUserInsuranceContract(payable(contractAddress));
        return i.getContractStatus();

    }

    function getContractBalance() external view returns (uint) {
        return address(this).balance;
    }

    function endContractProvider() external payable onlyInsuranceProviderOwner {
        LinkTokenInterface link = LinkTokenInterface(LINK_KOVAN);
        require(link.transfer(msg.sender, link.balanceOf(address(this))), "Unable to transfer");
        selfdestruct(payable(insurer));
    }

    function getLatestPrice() public view returns (int) {
        (
            uint80 roundID,
            int price,
            uint startedAt,
            uint timeStamp,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();
        require(timeStamp > 0, "Round not complete");
        return price;
    }

    receive() external payable { }
}