// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./IERC20.sol";

contract Wrap {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    IERC20 public token;

    constructor(IERC20 _tokenAddress) {
        token = IERC20(_tokenAddress);
    }

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => uint256[]) public fixedBalances;
    mapping(address => uint256[]) public releaseTime;
    mapping(address => uint256) public fixedStakeLength;

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function stake(uint256 amount) public virtual {
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }

    function fixedStake(uint256 _day, uint256 _amount) public virtual {
        fixedBalances[msg.sender].push(_amount);
        uint256 time = block.timestamp + _day * 1 days;
        releaseTime[msg.sender].push(time);
        fixedStakeLength[msg.sender] += 1;
        _totalSupply = _totalSupply.add(_amount);
        IERC20(token).safeTransferFrom(msg.sender, address(this), _amount);
    }

    function withdraw(uint256 amount) public virtual {
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    function _rescueScore(address account) internal {
        uint256 amount = _balances[account];

        _totalSupply = _totalSupply.sub(amount);
        _balances[account] = _balances[account].sub(amount);
        IERC20(token).safeTransfer(account, amount);
    }

    function withdrawFixedStake(uint256 _index) public virtual {
        require(fixedBalances[msg.sender].length >= _index, "No Record Found");
        require(fixedBalances[msg.sender][_index] != 0, "No Balance To Break");
        require(
            releaseTime[msg.sender][_index] <= block.timestamp,
            "Time isn't up"
        );

        _totalSupply = _totalSupply.sub(fixedBalances[msg.sender][_index]);
        IERC20(token).safeTransfer(
            msg.sender,
            fixedBalances[msg.sender][_index]
        );
        removeBalance(_index);
        removeReleaseTime(_index);
        fixedStakeLength[msg.sender] -= 1;
    }

    function removeBalance(uint256 index) internal {
        // Move the last element into the place to delete
        fixedBalances[msg.sender][index] = fixedBalances[msg.sender][
            fixedBalances[msg.sender].length - 1
        ];
        // Remove the last element
        fixedBalances[msg.sender].pop();
    }

    function removeReleaseTime(uint256 index) internal {
        // Move the last element into the place to delete
        releaseTime[msg.sender][index] = releaseTime[msg.sender][
            releaseTime[msg.sender].length - 1
        ];
        // Remove the last element
        releaseTime[msg.sender].pop();
    }
}
