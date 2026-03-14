// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @custom:predeploy 0x4200000000000000000000000000000000000069
/// @title PrivacyRouter
/// @notice System predeploy that stores per-address privacy rules.
///         The EVM precompile calls shouldShield() on every value transfer
///         to decide whether to auto-shield into the shielded pool.

/// @notice Privacy mode for an address
enum PrivacyMode {
    PUBLIC, // Default — normal transfers, no shielding
    AUTO_SHIELD, // All incoming transfers are auto-shielded
    CUSTOM // Shielding based on custom rules (min amount, whitelists)

}

/// @notice Privacy rules for an address
struct PrivacyRules {
    PrivacyMode mode;
    uint256 minAmount; // Only shield transfers >= this amount (0 = shield all)
}

contract PrivacyRouter {
    /// @notice Privacy rules per address
    mapping(address => PrivacyRules) private _rules;

    /// @notice Sender whitelist per address (sender => true if whitelisted)
    mapping(address => mapping(address => bool)) private _senderWhitelisted;

    /// @notice Token whitelist per address (token => true if whitelisted)
    mapping(address => mapping(address => bool)) private _tokenWhitelisted;

    /// @notice Sender whitelist arrays for enumeration
    mapping(address => address[]) private _senderWhitelistArray;

    /// @notice Token whitelist arrays for enumeration
    mapping(address => address[]) private _tokenWhitelistArray;

    /// @notice Emitted when an address changes its privacy mode
    event ModeChanged(address indexed account, PrivacyMode mode);

    /// @notice Emitted when an address updates its privacy rules
    event RulesChanged(address indexed account, uint256 minAmount, address[] tokenWhitelist, address[] senderWhitelist);

    /// @notice Set the privacy mode for msg.sender
    /// @param _mode PUBLIC, AUTO_SHIELD, or CUSTOM
    function setMode(PrivacyMode _mode) external {
        _rules[msg.sender].mode = _mode;
        emit ModeChanged(msg.sender, _mode);
    }

    /// @notice Set privacy rules for msg.sender
    /// @param _minAmount minimum transfer amount to trigger shielding (0 = all)
    /// @param _tokenWhitelist only shield these tokens (empty = all tokens)
    /// @param _senderWhitelist never shield transfers from these senders
    function setRules(
        uint256 _minAmount,
        address[] calldata _tokenWhitelist,
        address[] calldata _senderWhitelist
    )
        external
    {
        PrivacyRules storage rules = _rules[msg.sender];
        rules.minAmount = _minAmount;

        // Clear old token whitelist
        address[] storage oldTokens = _tokenWhitelistArray[msg.sender];
        for (uint256 i = 0; i < oldTokens.length; i++) {
            _tokenWhitelisted[msg.sender][oldTokens[i]] = false;
        }
        delete _tokenWhitelistArray[msg.sender];

        // Set new token whitelist
        for (uint256 i = 0; i < _tokenWhitelist.length; i++) {
            _tokenWhitelisted[msg.sender][_tokenWhitelist[i]] = true;
        }
        _tokenWhitelistArray[msg.sender] = _tokenWhitelist;

        // Clear old sender whitelist
        address[] storage oldSenders = _senderWhitelistArray[msg.sender];
        for (uint256 i = 0; i < oldSenders.length; i++) {
            _senderWhitelisted[msg.sender][oldSenders[i]] = false;
        }
        delete _senderWhitelistArray[msg.sender];

        // Set new sender whitelist
        for (uint256 i = 0; i < _senderWhitelist.length; i++) {
            _senderWhitelisted[msg.sender][_senderWhitelist[i]] = true;
        }
        _senderWhitelistArray[msg.sender] = _senderWhitelist;

        emit RulesChanged(msg.sender, _minAmount, _tokenWhitelist, _senderWhitelist);
    }

    /// @notice Get the full privacy rules for an address
    function getRules(address _account)
        external
        view
        returns (PrivacyMode mode, uint256 minAmount, address[] memory tokenWhitelist, address[] memory senderWhitelist)
    {
        PrivacyRules storage rules = _rules[_account];
        return (rules.mode, rules.minAmount, _tokenWhitelistArray[_account], _senderWhitelistArray[_account]);
    }

    /// @notice Get just the privacy mode for an address (cheaper than getRules)
    function getMode(address _account) external view returns (PrivacyMode) {
        return _rules[_account].mode;
    }

    /// @notice Determines whether a transfer should be auto-shielded.
    ///         Called by the EVM precompile on every value transfer.
    /// @param _recipient who is receiving the transfer
    /// @param _sender who is sending the transfer
    /// @param _amount transfer amount in wei
    /// @param _token token address (address(0) for native ETH)
    /// @return true if the transfer should be routed to the shielded pool
    function shouldShield(
        address _recipient,
        address _sender,
        uint256 _amount,
        address _token
    )
        external
        view
        returns (bool)
    {
        PrivacyRules storage rules = _rules[_recipient];

        // PUBLIC mode → never shield
        if (rules.mode == PrivacyMode.PUBLIC) {
            return false;
        }

        // AUTO_SHIELD or CUSTOM mode → evaluate rules
        // Sender is whitelisted → don't shield (keep public)
        if (_senderWhitelisted[_recipient][_sender]) {
            return false;
        }

        // Amount below minimum → don't shield
        if (_amount < rules.minAmount) {
            return false;
        }

        // Token whitelist is non-empty and token is not in it → don't shield
        if (_tokenWhitelistArray[_recipient].length > 0 && !_tokenWhitelisted[_recipient][_token]) {
            return false;
        }

        // All checks passed → shield this transfer
        return true;
    }
}
