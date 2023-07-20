// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

import "./TasksManager.sol";

contract AuctionManager {
     address private immutable owner; 
     TasksManager tasksManager;

     enum AuctionState {
        Created,
        Cancelled, 
        Finalized
    }

    struct Auction {
        address client;
        uint creationTime;
        uint auctionDeadline;
        uint taskDeadline;
        bytes32 clientVerification;
        string computationCode;
        string verificationCode;
        ProviderBid[] providerBids;
        WinnerBid winnerBid;
        AuctionState auctionState;   
    }

    struct ProviderBid {
        address provider;
        uint bid;
        uint providerUpVotes;
        uint providerDownVotes;
    }

    struct WinnerBid {
        address provider;
        uint bid;
    }

    mapping (bytes32 => Auction) auctions;
    bytes32[] bytes32_auctions;

    event AuctionCreated(bytes32 auctionID);
    event AuctionCancelled(bytes32 auctionID);
    event AuctionFinalized(bytes32 auctionID, address provider);
    event AuctionDeleted(bytes32 auctionID);
    event BidPlaced(bytes32 auctionID, address provider, uint bid);

    modifier ownerOnly() {
        require(
            msg.sender == owner,
            "Method can be called only by owner."
        );
        _;
    }

     modifier clientOnly(bytes32 _auctionID) {
        require(
            msg.sender == auctions[_auctionID].client,
            "Method can be called only by client."
        );
        _;
    }

     modifier inAuctionState(bytes32 _auctionID,AuctionState _auctionState) {
        require(
            auctions[_auctionID].auctionState == _auctionState,
            "Invalid AuctionState."
        );
        _;
    }


    modifier existingAuctionOnly(bytes32 _auctionID) {
        require(
            auctionExists(_auctionID),
            "Auction must exist"
        );
        _;
    }

    modifier notExistingAuctionOnly(bytes32 _auctionID) {
        require(
            !auctionExists(_auctionID),
            "Auction already exists"
        );
        _;
    }


    constructor(address payable _tasksManager)  {
        owner = msg.sender;
        tasksManager = TasksManager(_tasksManager);
    }

    function createAuction(bytes32 _auctionID, uint _auctionDeadline, uint _taskDeadline,bytes32 _clientVerification,
        string memory _verificationCode,
        string memory _computationCode
        ) public notExistingAuctionOnly(_auctionID){
        auctions[_auctionID].client = msg.sender;
        auctions[_auctionID].creationTime = block.timestamp;
        auctions[_auctionID].auctionDeadline = _auctionDeadline;
        auctions[_auctionID].taskDeadline = _taskDeadline;
        auctions[_auctionID].clientVerification = _clientVerification;
        auctions[_auctionID].verificationCode = _verificationCode;
        auctions[_auctionID].computationCode = _computationCode;

        auctions[_auctionID].auctionState = AuctionState.Created;
        bytes32_auctions.push(_auctionID);
        emit AuctionCreated(_auctionID);
    }

     function cancelAuction(bytes32 _auctionID) public clientOnly(_auctionID) inAuctionState(_auctionID, AuctionState.Created) existingAuctionOnly(_auctionID) {
        auctions[_auctionID].auctionState = AuctionState.Cancelled;
        emit AuctionCancelled(_auctionID);
     }

     function bid(bytes32 _auctionID, uint _bid) public  inAuctionState(_auctionID, AuctionState.Created)  existingAuctionOnly(_auctionID) {
        //  require(msg.sender != auctions[_auctionID].client, "Client can't bid to this auction"); //commented for testing
        require(
            (block.timestamp <= auctions[_auctionID].creationTime + auctions[_auctionID].auctionDeadline),
            "Time has expired."
        );
        uint providerIndex = 0;
        if(auctions[_auctionID].providerBids.length != 0)
        {    while(auctions[_auctionID].providerBids[providerIndex].provider != msg.sender)
            {
                providerIndex++;
                if(providerIndex > auctions[_auctionID].providerBids.length)
                    break;
            }
            if (providerIndex <= auctions[_auctionID].providerBids.length)
            {
                require(
                _bid < auctions[_auctionID].providerBids[providerIndex].bid,
                "Bid is not lower than than the previous one."
                );
            }
        }
        ProviderBid memory currentBid;
        currentBid.provider = msg.sender;
        currentBid.bid = _bid;
        currentBid.providerUpVotes = tasksManager.getPerformance(msg.sender).upVotes;
        currentBid.providerDownVotes = tasksManager.getPerformance(msg.sender).downVotes;
        auctions[_auctionID].providerBids.push(currentBid);
        emit BidPlaced(_auctionID, msg.sender, _bid);
     }

    function finalize(bytes32 _auctionID, address payable _provider) public payable clientOnly(_auctionID) inAuctionState(_auctionID, AuctionState.Created) existingAuctionOnly(_auctionID) returns (bytes32) {
        uint providerIndex = 0;
        while(auctions[_auctionID].providerBids[providerIndex].provider != _provider)
        {
            providerIndex++;
            if(providerIndex > auctions[_auctionID].providerBids.length)
                break;
        }
        if(providerIndex > auctions[_auctionID].providerBids.length)
         revert("Wrong provider address");
        WinnerBid memory _winnerBid;
        _winnerBid.provider = _provider;
        _winnerBid.bid = auctions[_auctionID].providerBids[providerIndex].bid;
        require (msg.value >= _winnerBid.bid * 2, "Client collateral is not enough");
        auctions[_auctionID].winnerBid = _winnerBid;
        Auction storage currentAuction = auctions[_auctionID];
        emit AuctionFinalized(_auctionID, _provider);
        bytes32 taskID = keccak256(abi.encode(currentAuction.client, _winnerBid, block.timestamp));
        uint clientCollateral = getClientCollateral(_auctionID);
        tasksManager.createTask{value: clientCollateral}(taskID, _provider,  _winnerBid.bid, currentAuction.taskDeadline, currentAuction.clientVerification,currentAuction.verificationCode, currentAuction.computationCode);
        return taskID; //check for reutrn, else add event TaskCreated
    }

    function getClientCollateral(bytes32 _auctionID) private view returns (uint) {
        return auctions[_auctionID].winnerBid.bid * 2;
    }

    function auctionExists(bytes32 _auctionID) public view returns (bool) {
            return (auctions[_auctionID].client != address(0));
        }

    function deleteAuctions() public ownerOnly { 
        for (uint i = bytes32_auctions.length; i > 0; i--)
        {
            bytes32 _auctionID = bytes32_auctions[i-1];
            if (auctions[_auctionID].auctionState == AuctionState.Finalized || auctions[_auctionID].auctionState == AuctionState.Cancelled) 
                        {
                delete(auctions[_auctionID]);
                bytes32_auctions[i-1] = bytes32_auctions[bytes32_auctions.length - 1];
                bytes32_auctions.pop();
                emit AuctionDeleted(_auctionID);
            }
        }
    }

    function deleteAuction(bytes32 _auctionID) public ownerOnly existingAuctionOnly(_auctionID) {
        delete(auctions[_auctionID]);
        for (uint i=0; i < bytes32_auctions.length; i++)
        {
            if (bytes32_auctions[i] == _auctionID)
            {
                bytes32_auctions[i] = bytes32_auctions[bytes32_auctions.length - 1];
                bytes32_auctions.pop();
                break;
            }
        }
        emit AuctionDeleted(_auctionID);
    }

     function getActiveAuctions() ownerOnly public view returns (uint256) {
        return bytes32_auctions.length;
    }

    function getAuctionBids(bytes32 _auctionID) public view returns(ProviderBid[] memory) {
        return auctions[_auctionID].providerBids;
    }
    
}