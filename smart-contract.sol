// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;
        return c;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) { return 0; }
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        return c;
    }

    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

interface IERC20 {
  function totalSupply() external view returns (uint256);
  function balanceOf(address account) external view returns (uint256);
  function transfer(address recipient, uint256 amount) external returns (bool);
  function allowance(address owner, address spender) external view returns (uint256);
  function approve(address spender, uint256 amount) external returns (bool);
  function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
  event Transfer(address indexed from, address indexed to, uint256 value);
  event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract Owner {
    address public owner;
    address public newOwner;

    event OwnershipTransferred(address indexed _from, address indexed _to);

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner {
        require(msg.sender == owner, 'Caller must be the owner!');
        _;
    }

    function transferOwnership(address _newOwner) public onlyOwner {
        require(_newOwner != address(0), 'New owner is the zero address.');
        newOwner = _newOwner;
    }

    function transferOwnershipAccept() public {
        require(msg.sender == newOwner, 'Caller must be the owner!');
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
        newOwner = address(0);
    }
}

contract Campaigns is Owner {
    
    using SafeMath for uint256;

    enum ProjectType {ETH, USDT}

    Project[] private projects;
    ProjectUSDT[] private projects_usdt;

    event ProjectStarted(address contractAddress, address projectStarter, string projectTitle, string projectDesc, uint256 deadline,
    uint256 goalAmount, ProjectType projectType);

    function startProject(string calldata title, string calldata description, uint deadline, uint amountToRaise, uint hold, ProjectType projectType) external onlyOwner {
        
        if(projectType == ProjectType.ETH) {
            Project newProject = new Project(msg.sender, title, description, deadline, amountToRaise, hold);
            projects.push(newProject);
            emit ProjectStarted(address(newProject), msg.sender, title, description, deadline, amountToRaise, ProjectType.ETH);
        }
        else if (projectType == ProjectType.USDT) {
            ProjectUSDT newProject = new ProjectUSDT(msg.sender, title, description, deadline, amountToRaise, hold);
            projects_usdt.push(newProject);
            emit ProjectStarted(address(newProject), msg.sender, title, description, deadline, amountToRaise, ProjectType.USDT);            
        }
        
    }                                                                                                                                   

    function returnAllProjects() external view returns(Project[] memory) {
        return projects;
    }
    function returnAllProjectsUSDT() external view returns(ProjectUSDT[] memory) {
        return projects_usdt;
    }
}

contract Project {
    using SafeMath for uint256;
    
    enum State {INITIATED, SUCCESSFUL, SENDED, CANCELED}

    address payable public creator;
    
    uint public assetAmount;
    uint public completeAt;
    uint public deadline;
    uint public refundFEE = 0;
    uint public currentBalance;
    uint public earnings = 0;
    uint public zHold;
    uint constant CAP = 1000000000000000000; //smallest currency unit

    string public title;
    string public description;
    
    State public state = State.INITIATED; 
    
    struct Investment {
        uint fund;
        uint rate;
        uint earningTotal;
    }

    mapping (address => Investment) public investor;

    event FundingReceived(address investor, uint amount, uint currentTotal);
    event RefundSent(address investor, uint amount, uint currentTotal);
    event Cancel(address creator, string title, uint assetAmount, uint currentTotal);
    event CreatorReceives(address recipient, uint amount);
    event DepositedEarnings(uint deposit);
    event InvestorReceived(uint amount);

    IERC20 ZPAY = IERC20(0x045Eb7e34e94B28C7A3641BC5e1A1F61f225Af9F);

    modifier onlyCreator() {
        require(msg.sender == creator, 'Only for the creator.');
        _;
    }

    constructor (address payable projectStarter, string memory projectTitle, string memory projectDesc, uint fundRaisingDeadline, uint goalAmount, uint hold) {
        creator = projectStarter;
        title = projectTitle;
        description = projectDesc;
        assetAmount = goalAmount;
        deadline = fundRaisingDeadline;
        currentBalance = 0;
        zHold = hold;
    }
    
    function setAssetAmount(uint newAssetAmount) internal {
        require(newAssetAmount > 0, 'New asset amount value must be greater than 0.');
        require(newAssetAmount >= assetAmount, 'New asset amount value must be greater than the old value.');
        assetAmount = newAssetAmount;
    }
    
    function setNewDeadline(uint newDeadline) internal {
        require(newDeadline > 0, 'New deadline value must be greater than 0.');
        require(newDeadline >= deadline, 'New deadline value must be greater than the old value.');
        deadline = newDeadline;
    }
    
    function setNewRefundFEE(uint _FEE) internal {
        require(_FEE >= 0 && _FEE <= 100, 'New fee must be between 0 and 100');
        refundFEE = _FEE;
    }
    
    function setNewZHold(uint newZ) internal {
        require(newZ >= 0, 'New Zhold total value must be greater than or equal to 0.');
        zHold = newZ;
    }
    
    function setNewValues(uint newAssetAmount, uint newDeadline, uint _FEE, uint newZ) external onlyCreator {
        require(state == State.INITIATED, 'Invalid state');
        setAssetAmount(newAssetAmount);
        setNewDeadline(newDeadline);
        setNewRefundFEE(_FEE);
        setNewZHold(newZ);
    }

    function buy() external payable {
        uint dif = assetAmount.sub(currentBalance);
        
        require(zHold <= ZPAY.balanceOf(msg.sender), 'You must have Zeela tokens in your portfolio to be able to invest.');
        require(msg.value <= dif, 'Higher than allowed value');
        require(msg.value > 0, 'Invest a value greater than 0.');
        require(block.timestamp < deadline, 'Campaign timed out.');
        require(state == State.INITIATED, 'Invalid state');
        require(msg.sender != creator, 'Creator cannot invest in the project.');
        
        Investment memory investment = investor[msg.sender];
        
        investment.fund = investment.fund + msg.value;
        investment.rate = investment.fund.mul(CAP).div(assetAmount);
        currentBalance = currentBalance.add(msg.value);

        investor[msg.sender] = Investment(investment.fund, investment.rate, 0);
        
        emit FundingReceived(msg.sender, msg.value, currentBalance);
        
        if(currentBalance >= assetAmount) {
            state = State.SUCCESSFUL;  
            completeAt = block.timestamp;
        }
    }
    
    function refund() external {
        require(state == State.INITIATED || state == State.CANCELED, 'Invalid state');
        
        Investment memory investment = investor[msg.sender];
        uint temp = investment.fund;
        
        require(temp > 0, 'Your invested amount is 0');
        temp = temp.mul(100-refundFEE).div(100);
        msg.sender.transfer(temp);
        currentBalance = currentBalance.sub(temp);
        
        investor[msg.sender] = Investment(0, 0, 0);
        
        emit RefundSent(msg.sender, temp, currentBalance);
    }
    
    function payout() external onlyCreator {
        require(state == State.SUCCESSFUL, 'Invalid state');
        uint temp = currentBalance;
        
        creator.transfer(temp);
        
        emit CreatorReceives(creator, temp);

        currentBalance = 0;
        state = State.SENDED;  
    }
    
    function cancel() external onlyCreator {
        require(state == State.INITIATED || state == State.SUCCESSFUL, 'Invalid state');
      
        emit Cancel(creator, title, assetAmount, currentBalance);
        state = State.CANCELED; 
    }
    
    function depositEarnings() external payable onlyCreator {
        require(state == State.SENDED, 'Invalid state');
        earnings = earnings + msg.value;
        emit DepositedEarnings(msg.value);   
    }
    
    function withdrawEarnings() external {
        require(state == State.SENDED, 'Invalid state');
        Investment memory investment = investor[msg.sender];
        uint temp = investment.fund;
        require(temp > 0, 'Your invested amount is 0');
        uint earning_temp = earnings.mul(investment.rate).div(CAP).sub(investment.earningTotal);
        if(earning_temp > 0) { 
            msg.sender.transfer(earning_temp); 
            investor[msg.sender] = Investment(temp, investment.rate, earning_temp + investment.earningTotal);
            emit InvestorReceived(earning_temp);
        }
    }
    
    function getInvestor(address inv) public view returns
    (
        uint256 fund,
        uint256 rate,
        uint256 earningTotal
    ) {
        Investment memory investment = investor[inv];
        fund = investment.fund;
        rate = investment.rate;
        earningTotal = investment.earningTotal;
    }

    function getDetails() public view returns 
    (
        address payable projectStarter,
        string memory projectTitle,
        string memory projectDesc,
        uint256 deadLine,
        State currentState,
        uint256 currentAmount,
        uint256 goalAmount,
        uint256 valueToComplete
    ) {
        projectStarter = creator;
        projectTitle = title;
        projectDesc = description;
        deadLine = deadline;
        currentState = state;
        currentAmount = currentBalance;
        goalAmount = assetAmount;
        valueToComplete = assetAmount.sub(currentBalance);
    }
    
    receive() external payable { 

    }
}

contract ProjectUSDT {
    using SafeMath for uint256;
    
    enum State {INITIATED, SUCCESSFUL, SENDED, CANCELED}

    address payable public creator;
    
    uint public assetAmount;
    uint public completeAt;
    uint public deadline;
    uint public refundFEE = 0;
    uint public currentBalance;
    uint public earnings = 0;
    uint public zHold;
    uint constant CAP = 1000000; //smallest currency unit

    string public title;
    string public description;
    
    State public state = State.INITIATED; 
    
    struct Investment {
        uint fund;
        uint rate;
        uint earningTotal;
    }

    mapping (address => Investment) public investor;

    event FundingReceived(address investor, uint amount, uint currentTotal);
    event RefundSent(address investor, uint amount, uint currentTotal);
    event Cancel(address creator, string title, uint assetAmount, uint currentTotal);
    event CreatorReceives(address recipient, uint amount);
    event DepositedEarnings(uint deposit);
    event InvestorReceived(uint amount);
    
    IERC20 ZPAY = IERC20(0x045Eb7e34e94B28C7A3641BC5e1A1F61f225Af9F);
    IERC20 USDT = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);

    modifier onlyCreator() {
        require(msg.sender == creator, 'Only for the creator.');
        _;
    }

    constructor (address payable projectStarter, string memory projectTitle, string memory projectDesc, uint fundRaisingDeadline, uint goalAmount, uint hold) {
        creator = projectStarter;
        title = projectTitle;
        description = projectDesc;
        assetAmount = goalAmount;
        deadline = fundRaisingDeadline;
        currentBalance = 0;
        zHold = hold;
    }
    
    function setAssetAmount(uint newAssetAmount) internal {
        require(newAssetAmount > 0, 'New asset amount value must be greater than 0.');
        require(newAssetAmount >= assetAmount, 'New asset amount value must be greater than the old value.');
        assetAmount = newAssetAmount;
    }
    
    function setNewDeadline(uint newDeadline) internal {
        require(newDeadline > 0, 'New deadline value must be greater than 0.');
        require(newDeadline >= deadline, 'New deadline value must be greater than the old value.');
        deadline = newDeadline;
    }
    
    function setNewRefundFEE(uint _FEE) internal {
        require(_FEE >= 0 && _FEE <= 100, 'New fee must be between 0 and 100');
        refundFEE = _FEE;
    }
    
    function setNewZHold(uint newZ) internal {
        require(newZ >= 0, 'New Zhold total value must be greater than or equal to 0.');
        zHold = newZ;
    }
    
    function setNewValues(uint newAssetAmount, uint newDeadline, uint _FEE, uint newZ) external onlyCreator {
        require(state == State.INITIATED, 'Invalid state');
        setAssetAmount(newAssetAmount);
        setNewDeadline(newDeadline);
        setNewRefundFEE(_FEE);
        setNewZHold(newZ);
    }

    function buy(uint payment) external {
        uint dif = assetAmount.sub(currentBalance);
        
        require(zHold <= ZPAY.balanceOf(msg.sender), 'You must have Zeela tokens in your portfolio to be able to invest.');
        
        require(USDT.balanceOf(msg.sender) >= payment, 'You dont have enough tokens.');
        USDT.transferFrom(msg.sender, address(this), payment);
        
        require(payment <= dif, 'Higher than allowed value');
        require(payment > 0, 'Invest a value greater than 0.');
        require(block.timestamp < deadline, 'Campaign timed out.');
        require(state == State.INITIATED, 'Invalid state');
        require(msg.sender != creator, 'Creator cannot invest in the project.');
        
        Investment memory investment = investor[msg.sender];
        
        investment.fund = investment.fund + payment;
        investment.rate = investment.fund.mul(CAP).div(assetAmount);
        currentBalance = currentBalance.add(payment);

        investor[msg.sender] = Investment(investment.fund, investment.rate, 0);
        
        emit FundingReceived(msg.sender, payment, currentBalance);
        
        if(currentBalance >= assetAmount) {
            state = State.SUCCESSFUL;  
            completeAt = block.timestamp;
        }
    }
    
    function refund() external {
        require(state == State.INITIATED || state == State.CANCELED, 'Invalid state');
        
        Investment memory investment = investor[msg.sender];
        uint temp = investment.fund;
        
        require(temp > 0, 'Your invested amount is 0');
        temp = temp.mul(100-refundFEE).div(100);
        
        USDT.transfer(msg.sender, temp);
        
        currentBalance = currentBalance.sub(temp);
        
        investor[msg.sender] = Investment(0, 0, 0);
        
        emit RefundSent(msg.sender, temp, currentBalance);
    }
    
    function payout() external onlyCreator {
        require(state == State.SUCCESSFUL, 'Invalid state');
        uint temp = currentBalance;
        
        USDT.transfer(creator, temp);
        
        emit CreatorReceives(creator, temp);

        currentBalance = 0;
        state = State.SENDED;  
    }
    
    function cancel() external onlyCreator {
        require(state == State.INITIATED || state == State.SUCCESSFUL, 'Invalid state');
      
        emit Cancel(creator, title, assetAmount, currentBalance);
        state = State.CANCELED; 
    }
    
    function depositEarnings(uint payment) external onlyCreator {
        require(USDT.balanceOf(msg.sender) >= payment, 'You dont have enough tokens.');
        USDT.transferFrom(msg.sender, address(this), payment);
        
        require(state == State.SENDED, 'Invalid state');
        earnings = earnings + payment;
        emit DepositedEarnings(payment);   
    }
    
    function withdrawEarnings() external {
        require(state == State.SENDED, 'Invalid state');
        Investment memory investment = investor[msg.sender];
        uint temp = investment.fund;
        require(temp > 0, 'Your invested amount is 0');
        uint earning_temp = earnings.mul(investment.rate).div(CAP).sub(investment.earningTotal);
        if(earning_temp > 0) { 
            USDT.transfer(msg.sender, earning_temp); 
            investor[msg.sender] = Investment(temp, investment.rate, earning_temp + investment.earningTotal);
            emit InvestorReceived(earning_temp);
        }
    }
    
    function getInvestor(address inv) public view returns
    (
        uint256 fund,
        uint256 rate,
        uint256 earningTotal
    ) {
        Investment memory investment = investor[inv];
        fund = investment.fund;
        rate = investment.rate;
        earningTotal = investment.earningTotal;
    }

    function getDetails() public view returns 
    (
        address payable projectStarter,
        string memory projectTitle,
        string memory projectDesc,
        uint256 deadLine,
        State currentState,
        uint256 currentAmount,
        uint256 goalAmount,
        uint256 valueToComplete
    ) {
        projectStarter = creator;
        projectTitle = title;
        projectDesc = description;
        deadLine = deadline;
        currentState = state;
        currentAmount = currentBalance;
        goalAmount = assetAmount;
        valueToComplete = assetAmount.sub(currentBalance);
    }
    
    receive() external payable { 

    }
}
