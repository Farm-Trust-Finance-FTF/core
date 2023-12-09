// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IFarmTrustSender {
    function whitelistChain(uint64 _destinationChainSelector) external;

    function denylistChain(uint64 _destinationChainSelector) external;

    function sendMessage(
        uint64 destinationChainSelector,
        address receiver,
        address tokenToTransfer,
        uint256 transferAmount
    ) external;

    function getNumberOfReceivedMessages()
        external
        view
        returns (uint256 number);

    function getLastReceivedMessageDetails()
        external
        view
        returns (bytes32 messageId, uint64, address, address, address, uint256);

    function depositETH() external payable;

    function depositToken(address token, uint256 amount) external payable;

    function withdraw() external;

    function withdrawToken(address token) external;

    receive() external payable;

    fallback() external payable;
}
