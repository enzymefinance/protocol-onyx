// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IUSDT {
    event AddedBlackList(address _user);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Deprecate(address newAddress);
    event DestroyedBlackFunds(address _blackListedUser, uint256 _balance);
    event Issue(uint256 amount);
    event Params(uint256 feeBasisPoints, uint256 maxFee);
    event Pause();
    event Redeem(uint256 amount);
    event RemovedBlackList(address _user);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Unpause();

    function MAX_UINT() external view returns (uint256);
    function _totalSupply() external view returns (uint256);
    function addBlackList(address _evilUser) external;
    function allowance(address _owner, address _spender) external view returns (uint256 remaining);
    function allowed(address, address) external view returns (uint256);
    function approve(address _spender, uint256 _value) external;
    function balanceOf(address who) external view returns (uint256);
    function balances(address) external view returns (uint256);
    function basisPointsRate() external view returns (uint256);
    function decimals() external view returns (uint256);
    function deprecate(address _upgradedAddress) external;
    function deprecated() external view returns (bool);
    function destroyBlackFunds(address _blackListedUser) external;
    function getBlackListStatus(address _maker) external view returns (bool);
    function getOwner() external view returns (address);
    function isBlackListed(address) external view returns (bool);
    function issue(uint256 amount) external;
    function maximumFee() external view returns (uint256);
    function name() external view returns (string memory);
    function owner() external view returns (address);
    function pause() external;
    function paused() external view returns (bool);
    function redeem(uint256 amount) external;
    function removeBlackList(address _clearedUser) external;
    function setParams(uint256 newBasisPoints, uint256 newMaxFee) external;
    function symbol() external view returns (string memory);
    function totalSupply() external view returns (uint256);
    function transfer(address _to, uint256 _value) external;
    function transferFrom(address _from, address _to, uint256 _value) external;
    function transferOwnership(address newOwner) external;
    function unpause() external;
    function upgradedAddress() external view returns (address);
}
