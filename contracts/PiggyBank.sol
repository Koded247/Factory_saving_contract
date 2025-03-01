
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PiggyBank is Ownable {
    address public immutable USDT_ADDRESS;
    address public immutable USDC_ADDRESS;
    address public immutable DAI_ADDRESS;
    address public immutable developer; 

    string public savingsPurpose;
    uint256 public duration; 
    uint256 public startTime;
    bool public isWithdrawn; 

    mapping(address => mapping(address => uint256)) public savings; 
    mapping(address => uint256) public totalTokenDeposits; 

    uint256 constant PENALTY_FEE = 15; 

    event Deposited(address indexed user, address indexed token, uint256 amount);
    event Withdrawn(address indexed user, address indexed token, uint256 amount, bool withPenalty);

    constructor(
        address _usdt,
        address _usdc,
        address _dai,
        address _developer,
        string memory _purpose,
        uint256 _duration,
        address _owner
    ) Ownable(_owner) {  
        USDT_ADDRESS = _usdt;
        USDC_ADDRESS = _usdc;
        DAI_ADDRESS = _dai;
        developer = _developer;
        savingsPurpose = _purpose;
        duration = _duration;
        startTime = block.timestamp;
        isWithdrawn = false;
    }

    modifier onlyAllowedToken(address _token) {
        require(
            _token == USDT_ADDRESS || _token == USDC_ADDRESS || _token == DAI_ADDRESS,
            "Only USDT, USDC, or DAI allowed"
        );
        _;
    }

    modifier notWithdrawn() {
        require(!isWithdrawn, "PiggyBank is already withdrawn");
        _;
    }

    function deposit(address _token, uint256 _amount) external onlyAllowedToken(_token) notWithdrawn onlyOwner {
        require(_amount > 0, "Amount must be greater than 0");

        address _owner = owner();

        IERC20 token = IERC20(_token);
        require(token.transferFrom(_owner, address(this), _amount), "Transfer failed");

        savings[_owner][_token] += _amount;
        totalTokenDeposits[_token] += _amount;

        emit Deposited(_owner, _token, _amount);
    }

    function withdraw(address _token, uint256 _amount) external onlyAllowedToken(_token) notWithdrawn onlyOwner {

        address _owner = owner();

        require(_amount > 0, "Amount must be greater than 0");
        require(savings[_owner][_token] >= _amount, "Insufficient balance");

        bool isMature = block.timestamp >= startTime + duration;
        IERC20 token = IERC20(_token);
        uint256 amountToSend = _amount;

        if (!isMature) {
           
            uint256 penalty = (_amount * PENALTY_FEE) / 100;
            amountToSend = _amount - penalty;
            require(token.transfer(developer, penalty), "Penalty transfer failed");
        }

        savings[_owner][_token] -= _amount;
        totalTokenDeposits[_token] -= _amount;
        require(token.transfer(_owner, amountToSend), "Withdrawal failed");

       
        if (totalTokenDeposits[USDT_ADDRESS] == 0 &&
            totalTokenDeposits[USDC_ADDRESS] == 0 &&
            totalTokenDeposits[DAI_ADDRESS] == 0) {
            isWithdrawn = true;
        }

        emit Withdrawn(_owner, _token, amountToSend, !isMature);
    }

    function getBalance(address _user, address _token) external view onlyAllowedToken(_token) returns (uint256) {
        return savings[_user][_token];
    }

    function timeLeft() external view returns (uint256) {
        if (block.timestamp >= startTime + duration) return 0;
        return (startTime + duration) - block.timestamp;
    }
}







