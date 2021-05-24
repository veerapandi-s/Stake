// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Pausable.sol";
import "./WhitelistAdminRole.sol";
import "./Wrap.sol";
import "./MyIERC721.sol";
import "./ERC721TokenReceiver.sol";

contract Stake is Wrap, Pausable, WhitelistAdminRole {
    struct Card {
        uint256 points;
        uint256 releaseTime;
        address erc721;
        address owner;
        uint256 supply;
    }

    using SafeMath for uint256;

    mapping(address => mapping(uint256 => Card)) public cards;
    mapping(address => uint256) public pendingWithdrawals;

    mapping(address => uint256) public points;
    mapping(address => uint256) public lastUpdateTime;
    uint256 public rewardRate = 86400;
    uint256 public periodStart;
    uint256 public minStake;
    uint256 public maxStake;
    address public controller;
    bool public constructed = false;
    address public rescuer;
    uint256 public spentScore;

    event Staked(address indexed user, uint256 amount);
    event FarmCreated(
        address indexed user,
        address indexed farm,
        uint256 fee,
        string uri
    );
    event FarmUri(address indexed farm, string uri);
    event Withdrawn(address indexed user, uint256 amount);
    event RescueRedeemed(address indexed user, uint256 amount);
    event Removed(
        address indexed erc1155,
        uint256 indexed card,
        address indexed recipient,
        uint256 amount
    );
    event Redeemed(
        address indexed user,
        address indexed erc1155,
        uint256 indexed id,
        uint256 amount
    );

    modifier updateReward(address account) {
        if (account != address(0)) {
            points[account] = earned(account);
            lastUpdateTime[account] = block.timestamp;
        }
        _;
    }

    constructor(
        uint256 _periodStart,
        uint256 _minStake,
        uint256 _maxStake,
        address _controller,
        IERC20 _tokenAddress,
        string memory _uri
    ) Wrap(_tokenAddress) {
        require(
            _minStake >= 0 && _maxStake > 0 && _maxStake >= _minStake,
            "Problem with min and max stake setup"
        );
        constructed = true;
        periodStart = _periodStart;
        minStake = _minStake;
        maxStake = _maxStake;
        controller = _controller;
        rescuer = _controller;
        // 		super.initWhiteListAdmin();
        emit FarmCreated(msg.sender, address(this), 0, _uri);
        emit FarmUri(address(this), _uri);
    }

    function setRewardRate(uint256 _rewardRate) external onlyWhitelistAdmin {
        require(_rewardRate > 0, "Reward rate too low");
        rewardRate = _rewardRate;
    }

    function setMinMaxStake(uint256 _minStake, uint256 _maxStake)
        external
        onlyWhitelistAdmin
    {
        require(
            _minStake >= 0 && _maxStake > 0 && _maxStake >= _minStake,
            "Problem with min and max stake setup"
        );
        minStake = _minStake;
        maxStake = _maxStake;
    }

    function setRescuer(address _rescuer) external onlyWhitelistAdmin {
        rescuer = _rescuer;
    }

    function earned(address account) public view returns (uint256) {
        return points[account].add(getCurrPoints(account));
    }

    function getCurrPoints(address account) internal view returns (uint256) {
        uint256 blockTime = block.timestamp;
        return
            blockTime.sub(lastUpdateTime[account]).mul(balanceOf(account)).div(
                rewardRate
            );
    }

    function stake(uint256 amount)
        public
        override
        updateReward(msg.sender)
        whenNotPaused()
    {
        require(block.timestamp >= periodStart, "Pool not open");
        require(
            amount.add(balanceOf(msg.sender)) >= minStake,
            "Too few deposit"
        );
        require(
            amount.add(balanceOf(msg.sender)) <= maxStake,
            "Deposit limit reached"
        );

        super.stake(amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public override updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");

        super.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function exit() external {
        withdraw(balanceOf(msg.sender));
    }

    function rescueScore(address account)
        external
        updateReward(account)
        returns (uint256)
    {
        require(msg.sender == rescuer, "!rescuer");
        uint256 earnedPoints = points[account];
        spentScore = spentScore.add(earnedPoints);
        points[account] = 0;

        if (balanceOf(account) > 0) {
            _rescueScore(account);
        }

        emit RescueRedeemed(account, earnedPoints);
        return earnedPoints;
    }

    function addNfts(
        uint256 _points,
        uint256 _releaseTime,
        address _erc721Address,
        uint256 _tokenId,
        address _owner,
        uint256 _cardAmount
    ) public onlyWhitelistAdmin returns (uint256) {
        require(_tokenId > 0, "Invalid token id");
        require(_cardAmount > 0, "Invalid card amount");
        Card storage c = cards[_erc721Address][_tokenId];
        c.points = _points;
        c.releaseTime = _releaseTime;
        c.erc721 = _erc721Address;
        c.owner = _owner;
        c.supply = c.supply.add(_cardAmount);
        return _tokenId;
    }

    function redeem(address _erc721Address, uint256 id)
        external
        updateReward(msg.sender)
    {
        require(cards[_erc721Address][id].points != 0, "Card not found");
        require(
            block.timestamp >= cards[_erc721Address][id].releaseTime,
            "Card not released"
        );
        require(
            points[msg.sender] >= cards[_erc721Address][id].points,
            "Redemption exceeds point balance"
        );

        points[msg.sender] = points[msg.sender].sub(
            cards[_erc721Address][id].points
        );
        spentScore = spentScore.add(cards[_erc721Address][id].points);

        MyIERC721(cards[_erc721Address][id].erc721).mint(msg.sender);

        emit Redeemed(
            msg.sender,
            cards[_erc721Address][id].erc721,
            id,
            cards[_erc721Address][id].points
        );
    }
}
