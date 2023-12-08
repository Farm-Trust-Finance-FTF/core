// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.0/token/ERC20/IERC20.sol";
import {IERC165} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.0/utils/introspection/IERC165.sol";
import {IAny2EVMMessageReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol";
import {MockUSDC} from "./MockUSDC.sol";

contract FarmTrustProtocol is CCIPReceiver, OwnerIsCreator {
    // CUSTOM ERRORS
    error NoMessageReceived();
    error IndexOutOfBound(uint256 providedIndex, uint256 maxIndex);
    error MessageIdNotExist(bytes32 messageId);
    error NotEnoughBalance(uint256, uint256);
    error NothingToWithdraw();
    error FailedToWithdrawEth(address owner, uint256 value);
    error RepaymentAmountIsLessThanAmountBorrowed();
    error CallerUSDCTokenBalanceInsufficientForRepayment();
    error CallerHasAlreadyBorrowedUSDC();
    error CallerHasNotTransferedThisToken();
    error InsufficientAmount();
    error WithdrawalFromZeroAddress();
    error ChainSelectorZero();
    error ZeroAddress();
    error ProtocolAllowanceIsLessThanAmountBorrowed();

    // EVENTS
    event MessageSent(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address receiver,
        address borrower,
        Client.EVMTokenAmount tokenAmount,
        uint256 fees
    );

    event MessageReceived(
        bytes32 indexed messageId,
        uint64 indexed sourceChainSelector,
        address sender,
        address depositor,
        Client.EVMTokenAmount tokenAmount
    );

    event ETHWithdrawn(address sender, uint256 amount);
    event TokenWithdrawn(address sender, uint256 amount);

    // Struct to hold details of a message.
    struct MessageIn {
        uint64 sourceChainSelector;
        address sender;
        address depositor;
        address token;
        uint256 amount;
    }

    // STORAGE VARIABLES
    // Array to keep track of the IDs of received messages.
    bytes32[] public receivedMessages;
    mapping(bytes32 => MessageIn) public messageDetail;
    // Depsitor Address => Deposited Token Address ==> amount
    mapping(address => mapping(address => uint256)) public deposits;
    // Depsitor Address => Borrowed Token Address ==> amount
    mapping(address => mapping(address => uint256)) public borrowings;

    MockUSDC public usdcToken;
    LinkTokenInterface linkToken;

    constructor(address _router, address link) CCIPReceiver(_router) {
        linkToken = LinkTokenInterface(link);
        // deploy mockUSD
        usdcToken = new MockUSDC();
    }

    /**
     * @param msgId messageId returned from the ` sendMessage()` in the source Blockchain ie `FarmTrustSender.sol`
     * @dev allows FFT user to borrow USDC. It uses the chainlink priceFeed to get the price of DAI/USDC
     */
    function borrowUSDC(bytes32 msgId) public returns (uint256) {
        uint256 borrowed = borrowings[msg.sender][address(usdcToken)];

        if (borrowed != 0) revert CallerHasAlreadyBorrowedUSDC();

        address transferredToken = messageDetail[msgId].token;
        if (transferredToken == address(0))
            revert CallerHasNotTransferedThisToken();

        uint256 deposited = deposits[msg.sender][transferredToken];
        uint256 borrowable = (deposited * 70) / 100; // 70% collaterization ratio.

        // DAI/USD PriceFeed on Sepolia
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            0x14866185B1962B63C3Ea9E03Bc1da838bab34C19
        );

        (, int256 price, , , ) = priceFeed.latestRoundData();
        uint256 price18decimals = uint256(price * (10 ** 10)); // make USD price 18 decimal places from 8 decimal places.

        uint256 borrowableInUSDC = borrowable * price18decimals;

        // MintUSDC
        usdcToken.mint(msg.sender, borrowableInUSDC);

        // Update state.
        borrowings[msg.sender][address(usdcToken)] = borrowableInUSDC;

        assert(borrowings[msg.sender][address(usdcToken)] == borrowableInUSDC);
        return borrowableInUSDC;
    }

    /**
     * @param amount repayment amount
     * @param destinationChain destination blockchain
     * @param receiver receiver address
     * @param msgId messageId
     * @dev allows a user to repay the protocol and transfers the token back to the source chain. Burns the borrowed token unbehalf of the user
     */

    function repayAndSendMessage(
        uint256 amount,
        uint64 destinationChain,
        address receiver,
        bytes32 msgId
    ) public {
        if (amount < borrowings[msg.sender][address(usdcToken)]) {
            revert RepaymentAmountIsLessThanAmountBorrowed();
        }

        // Get the deposit details, so it can be transferred back.
        address transferredToken = messageDetail[msgId].token;
        uint256 deposited = deposits[msg.sender][transferredToken];

        uint256 mockUSDCBalance = usdcToken.balanceOf(msg.sender);

        if (mockUSDCBalance < amount) {
            revert CallerUSDCTokenBalanceInsufficientForRepayment();
        }

        if (
            usdcToken.allowance(msg.sender, address(this)) <
            borrowings[msg.sender][address(usdcToken)]
        ) {
            revert ProtocolAllowanceIsLessThanAmountBorrowed();
        }

        usdcToken.burn(msg.sender, mockUSDCBalance);

        // Updates borrowings mapping
        borrowings[msg.sender][address(usdcToken)] = 0;
        // send transferred token and message back to Sepolia Sender contract
        _sendMessage(destinationChain, receiver, transferredToken, deposited);
    }

    function _sendMessage(
        uint64 destinationChainSelector,
        address receiver,
        address tokenToTransfer,
        uint256 transferAmount
    ) internal returns (bytes32 messageId) {
        if (destinationChainSelector == 0) revert ChainSelectorZero();
        if (receiver == address(0)) revert ZeroAddress();
        if (tokenToTransfer == address(0)) revert ZeroAddress();
        if (transferAmount == 0) revert InsufficientAmount();

        address borrower = msg.sender;

        // Compose the EVMTokenAmountStruct. This struct describes the tokens being transferred using CCIP.
        Client.EVMTokenAmount[]
            memory tokenAmounts = new Client.EVMTokenAmount[](1);

        Client.EVMTokenAmount memory tokenAmount = Client.EVMTokenAmount({
            token: tokenToTransfer,
            amount: transferAmount
        });

        tokenAmounts[0] = tokenAmount;

        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: abi.encode(borrower),
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: 200_000, strict: false})
            ),
            feeToken: address(linkToken)
        });

        // Initialize a router client instance to interact with cross-chain
        IRouterClient router = IRouterClient(this.getRouter());

        // Get the fee required to send the message
        uint256 fees = router.getFee(destinationChainSelector, evm2AnyMessage);

        if (fees > linkToken.balanceOf(address(this)))
            revert NotEnoughBalance(linkToken.balanceOf(address(this)), fees);

        // approve the Router to send LINK tokens on contract's behalf. I will spend the fees in LINK
        linkToken.approve(address(router), fees);

        require(
            IERC20(tokenToTransfer).approve(address(router), transferAmount),
            "Failed to approve router"
        );

        // Send the message through the router and store the returned message ID
        messageId = router.ccipSend(destinationChainSelector, evm2AnyMessage);

        // Emit an event with message details
        emit MessageSent(
            messageId,
            destinationChainSelector,
            receiver,
            borrower,
            tokenAmount,
            fees
        );

        deposits[borrower][tokenToTransfer] -= transferAmount;

        // Return the message ID
        return messageId;
    }

    /// handle a received message
    function _ccipReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    ) internal override {
        bytes32 messageId = any2EvmMessage.messageId; // fetch the messageId
        uint64 sourceChainSelector = any2EvmMessage.sourceChainSelector; // fetch the source chain identifier (aka selector)
        address sender = abi.decode(any2EvmMessage.sender, (address)); // abi-decoding of the sender address
        address depositor = abi.decode(any2EvmMessage.data, (address)); // abi-decoding of the depositor's address

        // Collect tokens transferred. This increases this contract's balance for that Token.
        Client.EVMTokenAmount[] memory tokenAmounts = any2EvmMessage
            .destTokenAmounts;
        address token = tokenAmounts[0].token;
        uint256 amount = tokenAmounts[0].amount;

        receivedMessages.push(messageId);

        MessageIn memory detail = MessageIn(
            sourceChainSelector,
            sender,
            depositor,
            token,
            amount
        );
        messageDetail[messageId] = detail;

        emit MessageReceived(
            messageId,
            sourceChainSelector,
            sender,
            depositor,
            tokenAmounts[0]
        );

        // Store depositor data.
        deposits[depositor][token] += amount;
    }

    function getNumberOfReceivedMessages()
        external
        view
        returns (uint256 number)
    {
        return receivedMessages.length;
    }

    function getReceivedMessageDetails(
        bytes32 messageId
    )
        external
        view
        returns (uint64, address, address, address token, uint256 amount)
    {
        MessageIn memory detail = messageDetail[messageId];
        if (detail.sender == address(0)) revert MessageIdNotExist(messageId);
        return (
            detail.sourceChainSelector,
            detail.sender,
            detail.depositor,
            detail.token,
            detail.amount
        );
    }

    function getLastReceivedMessageDetails()
        external
        view
        returns (bytes32 messageId, uint64, address, address, address, uint256)
    {
        // Revert if no messages have been received
        if (receivedMessages.length == 0) revert NoMessageReceived();

        // Fetch the last received message ID
        messageId = receivedMessages[receivedMessages.length - 1];

        // Fetch the details of the last received message
        MessageIn memory detail = messageDetail[messageId];

        return (
            messageId,
            detail.sourceChainSelector,
            detail.sender,
            detail.depositor,
            detail.token,
            detail.amount
        );
    }

    function isChainSupported(
        uint64 destChainSelector
    ) external view returns (bool supported) {
        return
            IRouterClient(this.getRouter()).isChainSupported(destChainSelector);
    }

    receive() external payable {}

    fallback() external payable {}

    /**
     * @notice Allows the contract owner to withdraw the entire balance of Ether from the contract.
     * @dev This function reverts if there are no funds to withdraw or if the transfer fails.
       It should only be callable by the owner of the contract.
     */
    function withdrawETH() public onlyOwner {
        // Retrieve the balance of this contract
        uint256 amount = address(this).balance;

        // Attempt to send the funds, capturing the success status and discarding any return data
        (bool sent, ) = msg.sender.call{value: amount}("");

        // Revert if the send failed, with information about the attempted transfer
        if (!sent) revert FailedToWithdrawEth(msg.sender, amount);

        emit ETHWithdrawn(msg.sender, amount);
    }

    /**
     * @notice Allows the owner of the contract to withdraw all tokens of a specific ERC20 token.
     * @dev This function reverts with a 'NothingToWithdraw' error if there are no tokens to withdraw.
     * @param token The contract address of the ERC20 token to be withdrawn.
     */

    function withdrawToken(address token) public onlyOwner {
        if (token == address(0)) revert WithdrawalFromZeroAddress();

        // Retrieve the balance of this contract
        uint256 amount = IERC20(token).balanceOf(address(this));
        IERC20(token).transfer(msg.sender, amount);

        emit TokenWithdrawn(msg.sender, amount);
    }
}
