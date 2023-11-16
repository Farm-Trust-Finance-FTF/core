// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MockUSDC is ERC20, ERC20Burnable, Ownable {
<<<<<<< HEAD
  constructor() ERC20("MockUSDC", "MUSDC") {}

  function mint(address to, uint256 amount) public onlyOwner {
    _mint(to, amount);
  }
=======
    constructor() ERC20("MockUSDC", "MUSDC") {}

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function burn(address to, uint256 amount) public {
        _burn(to, amount);
    }
>>>>>>> master
}
