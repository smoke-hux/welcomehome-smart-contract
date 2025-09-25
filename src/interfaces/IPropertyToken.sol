// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPropertyToken is IERC20 {
    function mint(address to, uint256 amount) external;
    function burn(uint256 amount) external;
    function burnFrom(address account, uint256 amount) external;
    function pause() external;
    function unpause() external;
    function setMaxTokens(uint256 _maxTokens) external;
    function connectToProperty(address _propertyContract, string memory _propertyId) external;
    function maxTokens() external view returns (uint256);
    function propertyContract() external view returns (address);
    function propertyId() external view returns (string memory);
    function getRemainingTokens() external view returns (uint256);
}