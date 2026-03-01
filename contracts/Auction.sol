//SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

//Import token contracts to interact with them.
import "./MyToken.sol";
import "./MyNFT.sol";
// Import OpenZeppelin's IERC721Receiver for safe NFT transfers.
import  "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
// Import OpenZeppelin's IERC721 and ERC165 for check that the entered address is the address of the contract implementing ERC721
import  "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import  "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/**
    * @title The main contract implementing the Dutch auction.
    * @author Rom1mel.
    * @notice Allows users to sell their NFTs and customize each lot in detail.
    * @dev Main contract of the project
*/

contract Auction is IERC721Receiver, ERC165{
    /**
     * @dev Token contract instances.
     */
    IERC20 private token;
    IERC721 private nft;

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
        address addressERC20; // The address of the token contract in which payment is accepted.
        address addressERC721; // The address of the contract implementing the collection of this NFT.
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
    /**
     * @dev Displays the current status of the lot: active - anyone can buy this lot; sold - the lot has already been purchased by someone;
     * canceled - the owner cancelled the listed lot; expired - the time to purchase the lot has expired.
     */
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
    error LotWasCancelled(uint256); //An attempt to get the price of a canceled lot (LotID)
    error IncorrectActionForLotStatus(lotStatus, lotStatus); // Еhe action is not possible due to the current status of the lot (current status, required status)
    error BalanceIsZero(); // Platform has zero balance of required token
    error LackOfFaunds(); // The user does not have enough tokens in their balance
    error YouAreNotOwner(); // Caller is not the contract owner or lot owner
    error YouDontHaveThisNFT(uint256); // The user does not own this NFT
    error NotApproved(uint256); // Token transfer has not been approved for this contract (NFTsId or token amount)
    error BalanceMustBeZero(); // When changing the tokens with which the contract interacts, the balance of old tokens must be zero.
    error NotAContract(IERC20, IERC721); //The addresses entered when creating a lot are not contract addresses.
    error NotAERC721(IERC721); //The addresse entered when creating a lot is not implement ERC721.

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
     * @dev Gets the current lot price, delegating its calculation to another function. The lot must not be canceled.
     * @param _lotId Identifier of the lot of interest
     * @return uint256 The current price of the lot (in EDU tokens)
     */
    function getPrice(uint256 _lotId) external view returns(uint256){
        require(_lotId < lotId, LotDoesNotExsist()); // Checking the correctness of the argument
        lotStatus _status = _lotStatus(_lotId);
        require(_status != lotStatus.canceled, LotWasCancelled(_lotId));
        if(_status == lotStatus.sold){
            return lots[_lotId].finalPrice;
        }
        if(_status == lotStatus.expired){
            return _price(_lotId, true);
        }
        else{
            return _price(_lotId, false);
        }
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
        require(_lotId < lotId, LotDoesNotExsist());
        return lots[_lotId];
    }
    /**
     * @param _lotId Identifier of the lot of interest
     * @return string A message explaining the current status of the lot.
     */
    function getLotStatus(uint256 _lotId) external view returns(string memory){
        require(_lotId < lotId, LotDoesNotExsist());
        lotStatus _status = _lotStatus(_lotId);
        if(_status == lotStatus.active) { return "The lot is put up for sale.";}
        else if(_status == lotStatus.sold) { return "The lot was purchased.";}
        else if(_status == lotStatus.canceled) { return "The lot was cancelled.";}
        else { return "Trading time is up.";}
    }

    /**
     * @notice Creates a lot and puts the NFT up for sale. Charges a commission.
     * @dev Adds the created lot to the lots mapping. Transfers the sold NFT and the fee to contract balance.
     * Requires token approval for both NFT and ERC20 tokens.
     * When creating instances, a check is performed to ensure the entered addresses are correct.
     * @param _tokenAddress The address of the token contract in which payment is accepted.
     * @param _NFTAddress The address of the contract implementing the collection of this NFT.
     * @param _usersNFT ID of the NFT listed for sale. Еhe user must own and approve the NFT
     * @param _beginPrice Starting price of the lot (in EDU tokens). Cannot be equal to 0 and Uint256Max
     * @param _discount Price decrease per discount period (in EDU tokens)
     * @param _periodOfDiscount Duration of one discount period (in seconds)
     * @param _timeToEnd Total auction duration (in seconds)
     * @return lotId The identifier of the newly created lot.
     */
    function addLot(address _tokenAddress, address _NFTAddress, uint256 _usersNFT, uint256 _beginPrice, uint256 _discount,
     uint256 _periodOfDiscount, uint256 _timeToEnd) external returns(uint256) {
        (IERC20 _ERC20, IERC721 _ERC721) = _createInstance(_tokenAddress, _NFTAddress);
        require(_ERC721.ownerOf(_usersNFT) == msg.sender, YouDontHaveThisNFT(_usersNFT));
        require(_ERC721.getApproved(_usersNFT) == address(this), NotApproved(_usersNFT));
        //Checking the buyer's approval and balance.
        require(_ERC20.balanceOf(msg.sender) >= addingFee, LackOfFaunds());
        require(_ERC20.allowance(msg.sender, address(this)) >= addingFee, NotApproved(addingFee));

        require(_beginPrice > 0, PriceCantBeZero());
        require(_beginPrice != type(uint256).max, PriceCantBeUint256Max());
        // Checking that the price will not go negative due to an excessive discount.
        require(_timeToEnd/_periodOfDiscount*_discount < _beginPrice, RezultDiscountMoreThenBefinPrice());
        //Change of contract states.
        address adressNull;
        uint256 finalPriceNull;
        Lot memory _lot = Lot(_tokenAddress, _NFTAddress, _usersNFT, msg.sender, _beginPrice, _discount,
         _periodOfDiscount, block.timestamp, _timeToEnd, adressNull, finalPriceNull);
        lots[lotId] = _lot;
        //charging a commission and transferring the NFT to the auction balance
        _ERC20.transferFrom(msg.sender, address(this), addingFee);
        _ERC721.safeTransferFrom(msg.sender, address(this), _usersNFT);
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
     * @param _lotId Identifier of the lot being purchased. The lot must exist and must not actived.
     */
    function buyLot(uint256 _lotId) external{
        require(_lotId < lotId, LotDoesNotExsist());
        require(_lotStatus(_lotId) == lotStatus.active, IncorrectActionForLotStatus(_lotStatus(_lotId), lotStatus.active));
        uint256 finalPriceOfLot = _price(_lotId, false);
        (IERC20 _ERC20, IERC721 _ERC721) = _createInstanceUncheced(lots[_lotId].addressERC20, lots[_lotId].addressERC721);
        //Checking the buyer's approval and balance.
        require(_ERC20.balanceOf(msg.sender) >= fee + finalPriceOfLot, LackOfFaunds());
        require(_ERC20.allowance(msg.sender, address(this)) >= fee + finalPriceOfLot, NotApproved(fee + finalPriceOfLot));
        //Change of contract states.
        lots[_lotId].buyer = msg.sender;
        lots[_lotId].finalPrice = finalPriceOfLot;
        //Charging a commission and payment. Transferring the NFT to the buyer.
        _ERC20.transferFrom(msg.sender, address(this), fee);
        _ERC20.transferFrom(msg.sender, lots[_lotId].lotOwner, finalPriceOfLot);
        _ERC721.safeTransferFrom(address(this), msg.sender, lots[_lotId].lotNFTsID);
        //Сreating a lot purchase event.
        emit LotBought(_lotId, msg.sender, finalPriceOfLot, block.timestamp);
    }
    /**
     * @notice Removes your NFT from sale. Does not refund the commission paid for listing the NFT for sale.
     * @dev Returns the NFT to the owner and makes the lot unavailable for purchase. Emits a lot cancellation event.
     * @param _lotId Identifier of the lot being purchased. The lot must exist and must be actived.
     */
    function cancelLot(uint256 _lotId) external{
        require(_lotId < lotId, LotDoesNotExsist());
        require(_lotStatus(_lotId) == lotStatus.active, IncorrectActionForLotStatus(_lotStatus(_lotId), lotStatus.active));
        require(msg.sender == lots[_lotId].lotOwner, YouAreNotOwner());
        IERC721 _ERC721 = _createInstance721(lots[_lotId].addressERC721);
        //Change of contract states.
        lots[_lotId].beginPrice = type(uint256).max;
        _ERC721.safeTransferFrom(address(this), msg.sender, lots[_lotId].lotNFTsID);
        //Сreating a lot cancel event.
        emit LotCanceled(_lotId, block.timestamp);
    }
    /**
     * @notice Allows you to pick up your NFT if it has not been purchased after the lot time has expired.
     * @dev Returns the NFT to the owner if the lot time has expired
     * @param _lotId Identifier of the lot being purchased. The lot must exist and must be expired.
     */
    function returnNFT(uint256 _lotId) external{
        require(_lotId < lotId, LotDoesNotExsist());
        require(msg.sender == lots[_lotId].lotOwner, YouAreNotOwner());
        require(_lotStatus(_lotId) == lotStatus.expired, IncorrectActionForLotStatus(_lotStatus(_lotId), lotStatus.expired));
        IERC721 _ERC721 = _createInstance721(lots[_lotId].addressERC721);

        _ERC721.safeTransferFrom(address(this), msg.sender, lots[_lotId].lotNFTsID);
    }
    /**
     * @dev Determines the current status of the lot:
     * the starting price is equal to the maximum uint256 - the lot was canceled;
     * the buyer of the lot is not equal to the zero address - the lot was purchased;
     * the set time has expired - the lot has expired;
     * none of the conditions are met - the lot is active.
     * @param _lotId Identifier of the lot of interest
     * @return lotStatus Enam, indicating the current status of the lot.
     */
    function _lotStatus(uint256 _lotId) internal view returns(lotStatus){
        if(lots[_lotId].beginPrice == type(uint256).max){
            return lotStatus.canceled;
        }
        if(lots[_lotId].buyer != address(0)){
            return lotStatus.sold;
        }
        if(block.timestamp - lots[_lotId].timeStemp > lots[_lotId].timeToEnd){
            return lotStatus.expired;
        } 
        return lotStatus.active;
        
    }
    /**
     * @dev Calculates the current price of the lot: 
     * starting price - ((current timestamp - lot creation timestamp) / discount period) * discount per period.
     * If the lot was expired: starting price - discount per period * time to end / discount period (starting price - maximum discount)
     * @param _lotId Identifier of the lot of interest
     * @param _isExpired Information on whether the lot is expired.
     * @return uint256 The current price of the lot (in EDU tokens)
     */
    function _price(uint256 _lotId, bool _isExpired) internal view returns(uint256){
        if (!_isExpired){
            return lots[_lotId].beginPrice - ((block.timestamp - lots[_lotId].timeStemp)/lots[_lotId].periodOfDiscount * lots[_lotId].discount);
        }
        else{
            return lots[_lotId].beginPrice - lots[_lotId].discount * lots[_lotId].timeToEnd / lots[_lotId].periodOfDiscount;
        }
    }
    /**
     * @dev Creates contract instances by performing checks that the addresses are not zero and that they belong to contracts.
     * @param _ERC20address  ERC20 token address.
     * @param _NFTaddress ERC721 token address.
     * @return Contract instances.
     */
    function _createInstance(address _ERC20address, address _NFTaddress) internal view returns(IERC20, IERC721){
        require(_ERC20address != address(0) && _NFTaddress != address(0), AddressCantBeZero());
        (IERC20 _ERC20, IERC721 _ERC721) = _createInstanceUncheced(_ERC20address, _NFTaddress);
        require(address(_ERC20).code.length != 0 && address(_ERC721).code.length != 0, NotAContract(_ERC20, _ERC721));
        return (_ERC20, _ERC721);
    }
    /**
     * @dev Creates contract instances without performing checks.
     * @param _ERC20  ERC20 token address.
     * @param _ERC721 ERC721 token address.
     * @return Contract instances.
     */
    function _createInstanceUncheced(address _ERC20, address _ERC721) internal pure returns(IERC20, IERC721){
        IERC20 erc20Instance = IERC20(_ERC20);
        IERC721 erc721Instance = IERC721(_ERC721);
        return (erc20Instance, erc721Instance);
    }
    /**
     * @dev Creates instances of the ERC721 token contract without performing checks.
     * @param _ERC721Address ERC721 token address.
     * @return Contract instances of the ERC721 token.
     */
    function _createInstance721(address _ERC721Address) internal pure returns(IERC721){
        IERC721 erc721Instance = IERC721(_ERC721Address);
        return erc721Instance;
    }
    /**
     * @dev Creates instances of the ERC20 token contract without performing checks.
     * @param _ERC20Address ERC20 token address.
     * @return Contract instances of the ERC20 token.
     */
    function _createInstance20(address _ERC20Address) internal pure returns(IERC20){
        IERC20 erc20Instance = IERC20(_ERC20Address);
        return erc20Instance;
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
     * @dev Transfers the selected amount of earned commissions in selected token to the owner's address.
     * @param _tokenAddress The address of the token you want to withdraw.
     * @param value Amount to be transferred to the owner's balance.
     * You cannot select 0 or an amount greater than the current contract balance to transfer.
     */
    function wisdrow(address _tokenAddress, uint256 value) external onlyOwner{
        IERC20 _ERC20 = _createInstance20(_tokenAddress);
        require(_ERC20.balanceOf(address(this)) != 0, BalanceIsZero());
        require(_ERC20.balanceOf(address(this)) >= value, LackOfFaunds());
        _ERC20.transfer(owner, value);
    }
    /**
     * @dev Transfers the all of earned commissions in selected token to the owner's address. The contract balance must be greater than 0
     * @param _tokenAddress The address of the token you want to withdraw.
     */
    function wisdrowAll(address _tokenAddress) external onlyOwner{
        IERC20 _ERC20 = _createInstance20(_tokenAddress);
        require(_ERC20.balanceOf(address(this)) != 0, BalanceIsZero());
        _ERC20.transfer(owner, _ERC20.balanceOf(address(this)));
    }
    /**
     * @dev Allows contract to accept safe NFT transfers.
     */
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external pure returns (bytes4){
        return IERC721Receiver.onERC721Received.selector;
    }
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC721Receiver).interfaceId;
    }
}