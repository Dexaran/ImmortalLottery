// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.5.1;

/**
 * @title Storage
 * @dev Store & retrieve value in a variable
 */
contract AirdropSignup {
    address public owner = msg.sender;
    
    mapping (uint256=>string) networks;
    mapping (uint256=>bool)   network_exists;
    
    mapping (address=>mapping (uint256=>string)) registries;
    
    function addNetwork(uint256 _id, string memory _network_name) public only_owner
    {
        require(!network_exists[_id]);
        network_exists[_id] = true;
        networks[_id] = _network_name;
    }
    
    function removeNetwork(uint256 _id) public only_owner
    {
        require(network_exists[_id]);
        networks[_id] = "";
        network_exists[_id] = false;
    }
    
    function assignAddress(uint256 _network_id, string memory _address) public
    {
        require(network_exists[_network_id]);
        registries[msg.sender][_network_id] = _address;
    }
    
    modifier only_owner
    {
        require(msg.sender == owner);
        _;
    }
}
