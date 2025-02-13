// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {SetupOpUSDC} from './SetupOpUSDC.sol';
import {MessageHashUtils} from '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';
import {USDCInitTxs} from 'contracts/utils/USDCInitTxs.sol';
import {IL1OpUSDCBridgeAdapter} from 'interfaces/IL1OpUSDCBridgeAdapter.sol';
import {IL1OpUSDCFactory} from 'interfaces/IL1OpUSDCFactory.sol';
import {USDC_IMPLEMENTATION_CREATION_CODE} from 'script/utils/USDCImplementationCreationCode.sol';

//solhint-disable custom-errors
//solhint-disable ordering
//solhint-disable reason-string
//solhint-disable max-line-length
contract OpUsdcTest is SetupOpUSDC {
  using MessageHashUtils for bytes32;
  /////////////////////////////////////////////////////////////////////
  //                         Ghost variables                         //
  /////////////////////////////////////////////////////////////////////

  uint256 internal _ghost_L1PreviousUserNonce;
  uint256 internal _ghost_L1CurrentUserNonce;
  bool internal _ghost_hasBeenDeprecatedBefore; // Track if setBurnAmount has been called once before
  bool internal _ghost_ownerAndAdminTransferred; // Track if the ownership has been transferred once before
  bool internal _ghost_bridgedUSDCProxyUpgraded; // Track if the bridged USDC proxy has been upgraded once before
  mapping(address => bool) internal _ghost_l2AdapterDeployed;
  mapping(address => bool) internal _ghost_l2FactoryDeployed;

  /////////////////////////////////////////////////////////////////////
  //                           Properties                            //
  /////////////////////////////////////////////////////////////////////

  /// @custom:property-id 0
  /// @custom:property deployment test
  function fuzz_testDeployments() public view {
    assert(l2Adapter.LINKED_ADAPTER() == address(l1Adapter));
    assert(l2Adapter.MESSENGER() == address(mockMessenger));
    assert(l2Adapter.USDC() == address(usdcBridged));

    assert(l1Adapter.LINKED_ADAPTER() == address(l2Adapter));
    assert(l1Adapter.MESSENGER() == address(mockMessenger));
    assert(l1Adapter.USDC() == address(usdcMainnet));
  }

  /// @custom:property-id 1
  /// @custom:property New messages should not be sent if the state is not active
  /// @custom:property-id 2
  /// @custom:property User who bridges tokens should receive them on the destination chain
  function fuzz_noMessageIfNotActiveL1(address _to, uint256 _amount, uint32 _minGasLimit) public agentOrDeployer {
    // Precondition
    require(!(_to == address(0) || _to == address(usdcMainnet) || _to == address(usdcBridged)));

    _amount = _boundAmountToMint(_to, _amount);

    _dealAndApproveUSDC(_currentCaller, _amount);

    uint256 _fromBalanceBefore = usdcMainnet.balanceOf(_currentCaller);
    uint256 _toBalanceBefore = usdcBridged.balanceOf(_to);
    uint256 _initialNonce = l1Adapter.userNonce(_currentCaller);

    hevm.prank(_currentCaller);
    // Action
    try l1Adapter.sendMessage(_to, _amount, _minGasLimit) {
      // Postcondition
      assert(l1Adapter.messengerStatus() == IL1OpUSDCBridgeAdapter.Status.Active);
      assert(usdcMainnet.balanceOf(_currentCaller) == _fromBalanceBefore - _amount);
      assert(usdcBridged.balanceOf(_to) == _toBalanceBefore + _amount);

      _ghost_L1PreviousUserNonce = _initialNonce;
      _ghost_L1CurrentUserNonce = l1Adapter.userNonce(_currentCaller);
    } catch {
      // can fail either because of wrong xdom msg sender or because of the status, but xdom sender is constrained in precond
      assert(l1Adapter.messengerStatus() != IL1OpUSDCBridgeAdapter.Status.Active);
      assert(usdcMainnet.balanceOf(_currentCaller) == _fromBalanceBefore);
    }
  }

  /// @custom:property-id 1
  /// @custom:property New messages should not be sent if the state is not active
  /// @custom:property-id 2
  /// @custom:property User who bridges tokens should receive them on the destination chain
  function fuzz_noSignedMessageIfNotActiveL1(
    address _to,
    uint256 _privateKey,
    uint256 _amount,
    uint32 _minGasLimit
  ) public {
    // Precondition
    require(_privateKey != 0);
    require(!(_to == address(0) || _to == address(usdcMainnet) || _to == address(usdcBridged)));

    _amount = _boundAmountToMint(_to, _amount);

    // create valid signature
    address _signer = hevm.addr(_privateKey);
    uint256 _nonce = l1Adapter.userNonce(_signer);
    uint256 _deadline = block.timestamp + 1 days;
    bytes memory _signature =
      _generateSignature(_to, _amount, _deadline, _nonce, _signer, _privateKey, address(l1Adapter));

    _dealAndApproveUSDC(_signer, _amount);

    uint256 _fromBalanceBefore = usdcMainnet.balanceOf(_signer);
    uint256 _toBalanceBefore = usdcBridged.balanceOf(_to);
    uint256 _initialNonce = l1Adapter.userNonce(_currentCaller);

    hevm.prank(_currentCaller);

    // Action
    try l1Adapter.sendMessage(_signer, _to, _amount, _signature, _deadline, _minGasLimit) {
      // Postcondition
      assert(l1Adapter.messengerStatus() == IL1OpUSDCBridgeAdapter.Status.Active);
      assert(usdcMainnet.balanceOf(_signer) == _fromBalanceBefore - _amount);
      assert(usdcBridged.balanceOf(_to) == _toBalanceBefore + _amount);

      _ghost_L1PreviousUserNonce = _initialNonce;
      _ghost_L1CurrentUserNonce = l1Adapter.userNonce(_currentCaller);
    } catch {
      // can fail either because of wrong xdom msg sender or because of the status, but xdom sender is constrained in precond
      assert(l1Adapter.messengerStatus() != IL1OpUSDCBridgeAdapter.Status.Active);
      assert(usdcMainnet.balanceOf(_signer) == _fromBalanceBefore);
    }
  }

  /// @custom:property-id 1
  /// @custom:property New messages should not be sent if the state is not active
  /// @custom:property-id 2
  /// @custom:property User who bridges tokens should receive them on the destination chain
  function fuzz_noMessageIfNotActiveL2(address _to, uint256 _amount, uint32 _minGasLimit) public agentOrDeployer {
    // Preconditions
    require(!(_to == address(0) || _to == address(usdcMainnet) || _to == address(usdcBridged)));

    _amount = _boundAmountToMint(_to, _amount);

    _dealAndApproveBridgedUSDC(_currentCaller, _amount, _minGasLimit);

    uint256 _fromBalanceBefore = usdcBridged.balanceOf(_currentCaller);
    uint256 _toBalanceBefore = usdcMainnet.balanceOf(_to);

    hevm.prank(_currentCaller);

    // Action
    try l2Adapter.sendMessage(_to, _amount, _minGasLimit) {
      // Postcondition
      assert(!l2Adapter.isMessagingDisabled());
      assert(usdcBridged.balanceOf(_currentCaller) == _fromBalanceBefore - _amount);
      if (_to == address(l1Adapter)) assert(usdcMainnet.balanceOf(_to) == _toBalanceBefore);
      else assert(usdcMainnet.balanceOf(_to) == _toBalanceBefore + _amount);
    } catch {
      // can fail either because of wrong xdom msg sender or because of the status, but xdom sender is constrained in precond
      assert(l2Adapter.isMessagingDisabled());
      assert(usdcBridged.balanceOf(_currentCaller) == _fromBalanceBefore);
    }
  }

  /// @custom:property-id 1
  /// @custom:property New messages should not be sent if the state is not active
  /// @custom:property-id 2
  /// @custom:property User who bridges tokens should receive them on the destination chain
  function fuzz_noSignedMessageIfNotActiveL2(
    address _to,
    uint256 _privateKey,
    uint256 _amount,
    uint32 _minGasLimit
  ) public {
    // Preconditions
    require(_privateKey != 0);
    require(!(_to == address(0) || _to == address(usdcMainnet) || _to == address(usdcBridged)));

    _amount = _boundAmountToMint(_to, _amount);

    address _signer = hevm.addr(_privateKey);
    uint256 _nonce = l2Adapter.userNonce(_signer);
    uint256 _deadline = block.timestamp + 1 days;
    bytes memory _signature =
      _generateSignature(_to, _amount, _deadline, _nonce, _signer, _privateKey, address(l2Adapter));

    _dealAndApproveBridgedUSDC(_signer, _amount, _minGasLimit);

    uint256 _fromBalanceBefore = usdcBridged.balanceOf(_signer);
    uint256 _toBalanceBefore = usdcMainnet.balanceOf(_to);

    hevm.prank(_currentCaller);
    // Action
    try l2Adapter.sendMessage(_signer, _to, _amount, _signature, _deadline, _minGasLimit) {
      // Postcondition
      assert(!l2Adapter.isMessagingDisabled());
      assert(usdcBridged.balanceOf(_signer) == _fromBalanceBefore - _amount);
      if (_to == address(l1Adapter)) assert(usdcMainnet.balanceOf(_to) == _toBalanceBefore);
      else assert(usdcMainnet.balanceOf(_to) == _toBalanceBefore + _amount);
    } catch {
      // can fail either because of wrong xdom msg sender or because of the status, but xdom sender is constrained in precond
      assert(l2Adapter.isMessagingDisabled());
      assert(usdcBridged.balanceOf(_signer) == _fromBalanceBefore);
    }
  }

  /// @custom:property-id 5
  /// @custom:property user nonce should be monotonically increasing
  function fuzz_L1NonceIncremental() public view {
    if (_ghost_L1CurrentUserNonce == 0) {
      assert(l1Adapter.userNonce(_currentCaller) == 0);
    } else {
      assert(_ghost_L1PreviousUserNonce == _ghost_L1CurrentUserNonce - 1);
    }
  }

  /// @custom:property-id 6
  /// @custom:property Locked USDC on L1adapter should be able to be burned only if L1 adapter is deprecated
  function fuzz_BurnLockedUSDC() public {
    // Enable l1 adapter to burn locked usdc
    hevm.prank(usdcMainnet.masterMinter());
    usdcMainnet.configureMinter(address(l1Adapter), type(uint256).max);

    require(l1Adapter.messengerStatus() == IL1OpUSDCBridgeAdapter.Status.Deprecated);

    uint256 _currentBalance = usdcMainnet.balanceOf(address(l1Adapter));
    uint256 _burnAmount = l1Adapter.burnAmount();
    uint256 _expectedBalance = _burnAmount > _currentBalance ? 0 : _currentBalance - _burnAmount;

    hevm.prank(l1Adapter.burnCaller());
    // 6
    try l1Adapter.burnLockedUSDC() {
      assert(l1Adapter.messengerStatus() == IL1OpUSDCBridgeAdapter.Status.Deprecated);
      assert(usdcMainnet.balanceOf(address(l1Adapter)) == _expectedBalance);
    } catch {
      assert(false);
    }
  }

  /// @custom:property-id 7
  /// @custom:property Status pause should be able to be set only by the owner and through the correct function
  function fuzz_PauseMessaging(uint32 _minGasLimit) public agentOrDeployer {
    // Precondition
    IL1OpUSDCBridgeAdapter.Status _previousL1Status = l1Adapter.messengerStatus();

    hevm.prank(_currentCaller);
    // Action
    // 7
    try l1Adapter.stopMessaging(_minGasLimit) {
      // Post condition
      assert(_currentCaller == l1Adapter.owner());
      assert(
        _previousL1Status == IL1OpUSDCBridgeAdapter.Status.Active
          || _previousL1Status == IL1OpUSDCBridgeAdapter.Status.Paused
      );
      assert(l1Adapter.messengerStatus() == IL1OpUSDCBridgeAdapter.Status.Paused);
    } catch {
      assert(
        l1Adapter.messengerStatus() != IL1OpUSDCBridgeAdapter.Status.Active
          || l1Adapter.messengerStatus() != IL1OpUSDCBridgeAdapter.Status.Paused || _currentCaller != l1Adapter.owner()
      );
    }
  }

  /// @custom:property-id 8
  /// @custom:property Resume should be able to be set only by the owner and through the correct function
  function fuzz_ResumeMessaging(uint32 _minGasLimit) public agentOrDeployer {
    IL1OpUSDCBridgeAdapter.Status _previousL1Status = l1Adapter.messengerStatus();

    hevm.prank(_currentCaller);
    // 8
    try l1Adapter.resumeMessaging(_minGasLimit) {
      assert(_currentCaller == l1Adapter.owner());
      assert(
        _previousL1Status == IL1OpUSDCBridgeAdapter.Status.Active
          || _previousL1Status == IL1OpUSDCBridgeAdapter.Status.Paused
      );
      assert(l1Adapter.messengerStatus() == IL1OpUSDCBridgeAdapter.Status.Active);
    } catch {
      assert(
        l1Adapter.messengerStatus() != IL1OpUSDCBridgeAdapter.Status.Active
          || l1Adapter.messengerStatus() != IL1OpUSDCBridgeAdapter.Status.Paused || _currentCaller != l1Adapter.owner()
      );
    }
  }

  /// @custom:property-id 9
  /// @custom:property Set burn only if migrating  9
  function fuzz_setBurnAmount() public {
    // Precondition
    uint256 _previousBurnAmount = l1Adapter.burnAmount();
    uint256 _l2totalSupply = usdcBridged.totalSupply();
    IL1OpUSDCBridgeAdapter.Status _previousState = l1Adapter.messengerStatus();

    hevm.prank(l1Adapter.MESSENGER());
    // Action
    // 9
    try l1Adapter.setBurnAmount(_l2totalSupply) {
      //Precontion
      assert(_previousState == IL1OpUSDCBridgeAdapter.Status.Upgrading);
      // Postcondition
      assert(l1Adapter.messengerStatus() == IL1OpUSDCBridgeAdapter.Status.Deprecated);
      assert(l1Adapter.burnAmount() == _l2totalSupply);
      _ghost_hasBeenDeprecatedBefore = true;
    } catch {
      assert(l1Adapter.burnAmount() == _previousBurnAmount);
    }
  }

  /// @custom:property-id 10
  /// @custom:property Deprecated state should be irreversible
  function fuzz_deprecatedIrreversible() public view {
    // If the l1 adapter has been deprecated once before, it cannot have any other status ever again
    if (_ghost_hasBeenDeprecatedBefore) assert(l1Adapter.messengerStatus() == IL1OpUSDCBridgeAdapter.Status.Deprecated);
  }

  /// @custom:property-id 11
  /// @custom:property Upgrading state only via migrate to native, should be callable multiple times (msg fails)
  function fuzz_migrateToNativeMultipleCall(address _burnCaller, address _roleCaller) public {
    // Precondition
    // Insure we haven't started the migration or we only initiated/is pending in the bridge
    require(
      l1Adapter.messengerStatus() == IL1OpUSDCBridgeAdapter.Status.Active
        || l1Adapter.messengerStatus() == IL1OpUSDCBridgeAdapter.Status.Upgrading
    );

    require(_burnCaller != address(0) && _roleCaller != address(0));

    // As the bridge would relay and execute the migration atomically, including deprecating l1adapter, we need to prevent
    // it from relaying the message to test this property
    mockMessenger.pauseMessaging();

    // Action
    // 11
    try l1Adapter.migrateToNative(_burnCaller, _roleCaller, 0, 0) {
      assert(l1Adapter.messengerStatus() == IL1OpUSDCBridgeAdapter.Status.Upgrading);
    } catch {}

    // try calling a second time
    try l1Adapter.migrateToNative(_burnCaller, _roleCaller, 0, 0) {}
    catch {
      assert(false);
    }
  }

  /// @custom:property-id 12
  /// @custom:property Can receive USDC even if the state is not active
  function fuzz_receiveMessageIfNotActiveL1(address _to, uint256 _amount) public agentOrDeployer {
    // Precondition
    require(_to != address(0) && _to != address(usdcMainnet) && _to != address(usdcBridged));
    require(l1Adapter.messengerStatus() != IL1OpUSDCBridgeAdapter.Status.Active);

    _amount = _boundAmountToMint(_to, _amount);

    // provided enough usdc on l1
    hevm.prank(_usdcMinter);
    usdcMainnet.mint(address(l1Adapter), _amount);

    // Set L2Adapter as the sender on L2
    mockMessenger.setDomainMessageSender(address(l2Adapter));

    // cache balance
    uint256 _toBalanceBefore = usdcMainnet.balanceOf(_to);

    hevm.prank(l1Adapter.MESSENGER());
    // Action
    try l1Adapter.receiveMessage(_to, _amount) {
      // Postcondition
      if (_to == address(l1Adapter)) assert(usdcMainnet.balanceOf(_to) == _toBalanceBefore);
      else assert(usdcMainnet.balanceOf(_to) == _toBalanceBefore + _amount);
    } catch {
      assert(usdcMainnet.balanceOf(_to) == _toBalanceBefore);
    }
  }

  /// @custom:property-id 12
  /// @custom:property Can receive USDC even if the state is not active
  function fuzz_receiveMessageIfNotActiveL2(address _to, uint256 _amount) public agentOrDeployer {
    // Precondition
    require(_to != address(0) && _to != address(usdcMainnet) && _to != address(usdcBridged));
    require(l2Adapter.isMessagingDisabled());

    _amount = clamp(_amount, 0, usdcBridged.balanceOf(_to) - 2 ** 255 - 1 - _amount);

    // Set L1 Adapter as sender
    mockMessenger.setDomainMessageSender(address(l1Adapter));

    // cache balance
    uint256 _toBalanceBefore = usdcBridged.balanceOf(_to);

    hevm.prank(l2Adapter.MESSENGER());
    // Action
    try l2Adapter.receiveMessage(_to, _amount) {
      // Postcondition
      assert(usdcBridged.balanceOf(_to) == _toBalanceBefore + _amount);
    } catch {
      assert(usdcBridged.balanceOf(_to) == _toBalanceBefore);
    }
  }

  /// @custom:property-id 13
  /// @custom:property Bridged USDC Proxy should only be upgradeable through the L2 Adapter
  function fuzz_proxyUpgradeOnlyThroughL2() public agentOrDeployer {
    // Precondition
    require(l1Adapter.messengerStatus() != IL1OpUSDCBridgeAdapter.Status.Deprecated);
    // Get the current implementation of the bridged USDC proxy
    address _currentImplementation =
      address(uint160(uint256(hevm.load(address(usdcBridged), keccak256('org.zeppelinos.proxy.implementation')))));
    // Action
    if (!_ghost_bridgedUSDCProxyUpgraded) {
      assert(usdcBridgedImplementation == _currentImplementation);
    }
  }

  /// @custom:property-id 14
  /// @custom:property Incoming successful messages should only come from the linked adapter's
  function fuzz_l1LinkedAdapterIncommingMessages(uint8 _selectorIndex, uint256 _amount, address _address) public {
    _selectorIndex = _selectorIndex % 2;
    hevm.prank(l1Adapter.MESSENGER());
    if (_selectorIndex == 0) {
      require(usdcMainnet.balanceOf(address(l1Adapter)) >= _amount);
      try l1Adapter.receiveMessage(_address, _amount) {
        // Mint tokens to L1 adapter to keep the balance consistent
        hevm.prank(_usdcMinter);
        usdcMainnet.mint(address(l1Adapter), _amount);
        assert(mockMessenger.xDomainMessageSender() == address(l2Adapter));
      } catch {}
    } else {
      try l1Adapter.setBurnAmount(usdcBridged.totalSupply()) {
        // This will deprecate the adapter
        _ghost_hasBeenDeprecatedBefore = true;
        assert(mockMessenger.xDomainMessageSender() == address(l2Adapter));
      } catch {}
    }
  }

  /// @custom:property-id 14
  /// @custom:property Incoming successful messages should only come from the linked adapter's
  function fuzz_l2LinkedAdapterIncommingMessages(uint8 _selectorIndex, uint256 _amount, address _address) public {
    _selectorIndex = _selectorIndex % 3;

    hevm.prank(l2Adapter.MESSENGER());
    if (_selectorIndex == 0) {
      try l2Adapter.receiveMessage(_address, _amount) {
        // Mint tokens to L1 adapter to keep the balance consistent
        hevm.prank(_usdcMinter);
        usdcMainnet.mint(address(l1Adapter), _amount);
        assert(mockMessenger.xDomainMessageSender() == address(l1Adapter));
      } catch {}
    } else if (_selectorIndex == 1) {
      require(l1Adapter.messengerStatus() == IL1OpUSDCBridgeAdapter.Status.Upgrading);
      try l2Adapter.receiveMigrateToNative(_address, 0) {
        assert(mockMessenger.xDomainMessageSender() == address(l1Adapter));
      } catch {}
    } else if (_selectorIndex == 2) {
      try l2Adapter.receiveStopMessaging() {
        assert(mockMessenger.xDomainMessageSender() == address(l1Adapter));
      } catch {}
    } else {
      try l2Adapter.receiveResumeMessaging() {
        assert(mockMessenger.xDomainMessageSender() == address(l1Adapter));
      } catch {}
    }
  }

  /// @custom:property-id 15
  /// @custom:property Any chain should be able to have as many protocols deployed without the factory blocking deployments
  /// @custom:property-id 16
  /// @custom:property Protocols deployed on one L2 should never have a matching address with a protocol on a different L2
  function fuzz_factoryNeverFailsToDeploy() public agentOrDeployer {
    bytes[] memory usdcInitTxns = new bytes[](3);
    usdcInitTxns[0] = USDCInitTxs.INITIALIZEV2;
    usdcInitTxns[1] = USDCInitTxs.INITIALIZEV2_1;
    usdcInitTxns[2] = USDCInitTxs.INITIALIZEV2_2;

    IL1OpUSDCFactory.L2Deployments memory _l2Deployments =
      IL1OpUSDCFactory.L2Deployments(address(this), USDC_IMPLEMENTATION_CREATION_CODE, usdcInitTxns, 3_000_000);

    try factory.deploy(address(mockMessenger), _currentCaller, _l2Deployments) returns (
      address, address _l2Factory, address _l2Adapter
    ) {
      // Postcondition
      // 16 - no matching address on different L2
      assert(!_ghost_l2AdapterDeployed[_l2Adapter]);
      assert(!_ghost_l2FactoryDeployed[_l2Factory]);

      _ghost_l2AdapterDeployed[_l2Adapter] = true;
      _ghost_l2FactoryDeployed[_l2Factory] = true;
    } catch {
      // 15
      assert(false);
    }
  }

  /// @custom:property-id 17
  /// @custom:property USDC proxy admin and token ownership rights on l2 can only be transferred after the migration to native flow
  function fuzz_onlyMigrateToNativeForOwnershipTransfer(address _newOwner) public {
    address _roleCaller = l2Adapter.roleCaller();
    // Precondition
    //Insure the adapter has received the migration to native message
    require(_roleCaller != address(0));
    //Insura that the new owner is not the zero address, transfer ownership to the zero address is not allowed
    require(
      _newOwner != address(0) && _newOwner != usdcBridged.owner() && l2Adapter.roleCaller() != usdcBridged.admin()
    );

    hevm.prank(_roleCaller);
    // Action
    try l2Adapter.transferUSDCRoles(_newOwner) {
      // 17
      // Postcondition
      assert(usdcBridged.owner() == _newOwner);
      assert(usdcBridged.admin() == _roleCaller);
    } catch {}
  }

  /// @custom:property-id 18
  /// @custom:property Status should either be active, paused, upgrading or deprecated
  function fuzz_correctStatus() public view {
    assert(
      l1Adapter.messengerStatus() == IL1OpUSDCBridgeAdapter.Status.Active
        || l1Adapter.messengerStatus() == IL1OpUSDCBridgeAdapter.Status.Paused
        || l1Adapter.messengerStatus() == IL1OpUSDCBridgeAdapter.Status.Upgrading
        || l1Adapter.messengerStatus() == IL1OpUSDCBridgeAdapter.Status.Deprecated
    );
  }

  /////////////////////////////////////////////////////////////////////
  //                Expose target contract selectors                 //
  /////////////////////////////////////////////////////////////////////

  // Expose all selectors from the adapter, pranked and with ghost variables if needed
  // Caller is one of the _agents (incl the deployer/initial owner)
  function generateCallAdapterL1(
    uint256 _selectorIndex,
    address _addressA,
    address _addressB,
    uint256 _uintA,
    uint256 _uintB,
    uint32 _uint32A,
    uint32 _uint32B
  ) public agentOrDeployer {
    _selectorIndex = _selectorIndex % 8;

    require(_uintB != 0);
    address _signerAd = hevm.addr(_uintB);
    uint256 _nonce = l1Adapter.userNonce(_signerAd);
    uint256 _deadline = block.timestamp + 1 days;
    bytes memory _signature =
      _generateSignature(_addressB, _uintA, _deadline, _nonce, _signerAd, _uintB, address(l1Adapter));

    hevm.prank(_currentCaller);

    if (_selectorIndex == 0) {
      // Do not revert on the transferFrom call
      _uintA = _boundAmountToMint(_currentCaller, _uintA);
      hevm.prank(_usdcMinter);
      usdcMainnet.mint(_currentCaller, _uintA);

      hevm.prank(_currentCaller);
      usdcMainnet.approve(address(l1Adapter), _uintA);

      // Do not make assumption on nonce logic here, just collect them
      uint256 _initialNonce = l1Adapter.userNonce(_currentCaller);

      hevm.prank(_currentCaller);
      try l1Adapter.sendMessage(_addressA, _uintA, _uint32A) {
        _ghost_L1PreviousUserNonce = _initialNonce;
        _ghost_L1CurrentUserNonce = l1Adapter.userNonce(_currentCaller);
      } catch {}
    } else if (_selectorIndex == 1) {
      uint256 _initialNonce = l1Adapter.userNonce(_currentCaller);

      try l1Adapter.sendMessage(_signerAd, _addressB, _uintA, _signature, _deadline, _uint32A) {
        _ghost_L1PreviousUserNonce = _initialNonce;
        _ghost_L1CurrentUserNonce = l1Adapter.userNonce(_currentCaller);
      } catch {}
    } else if (_selectorIndex == 2) {
      try l1Adapter.receiveMessage(_addressA, _uintA) {} catch {}
    } else if (_selectorIndex == 3) {
      try l1Adapter.migrateToNative(_addressA, _addressB, _uint32A, _uint32B) {} catch {}
    } else if (_selectorIndex == 4) {
      try l1Adapter.setBurnAmount(_uintA) {
        // This will deprecate the adapter
        _ghost_hasBeenDeprecatedBefore = true;
      } catch {}
    } else if (_selectorIndex == 5) {
      try l1Adapter.burnLockedUSDC() {} catch {}
    } else if (_selectorIndex == 6) {
      try l1Adapter.stopMessaging(_uint32A) {} catch {}
    } else {
      try l1Adapter.resumeMessaging(_uint32A) {} catch {}
    }
  }

  function generateCallAdapterL2(
    uint256 _selectorIndex,
    address _addressA,
    address _addressB,
    uint256 _uintA,
    uint256 _uintB,
    bytes calldata _bytesA,
    uint32 _uint32A
  ) public agentOrDeployer {
    _selectorIndex = _selectorIndex % 8;

    require(_uintB != 0);
    address _signerAd = hevm.addr(_uintB);
    uint256 _nonce = l2Adapter.userNonce(_signerAd);
    uint256 _deadline = block.timestamp + 1 days;
    bytes memory _signature =
      _generateSignature(_addressB, _uintA, _deadline, _nonce, _signerAd, _uintB, address(l2Adapter));

    hevm.prank(_currentCaller);

    if (_selectorIndex == 0) {
      try l2Adapter.sendMessage(_addressA, _uintA, _uint32A) {} catch {}
    } else if (_selectorIndex == 1) {
      try l2Adapter.sendMessage(_signerAd, _addressB, _uintA, _signature, _deadline, _uint32A) {} catch {}
    } else if (_selectorIndex == 2) {
      try l2Adapter.receiveMessage(_addressA, _uintA) {} catch {}
    } else if (_selectorIndex == 3) {
      try l2Adapter.receiveMigrateToNative(_addressA, _uint32A) {} catch {}
    } else if (_selectorIndex == 4) {
      try l2Adapter.receiveStopMessaging() {} catch {}
    } else if (_selectorIndex == 5) {
      try l2Adapter.receiveResumeMessaging() {} catch {}
    } else if (_selectorIndex == 6) {
      try l2Adapter.callUsdcTransaction(_bytesA) {
        // If USDC implementation is upgraded, set the ghost variable
        // UpgradeTo and UPCgradeToAndCall selectors
        if (bytes4(_bytesA) == 0x3659cfe6 || bytes4(_bytesA) == 0x4f1ef286) {
          _ghost_bridgedUSDCProxyUpgraded = true;
        }
      } catch {}
    } else {
      try l2Adapter.transferUSDCRoles(_addressA) {
        _ghost_ownerAndAdminTransferred = true;
      } catch {}
    }
  }

  // Send a call to the L1 or L2 adapter (simulating a direct interaction with the bridge to send the crosschain msg)
  function generateMessageToL1(
    uint256 _selectorIndex,
    address _addressA,
    address _addressB,
    uint256 _uintA,
    uint256 _uintB,
    bytes calldata _bytesA,
    uint32 _uint32A,
    uint32 _uint32B
  ) public agentOrDeployer {
    _selectorIndex = _selectorIndex % 8;
    bytes memory _payload;

    if (_selectorIndex == 0) {
      _payload = abi.encodeWithSignature('sendMessage(address,uint256,uint32)', abi.encode(_addressA, _uintA, _uint32A));
    } else if (_selectorIndex == 1) {
      _payload = abi.encodeWithSignature(
        'sendMessage(address,address,uint256,bytes,uint256,uint32)',
        abi.encode(_addressA, _addressB, _uintA, _bytesA, _uintB, _uint32A)
      );
    } else if (_selectorIndex == 2) {
      _payload = abi.encodeCall(l1Adapter.receiveMessage, (_addressA, _uintA));
    } else if (_selectorIndex == 3) {
      _payload = abi.encodeCall(l1Adapter.migrateToNative, (_addressA, _addressB, _uint32A, _uint32B));
    } else if (_selectorIndex == 4) {
      _payload = abi.encodeCall(l1Adapter.setBurnAmount, (_uintA));
    } else if (_selectorIndex == 5) {
      _payload = abi.encodeCall(l1Adapter.burnLockedUSDC, ());
    } else if (_selectorIndex == 6) {
      _payload = abi.encodeCall(l1Adapter.stopMessaging, (_uint32A));
    } else {
      _payload = abi.encodeCall(l1Adapter.resumeMessaging, (_uint32A));
    }

    hevm.prank(_currentCaller);
    mockMessenger.sendMessage(_currentCaller, _payload, _uint32A);
  }

  function generateMessageToL2(
    uint256 _selectorIndex,
    address _addressA,
    address _addressB,
    uint256 _uintA,
    uint256 _uintB,
    bytes calldata _bytesA,
    uint32 _uint32A
  ) public agentOrDeployer {
    _selectorIndex = _selectorIndex % 7;
    bytes memory _payload;

    if (_selectorIndex == 0) {
      _payload = abi.encodeWithSignature('sendMessage(address,uint256,uint32)', abi.encode(_addressA, _uintA, _uint32A));
    } else if (_selectorIndex == 1) {
      _payload = abi.encodeWithSignature(
        'sendMessage(address,address,uint256,bytes,uint256,uint32)',
        abi.encode(_addressA, _addressB, _uintA, _bytesA, _uintB, _uint32A)
      );
    } else if (_selectorIndex == 2) {
      _payload = abi.encodeCall(l2Adapter.receiveMessage, (_addressA, _uintA));
    } else if (_selectorIndex == 3) {
      _payload = abi.encodeCall(l2Adapter.receiveMigrateToNative, (_addressA, _uint32A));
    } else if (_selectorIndex == 4) {
      _payload = abi.encodeCall(l2Adapter.receiveStopMessaging, ());
    } else if (_selectorIndex == 5) {
      _payload = abi.encodeCall(l2Adapter.receiveResumeMessaging, ());
    } else {
      _payload = abi.encodeCall(l2Adapter.callUsdcTransaction, (_bytesA));
    }

    hevm.prank(_currentCaller);
    mockMessenger.sendMessage(_currentCaller, _payload, _uint32A);
  }

  // function generateCallFactory()
  // done in 15/16

  function generateCallUSDCL1(
    uint256 _selectorIndex,
    address _addressA,
    address _addressB,
    address _addressC,
    address _addressD,
    uint256 _uintA,
    uint8 _uint8A
  ) public agentOrDeployer {
    _selectorIndex = _selectorIndex % 12;

    if (_selectorIndex == 0) {
      usdcMainnet.mint(_addressA, _uintA);
    } else if (_selectorIndex == 1) {
      usdcMainnet.burn(_uintA);
    } else if (_selectorIndex == 2) {
      usdcMainnet.transferOwnership(_addressA);
    } else if (_selectorIndex == 3) {
      usdcMainnet.changeAdmin(_addressA);
    } else if (_selectorIndex == 4) {
      usdcMainnet.initialize('', '', '', _uint8A, _addressA, _addressB, _addressC, _addressD);
    } else if (_selectorIndex == 5) {
      usdcMainnet.configureMinter(_addressA, _uintA);
    } else if (_selectorIndex == 6) {
      usdcMainnet.updateMasterMinter(_addressA);
    } else if (_selectorIndex == 7) {
      usdcMainnet.upgradeTo(_addressA);
    } else if (_selectorIndex == 8) {
      usdcMainnet.upgradeToAndCall(_addressA, '');
    } // Add a call here?
    else if (_selectorIndex == 9) {
      usdcMainnet.transfer(_addressA, _uintA);
    } else if (_selectorIndex == 10) {
      usdcMainnet.approve(_addressA, _uintA);
    } else if (_selectorIndex == 11) {
      usdcMainnet.transferFrom(_addressA, _addressB, _uintA);
    }
  }

  // target both usdc contract and proxy
  function generateCallUSDCL2(
    uint256 _selectorIndex,
    address _addressA,
    address _addressB,
    address _addressC,
    address _addressD,
    uint256 _uintA,
    uint8 _uint8A
  ) public agentOrDeployer {
    _selectorIndex = _selectorIndex % 12;

    if (_selectorIndex == 0) {
      usdcBridged.mint(_addressA, _uintA);
    } else if (_selectorIndex == 1) {
      usdcBridged.burn(_uintA);
    } else if (_selectorIndex == 2) {
      usdcBridged.transferOwnership(_addressA);
    } else if (_selectorIndex == 3) {
      usdcBridged.changeAdmin(_addressA);
    } else if (_selectorIndex == 4) {
      usdcBridged.initialize('', '', '', _uint8A, _addressA, _addressB, _addressC, _addressD);
    } else if (_selectorIndex == 5) {
      usdcBridged.configureMinter(_addressA, _uintA);
    } else if (_selectorIndex == 6) {
      usdcBridged.updateMasterMinter(_addressA);
    } else if (_selectorIndex == 7) {
      usdcBridged.upgradeTo(_addressA);
    } else if (_selectorIndex == 8) {
      usdcBridged.upgradeToAndCall(_addressA, '');
    } // Add a call here?
    else if (_selectorIndex == 9) {
      usdcBridged.transfer(_addressA, _uintA);
    } else if (_selectorIndex == 10) {
      usdcBridged.approve(_addressA, _uintA);
    } else if (_selectorIndex == 11) {
      usdcBridged.transferFrom(_addressA, _addressB, _uintA);
    }
  }

  function generateMessageUSDCL1(
    int256 _selectorIndex,
    address _addressA,
    address _addressB,
    address _addressC,
    address _addressD,
    uint256 _uintA,
    uint8 _uint8A
  ) public agentOrDeployer {
    _selectorIndex = _selectorIndex % 12;

    bytes memory _calldata;

    if (_selectorIndex == 0) {
      _calldata = abi.encodeCall(usdcMainnet.mint, (_addressA, _uintA));
    } else if (_selectorIndex == 1) {
      _calldata = abi.encodeCall(usdcMainnet.burn, (_uintA));
    } else if (_selectorIndex == 2) {
      _calldata = abi.encodeCall(usdcMainnet.transferOwnership, (_addressA));
    } else if (_selectorIndex == 3) {
      _calldata = abi.encodeCall(usdcMainnet.changeAdmin, (_addressA));
    } else if (_selectorIndex == 4) {
      _calldata =
        abi.encodeCall(usdcMainnet.initialize, ('', '', '', _uint8A, _addressA, _addressB, _addressC, _addressD));
    } else if (_selectorIndex == 5) {
      _calldata = abi.encodeCall(usdcMainnet.configureMinter, (_addressA, _uintA));
    } else if (_selectorIndex == 6) {
      _calldata = abi.encodeCall(usdcMainnet.updateMasterMinter, (_addressA));
    } else if (_selectorIndex == 7) {
      _calldata = abi.encodeCall(usdcMainnet.upgradeTo, (_addressA));
    } else if (_selectorIndex == 8) {
      _calldata = abi.encodeCall(usdcMainnet.upgradeToAndCall, (_addressA, ''));
    } // Add a call here?
    else if (_selectorIndex == 9) {
      _calldata = abi.encodeCall(usdcMainnet.transfer, (_addressA, _uintA));
    } else if (_selectorIndex == 10) {
      _calldata = abi.encodeCall(usdcMainnet.approve, (_addressA, _uintA));
    } else if (_selectorIndex == 11) {
      _calldata = abi.encodeCall(usdcMainnet.transferFrom, (_addressA, _addressB, _uintA));
    }
  }

  function generateMessageUSDCL2(
    int256 _selectorIndex,
    address _addressA,
    address _addressB,
    address _addressC,
    address _addressD,
    uint256 _uintA,
    uint8 _uint8A
  ) public agentOrDeployer {
    _selectorIndex = _selectorIndex % 12;

    bytes memory _calldata;

    if (_selectorIndex == 0) {
      _calldata = abi.encodeCall(usdcBridged.mint, (_addressA, _uintA));
    } else if (_selectorIndex == 1) {
      _calldata = abi.encodeCall(usdcBridged.burn, (_uintA));
    } else if (_selectorIndex == 2) {
      _calldata = abi.encodeCall(usdcBridged.transferOwnership, (_addressA));
    } else if (_selectorIndex == 3) {
      _calldata = abi.encodeCall(usdcBridged.changeAdmin, (_addressA));
    } else if (_selectorIndex == 4) {
      _calldata =
        abi.encodeCall(usdcBridged.initialize, ('', '', '', _uint8A, _addressA, _addressB, _addressC, _addressD));
    } else if (_selectorIndex == 5) {
      _calldata = abi.encodeCall(usdcBridged.configureMinter, (_addressA, _uintA));
    } else if (_selectorIndex == 6) {
      _calldata = abi.encodeCall(usdcBridged.updateMasterMinter, (_addressA));
    } else if (_selectorIndex == 7) {
      _calldata = abi.encodeCall(usdcBridged.upgradeTo, (_addressA));
    } else if (_selectorIndex == 8) {
      _calldata = abi.encodeCall(usdcBridged.upgradeToAndCall, (_addressA, ''));
    } // Add a call here?
    else if (_selectorIndex == 9) {
      _calldata = abi.encodeCall(usdcBridged.transfer, (_addressA, _uintA));
    } else if (_selectorIndex == 10) {
      _calldata = abi.encodeCall(usdcBridged.approve, (_addressA, _uintA));
    } else if (_selectorIndex == 11) {
      _calldata = abi.encodeCall(usdcBridged.transferFrom, (_addressA, _addressB, _uintA));
    }
  }

  // TODO: review this and use different approach if the message is trigger by l1Adapter or l2Adapter
  function _boundAmountToMint(address _to, uint256 _amount) internal view returns (uint256) {
    uint256 _maxBalance = max(
      max(usdcMainnet.balanceOf(_to), usdcBridged.balanceOf(_to)),
      max(usdcMainnet.balanceOf(address(l1Adapter)), usdcBridged.balanceOf(address(l2Adapter)))
    );

    return clamp(_amount, 1, 2 ** 255 - 1 - _maxBalance);
  }

  function _dealAndApproveUSDC(address _from, uint256 _amount) internal {
    // provided enough usdc on l1
    hevm.prank(_usdcMinter);
    usdcMainnet.mint(_from, _amount);

    // approve the adapter to spend the usdc
    hevm.prank(_from);
    usdcMainnet.approve(address(l1Adapter), _amount);
  }

  /**
   * @dev Provides bridged USDC through the L1 adapter to not bypass the logic.
   */
  function _dealAndApproveBridgedUSDC(address _from, uint256 _amount, uint32 _minGasLimit) internal {
    // provided enough usdc on l1
    hevm.prank(_usdcMinter);
    usdcMainnet.mint(_from, _amount);

    hevm.prank(_from);
    usdcMainnet.approve(address(l1Adapter), _amount);

    uint256 _initialNonce = l1Adapter.userNonce(_currentCaller);

    hevm.prank(_from);
    l1Adapter.sendMessage(_from, _amount, _minGasLimit);

    _ghost_L1PreviousUserNonce = _initialNonce;
    _ghost_L1CurrentUserNonce = l1Adapter.userNonce(_currentCaller);

    // Approve the L2 adapter to spend the bridgedUSDC
    hevm.prank(_from);
    usdcBridged.approve(address(l2Adapter), _amount);
  }

  function _generateSignature(
    address _to,
    uint256 _amount,
    uint256 _deadline,
    uint256 _nonce,
    address _signerAd,
    uint256 _signerPk,
    address _adapter
  ) internal returns (bytes memory _signature) {
    bytes32 _digest =
      keccak256(abi.encode(_adapter, block.chainid, _to, _amount, _deadline, _nonce)).toEthSignedMessageHash();
    hevm.prank(_signerAd);
    (uint8 v, bytes32 r, bytes32 s) = hevm.sign(_signerPk, _digest);
    _signature = abi.encodePacked(r, s, v);
  }
}
