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

    function getContract(address contractAddress) external view returns (InsuranceContract) {
        return contracts[contractAddress];
    }

    function updateContract(address contractAddress) external {
        InsuranceContract i = InsuranceContract(payable(contractAddress));
        i.updateContract();
    }

    function getContractRainfall(address contractAddress) external view returns (uint) {
        InsuranceContract i = InsuranceContract(payable(contractAddress));
        return i.getCurrentRainfall();
    }

    function getContractRequestCount(address contractAddress) external view returns (uint) {
        InsuranceContract i = InsuranceContract(payable(contractAddress));
        return i.getRequestCount();
    }

    function getInsurer() external view returns (address) {
        return insurer;
    }

    function getContractStatus(address contractAddress) external view returns (bool) {
        InsuranceContract i = InsuranceContract(payable(contractAddress));
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

contract InsuranceContract is ChainlinkClient, ConfirmedOwner {
    AggregatorV3Interface internal priceFeed;
    uint public constant DAY_IN_SECONDS = 60;
    uint public constant DROUGHT_DAYS_THRESHOLD = 3;
    uint256 private oraclePaymentAmount;

    using Chainlink for Chainlink.Request;

    address public insurer;
    address public client;
    uint public startDate;
    uint public duration;
    uint public premium;
    uint public payoutValue;
    string public cropLocation;

    uint[2] public currentRainfallList;
    bytes32[2] public jobIds;
    address[2] public oracles;

    uint public daysWithoutRain;
    bool public contractActive;
    bool public contractPaid = false;
    uint public currentRainfall = 0;
    uint public currentRainfallDateChecked = block.timestamp;
    uint public requestCount = 0;
    uint public dataRequestsSent = 0;

    event ContractCreated(address insurer, address client, uint duration, uint premium, uint totalCover);
    event ContractPaidOut(uint paidTime, uint totalPaid, uint finalRainfall);
    event ContractEnded(uint endTime, uint totalReturned);
    event RainfallThresholdReset(uint rainfall);
    event DataRequestSent(bytes32 requestId);
    event DataReceived(uint rainfall);

    constructor (
        address _client,
        uint _duration,
        uint _premium,
        uint _payoutValue,
        string memory _cropLocation,
        address _link,
        uint256 _oraclePaymentAmount
    )
        payable ConfirmedOwner(msg.sender)
    {
        priceFeed = AggregatorV3Interface(0x9326BFA02ADD2366b30bacB125260Af641031331);
        setChainlinkToken(_link);
        _oraclePaymentAmount = (1 * LINK_DIVISIBILITY) / 10;
        oraclePaymentAmount = _oraclePaymentAmount;

        require(msg.value >= _payoutValue / uint(getLatestPrice()), "Not enough funds sent to contract");

        insurer = msg.sender;
        client = _client;
        startDate = block.timestamp;
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

        emit ContractCreated(insurer, client, duration, premium, payoutValue);
    }

    modifier onContractEnded() {
        if (startDate + duration < block.timestamp) {
            _;
        }
    }

    modifier onContractActive() {
        require(contractActive, 'Contract has ended, cant interact with it anymore');
        _;
    }

    modifier callFrequencyOncePerDay() {
        require(block.timestamp - currentRainfallDateChecked > (DAY_IN_SECONDS - DAY_IN_SECONDS / 12), 'Can only check rainfall once per day');
        _;
    }

    function updateContract() public onContractActive() {
        checkEndContract();
        if (contractActive) {
            dataRequestsSent = 0;
            string memory url = string(abi.encodePacked("https://worldweatheronline.com/api/v1/weather.ashx?key=", "629c6dd09bbc4364b7a33810200911", "&q=", cropLocation, "&format=json&num_of_days=1"));
            checkRainfall(oracles[0], jobIds[0], url, "data.current_condition.0.precipMM");

            url = string(abi.encodePacked("https://api.weatherbit.io/v2.0/current?city=", cropLocation, "&key=", "b4e40205aeb3f27b74333393de24ca79"));
            checkRainfall(oracles[1], jobIds[1], url, "data.0.precipitation");
        }
    }

/**
 * @dev Calls out to an Oracle to obtain weather data
 */
function checkRainfall(address _oracle, bytes32 _jobId, string memory _url, string memory _path) private onContractActive() returns (bytes32 requestId)   {

    //First build up a request to get the current rainfall
    Chainlink.Request memory req = buildChainlinkRequest(_jobId, address(this), this.checkRainfallCallBack.selector);

    req.add("get", _url);
    req.add("path", _path);
    int256 timesAmount = 10 ** 18;
    req.addInt("times", timesAmount);

    requestId =  sendChainlinkRequestTo(_oracle, req, oraclePaymentAmount);
    emit DataRequestSent(requestId);
    return requestId;
}
    function getCurrentRainfall() public view returns (uint) {
    return currentRainfall;
}
    function checkRainfallCallBack(bytes32 _requestId, uint256 _rainfall) public recordChainlinkFulfillment(_requestId) onContractActive() callFrequencyOncePerDay() {
        currentRainfallList[dataRequestsSent] = _rainfall;
        dataRequestsSent = dataRequestsSent + 1;

        if (dataRequestsSent > 1) {
            currentRainfall = (currentRainfallList[0] + currentRainfallList[1]) / 2;
            currentRainfallDateChecked = block.timestamp;
            requestCount += 1;

            if (currentRainfall == 0) {
                daysWithoutRain += 1;
            } else {
                daysWithoutRain = 0;
                emit RainfallThresholdReset(currentRainfall);
            }

            if (daysWithoutRain >= DROUGHT_DAYS_THRESHOLD) {
                payOutContract();
            }
        }

        emit DataReceived(_rainfall);
    }

    function payOutContract() private onContractActive() {
        payable(client).transfer(address(this).balance);

        LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
        require(link.transfer(insurer, link.balanceOf(address(this))), "Unable to transfer");

        emit ContractPaidOut(block.timestamp, payoutValue, currentRainfall);

        contractActive = false;
        contractPaid = true;
    }

/**
 * @dev Get the count of requests that have occurred for the Insurance Contract
 */
function getRequestCount() external view returns (uint) {
    return requestCount;
}
/**
 * @dev Get the status of the contract
 */
function getContractStatus() external view returns (bool) {
    return contractActive;
}

    /**
     * @dev Get the contract start date
     */
    function getContractStartDate() external view returns (uint) {
        return startDate;
    }

    /**
     * @dev Get the Premium paid
     */
    function getPremium() external view returns (uint) {
        return premium;
    }

        /**
     * @dev Get whether the contract has been paid out or not
     */
    function getContractPaid() external view returns (bool) {
        return contractPaid;
    }

        /**
     * @dev Get the recorded number of days without rain
     */
    function getDaysWithoutRain() external view returns (uint) {
        return daysWithoutRain;
    }

        /**
     * @dev Get the contract duration
     */
    function getDuration() external view returns (uint) {
        return duration;
    }

        /**
     * @dev Get the Total Cover
     */
    function getPayoutValue() external view returns (uint) {
        return payoutValue;
    }

        /**
     * @dev Get the balance of the contract
     */
    function getContractBalance() external view returns (uint) {
        return address(this).balance;
    }

        /**
     * @dev Get the Crop Location
     */
    function getLocation() external view returns ( string memory) {
        return cropLocation;
    }

/**
 * @dev Insurance conditions have not been met, and contract expired, end contract and return funds
 */ 
function checkEndContract() private onContractEnded()   {
    // Insurer needs to have performed at least 1 weather call per day to be eligible to retrieve funds back.
    // We will allow for 1 missed weather call to account for unexpected issues on a given day.
    if (requestCount >= (duration / DAY_IN_SECONDS - 2)) {
        // return funds back to insurance provider then end/kill the contract
        payable(insurer).transfer(address(this).balance);
    } else { // insurer hasn't done the minimum number of data requests, client is eligible to receive his premium back
        // need to use ETH/USD price feed to calculate ETH amount
        //payable(client).transfer(premium.div(uint(getLatestPrice())));
        payable(client).transfer(premium / uint(getLatestPrice()));

        payable(insurer).transfer(address(this).balance);
    }

    // transfer any remaining LINK tokens back to the insurer
    LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
    require(link.transfer(payable(insurer), link.balanceOf(address(this))), "Unable to transfer remaining LINK tokens");

    // mark contract as ended, so no future state changes can occur on the contract
    contractActive = false;
    emit ContractEnded(block.timestamp, address(this).balance);
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

    function getChainlinkToken() public view returns (address) {
        return chainlinkTokenAddress();
    }

    fallback() external payable { }
    receive() external payable { }
}