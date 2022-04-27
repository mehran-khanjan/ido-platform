// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./SelfStarterV2.sol";

contract LaunchpadFactory is Ownable, ReentrancyGuard {
    string public version = "v0.0";
    bool public whitelistEnforced;
    mapping (address => bool) public whitelistedOperators;

    // owner => launchpads[]
    mapping (address => address[]) public launchpads;
    //launchpad => launch timestamp
    mapping (address => uint256) public launchIndex;
    // launchpad => owner
    mapping (address => address) public operator;

    event LaunchpadDeployed(address indexed launchpadAddress, address indexed creator);

    constructor(string memory _version) {
        version = _version;
    }
}