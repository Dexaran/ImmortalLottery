# Immortal Lottery

This repo will hold source codes of the Immortal Lottery Project.

If you have any feedback or questions - feel free to create a [new issue](https://github.com/Dexaran/ImmortalLottery/issues/new) in this repo. We will use issues as the main thread for Immortal Lottery communications at this stage.

## Deployment

- Entropy: 0x857803da626177C946012461382685d323201F32
- Lottery (mainnet CLO; 1 hour deposit; 1 hour reveal phase): 0xE5412b4420f69A5509e2bE93A5AEA0F666EEF20E

## Deploying custom lottery

1. Compile & deploy the [Lottery contract](https://github.com/Dexaran/ImmortalLottery/blob/main/IML_Lottery.sol).
2. Compile & deploy the [Entropy contract](https://github.com/Dexaran/ImmortalLottery/blob/main/IML_Entropy.sol).
3. Call the [configure](https://github.com/Dexaran/ImmortalLottery/blob/main/IML_Lottery.sol#L346) function of the Lottery contract and set the (1) min deposit amount in WEI, (2) maximum amount of deposits allowed from one account (recommended 2 to 5 - higher value causes higher GAS during winner calculation), (3) duration of the deposit phase in seconds, (4) duration of the reveal phase in seconds.
4. Call the set_entropy_contract() function of the Lottery contract and connect it with the Entropy contract address.
5. Call the set_lottery_contract() function of the Entropy contract and connect it with the Lottery contract address.



## Testnet deployment

Signup contract: 0xbCa749885f7A75C7777a9F111f2820F6a3a5bE72
