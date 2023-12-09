// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IFarmTrustProtocol {
    function borrowUSDC(bytes32 msgId) external returns (uint256);

    function repayAndSendMessage(
        uint256 amount,
        uint64 destinationChain,
        address receiver,
        bytes32 msgId
    ) external;

    function getNumberOfReceivedMessages()
        external
        view
        returns (uint256 number);

    function getReceivedMessageDetails(
        bytes32 messageId
    )
        external
        view
        returns (uint64, address, address, address token, uint256 amount);

    function getLastReceivedMessageDetails()
        external
        view
        returns (bytes32 messageId, uint64, address, address, address, uint256);

    function withdraw() external;

    function withdrawToken(address token) external;

    receive() external payable;

    fallback() external payable;
}
