// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract EducationToken is IERC20Metadata{
    mapping (address => uint256) private _balance;
    mapping (address => mapping(address => uint256)) private _approwals;
    uint256 private _totalSupply;
    string private _name;
    string private _symbol;
    uint8 private constant _decimals = 18;
    address private owner;

    error addressCantBeZero();
    error luckOfFunds(uint256, uint256);
    error ownerDontApproveThisAmount(uint256, uint256);
    error approveToYourself();
    error thisFunctionForSpender(string);
    error onlyForOwner(address);

    modifier onlyOwner {
        require(msg.sender == owner, onlyForOwner(owner));
        _;
    }

    event Mint(address indexed recepient, uint256 value);
    event Burn(uint256 indexed value);

    constructor(string memory names, string memory symbols){
        _name = names;
        _symbol = symbols;
        _balance[msg.sender] = 10000;
        _totalSupply = 10000;
        owner = msg.sender;
    }
  
    function name() external view returns (string memory){
        return _name;
    }
    function symbol() external view returns (string memory){
        return _symbol;
    }
    function decimals() external pure returns (uint8){
        return _decimals;
    }
    function getOwner() external view returns(address){
        return owner;
    }
    function totalSupply() external view returns(uint256){
        return _totalSupply;
    }
    function balanceOf(address _user) external view returns(uint256){
        require(_user != address(0), addressCantBeZero());
        return _balance[_user];
    }
    function allowance(address _owner, address _spender) external view returns(uint256){
        require(_owner != address(0) && _spender != address(0), addressCantBeZero());
        return _approwals[_owner][_spender];
    }

    function transfer(address _to, uint256 _value) external returns(bool){
        require(_to != address(0), addressCantBeZero());
        require(_balance[msg.sender] >= _value, luckOfFunds(_balance[msg.sender], _value));
        _transfer(msg.sender, _to, _value);
        return true;
    }
    function approve(address _spender, uint256 _value) external returns(bool){
        require(_spender != address(0), addressCantBeZero());
        require(msg.sender != _spender, approveToYourself());
        _approve(msg.sender, _spender, _value, true);
        return true;
    }
    function transferFrom(address _from, address _to, uint256 _value) external returns(bool){
        require(_from != address(0) && _to != address(0), addressCantBeZero());
        require(msg.sender != _from, thisFunctionForSpender("Using transact"));
        require(_balance[_from] >= _value, luckOfFunds(_balance[_from], _value));
        require(_approwals[_from][msg.sender] >= _value, ownerDontApproveThisAmount(_value, _approwals[_from][msg.sender]));
        if(_approwals[_from][msg.sender] != type(uint256).max){
            _approve(_from, msg.sender, _approwals[_from][msg.sender] - _value, false);
        }
        _transfer(_from, _to, _value);
        return true;
    }
    function mint(address _recipient, uint256 _value) external onlyOwner returns(bool){
        require(_recipient != address(0), addressCantBeZero());
        _transfer(address(0), _recipient, _value);
        return true;
    }
    function burn(uint256 _value) external onlyOwner returns(bool){
        require(_balance[msg.sender] >= _value, luckOfFunds(_balance[msg.sender], _value));
        _transfer(msg.sender, address(0), _value);
        return true;
    }

    function _transfer(address _from, address _to, uint256 _value) internal{
        if (_from == address(0)){ //mint
            _totalSupply += _value;
            _balance[_to] += _value;
            emit Mint(_to,_value);
        }
        else if (_to == address(0)){//burn
            _totalSupply -= _value;
            _balance[_from] -= _value;
            emit Burn(_value);
        }
        else {
            _balance[_from] -= _value;
            _balance[_to] += _value;
            emit Transfer(_from, _to, _value);
        } 
    }
    function _approve(address _owner, address _spender, uint256 _value, bool _emitEvent) internal{
        if (_emitEvent){
            emit Approval(_owner, _spender, _value);
            _updateApprove(_owner, _spender, _value);
        }
        else {
            _updateApprove(_owner, _spender, _value);
        }
    }
    function _updateApprove(address _owner, address _spender, uint256 _value) internal{
        _approwals[_owner][_spender] = _value;
    }
}