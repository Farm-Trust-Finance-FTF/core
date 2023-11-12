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
    string constant OPEN_WEATHER_KEY = "f308642762d425d44855cf07466f05ab";
    string constant OPEN_WEATHER_PATH = "rain.1h";

    string constant WEATHERBIT_URL = "https://api.weatherbit.io/v2.0/current?";
    string constant WEATHERBIT_KEY = "3daaae1d22e648b8a8310562bf5184f9";
    string constant WEATHERBIT_PATH = "data.0.precip";

    uint daysWithoutRain;
    bool contractActive;
    bool contractPaid = false;
    uint currentRainfall = 0;
    uint currentRainfallDateChecked = now;
    uint requestCount = 0;
    uint dataRequestsSent = 0;

    modifier onlyOwner() {
		require(insurer == msg.sender,'Only Insurance provider can do this');
        _;
    }
    modifier onContractEnded() {
        if (startDate + duration < now) {
        _;
        }
    }
    modifier onContractActive() {
        require(contractActive == true ,'Contract has ended, cant interact with it anymore');
        _;
    }
    modifier callFrequencyOncePerDay() {
        require(now.sub(currentRainfallDateChecked) > (DAY_IN_SECONDS.sub(DAY_IN_SECONDS.div(12))),'Can only check rainfall once per day');
        _;
    }

    event contractCreated(address _insurer, address _client, uint _duration, uint _premium, uint _totalCover);
    event contractPaidOut(uint _paidTime, uint _totalPaid, uint _finalRainfall);
    event contractEnded(uint _endTime, uint _totalReturned);
    event ranfallThresholdReset(uint _rainfall);
    event dataRequestSent(bytes32 requestId);
    event dataReceived(uint _rainfall);

    constructor(address _client, uint _duration, uint _premium, uint _payoutValue,
    string _cropLocation, address _link,
    uint256 _oraclePaymentAmount)  payable Ownable() public {
        //set ETH/USD Price Feed
        priceFeed = AggregatorV3Interface(0x9326BFA02ADD2366b30bacB125260Af641031331);

        //initialize variables required for Chainlink Network interaction
        setChainlinkToken(_link);
        oraclePaymentAmount = _oraclePaymentAmount;

        //first ensure insurer has fully funded the contract
        require(msg.value >= _payoutValue.div(uint(getLatestPrice())), "Not enough funds sent to contract");

        //now initialize values for the contract
        insurer= msg.sender;
        client = _client;
        startDate = now ; //contract will be effective immediately on creation
        duration = _duration;
        premium = _premium;
        payoutValue = _payoutValue;
        daysWithoutRain = 0;
        contractActive = true;
        cropLocation = _cropLocation;

        oracles[0] = 0x05c8fadf1798437c143683e665800d58a42b6e19;
        oracles[1] = 0x05c8fadf1798437c143683e665800d58a42b6e19;
        jobIds[0] = 'a17e8fbf4cbf46eeb79e04b3eb864a4e';
        jobIds[1] = 'a17e8fbf4cbf46eeb79e04b3eb864a4e';

        emit contractCreated(insurer,
                            client,
                            duration,
                            premium,
                            payoutValue);
    }

    function updateContract() public onContractActive() returns (bytes32 requestId)   {
        checkEndContract();

        if (contractActive) {
            dataRequestsSent = 0;
            //First build up a request to World Weather Online to get the current rainfall
            string memory url = string(abi.encodePacked(WORLD_WEATHER_ONLINE_URL, "key=",WORLD_WEATHER_ONLINE_KEY,"&q=",cropLocation,"&format=json&num_of_days=1"));
            checkRainfall(oracles[0], jobIds[0], url, WORLD_WEATHER_ONLINE_PATH);

            // Now build up the second request to WeatherBit
            url = string(abi.encodePacked(WEATHERBIT_URL, "city=",cropLocation,"&key=",WEATHERBIT_KEY));
            checkRainfall(oracles[1], jobIds[1], url, WEATHERBIT_PATH);
        }
    }

    function checkRainfall(address _oracle, bytes32 _jobId, string _url, string _path) private onContractActive() returns (bytes32 requestId)   {

        //First build up a request to get the current rainfall
        Chainlink.Request memory req = buildChainlinkRequest(_jobId, address(this), this.checkRainfallCallBack.selector);

        req.add("get", _url); //sends the GET request to the oracle
        req.add("path", _path);
        req.addInt("times", 100);

        requestId = sendChainlinkRequestTo(_oracle, req, oraclePaymentAmount);

        emit dataRequestSent(requestId);
    }

    function checkRainfallCallBack(bytes32 _requestId, uint256 _rainfall) public recordChainlinkFulfillment(_requestId) onContractActive() callFrequencyOncePerDay()  {
        //set current temperature to value returned from Oracle, and store date this was retrieved (to avoid spam and gaming the contract)
        currentRainfallList[dataRequestsSent] = _rainfall;
        dataRequestsSent = dataRequestsSent + 1;

       //set current rainfall to average of both values
        if (dataRequestsSent > 1) {
        currentRainfall = (currentRainfallList[0].add(currentRainfallList[1]).div(2));
        currentRainfallDateChecked = now;
        requestCount +=1;

          //check if payout conditions have been met, if so call payoutcontract, which should also end/kill contract at the end
          if (currentRainfall == 0 ) { //temp threshold has been  met, add a day of over threshold
            daysWithoutRain += 1;
            } else {
              //there was rain today, so reset daysWithoutRain parameter
            daysWithoutRain = 0;
            emit ranfallThresholdReset(currentRainfall);
            }

          if (daysWithoutRain >= DROUGHT_DAYS_THRESDHOLD) {  // day threshold has been met
              //need to pay client out insurance amount
            payOutContract();
            }
        }

        emit dataReceived(_rainfall);

    }

}