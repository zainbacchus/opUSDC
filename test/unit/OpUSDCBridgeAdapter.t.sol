// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {OpUSDCBridgeAdapter} from 'contracts/universal/OpUSDCBridgeAdapter.sol';
import {Test} from 'forge-std/Test.sol';

contract ForTestOpUSDCBridgeAdapter is OpUSDCBridgeAdapter {
  constructor(
    address _usdc,
    address _messenger,
    address _linkedAdapter
  ) OpUSDCBridgeAdapter(_usdc, _messenger, _linkedAdapter) {}

  function sendMessage(uint256 _amount, uint32 _minGasLimit) external override {}

  function receiveMessage(address _user, uint256 _amount) external override {}
}

abstract contract Base is Test {
  ForTestOpUSDCBridgeAdapter public adapter;

  address internal _usdc = makeAddr('opUSDC');
  address internal _messenger = makeAddr('messenger');
  address internal _linkedAdapter = makeAddr('linkedAdapter');

  function setUp() public virtual {
    adapter = new ForTestOpUSDCBridgeAdapter(_usdc, _messenger, _linkedAdapter);
  }
}

contract UnitInitialization is Base {
  function testInitialization() public {
    assertEq(adapter.USDC(), _usdc, 'USDC should be set to the provided address');
    assertEq(adapter.MESSENGER(), _messenger, 'Messenger should be set to the provided address');
    assertEq(adapter.LINKED_ADAPTER(), _linkedAdapter, 'Linked adapter should be set to the provided address');
  }
}
