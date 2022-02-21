// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";

contract MockSynth is ERC20 {

    mapping(address => bool) permitted;

    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol, 18) {
        permitted[msg.sender] = true;
    }

    function setPermitter(address _user, bool _status) external {
        require(permitted[msg.sender]);

        permitted[_user] = _status;
    }

    function mint(address user, uint256 amt) external {
        require(permitted[msg.sender]);

        _mint(user, amt);
    }

    function burn(address user, uint256 amt) external {
        require(permitted[msg.sender]);

        _burn(user, amt);
    }
}
