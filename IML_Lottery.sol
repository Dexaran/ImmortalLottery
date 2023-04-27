// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";

abstract contract Entropy_interface {
    function get_entropy() public virtual view returns (uint256);
    function new_round() virtual external;
    function deposit_entropy_reward() external virtual payable;
    function get_entropy_collateral() public view virtual returns (uint256);
}

contract Lottery {
    event NewRound(uint256 indexed round_id);
    event RoundFinished(uint256 indexed round_id, address indexed winner, uint256 reward);
    event Deposit(address indexed depositor, uint256 amount_deposited, uint256 amount_credited);
    event Refund(address indexed receiver, uint256 indexed round_id, uint256 amount);

    address public owner = msg.sender;
    address payable public entropy_contract;
    address payable public reward_pool_contract; // Token rewards go to the special "staking contract"
    
    //uint256 public deposits_phase_duration = 3 days; // The length of a phase when deposits are accepted;
    //uint256 public entropy_phase_duration  = 1 days; // The length of a phase when entropy providers reveal their entropy inputs;
    uint256 public deposits_phase_duration = 10 minutes;
    uint256 public entropy_phase_duration  = 5 minutes;

    uint256 public entropy_fee          = 30;   // (will be divided by 1000 during calculations i.e. 1 means 0.1%) | this reward goes to the entropy providers reward pool
    // 30 is 3%
    uint256 public token_reward_fee     = 100;  // This reward goes to staked tokens reward pool
    // 100 is 10%
    
    uint256 public min_allowed_bet      = 1000 ether; // 1K CLO for now
    uint8   public max_allowed_deposits = 20;          // A user can make 20 bets during a single round
    
    uint256 public current_round;
    uint256 public round_start_timestamp;
    uint256 public round_reward;
    bool    public round_reward_paid = false;
    
    mapping (uint256 => bool) public round_successful; // Allows "refunds" of not succesful rounds.
    
    uint256 public current_interval_end; // Used for winner calculations
    
    struct interval
    {
        uint256 interval_start;
        uint256 interval_end;
    }
    
    struct player
    {
        mapping (uint256 => uint8)   num_deposits;
        uint256 last_round;
        mapping (uint256 => mapping (uint8 => interval)) win_conditions; // This player is considered to be a winner when RNG provides a number that matches this intervals
        mapping (uint256 => bool)    round_refunded;
    }
    
    mapping (address => player) public players;
    
    receive() external payable
    {
        if(get_phase() == 0)
        {
            start_new_round();
        }
        else if(get_phase() == 1)
        {
            deposit();
        }
        else
        {
            revert();
        }
    }
    
    function get_round() public view returns (uint256)
    {
        return current_round;
    }

    function get_win_conditions(address _player, uint256 _round, uint8 _depoindex) public view returns(uint256 _start, uint256 _end)
    {
        _start = players[_player].win_conditions[_round][_depoindex].interval_start;
        _end   = players[_player].win_conditions[_round][_depoindex].interval_end;
    }

    function is_winner(address _user) public view returns (bool)
    {
        bool winner = false;

        for (uint8 i = 0; i <= players[_user].num_deposits[current_round]; i++)
        {
            if(players[_user].win_conditions[current_round][i].interval_start < RNG() && players[_user].win_conditions[current_round][i].interval_end > RNG())
            {
                winner = true;
            }
        }
        return winner;
    }
    
    function get_phase() public view returns (uint8)
    {
        // 0 - the lottery is not active                      / pending reward claim or new round start
        // 1 - a lottery round is in progress                 / acquiring deposits
        // 2 - deposits are acquired                          / entropy revealing phase
        // 3 - entropy is revealed, but winner is not paid    / it is the time to pay the winner
        // 4 - round is finished and the winner is paid       / anyone can start a new round
        
        uint8 _status = 0;
        if(round_start_timestamp <= block.timestamp && block.timestamp <= round_start_timestamp + deposits_phase_duration)
        {
            _status = 1;
        }
        else if (round_start_timestamp < block.timestamp && block.timestamp < round_start_timestamp + deposits_phase_duration + entropy_phase_duration)
        {
            _status = 2;
        }
        else if (round_start_timestamp < block.timestamp && block.timestamp > round_start_timestamp + deposits_phase_duration + entropy_phase_duration && !round_reward_paid)
        {
            _status = 3;
        }
        /*
        else if (round_start_timestamp < block.timestamp && block.timestamp > round_start_timestamp + deposits_phase_duration + entropy_phase_duration && round_reward_paid)
        {
            _status = 4;
        }
        */
        
        return _status;
    }
    
    function deposit() public payable
    {
        require (msg.value >= min_allowed_bet, "Minimum bet condition is not met");
        require (players[msg.sender].num_deposits[current_round] < max_allowed_deposits || players[msg.sender].last_round < current_round, "Too much deposits during this round");
        require (get_phase() == 1, "Deposits are only allowed during the depositing phase");
        
        if(players[msg.sender].last_round < current_round)
        {
            players[msg.sender].last_round   = current_round;
            players[msg.sender].num_deposits[current_round] = 0;
        }
        else
        {
            players[msg.sender].num_deposits[current_round]++;
        }
        
        // Assign the "winning interval" for the player
        players[msg.sender].win_conditions[current_round][players[msg.sender].num_deposits[current_round]].interval_start = current_interval_end;
        players[msg.sender].win_conditions[current_round][players[msg.sender].num_deposits[current_round]].interval_end   = current_interval_end + msg.value;
        current_interval_end += msg.value;
        
        uint256 _reward_after_fees = msg.value;

        
        // TODO: replace it with SafeMath
        // TODO: update the contract to only send rewards upon completion of the round
        send_token_reward(msg.value * token_reward_fee / 1000);
        _reward_after_fees -= (msg.value * token_reward_fee / 1000);
        
        
        send_entropy_reward(msg.value * entropy_fee / 1000);
        _reward_after_fees -= msg.value * entropy_fee / 1000;
        
        round_reward += _reward_after_fees;

        emit Deposit(msg.sender, msg.value, _reward_after_fees);
    }
    
    function refund(uint256 _round) external
    {
        require(current_round > _round, "Only refunds of finished rounds are allowed");
        require(!round_successful[_round], "Only refunds of FAILED rounds are allowed");
        
        // Calculating the refund amount
        uint256 _reward = 0;
        for (uint8 i = 0; i < players[msg.sender].num_deposits[_round]; i++)
        {
            _reward += players[msg.sender].win_conditions[_round][i].interval_end - players[msg.sender].win_conditions[_round][i].interval_start;
        }
        
        // Subtract the entropy fee
        _reward -= _reward * entropy_fee / 1000;
        
        players[msg.sender].round_refunded[_round] = true;
        payable(msg.sender).transfer(_reward);

        emit Refund(msg.sender, _round, _reward);
    }
    
    function send_entropy_reward(uint256 _reward) internal
    {
        //entropy_contract.transfer(msg.value * entropy_fee / 1000);
        //entropy_contract.transfer(_reward);

        Entropy_interface(entropy_contract).deposit_entropy_reward{value: _reward}();
    }
    
    function send_token_reward(uint256 _reward) internal
    {
        //reward_pool_contract.transfer(msg.value * token_reward_fee / 1000);
        //reward_pool_contract.transfer(_reward);
        reward_pool_contract.call{value: _reward};
    }
    
    function start_new_round() public payable
    {
        require(current_round == 0 || round_reward_paid, "Cannot start a new round while reward for the previous one is not paid. Call finish_round function");
        
        current_round++;

        emit NewRound(current_round);

        round_start_timestamp = block.timestamp;
        current_interval_end  = 0;
        round_reward_paid     = false;
        
        Entropy_interface(entropy_contract).new_round();
        
        //require_entropy_provider(msg.sender); // Request the starter of a new round to also provide initial entropy
        
        // Initiate the first deposit of the round
        deposit();
    }
    
    function finish_round(address payable _winner) public
    {
        // Important: finishing an active round does not automatically start a new one
        require(block.timestamp > round_start_timestamp + deposits_phase_duration + entropy_phase_duration, "Round can be finished after the entropy reveal phase only");
        
        
        //require(check_entropy_criteria(), "There is not enough entropy to ensure a fair winner calculation");
        
        if(check_entropy_criteria())
        {
            // Round is succsefully completed and there was enough entropy provided
            round_successful[current_round] = true;
            
            // Paying the winner
            // Safe loop, cannot be more than 20 iterations
            for (uint8 i = 0; i <= players[_winner].num_deposits[current_round]; i++)
            {
                if(players[_winner].win_conditions[current_round][i].interval_start < RNG() && players[_winner].win_conditions[current_round][i].interval_end > RNG())
                {
                    _winner.transfer(round_reward);
                    round_reward_paid = true;
                }
            }

            emit RoundFinished(current_round, _winner, round_reward);
        }
        else
        {
            // Round is completed without sufficient entropy => allow refunds and increase the round counter
            // round_successful[current_round] = false; // This values are `false` by default in solidity
            
            round_reward_paid = true;

            emit RoundFinished(current_round, address(0), 0);
        }
        
        require(round_reward_paid, "The provided address is not a winner of the current round");
    }
    
    function pay_fees() internal
    {
        
    }
    
    function RNG() public view returns (uint256)
    {
        // Primitive random number generator dependant on both `entropy` and `interval` for testing reasons
        uint256 _entropy = Entropy_interface(entropy_contract).get_entropy();
        uint256 _timestamp = round_start_timestamp + deposits_phase_duration + entropy_phase_duration;
        uint256 _result;

        assembly
        {
            _entropy := mul(_entropy, 115792089237316195423570985008687907853269984665640564039457584007913129639935)
            _entropy := mul(_entropy, _timestamp)
        }
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
        //return true;

        return Entropy_interface(entropy_contract).get_entropy_collateral() > 0;
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

    function set_entropy_contract(address payable _new_contract) public only_owner
    {
        entropy_contract = _new_contract;
    }

    function set_reward_contract(address payable _new_contract) public only_owner
    {
        reward_pool_contract = _new_contract;
    }

    function rescueERC20(address token, address to) external only_owner {
        uint256 value = IERC20(token).balanceOf(address(this));
        IERC20(token).transfer(to, value);
    }

    function configure(uint256 _min_bet, uint8 _max_deposits, uint256 _deposit_phase_duration, uint256 _reveal_phase_duration) public only_owner
    {
        min_allowed_bet = _min_bet;
        max_allowed_deposits = _max_deposits;
        deposits_phase_duration = _deposit_phase_duration;
        entropy_phase_duration  = _reveal_phase_duration;
    }

    function configureFees(uint256 _entropy_fee, uint256 _token_reward_fee) public only_owner
    {
        entropy_fee = _entropy_fee;
        token_reward_fee = _token_reward_fee;
    }
}
