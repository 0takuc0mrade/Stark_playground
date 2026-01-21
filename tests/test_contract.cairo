use starknet::ContractAddress;
use snforge_std::{declare, ContractClassTrait,DeclareResultTrait, spy_events, start_cheat_caller_address, stop_cheat_caller_address, EventSpyAssertionsTrait, set_balance, Token};
use stark_playground::contributions::{IContributeDispatcher, IContributeDispatcherTrait};
use stark_playground::contributions::Contribute::{Event, campaignCreated, userContributed, userRefunded};
use stark_playground::utils::{stark_address, strk_to_fri};
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

fn user_address() -> ContractAddress {
    'user'.try_into().unwrap()
}

fn deploy_contract() -> IContributeDispatcher {
    let contract = declare("Contribute").unwrap().contract_class();
    let mut constructor_args = array![];

    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let dispatcher = IContributeDispatcher { contract_address };
    dispatcher
}

fn create_campaign() -> (u32, IContributeDispatcher) {
    let dispatcher = deploy_contract();
    let target_amount:u256 = 5;
    dispatcher.create_campaign(target_amount);
    let campaign_count = dispatcher.get_campaign_count();
    (campaign_count, dispatcher)
}

#[test]
fn test_contract_initialization(){
    let dispatcher = deploy_contract();
    let campaign_count = dispatcher.get_campaign_count();
    assert!(campaign_count == 0, "Contract not initialised");
}

#[test]
fn test_create_campaign(){
    let dispatcher = deploy_contract();
    dispatcher.create_campaign(5);
    let campaign_count = dispatcher.get_campaign_count();
    assert!(campaign_count == 1, "Campaign not cretaed");
}

#[test]
fn test_create_campaign_with_event(){
    let dispatcher = deploy_contract();
    let mut spy = spy_events();

    start_cheat_caller_address(dispatcher.contract_address, user_address());
    dispatcher.create_campaign(5);
    stop_cheat_caller_address(dispatcher.contract_address);
    let campaign_count = dispatcher.get_campaign_count();
    let expected_event: campaignCreated = campaignCreated { creator: user_address(), campaign_id: campaign_count };
    spy.assert_emitted(@array![(
        dispatcher.contract_address,
        Event::CampaignCreated(expected_event),
    )])
}

#[test]
#[should_panic(expected: "Insufficient balance")]
fn test_contribute_insufficient_balance(){
    let (campaign_id, dispatcher) = create_campaign();
    let amount: u256 = 3;

    start_cheat_caller_address(dispatcher.contract_address, user_address());
    dispatcher.contribute(campaign_id, amount);
}

#[test]
#[should_panic(expected: "Contract isn't allowed to spend enough STRK")]
fn test_contribute_insufficient_allowance(){
    let (campaign_id, dispatcher) = create_campaign();
    let amount: u256 = 3;
    let contributor = user_address();

    set_balance(contributor, strk_to_fri(7), Token::STRK);
    start_cheat_caller_address(dispatcher.contract_address, contributor);
    dispatcher.contribute(campaign_id, amount);
}

#[test]
fn test_contribute_campaign_open(){
    let (campaign_id, dispatcher) = create_campaign();
    let amount: u256 = 3;
    let contributor = user_address();
    let mut spy = spy_events();

    set_balance(contributor, strk_to_fri(10), Token::STRK);
    let erc20: IERC20Dispatcher = IERC20Dispatcher { contract_address: stark_address() };

    start_cheat_caller_address(erc20.contract_address, contributor);
    erc20.approve(dispatcher.contract_address, strk_to_fri(5));
    stop_cheat_caller_address(erc20.contract_address);

    start_cheat_caller_address(dispatcher.contract_address, contributor);
    dispatcher.contribute(campaign_id, amount);
    stop_cheat_caller_address(dispatcher.contract_address);

    //I used get_contributions() here, safe to say it functions properly
    let campaign_contributions = dispatcher.get_contributions(campaign_id);

    assert!(campaign_contributions == amount, "No contributions made");

    let expected_event = userContributed { user: contributor, campaign_id , amount };

    spy.assert_emitted(@array![(
        dispatcher.contract_address,
        Event::UserContributed(expected_event),
    )]);
}

#[test]
#[should_panic(expected: "Campaign has been closed")]
fn test_contribute_campaign_closed(){
    let (campaign_id, dispatcher) = create_campaign();
    let amount: u256 = 6;
    let contributor = user_address();

    set_balance(contributor, strk_to_fri(10), Token::STRK);
    let erc20: IERC20Dispatcher = IERC20Dispatcher { contract_address: stark_address() };

    start_cheat_caller_address(erc20.contract_address, contributor);
    erc20.approve(dispatcher.contract_address, strk_to_fri(8));
    stop_cheat_caller_address(erc20.contract_address);

    start_cheat_caller_address(dispatcher.contract_address, contributor);
    dispatcher.contribute(campaign_id, amount);
    stop_cheat_caller_address(dispatcher.contract_address);

    let new_amount: u256 = 1;
    //contribute again
    start_cheat_caller_address(dispatcher.contract_address, contributor);
    dispatcher.contribute(campaign_id, new_amount);
    stop_cheat_caller_address(dispatcher.contract_address);
}

#[test]
fn test_get_specific_user_contribution(){
    let (campaign_id, dispatcher) = create_campaign();
    let amount: u256 = 3;
    let contributor = user_address();

    set_balance(contributor, strk_to_fri(10), Token::STRK);
    let erc20: IERC20Dispatcher = IERC20Dispatcher { contract_address: stark_address() };

    start_cheat_caller_address(erc20.contract_address, contributor);
    erc20.approve(dispatcher.contract_address, strk_to_fri(5));
    stop_cheat_caller_address(erc20.contract_address);

    start_cheat_caller_address(dispatcher.contract_address, contributor);
    dispatcher.contribute(campaign_id, amount);


    let user_contributions = dispatcher.get_my_contributions(campaign_id);

    stop_cheat_caller_address(dispatcher.contract_address);

    assert!(user_contributions == amount, "Get contributions failed");
}

#[test]
fn test_refunded_with_events(){
    let (campaign_id, dispatcher) = create_campaign();
    let amount: u256 = 3;
    let contributor = user_address();
    let mut spy = spy_events();

    set_balance(contributor, strk_to_fri(10), Token::STRK);
    let erc20: IERC20Dispatcher = IERC20Dispatcher { contract_address: stark_address() };

    start_cheat_caller_address(erc20.contract_address, contributor);
    erc20.approve(dispatcher.contract_address, strk_to_fri(5));
    stop_cheat_caller_address(erc20.contract_address);

    start_cheat_caller_address(dispatcher.contract_address, contributor);
    dispatcher.contribute(campaign_id, amount);


    let user_contributions = dispatcher.get_my_contributions(campaign_id);

    stop_cheat_caller_address(dispatcher.contract_address);

    assert!(user_contributions == amount, "Get contributions failed");

    //let's refund now
    start_cheat_caller_address(dispatcher.contract_address, contributor);
    dispatcher.refund(campaign_id);

    let new_user_contributions = dispatcher.get_my_contributions(campaign_id);

    stop_cheat_caller_address(dispatcher.contract_address);

    assert!(new_user_contributions == 0, "The refund mechanism failed");

    let expected_events = userRefunded { caller: contributor, campaign_id , amount: user_contributions };

    spy.assert_emitted(@array![(
        dispatcher.contract_address,
        Event::UserRefunded(expected_events),
    )]);
}