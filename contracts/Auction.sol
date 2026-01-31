//SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import "./MyToken.sol";
import "./MyNFT.sol";
import  "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract Auction is IERC721Receiver{
    EducationToken contractEDU;
    NFTsLot lotNFTContract;
    //owner's address
    address public owner;
    //lot storage
    mapping(uint256 => Lot) public lots;
    //commission when adding lot
    uint256 public addingFee;
    //commission when purchasing a lot
    uint256 public fee;
    
    uint256 internal lotId;

    struct Lot{
        uint256 lotNFTsID;
        address lotOwner;
        uint256 beginPrice;
        uint256 discount;
        uint256 periodOfDiscount;
        uint256 timeStemp;
        uint256 timeToEnd;
        address buyer;
        uint256 finalPrice;
    }

    error PriceCantBeZero();
    error FeeCantBeZero();
    error RezultDiscountMoreThenBefinPrice();
    error LotDoesNotExsist();
    error LotIsEnd();
    error BalanceIsZero();
    error LackOfFaunds();
    error YouAreNotOwner();
    error YouDontHaveThisNFT(uint256);
    error NotApproved();

    event LotAdded(uint256 indexed lotId, address lotOwner, uint256 indexed beginPrice, uint256 timeStemp);
    event LotBought(uint256 indexed lotId, address buyer, uint256 indexed finalPrice, uint256 timeStemp);

    modifier onlyOwner {
        require(msg.sender == owner, YouAreNotOwner());
        _;
    }

    constructor (uint256 _fee, uint256 _addingFee){
        require(_fee!=0 && _addingFee!=0, FeeCantBeZero());
        owner = msg.sender;
        addingFee = _addingFee; 
        fee = _fee; 
    }
    
    function getFee() public view returns(uint256){
        return fee;
    }
    function getOwner() public view returns(address){
        return owner;
    }
    function getAddingFee() public view returns(uint256){
        return addingFee;
    }
    function getCurrentPrice(uint256 _lotId) public view returns(uint256){
        require(_lotId <= lotId, LotDoesNotExsist());
        require(lots[_lotId].buyer == address(0), LotIsEnd());
        return lots[_lotId].beginPrice - ((block.timestamp - lots[_lotId].timeStemp)/lots[_lotId].periodOfDiscount * lots[_lotId].discount);
    }

    function getAuctionNumber() public view returns(uint256){
        return lotId;
    }
    function getLot(uint256 _lotId) public view returns(Lot memory){
        require(_lotId <= lotId, LotDoesNotExsist());
        return lots[_lotId];
    }

    function addLot(uint256 _usersNFT, uint256 _beginPrice, uint256 _discount, uint256 _periodOfDiscount, uint256 _timeToEnd) external returns(uint256) {
        require(lotNFTContract.ownerOf(_usersNFT) == msg.sender, YouDontHaveThisNFT(_usersNFT));
        require(lotNFTContract.getApproved(_usersNFT) == address(this), NotApproved());

        require(contractEDU.balanceOf(msg.sender) >= addingFee, LackOfFaunds());
        require(contractEDU.allowance(msg.sender, address(this)) >= addingFee, NotApproved());

        require(_beginPrice > 0, PriceCantBeZero());
        require(_timeToEnd/_periodOfDiscount*_discount < _beginPrice, RezultDiscountMoreThenBefinPrice());

        contractEDU.transferFrom(msg.sender, address(this), addingFee);
        lotNFTContract.safeTransferFrom(msg.sender, address(this), _usersNFT);

        address adressNull;
        uint256 finalPriceNull;
        Lot memory _lot = Lot(_usersNFT, msg.sender, _beginPrice, _discount, _periodOfDiscount, block.timestamp, _timeToEnd, adressNull, finalPriceNull);
        lots[lotId] = _lot;

        emit LotAdded(lotId, msg.sender, _beginPrice, block.timestamp);
        lotId++;

        return lotId - 1;
    }
    
    function lotIsEnd(uint256 _lotId) internal view returns(bool){
        return block.timestamp - lots[_lotId].timeStemp > lots[_lotId].timeToEnd || lots[_lotId].buyer != address(0);
    }


    function buyLot(uint256 _lotId) external{
        require(_lotId <= lotId, LotDoesNotExsist());
        require(!lotIsEnd(_lotId), LotIsEnd());
        uint256 finalPriceOfLot = getCurrentPrice(_lotId);

        require(contractEDU.balanceOf(msg.sender) >= fee + finalPriceOfLot, LackOfFaunds());
        require(contractEDU.allowance(msg.sender, address(this)) >= fee + finalPriceOfLot, NotApproved());

        contractEDU.transferFrom(msg.sender, address(this), fee);
        contractEDU.transferFrom(msg.sender, lots[_lotId].lotOwner, finalPriceOfLot);

        lots[_lotId].buyer = msg.sender;
        lots[_lotId].finalPrice = finalPriceOfLot;

        lotNFTContract.safeTransferFrom(address(this), msg.sender, lots[_lotId].lotNFTsID);

        emit LotBought(_lotId, msg.sender, finalPriceOfLot, block.timestamp);
    }

    function setFee(uint256 newFee) external onlyOwner{
        require(newFee!=0, FeeCantBeZero());
        fee = newFee;
    }
    function setAddingFee(uint256 newFee) external onlyOwner{
        require(newFee!=0, FeeCantBeZero());
        addingFee = newFee;
    }

    function wisdrow(uint256 value) external onlyOwner{
        require(contractEDU.balanceOf(address(this)) != 0, BalanceIsZero());
        require(contractEDU.balanceOf(address(this)) >= value, LackOfFaunds());
        contractEDU.transfer(owner, value);
    }
    function wisdrowAll() external onlyOwner{
        require(contractEDU.balanceOf(address(this)) != 0, BalanceIsZero());
        contractEDU.transfer(owner, contractEDU.balanceOf(address(this)));
    }

    function setTokensAddress(address _EDU, address _NFT) external onlyOwner{
        contractEDU = EducationToken(_EDU);
        lotNFTContract = NFTsLot(_NFT);
    }
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external pure returns (bytes4){
        return IERC721Receiver.onERC721Received.selector;
    }
}