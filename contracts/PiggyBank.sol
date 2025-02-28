
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PiggyBank is Ownable {
    address public immutable USDT_ADDRESS;
    address public immutable USDC_ADDRESS;
    address public immutable DAI_ADDRESS;
    address public immutable developer; // Where penalty fees go

    string public savingsPurpose;
    uint256 public duration; // In seconds
    uint256 public startTime;
    bool public isWithdrawn; // Tracks if funds are withdrawn

    mapping(address => mapping(address => uint256)) public savings; // user => token => amount
    mapping(address => uint256) public totalTokenDeposits; // token => total

    uint256 constant PENALTY_FEE = 15; // 15% penalty for early withdrawal

    event Deposited(address indexed user, address indexed token, uint256 amount);
    event Withdrawn(address indexed user, address indexed token, uint256 amount, bool withPenalty);

    constructor(
        address _usdt,
        address _usdc,
        address _dai,
        address _developer,
        string memory _purpose,
        uint256 _duration
    ) Ownable(msg.sender) {  // Explicitly call Ownable constructor with msg.sender
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

    function deposit(address _token, uint256 _amount) external onlyAllowedToken(_token) notWithdrawn {
        require(_amount > 0, "Amount must be greater than 0");

        IERC20 token = IERC20(_token);
        require(token.transferFrom(msg.sender, address(this), _amount), "Transfer failed");

        savings[msg.sender][_token] += _amount;
        totalTokenDeposits[_token] += _amount;

        emit Deposited(msg.sender, _token, _amount);
    }

    function withdraw(address _token, uint256 _amount) external onlyAllowedToken(_token) notWithdrawn {
        require(_amount > 0, "Amount must be greater than 0");
        require(savings[msg.sender][_token] >= _amount, "Insufficient balance");

        bool isMature = block.timestamp >= startTime + duration;
        IERC20 token = IERC20(_token);
        uint256 amountToSend = _amount;

        if (!isMature) {
            // Apply 15% penalty if withdrawing early
            uint256 penalty = (_amount * PENALTY_FEE) / 100;
            amountToSend = _amount - penalty;
            require(token.transfer(developer, penalty), "Penalty transfer failed");
        }

        savings[msg.sender][_token] -= _amount;
        totalTokenDeposits[_token] -= _amount;
        require(token.transfer(msg.sender, amountToSend), "Withdrawal failed");

        // If all funds are withdrawn, halt the contract
        if (totalTokenDeposits[USDT_ADDRESS] == 0 &&
            totalTokenDeposits[USDC_ADDRESS] == 0 &&
            totalTokenDeposits[DAI_ADDRESS] == 0) {
            isWithdrawn = true;
        }

        emit Withdrawn(msg.sender, _token, amountToSend, !isMature);
    }

    function getBalance(address _user, address _token) external view onlyAllowedToken(_token) returns (uint256) {
        return savings[_user][_token];
    }

    function timeLeft() external view returns (uint256) {
        if (block.timestamp >= startTime + duration) return 0;
        return (startTime + duration) - block.timestamp;
    }
}







