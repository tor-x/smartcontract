
/**
 * @title ClaimableCrowdsale
 * @title TORX.network claimable crowdsale contract.
 */
contract ClaimableCrowdsale is Pausable {
    using SafeMath for uint256;

    // all accepted ethers will be sent to this address
    address beneficiaryAddress1;
    address beneficiaryAddress2;
    address beneficiaryAddress3;    
    // all remain tokens after ICO should go to that address
    address public bankAddress;

    // token instance
    TORXToken public token;

    uint256 public maxTokensAmount;
    uint256 public issuedTokensAmount = 0;
    uint256 public minBuyableAmount;
    uint256 public tokenRate; // amount of TORX per 1 ETH
    
    bool public isFinished = false;

    // buffer for claimable tokens
    mapping(address => uint256) public tokens;
    mapping(address => bool) public approved;
    mapping(uint32 => address) internal tokenReceivers;
    uint32 internal receiversCount;

    /**
    * Events for token purchase logging
    */
    event TokenBought(address indexed _buyer, uint256 _tokens, uint256 _amount);
    event TokenAdded(address indexed _receiver, uint256 _tokens, uint256 _equivalentAmount);
    event TokenToppedUp(address indexed _receiver, uint256 _tokens, uint256 _equivalentAmount);
    event TokenSubtracted(address indexed _receiver, uint256 _tokens, uint256 _equivalentAmount);
    event TokenSent(address indexed _receiver, uint256 _tokens);

    modifier inProgress() {
        require (!isFinished);
        require (issuedTokensAmount <= maxTokensAmount);

        _;
    }
    
    /**
    * @param _tokenAddress address of a TORX token contract
    * @param _bankAddress address for remain TORX tokens accumulation
    * @param _beneficiaryAddress1 - 1/2 accepted ETH go to this address
    * @param _beneficiaryAddress1 - 1/4 accepted ETH go to this address
    * @param _beneficiaryAddress1 - 1/4 accepted ETH go to this address
    * @param _tokenRate rate TORX per 1 ETH
    * @param _minBuyableAmount min ETH per each buy action (in ETH wei)
    * @param _maxTokensAmount ICO TORX capacity (in TORX wei)
    * 
    */
    function ClaimableCrowdsale(
        address _tokenAddress,
        address _bankAddress,
        address _beneficiaryAddress1,
        address _beneficiaryAddress2,
        address _beneficiaryAddress3,
        uint256 _tokenRate,
        uint256 _minBuyableAmount,
        uint256 _maxTokensAmount
    ) {
        token = TORXToken(_tokenAddress);
        bankAddress = _bankAddress;
        beneficiaryAddress1 = _beneficiaryAddress1;
        beneficiaryAddress2 = _beneficiaryAddress2;
        beneficiaryAddress3 = _beneficiaryAddress3;
        tokenRate = _tokenRate;
        minBuyableAmount = _minBuyableAmount;
        maxTokensAmount = _maxTokensAmount;
    }

    /*
     * @dev Set new TORX token exchange rate.
     */
    function setTokenRate(uint256 _tokenRate) onlyOwner {
        require (_tokenRate > 0);
        tokenRate = _tokenRate;
    }

    /**
     * Buy TORX. Tokens will be stored in contract until claim stage
     */
    function buy() payable inProgress whenNotPaused {
        uint256 payAmount = msg.value;
        uint256 returnAmount = 0;
        uint256 Amount1 = 0;
        uint256 Amount2 = 0;
        uint256 Amount3 = 0;

        // calculate token amount to be transfered to investor
        uint256 tokensAmount = tokenRate.mul(payAmount);
    
        if (issuedTokensAmount + tokensAmount > maxTokensAmount) {
            tokensAmount = maxTokensAmount.sub(issuedTokensAmount);
            payAmount = tokensAmount.div(tokenRate);
            returnAmount = msg.value.sub(payAmount);
        }
    
        issuedTokensAmount = issuedTokensAmount.add(tokensAmount);
        require (issuedTokensAmount <= maxTokensAmount);

        storeTokens(msg.sender, tokensAmount);
        TokenBought(msg.sender, tokensAmount, payAmount);

        Amount1 = payAmount/2;
        Amount2 = payAmount/4;
        Amount3 = payAmount/4;

        beneficiaryAddress1.transfer(Amount1);
        beneficiaryAddress2.transfer(Amount2);
        beneficiaryAddress3.transfer(Amount3);

    
        if (returnAmount > 0) {
            msg.sender.transfer(returnAmount);
        }
    }

    /**
     * Add TORX payed by another crypto (BTC, LTC). Tokens will be stored in contract until claim stage
     */
    function add(address _receiver, uint256 _equivalentEthAmount) onlyOwner inProgress whenNotPaused {
        uint256 tokensAmount = tokenRate.mul(_equivalentEthAmount);
        issuedTokensAmount = issuedTokensAmount.add(tokensAmount);

        storeTokens(_receiver, tokensAmount);
        TokenAdded(_receiver, tokensAmount, _equivalentEthAmount);
    }

    /**
     * Add TORX by referral program. Tokens will be stored in contract until claim stage
     */
    function topUp(address _receiver, uint256 _equivalentEthAmount) onlyOwner whenNotPaused {
        uint256 tokensAmount = tokenRate.mul(_equivalentEthAmount);
        issuedTokensAmount = issuedTokensAmount.add(tokensAmount);

        storeTokens(_receiver, tokensAmount);
        TokenToppedUp(_receiver, tokensAmount, _equivalentEthAmount);
    }

    /**
     * Reduce bought TORX amount. Emergency use only
     */
    function sub(address _receiver, uint256 _equivalentEthAmount) onlyOwner whenNotPaused {
        uint256 tokensAmount = tokenRate.mul(_equivalentEthAmount);

        require (tokens[_receiver] >= tokensAmount);

        tokens[_receiver] = tokens[_receiver].sub(tokensAmount);
        issuedTokensAmount = issuedTokensAmount.sub(tokensAmount);

        TokenSubtracted(_receiver, tokensAmount, _equivalentEthAmount);
    }

    /**
     * Internal method for storing tokens in contract until claim stage
     */
    function storeTokens(address _receiver, uint256 _tokensAmount) internal whenNotPaused {
        if (tokens[_receiver] == 0) {
            tokenReceivers[receiversCount] = _receiver;
            receiversCount++;
            approved[_receiver] = false;
        }
        tokens[_receiver] = tokens[_receiver].add(_tokensAmount);
    }

    /**
     * Claim all bought TORX. Available tokens will be sent to transaction sender address if it is approved
     */
    function claim() whenNotPaused {
        claimFor(msg.sender);
    }

    /**
     * Claim all bought TORX for specific approved address
     */
    function claimOne(address _receiver) onlyOwner whenNotPaused {
        claimFor(_receiver);
    }

    /**
     * Claim all bought TORX for all approved addresses
     */
    function claimAll() onlyOwner whenNotPaused {
        for (uint32 i = 0; i < receiversCount; i++) {
            address receiver = tokenReceivers[i];
            if (approved[receiver] && tokens[receiver] > 0) {
                claimFor(receiver);
            }
        }
    }

    /**
     * Internal method for claiming tokens for specific approved address
     */
    function claimFor(address _receiver) internal whenNotPaused {
        require(approved[_receiver]);
        require(tokens[_receiver] > 0);

        uint256 tokensToSend = tokens[_receiver];
        tokens[_receiver] = 0;

        token.transferFrom(bankAddress, _receiver, tokensToSend);
        TokenSent(_receiver, tokensToSend);
    }

    function approve(address _receiver) onlyOwner whenNotPaused {
        approved[_receiver] = true;
    }
    
    /**
     * Finish Sale.
     */
    function finish() onlyOwner {
        require (issuedTokensAmount <= maxTokensAmount);
        require (!isFinished);
        isFinished = true;
        token.transfer(bankAddress, token.balanceOf(this));
    }

    function getReceiversCount() constant onlyOwner returns (uint32) {
        return receiversCount;
    }

    function getReceiver(uint32 i) constant onlyOwner returns (address) {
        return tokenReceivers[i];
    }
    
    /**
     * Buy TORX. Tokens will be stored in contract until claim stage
     */
    function() external payable {
        buy();
    }
}

/**
 * @title ChangeableRateCrowdsale
 * @dev TORX.Network Main Sale stage
 */
contract ChangeableRateCrowdsale is ClaimableCrowdsale {

    struct RateBoundary {
        uint256 amount;
        uint256 rate;
    }

    mapping (uint => RateBoundary) public rateBoundaries;
    uint public currentBoundary = 0;
    uint public numOfBoundaries = 0;
    uint256 public nextBoundaryAmount;

    /**
    * @param _tokenAddress address of a TORX token contract
    * @param _bankAddress address for remain TORX tokens accumulation
    * @param _beneficiaryAddress1 - 1/2 accepted ETH go to this address
    * @param _beneficiaryAddress2 - 1/4 accepted ETH go to this address
    * @param _beneficiaryAddress3 - 1/4 accepted ETH go to this address
    * @param _tokenRate rate TORX per 1 ETH
    * @param _minBuyableAmount min ETH per each buy action (in ETH wei)
    * @param _maxTokensAmount ICO TORX capacity (in TORX wei)
    */
    function ChangeableRateCrowdsale(
        address _tokenAddress,
        address _bankAddress,
        address _beneficiaryAddress1,
        address _beneficiaryAddress2,
        address _beneficiaryAddress3,
        uint256 _tokenRate,
        uint256 _minBuyableAmount,
        uint256 _maxTokensAmount
    ) ClaimableCrowdsale(
        _tokenAddress,
        _bankAddress,
        _beneficiaryAddress1,
        _beneficiaryAddress2,
        _beneficiaryAddress3,
        _tokenRate,
        _minBuyableAmount,
        _maxTokensAmount
    ) {
        rateBoundaries[numOfBoundaries++] = RateBoundary({
            amount : 12090 ether,
            rate : 1450
        });
        rateBoundaries[numOfBoundaries++] = RateBoundary({
            amount : 20590 ether,
            rate : 1350
        });
        rateBoundaries[numOfBoundaries++] = RateBoundary({
            amount : 21780 ether,
            rate : 1200
        });
        rateBoundaries[numOfBoundaries++] = RateBoundary({
            amount : 229070 ether,
            rate : 1190
        });
        rateBoundaries[numOfBoundaries++] = RateBoundary({
            amount : 24160 ether,
            rate : 1180
        });
        rateBoundaries[numOfBoundaries++] = RateBoundary({
            amount : 25350 ether,
            rate : 1170
        });
        rateBoundaries[numOfBoundaries++] = RateBoundary({
            amount : 26540 ether,
            rate : 1160
        });
        rateBoundaries[numOfBoundaries++] = RateBoundary({
            amount : 27730 ether,
            rate : 1150
        });
        rateBoundaries[numOfBoundaries++] = RateBoundary({
            amount : 28920 ether,
            rate : 1140
        });
        rateBoundaries[numOfBoundaries++] = RateBoundary({
            amount : 30110 ether,
            rate : 1130
        });
        rateBoundaries[numOfBoundaries++] = RateBoundary({
            amount : 31300 ether,
            rate : 1120
        });
        rateBoundaries[numOfBoundaries++] = RateBoundary({
            amount : 32490 ether,
            rate : 1110
        });
        rateBoundaries[numOfBoundaries++] = RateBoundary({
            amount : 33680 ether,
            rate : 1100
        });
        rateBoundaries[numOfBoundaries++] = RateBoundary({
            amount : 34870 ether,
            rate : 1090
        });
        rateBoundaries[numOfBoundaries++] = RateBoundary({
            amount : 34870 ether,
            rate : 1080
        });
        rateBoundaries[numOfBoundaries++] = RateBoundary({
            amount : 36060 ether,
            rate : 1070
        });
        rateBoundaries[numOfBoundaries++] = RateBoundary({
            amount : 37250 ether,
            rate : 1060
        });
        rateBoundaries[numOfBoundaries++] = RateBoundary({
            amount : 38440 ether,
            rate : 1050
        });
        rateBoundaries[numOfBoundaries++] = RateBoundary({
            amount : 39630 ether,
            rate : 1040
        });
        rateBoundaries[numOfBoundaries++] = RateBoundary({
            amount : 40820 ether,
            rate : 1030
        });
        rateBoundaries[numOfBoundaries++] = RateBoundary({
            amount : 42010 ether,
            rate : 1020
        });
        rateBoundaries[numOfBoundaries++] = RateBoundary({
            amount : 43200 ether,
            rate : 1010
        });
        rateBoundaries[numOfBoundaries++] = RateBoundary({
            amount : 44390 ether,
            rate : 1000
        });
        nextBoundaryAmount = rateBoundaries[currentBoundary].amount;
    }

    /**
     * Internal method to change rate if boundary is hit
     */
    function touchRate() internal {
        if (issuedTokensAmount >= nextBoundaryAmount) {
            currentBoundary++;
            if (currentBoundary >= numOfBoundaries) {
                nextBoundaryAmount = maxTokensAmount;
            }
            else {
                nextBoundaryAmount = rateBoundaries[currentBoundary].amount;
                tokenRate = rateBoundaries[currentBoundary].rate;
            }
        }
    }

    /**
     * Inherited internal method for storing tokens in contract until claim stage
     */
    function storeTokens(address _receiver, uint256 _tokensAmount) internal whenNotPaused {
        ClaimableCrowdsale.storeTokens(_receiver, _tokensAmount);
        touchRate();
    }
}
