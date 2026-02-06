//SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

//Import token contracts to interact with them.
import "./MyToken.sol";
import "./MyNFT.sol";
// Import OpenZeppelin's IERC721Receiver for safe NFT transfers.
import  "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/**
    * @title The main contract implementing the Dutch auction.
    * @author Rom1mel.
    * @notice Allows users to sell their NFTs and customize each lot in detail.
    * @dev Main contract of the project
*/

contract Auction is IERC721Receiver{
    /**
     * @dev Token contract instances.
     */
    EducationToken contractEDU;
    NFTsLot lotNFTContract;

    /**
     * @dev Contract state variables
     */
    address public owner; // The address of the contract owner
    mapping(uint256 => Lot) public lots; // Storage for all auction lots
    uint256 public addingFee; // Platform commission (in EDU tokens) for adding a new lot
    uint256 public fee; // Platform commission (in EDU tokens) for purchasing a lot
    /**
     * @dev Increases by 1 when a new lot is added. Represents the total number of lots created.
     */
    uint256 internal lotId; // Current lot identifier counter

    /**
     * @dev Structure representing an auction lot
     */
    struct Lot{
        uint256 lotNFTsID; // ID of the NFT being auctioned
        address lotOwner; // Address of the lot creator (seller)
        uint256 beginPrice;  // Starting price of the lot (in EDU tokens)
        uint256 discount; // Price decrease per discount period (in EDU tokens)
        uint256 periodOfDiscount; // Duration of one discount period (in seconds)
        uint256 timeStemp; // The timestamp when the lot was created
        uint256 timeToEnd; // Total auction duration (in seconds)
        address buyer; // Address of the buyer (zero address if not sold)
        uint256 finalPrice; // Final purchase price (in EDU tokens, zero if not sold)
    }
    enum lotStatus {
        active, sold, canceled, expired
    }

    /**
     * @dev Custom errors to better understand the reasons for transaction reverts.
     */
    error PriceCantBeZero(); // Lot price cannot be zero
    error PriceCantBeUint256Max(); // Lot price cannot be uint256Max
    error FeeCantBeZero();  // Platform fee cannot be zero
    error AddressCantBeZero(); //Token address cannot be zero
    error RezultDiscountMoreThenBefinPrice(); // Total discount exceeds starting price
    error LotDoesNotExsist(); // Requested lot ID does not exist
    error IncorrectActionForLotStatus(lotStatus, lotStatus); // Еhe action is not possible due to the current status of the lot (current status, required status)
    error BalanceIsZero(); // Platform has zero balance of required token
    error LackOfFaunds(); // The user does not have enough tokens in their balance
    error YouAreNotOwner(); // Caller is not the contract owner or lot owner
    error YouDontHaveThisNFT(uint256); // The user does not own this NFT
    error NotApproved(); // Token transfer has not been approved for this contract

    /**
     * @dev Events for tracking contract activity
    */
    event LotAdded(uint256 indexed lotId, address lotOwner, uint256 indexed beginPrice, uint256 timeStemp);
    event LotBought(uint256 indexed lotId, address buyer, uint256 indexed finalPrice, uint256 timeStemp);
    event LotCanceled(uint256 indexed lotId, uint256 timeStemp);

    /**
     * @dev Modifier to restrict function access to contract owner only
    */
    modifier onlyOwner {
        require(msg.sender == owner, YouAreNotOwner());
        _;
    }

    /** 
        * @dev Sets the contract owner to the person who deployed it.
        * It also sets and verifies the correctness of commissions for buying and creating lots.
        * @param _fee Platform commission for buying lots (in EDU tokens)
        * @param _addingFee Platform commission for adding new lots (in EDU tokens)
    */
    constructor (uint256 _fee, uint256 _addingFee){
        require(_fee!=0 && _addingFee!=0, FeeCantBeZero());
        owner = msg.sender;
        addingFee = _addingFee; 
        fee = _fee; 
    } 
    
    /**
     * @return uint256 The current platform commission for purchasing a lot (in EDU tokens)
     */
    function getFee() public view returns(uint256){
        return fee;
    }

    /**
     * @return address The owner's address
     */
    function getOwner() public view returns(address){
        return owner;
    }

    /**
     * @return uint256 The current platform commission for creating a lot (in EDU tokens)
     */
    function getAddingFee() public view returns(uint256){
        return addingFee;
    }

    /**
     * @dev Calculates the current price of the lot: 
     * starting price - ((current timestamp - lot creation timestamp) / discount period) * discount per period.
     * @param _lotId Identifier of the lot of interest
     * @return uint256 The current price of the lot (in EDU tokens)
     */
    function getCurrentPrice(uint256 _lotId) public view returns(uint256){
        require(_lotId <= lotId, LotDoesNotExsist()); // Checking the correctness of the argument
        //TODO: Create a separate function for viewing and calculating the price of a lot.
        require(lots[_lotId].buyer == address(0), LotIsEnd()); // Checking that the lot is not finished 
        return lots[_lotId].beginPrice - ((block.timestamp - lots[_lotId].timeStemp)/lots[_lotId].periodOfDiscount * lots[_lotId].discount);
    }

    /**
     * @return uint256 The total number of lots created (last assigned lot ID)
     */
    function getAuctionNumber() public view returns(uint256){
        return lotId;
    }
    
    /**
     * @param _lotId Identifier of the lot of interest
     * @return lot A structure containing complete information about a lot
     */
    function getLot(uint256 _lotId) public view returns(Lot memory){
        require(_lotId <= lotId, LotDoesNotExsist());
        return lots[_lotId];
    }

    /**
     * @notice Creates a lot and puts the NFT up for sale. Charges a commission.
     * @dev Adds the created lot to the lots mapping. Transfers the sold NFT and the fee to contract balance.
     * Requires token approval for both NFT and EDU tokens.
     * @param _usersNFT ID of the NFT listed for sale. Еhe user must own and approve the NFT
     * @param _beginPrice Starting price of the lot (in EDU tokens). Cannot be equal to 0 and Uint256Max
     * @param _discount Price decrease per discount period (in EDU tokens)
     * @param _periodOfDiscount Duration of one discount period (in seconds)
     * @param _timeToEnd Total auction duration (in seconds)
     * @return lotId The identifier of the newly created lot.
     */
    //TODO: Refund NFTs if the lot was not purchased
    //TODO: Give the user the opportunity to remove the lot from sale
    function addLot(uint256 _usersNFT, uint256 _beginPrice, uint256 _discount, uint256 _periodOfDiscount, uint256 _timeToEnd) external returns(uint256) {
        require(lotNFTContract.ownerOf(_usersNFT) == msg.sender, YouDontHaveThisNFT(_usersNFT));
        require(lotNFTContract.getApproved(_usersNFT) == address(this), NotApproved());
        //Checking the buyer's approval and balance.
        require(contractEDU.balanceOf(msg.sender) >= addingFee, LackOfFaunds());
        require(contractEDU.allowance(msg.sender, address(this)) >= addingFee, NotApproved());

        require(_beginPrice > 0, PriceCantBeZero());
        require(_beginPrice != type(uint256).max, PriceCantBeUint256Max());
        // Checking that the price will not go negative due to an excessive discount.
        require(_timeToEnd/_periodOfDiscount*_discount < _beginPrice, RezultDiscountMoreThenBefinPrice());
        //Change of contract states.
        address adressNull;
        uint256 finalPriceNull;
        Lot memory _lot = Lot(_usersNFT, msg.sender, _beginPrice, _discount, _periodOfDiscount, block.timestamp, _timeToEnd, adressNull, finalPriceNull);
        lots[lotId] = _lot;
        //charging a commission and transferring the NFT to the auction balance
        contractEDU.transferFrom(msg.sender, address(this), addingFee);
        lotNFTContract.safeTransferFrom(msg.sender, address(this), _usersNFT);
        //Сreating a lot create event.
        emit LotAdded(lotId, msg.sender, _beginPrice, block.timestamp);
        //Сhanging the state variable responsible for the ID of the next lot.
        lotId++;

        return lotId - 1;
    } 
    /**
     * @notice Purchase of NFT listed as part of the lot using EDU tokens.
     * @dev Transfers the buyer's EDU tokens (price + fee) and the purchased NFT to the buyer. 
     * Requires token approval for EDU tokens. Marks the lot as purchased and emits an event.
     * @param _lotId Identifier of the lot being purchased. The lot must exist and must not be completed.
     */
    function buyLot(uint256 _lotId) external{
        require(_lotId <= lotId, LotDoesNotExsist());
        require(!lotIsEnd(_lotId), LotIsEnd());
        uint256 finalPriceOfLot = getCurrentPrice(_lotId);
        //Checking the buyer's approval and balance.
        require(contractEDU.balanceOf(msg.sender) >= fee + finalPriceOfLot, LackOfFaunds());
        require(contractEDU.allowance(msg.sender, address(this)) >= fee + finalPriceOfLot, NotApproved());
        //Change of contract states.
        lots[_lotId].buyer = msg.sender;
        lots[_lotId].finalPrice = finalPriceOfLot;
        //Charging a commission and payment. Transferring the NFT to the buyer.
        contractEDU.transferFrom(msg.sender, address(this), fee);
        contractEDU.transferFrom(msg.sender, lots[_lotId].lotOwner, finalPriceOfLot);
        lotNFTContract.safeTransferFrom(address(this), msg.sender, lots[_lotId].lotNFTsID);
        //Сreating a lot purchase event.
        emit LotBought(_lotId, msg.sender, finalPriceOfLot, block.timestamp);
    }
    function cancelLot(uint256 _lotId) external{
        require(_lotId <= lotId, LotDoesNotExsist());
        require(!lotIsEnd(_lotId), LotIsEnd());
        require(msg.sender == lots[_lotId].lotOwner, YouAreNotOwner());

        lots[_lotId].beginPrice = type(uint256).max;
        _returnNFT(_lotId, msg.sender);

        emit LotCanceled(_lotId, block.timestamp);
    }
    function takeNFT(uint256 _lotId) external{
        require(_lotId <= lotId, LotDoesNotExsist());
        require(lotIsEnd(_lotId) == lotStatus.expired , NFTsCantBeReturned(lotIsEnd(_lotId)));

    }
    /**
     * @dev Checks if the lot is finished: the auction time has expired or the lot has been purchased.
     * @param _lotId Identifier of the lot of interest
     * @return bool True if the auction has ended, false otherwise
     */
    function _lotStatus(uint256 _lotId) internal view returns(lotStatus){
        if(lots[_lotId].beginPrice == type(uint256).max){
            return lotStatus.canceled;
        } 
        else if(block.timestamp - lots[_lotId].timeStemp > lots[_lotId].timeToEnd){
            return lotStatus.expired;
        } 
        else if(lots[_lotId].buyer != address(0)){
            return lotStatus.sold;
        }
        else{
            return lotStatus.active;
        }
    }
    function _returnNFT(uint256 _lotId, address _ownerOfLot) internal {
        lotNFTContract.safeTransferFrom(address(this), _ownerOfLot, lots[_lotId].lotNFTsID);
    }
    /**
     * @dev Sets a new commission when purchasing a lot. Available only to the owner.
     * @param newFee New commission when purchasing a lot. Cannot be equal to zero
     */
    function setFee(uint256 newFee) external onlyOwner{
        require(newFee!=0, FeeCantBeZero());
        fee = newFee;
    }
    /**
     * @dev Sets a new commission when creating a lot. Available only to the owner.
     * @param newFee New commission when creating a lot. Cannot be equal to zero
     */
    function setAddingFee(uint256 newFee) external onlyOwner{
        require(newFee!=0, FeeCantBeZero());
        addingFee = newFee;
    }

    /**
     * @dev Transfers the selected amount of earned commissions to the owner's address.
     * @param value Amount to be transferred to the owner's balance.
     * You cannot select 0 or an amount greater than the current contract balance to transfer.
     */
    function wisdrow(uint256 value) external onlyOwner{
        require(contractEDU.balanceOf(address(this)) != 0, BalanceIsZero());
        require(contractEDU.balanceOf(address(this)) >= value, LackOfFaunds());
        contractEDU.transfer(owner, value);
    }
    /**
     * @dev Transfers the all of earned commissions to the owner's address. The contract balance must be greater than 0
     */
    function wisdrowAll() external onlyOwner{
        require(contractEDU.balanceOf(address(this)) != 0, BalanceIsZero());
        contractEDU.transfer(owner, contractEDU.balanceOf(address(this)));
    }
    /**
     * @dev Сreates instances of token contracts to interact with them.
     * @param _EDU ERC20 token address. Cannot be 0.
     * @param _EDU ERC721 token address. Cannot be 0.
     */
    // TODO: Check that the address belongs to the contract. Make it impossible to change the address if there are active lots
    function setTokensAddress(address _EDU, address _NFT) external onlyOwner{
        require(_EDU != address(0) && _NFT != address(0), AddressCantBeZero());
        contractEDU = EducationToken(_EDU);
        lotNFTContract = NFTsLot(_NFT);
    }
    /**
     * @dev Allows contract to accept safe NFT transfers.
     */
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external pure returns (bytes4){
        return IERC721Receiver.onERC721Received.selector;
    }
}