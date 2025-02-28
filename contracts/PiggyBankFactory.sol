// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./PiggyBank.sol";

contract PiggyBankFactory {
    address public immutable USDT_ADDRESS;
    address public immutable USDC_ADDRESS;
    address public immutable DAI_ADDRESS;
    address public immutable developer;

    mapping(address => address[]) public userPiggyBanks; // user => array of piggybank addresses
    event PiggyBankCreated(address indexed creator, address piggyBank, string purpose);

    constructor(
        address _usdt,
        address _usdc,
        address _dai,
        address _developer
    ) {
        USDT_ADDRESS = _usdt;
        USDC_ADDRESS = _usdc;
        DAI_ADDRESS = _dai;
        developer = _developer;
    }

    // Deploy using CREATE2
    function createPiggyBankWithCreate2(string memory _purpose, uint256 _duration, bytes32 _salt)
        external
        returns (address)
    {
        address piggyBankAddr = address(
            new PiggyBank{salt: _salt}(
                USDT_ADDRESS,
                USDC_ADDRESS,
                DAI_ADDRESS,
                developer,
                _purpose,
                _duration
            )
        );

        userPiggyBanks[msg.sender].push(piggyBankAddr);
        emit PiggyBankCreated(msg.sender, piggyBankAddr, _purpose);
        return piggyBankAddr;
    }

    // Deploy using regular 'new' keyword
    function createPiggyBank(string memory _purpose, uint256 _duration) external returns (address) {
        PiggyBank piggyBank = new PiggyBank(
            USDT_ADDRESS,
            USDC_ADDRESS,
            DAI_ADDRESS,
            developer,
            _purpose,
            _duration
        );

        address piggyBankAddr = address(piggyBank);
        userPiggyBanks[msg.sender].push(piggyBankAddr);
        emit PiggyBankCreated(msg.sender, piggyBankAddr, _purpose);
        return piggyBankAddr;
    }

    function getUserPiggyBanks(address _user) external view returns (address[] memory) {
        return userPiggyBanks[_user];
    }

    // Predict CREATE2 address (optional utility)
    function predictAddress(string memory _purpose, uint256 _duration, bytes32 _salt)
        public
        view
        returns (address)
    {
        bytes memory bytecode = abi.encodePacked(
            type(PiggyBank).creationCode,
            abi.encode(USDT_ADDRESS, USDC_ADDRESS, DAI_ADDRESS, developer, _purpose, _duration)
        );
        bytes32 hash = keccak256(
            abi.encodePacked(bytes1(0xff), address(this), _salt, keccak256(bytecode))
        );
        return address(uint160(uint256(hash)));
    }
}