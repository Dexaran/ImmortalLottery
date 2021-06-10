// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.5.1;

/**
 * @title Storage
 * @dev Store & retrieve value in a variable
 */
contract Signup {
    address public owner = msg.sender;
    
    event NetworkAdded(string _network_name, uint256 _network_id);
    event NetworkRemoved(string _network_name, uint256 _network_id);
    
    mapping (uint256=>string) networks;
    mapping (uint256=>bool)   network_exists;
    
    mapping (address=>mapping (uint256=>string)) registries;
    
    function addNetwork(uint256 _id, string memory _network_name) public only_owner
    {
        require(!network_exists[_id]);
        network_exists[_id] = true;
        networks[_id] = _network_name;
        
        emit NetworkAdded(_network_name, _id);
    }
    
    function removeNetwork(uint256 _id) public only_owner
    {
        require(network_exists[_id]);
        emit NetworkRemoved( networks[_id], _id);
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
