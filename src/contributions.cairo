#[starknet::interface]
pub trait IContribute<T>{
    fn create_campaign(ref self: T, target: u256);
    fn contribute(ref self: T, campaign_id: u32, amount: u256);
    fn get_contributions(self: @T, campaign_id: u32) -> u256;
    fn get_my_contributions(self: @T, campaign_id: u32) -> u256;
    fn refund(ref self: T, campaign_id: u32);
}

#[starknet::contract]
pub mod Contribute{
    use starknet::storage::StoragePathEntry;
    use super::IContribute;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::storage::Map;
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use stark_playground::utils::{strk_to_fri, stark_address};


    #[storage]
    struct Storage{
        campaign_count: u32,
        campaigns: Map<u32, CampaignNode>,
    }

    #[starknet::storage_node]
    struct CampaignNode {
        creator: ContractAddress,
        target_amount: u256,
        current_amount: u256,
        is_active: bool,
        contributions: Map<ContractAddress, u256>,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.campaign_count.write(0);
    }

    #[abi(embed_v0)]
    impl ContributeImpl of IContribute<ContractState>{
        fn create_campaign(ref self: ContractState, target: u256){
            let creator = get_caller_address();
            let mut campaign_count = self.campaign_count.read();
            let new_campaign_id = campaign_count + 1;

            let mut campaign = self.campaigns.entry(new_campaign_id);
            campaign.creator.write(creator);
            campaign.target_amount.write(target);
            campaign.current_amount.write(0);
            campaign.is_active.write(true);

            self.campaign_count.write(new_campaign_id);
        }

         fn contribute(ref self: ContractState, campaign_id: u32, amount: u256){
            let strk_amount = strk_to_fri(amount);
            let contributor = get_caller_address();
            let contract = get_contract_address();
            let strk_address = stark_address();
            let dispatch = IERC20Dispatcher { contract_address: strk_address };
            let balance = dispatch.balance_of(contributor);
            assert!(balance >= strk_amount, "Insufficient balance");

            let allowance = dispatch.allowance(contributor, contract);
            assert!(allowance >= strk_amount, "Contract isn't allowed to spend enough STRK");

            let mut campaign = self.campaigns.entry(campaign_id);
            let is_active = campaign.is_active.read();
            assert!(is_active == true, "Campaign has been closed");
            let current_amount = campaign.current_amount.read();
            let updated_amount = current_amount + amount;
            campaign.current_amount.write(updated_amount);
            let current_user_contribution = campaign.contributions.entry(contributor).read();
            let user_contribution = current_user_contribution + amount;
            campaign.contributions.entry(contributor).write(user_contribution);

            let success = dispatch.transfer_from(contributor, contract, strk_amount);
            assert!(success, "unsuccessful transfer");
         }

         fn get_contributions(self: @ContractState, campaign_id: u32) -> u256 {
            let mut campaign = self.campaigns.entry(campaign_id);
            let total_contributed = campaign.current_amount.read();
            total_contributed
         }

         fn get_my_contributions(self: @ContractState, campaign_id: u32) -> u256 {
            let user = get_caller_address();
            let mut campaign = self.campaigns.entry(campaign_id);
            let total_contributed = campaign.contributions.entry(user).read();
            total_contributed
         }

         fn refund(ref self: ContractState, campaign_id: u32){
            let mut campaign = self.campaigns.entry(campaign_id);
            let user = get_caller_address();
            let user_balance = campaign.contributions.entry(user).read();
            let strk_amount = strk_to_fri(user_balance);

            //let contract = get_contract_address();
            let strk_address = stark_address();
            let dispatch = IERC20Dispatcher { contract_address: strk_address };
            // let balance = dispatch.balance_of(user);
            // assert!(balance >= strk_amount, "Insufficient balance");

            let campaign_balance = campaign.current_amount.read();
            assert!(user_balance != 0, "You have been refunded");
            campaign.contributions.entry(user).write(0);
            campaign_balance - user_balance;

            let success = dispatch.transfer(user, strk_amount);
            assert!(success, "unsuccessful transfer");
         }
    }
}