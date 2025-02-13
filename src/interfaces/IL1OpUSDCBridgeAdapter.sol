// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IL1OpUSDCBridgeAdapter {
  /*///////////////////////////////////////////////////////////////
                            ENUMS
  ///////////////////////////////////////////////////////////////*/

  /**
   * @notice The status of an L1 Messenger
   * @param Active The messenger is active
   * @param Paused The messenger is paused
   * @param Upgrading The messenger is upgrading
   * @param Deprecated The messenger is deprecated
   */
  enum Status {
    Active,
    Paused,
    Upgrading,
    Deprecated
  }

  /*///////////////////////////////////////////////////////////////
                            EVENTS
  ///////////////////////////////////////////////////////////////*/

  /**
   * @notice Emitted when the burn amount is set
   * @param _burnAmount The amount to be burned
   */
  event BurnAmountSet(uint256 _burnAmount);

  /**
   * @notice Emitted when the migration process is complete
   */
  event MigrationComplete();

  /*///////////////////////////////////////////////////////////////
                            LOGIC
  ///////////////////////////////////////////////////////////////*/

  /**
   * @notice Initiates the process to migrate the bridged USDC to native USDC
   * @param _roleCaller The address that will be allowed to transfer the usdc roles
   * @param _burnCaller The address that will be allowed to call this contract to burn the USDC tokens
   * @param _minGasLimitReceiveOnL2 Minimum gas limit that the message can be executed with on L2
   * @param _minGasLimitSetBurnAmount Minimum gas limit that the message can be executed with to set the burn amount
   */
  function migrateToNative(
    address _roleCaller,
    address _burnCaller,
    uint32 _minGasLimitReceiveOnL2,
    uint32 _minGasLimitSetBurnAmount
  ) external;

  /**
   * @notice Sets the amount of USDC tokens that will be burned when the burnLockedUSDC function is called
   * @param _amount The amount of USDC tokens that will be burned
   * @dev Only callable by a whitelisted messenger during its migration process
   */
  function setBurnAmount(uint256 _amount) external;

  /**
   * @notice Burns the USDC tokens locked in the contract
   * @dev The amount is determined by the burnAmount variable, which is set in the setBurnAmount function
   */
  function burnLockedUSDC() external;

  /**
   * @notice Send a message to the linked adapter to call receiveStopMessaging() and stop outgoing messages.
   * @dev Only callable by the owner of the adapter
   * @dev Setting isMessagingDisabled to true is an irreversible operation
   * @param _minGasLimit Minimum gas limit that the message can be executed with
   */
  function stopMessaging(uint32 _minGasLimit) external;

  /**
   * @notice Resume messaging on the messenger
   * @dev Only callable by the owner
   * @dev Cant resume deprecated messengers
   * @param _minGasLimit Minimum gas limit that the message can be executed with
   */
  function resumeMessaging(uint32 _minGasLimit) external;

  /*///////////////////////////////////////////////////////////////
                            VARIABLES
  ///////////////////////////////////////////////////////////////*/

  /**
   * @notice Fetches the amount of USDC tokens that will be burned when the burnLockedUSDC function is called
   * @return _burnAmount The amount of USDC tokens that will be burned
   */
  function burnAmount() external view returns (uint256 _burnAmount);

  /**
   * @notice Fetches the address of the burn caller
   * @return _burnCaller The address of the burn caller
   */
  function burnCaller() external view returns (address _burnCaller);

  /**
   * @notice Fetches the status of the messenger
   * @return _status The status of the messenger
   */
  function messengerStatus() external view returns (Status _status);
}
