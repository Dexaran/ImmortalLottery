// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";

abstract contract Lottery_interface {
    function get_round() public view virtual returns (uint256);
    function get_phase() public view virtual returns (uint8); // 0 - inactive / 1 - deposits phase and entropy collecting / 2 - entropy reveal phase
}

contract Entropy {
    address public owner = msg.sender;
    address public lottery_contract;
    
    struct provider
    {
        uint256 round;
        bytes32 entropy_hash;
    }
    
    uint256 public collateral_threshold = 100000 ether;     // Collateral for one entropy submission
    mapping (bytes32=>bool) public prohibited_hashes;       // A mapping of already used entropy submissions
    mapping (address=>provider) public entropy_providers;   // A mapping of active entropy submissions of the round
    
    uint256 public entropy_reward = 0;                  // Collected entropy reward for the current round
    
    uint256 public entropy = 0;                         // A number used as entropy input for the main Lottery Contract
    uint256 public current_round = 0;
    uint256 public num_providers = 0;                   // The number of entropy providers for the current round
    
    receive() external payable
    {
        deposit_entropy_reward();
    }

    fallback() external payable
    {
        deposit_entropy_reward();
    }
    
    function get_entropy() public view returns (uint256)
    {
        return entropy;
    }
    
    function deposit_entropy_reward() public payable 
    {
        entropy_reward += msg.value;
    }
    
    function new_round() public only_lottery_contract
    {
        entropy_reward = address(this).balance; // All unrevealed entropy collaterals are now next round rewards
        current_round  = Lottery_interface(lottery_contract).get_round(); // Update the round
        num_providers  = 0;
    }
    
    function submit_entropy(bytes32 _entropy_hash) public payable 
    {
        require(msg.value == collateral_threshold, "Collateral amount is incorrect");
        require(!prohibited_hashes[_entropy_hash], "This entropy input was already used previously");
        require(entropy_providers[msg.sender].round < current_round, "This address is already an entropy provider in this round");
        require(Lottery_interface(lottery_contract).get_phase() == 1, "Entropy submissions are only allowed during the depositing lottery phase");
        
        prohibited_hashes[_entropy_hash] = true; // Mark this hash as "already used" to prevent its future uses
        
        entropy_providers[msg.sender].round = current_round;
        entropy_providers[msg.sender].entropy_hash = _entropy_hash;
        
        num_providers++;
    }
    
    function reveal_entropy(uint256 _entropy_payload, uint256 _salt) public
    {
        require(entropy_providers[msg.sender].round == current_round, "The address is trying to reveal the entropy for inappropriate round");
        require(sha256(abi.encodePacked(_entropy_payload, _salt)) == entropy_providers[msg.sender].entropy_hash, "Entropy values do not match the provided hash");
        // require(Lottery_interface(lottery_contract).get_phase() == 2, "Entropy reveals are only allowed during the reveal phase");
        entropy += _entropy_payload;
        payable(msg.sender).transfer(collateral_threshold + (entropy_reward / num_providers));
    }
    
    function test_hash(uint256 _entropy_payload, uint256 _salt) pure public returns (bytes32)
    {
        return sha256(abi.encodePacked(_entropy_payload, _salt));
    }
    
    
    modifier only_owner
    {
        require(msg.sender == owner);
        _;
    }
    
    modifier only_lottery_contract
    {
        require(msg.sender == lottery_contract);
        _;
    }

    function set_lottery_contract(address payable _new_contract) public only_owner
    {
        lottery_contract = _new_contract;
    }

    function rescueERC20(address token, address to) external only_owner {
        uint256 value = IERC20(token).balanceOf(address(this));
        IERC20(token).transfer(to, value);
    }
}
