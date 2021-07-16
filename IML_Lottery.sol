// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.5.1;

contract Entropy_interface {
    function get_entropy() public view returns (uint256);
}

contract Lottery {
    address public owner = msg.sender;
    address payable public entropy_contract;
    address payable public reward_pool_contract; // Token rewards go to the special "staking contract"
    
    uint256 public deposits_phase_duration = 3 days; // The length of a phase when deposits are accepted;
    uint256 public entropy_phase_duration  = 1 days; // The length of a phase when entropy providers reveal their entropy inputs;
    
    uint256 public entropy_fee          = 30;   // (will be divided by 1000 during calculations i.e. 1 means 0.1%) | this reward goes to the entropy providers reward pool
    uint256 public token_reward_fee     = 100;  // This reward goes to staked tokens reward pool
    
    uint256 public min_allowed_bet      = 1000 ether; // 1K CLO for now
    uint8   public max_allowed_deposits = 20;          // A user can make 20 bets during a single round
    
    uint256 public current_round;
    uint256 public round_start_timestamp;
    uint256 public round_reward;
    bool    public round_reward_paid = false;
    
    uint256 public current_interval_end; // Used for winner calculations
    
    struct interval
    {
        uint256 interval_start;
        uint256 interval_end;
    }
    
    struct player
    {
        uint8   num_deposits;
        uint256 last_round;
        mapping (uint8 => interval) win_conditions; // This player is considered to be a winner when RNG provides a number that matches this intervals
    }
    
    mapping (address => player) public players;
    
    function get_round() public view returns (uint256)
    {
        return current_round;
    }
    
    function get_phase() public view returns (uint8)
    {
        // 0 - the lottery is not active     / pending reward claim or new round start
        // 1 - a lottery round is in progress/ acquiring deposits
        // 2 - deposits are acquired         / entropy revealing phase
        
        uint8 _status = 0;
        if(round_start_timestamp < now && now < round_start_timestamp + deposits_phase_duration)
        {
            _status = 1;
        }
        else if (round_start_timestamp < now && now < round_start_timestamp + deposits_phase_duration + entropy_phase_duration)
        {
            _status = 2;
        }
        
        return _status;
    }
    
    function deposit() public payable
    {
        require (msg.value > min_allowed_bet, "Minimum bet condition is not met");
        require (players[msg.sender].num_deposits < max_allowed_deposits || players[msg.sender].last_round < current_round, "Too much deposits during this round");
        require (get_phase() == 1, "Deposits are only allowed during the depositing phase");
        
        if(players[msg.sender].last_round < current_round)
        {
            players[msg.sender].last_round   = current_round;
            players[msg.sender].num_deposits = 0;
        }
        else
        {
            players[msg.sender].num_deposits++;
        }
        
        // Assign the "winning interval" for the player
        players[msg.sender].win_conditions[players[msg.sender].num_deposits].interval_start = current_interval_end;
        players[msg.sender].win_conditions[players[msg.sender].num_deposits].interval_end   = current_interval_end + msg.value;
        current_interval_end += msg.value;
        
        uint256 _reward_with_fees = msg.value;
        
        // TODO: replace it with SafeMath
        send_token_reward(msg.value * token_reward_fee / 1000);
        _reward_with_fees -= msg.value * token_reward_fee / 1000;
        
        send_entropy_reward(msg.value * entropy_fee / 1000);
        _reward_with_fees -= msg.value * entropy_fee / 1000;
        
        round_reward += _reward_with_fees;
    }
    
    function send_entropy_reward(uint256 _reward) internal
    {
        //entropy_contract.transfer(msg.value * entropy_fee / 1000);
        
        entropy_contract.transfer(_reward);
    }
    
    function send_token_reward(uint256 _reward) internal
    {
        //reward_pool_contract.transfer(msg.value * token_reward_fee / 1000);
        reward_pool_contract.transfer(_reward);
    }
    
    function start_new_round() public payable
    {
        require(current_round == 0 || round_reward_paid, "Cannot start a new round while reward for the previous one is not paid. Call finish_round function");
        
        round_start_timestamp = now;
        current_interval_end  = 0;
        round_reward_paid     = false;
        
        //require_entropy_provider(msg.sender); // Request the starter of a new round to also provide initial entropy
        
        // Initiate the first deposit of the round
        deposit();
    }
    
    function finish_round(address payable _winner) public
    {
        // Important: finishing an active round does not automatically start a new one
        require(now > round_start_timestamp + deposits_phase_duration + entropy_phase_duration, "Round can be finished after the entropy reveal phase only");
        require(check_entropy_criteria(), "There is not enough entropy to ensure a fair winner calculation");
        
        // Safe loop, cannot be more than 20 iterations
        for (uint8 i=0; i<players[_winner].num_deposits; i++)
        {
            if(players[_winner].win_conditions[i].interval_start < RNG() && players[_winner].win_conditions[i].interval_end > RNG())
            {
                _winner.transfer(round_reward);
                round_reward_paid = true;
            }
        }
        
        require(round_reward_paid, "The provided address is not a winner of the current round");
    }
    
    function RNG() public view returns (uint256)
    {
        // Primitive random number generator dependant on both `entropy` and `interval` for testing reasons
        uint256 _entropy = Entropy_interface(entropy_contract).get_entropy();
        uint256 _result;
        // `entropy` is a random value; can be greater or less than `current_interval_end`
        
        if(_entropy > current_interval_end)
        {
            _result = _entropy % current_interval_end;
        }
        else
        {
            _result = current_interval_end % _entropy;
        }
        
        return _result;
    }
    
    function check_entropy_criteria() public returns (bool)
    {
        // Needs to check the sufficiency of entropy for the round reward prizepool size
        return true;
    }
    
    modifier only_owner
    {
        require(msg.sender == owner);
        _;
    }
    
    modifier only_entropy_contract
    {
        require(msg.sender == entropy_contract);
        _;
    }
}
