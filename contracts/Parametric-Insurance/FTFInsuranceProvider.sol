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

    function getContract(address _contract) external view returns (InsuranceContract) {
        return contracts[_contract];
    }

    function updateContract(address _contract) external {
        InsuranceContract i = InsuranceContract(_contract);
        i.updateContract();
    }

    function getContractRainfall(address _contract) external view returns(uint) {
        InsuranceContract i = InsuranceContract(_contract);
        return i.getCurrentRainfall();
    }

    function getContractRequestCount(address _contract) external view returns(uint) {
        InsuranceContract i = InsuranceContract(_contract);
        return i.getRequestCount();
    }

    function getInsurer() external view returns (address) {
        return insurer;
    }

    function getContractStatus(address _address) external view returns (bool) {
        InsuranceContract i = InsuranceContract(_address);
        return i.getContractStatus();
    }
    function getContractBalance() external view returns (uint) {
        return address(this).balance;
    }

    function endContractProvider() external payable onlyOwner() {
        LinkTokenInterface link = LinkTokenInterface(LINK_KOVAN);
        require(link.transfer(msg.sender, link.balanceOf(address(this))), "Unable to transfer");
        selfdestruct(insurer);
    }

    function getLatestPrice() public view returns (int) {
        (
            uint80 roundID,
            int price,
            uint startedAt,
            uint timeStamp,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();
        // If the round is not complete yet, timestamp is 0
        require(timeStamp > 0, "Round not complete");
        return price;
    }

     //receive() external payable { }
        fallback() external payable { }
    //function() external payable { }
}

contract InsuranceContract is ChainlinkClient, Ownable  {

    using SafeMathChainlink for uint;
    AggregatorV3Interface internal priceFeed;

    uint public constant DAY_IN_SECONDS = 60;
    uint public constant DROUGHT_DAYS_THRESDHOLD = 3 ;
    uint256 private oraclePaymentAmount;

    address public insurer;
    address client;
    uint startDate;
    uint duration;
    uint premium;
    uint payoutValue;
    string cropLocation;


    uint256[2] public currentRainfallList;
    bytes32[2] public jobIds;
    address[2] public oracles;

    string constant WORLD_WEATHER_ONLINE_URL = "http://api.worldweatheronline.com/premium/v1/weather.ashx?";
    string constant WORLD_WEATHER_ONLINE_KEY = "";
    string constant WORLD_WEATHER_ONLINE_PATH = "data.current_condition.0.precipMM";

    string constant OPEN_WEATHER_URL = "https://openweathermap.org/data/2.5/weather?";
    string constant OPEN_WEATHER_KEY = "";
    string constant OPEN_WEATHER_PATH = "rain.1h";

    string constant WEATHERBIT_URL = "https://api.weatherbit.io/v2.0/current?";
    string constant WEATHERBIT_KEY = "";
    string constant WEATHERBIT_PATH = "data.0.precip";

    uint daysWithoutRain;
    bool contractActive;
    bool contractPaid = false;
    uint currentRainfall = 0;
    uint currentRainfallDateChecked = now;
    uint requestCount = 0;
    uint dataRequestsSent = 0;

    constructor(address _client, uint _duration, uint _premium, uint _payoutValue,
    string _cropLocation, address _link,
    uint256 _oraclePaymentAmount)  payable Ownable() public {
    }
}