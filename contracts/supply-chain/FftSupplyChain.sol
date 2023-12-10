// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0;

contract FtfSupplyChain {
        uint32 public product_id = 0;   // Product ID
    uint32 public participant_id = 0;   // Participant ID
    uint32 public owner_id = 0;   // Ownership ID

    struct product {
        string modelNumber;
        string partNumber;
        string serialNumber;
        address productOwner;
        uint32 cost;
        uint32 mfgTimeStamp;
    }

    mapping(uint32 => product) public products;

    struct participant {
        string userName;
        string password;
        string participantType;
        address participantAddress;
    }
    mapping(uint32 => participant) public participants;

    struct ownership {
        uint32 productId;
        uint32 ownerId;
        uint32 trxTimeStamp;
        address productOwner;
    }

    mapping(uint32 => ownership) public ownerships; // ownerships by ownership ID (owner_id)
    mapping(uint32 => uint32[]) public productTrack;  // ownerships by Product ID (product_id) / Movement track for a product

    event TransferOwnership(uint32 productId);

    function addParticipant(string memory _name, string memory _pass, address _pAdd, string memory _pType) public returns (uint32){
        uint32 userId = participant_id++;
        participants[userId].userName = _name;
        participants[userId].password = _pass;
        participants[userId].participantAddress = _pAdd;
        participants[userId].participantType = _pType;

        return userId;
    }
}

