use starknet::ContractAddress;

pub fn strk_to_fri(mut amount: u256) -> u256 {
    const decimals: u8 = 18;
    let mut i: u8 = 0;

    while i != decimals {
        amount = amount * 10;
        i = i + 1;
    };
    amount
}

pub fn stark_address() -> ContractAddress{
    0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d.try_into().unwrap()
}