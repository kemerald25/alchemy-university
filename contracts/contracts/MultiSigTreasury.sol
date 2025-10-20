// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MultiSigTreasury
 * @notice A multi-signature treasury contract with proposal-based spending
 * @dev Allows members to create proposals, vote on them, and execute approved transactions
 * 
 * Security Features:
 * - Reentrancy protection on critical functions
 * - Member-only access controls
 * - Proposal execution limits
 * - Vote changing with proper accounting
 * - Threshold validation
 * - Duplicate vote prevention
 */
contract MultiSigTreasury {
    
    // ============ State Variables ============
    
    /// @notice Minimum number of approvals required to execute a proposal
    uint256 public approvalThreshold;
    
    /// @notice Total number of members in the treasury
    uint256 public memberCount;
    
    /// @notice Mapping to track if an address is a member
    mapping(address => bool) public isMember;
    
    /// @notice Array of all member addresses
    address[] public members;
    
    /// @notice Counter for proposal IDs
    uint256 public proposalCount;
    
    // ============ Structs ============
    
    /// @notice Represents a spending proposal
    struct Proposal {
        address proposer;           // Who created the proposal
        address payable target;     // Where to send funds
        uint256 amount;            // How much to send
        string description;        // What it's for
        uint256 approvalCount;     // Current approval votes
        uint256 rejectionCount;    // Current rejection votes
        bool executed;             // Has it been executed
        bool cancelled;            // Has it been cancelled
        uint256 createdAt;        // When it was created
    }
    
    /// @notice Mapping from proposal ID to Proposal
    mapping(uint256 => Proposal) public proposals;
    
    /// @notice Tracks votes: proposalId => voter => vote (true = approve, false = reject)
    mapping(uint256 => mapping(address => bool)) public votes;
    
    /// @notice Tracks if member has voted: proposalId => voter => hasVoted
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    
    // ============ Events ============
    
    event MemberAdded(address indexed member, uint256 newMemberCount);
    event MemberRemoved(address indexed member, uint256 newMemberCount);
    event ThresholdChanged(uint256 oldThreshold, uint256 newThreshold);
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        address indexed target,
        uint256 amount,
        string description
    );
    event VoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        bool approve
    );
    event VoteChanged(
        uint256 indexed proposalId,
        address indexed voter,
        bool oldVote,
        bool newVote
    );
    event ProposalExecuted(
        uint256 indexed proposalId,
        address indexed executor,
        bool success
    );
    event ProposalCancelled(uint256 indexed proposalId, address indexed canceller);
    event FundsDeposited(address indexed depositor, uint256 amount);
    event FundsWithdrawn(address indexed recipient, uint256 amount);
    
    // ============ Modifiers ============
    
    /// @notice Restricts function access to members only
    modifier onlyMember() {
        require(isMember[msg.sender], "Not a member");
        _;
    }
    
    /// @notice Validates that a proposal exists and is valid
    modifier validProposal(uint256 proposalId) {
        require(proposalId < proposalCount, "Proposal does not exist");
        require(!proposals[proposalId].executed, "Proposal already executed");
        require(!proposals[proposalId].cancelled, "Proposal cancelled");
        _;
    }
    
    /// @notice Prevents reentrancy attacks
    bool private locked;
    modifier nonReentrant() {
        require(!locked, "Reentrancy detected");
        locked = true;
        _;
        locked = false;
    }
    
    // ============ Constructor ============
    
    /**
     * @notice Initializes the treasury with founding members
     * @param _members Array of initial member addresses
     * @param _approvalThreshold Number of approvals needed to execute proposals
     * @dev Deployer is automatically added as a member
     */
    constructor(address[] memory _members, uint256 _approvalThreshold) {
        require(_members.length > 0, "Need at least one member");
        require(_approvalThreshold > 0, "Threshold must be positive");
        require(_approvalThreshold <= _members.length + 1, "Threshold too high");
        
        // Add deployer as first member
        isMember[msg.sender] = true;
        members.push(msg.sender);
        memberCount = 1;
        
        // Add provided members
        for (uint256 i = 0; i < _members.length; i++) {
            address member = _members[i];
            
            // Security: Validate member address
            require(member != address(0), "Invalid member address");
            require(!isMember[member], "Duplicate member");
            require(member != msg.sender, "Deployer already added");
            
            isMember[member] = true;
            members.push(member);
            memberCount++;
        }
        
        approvalThreshold = _approvalThreshold;
        
        emit ThresholdChanged(0, _approvalThreshold);
    }
    
    // ============ Receive Function ============
    
    /**
     * @notice Allows the contract to receive ETH
     */
    receive() external payable {
        emit FundsDeposited(msg.sender, msg.value);
    }
    
    // ============ Member Management ============
    
    /**
     * @notice Creates a proposal to add a new member
     * @param newMember Address of the member to add
     * @return proposalId The ID of the created proposal
     * @dev This creates a special proposal that will call addMemberInternal
     */
    function proposeAddMember(address newMember) external onlyMember returns (uint256) {
        require(newMember != address(0), "Invalid address");
        require(!isMember[newMember], "Already a member");
        
        uint256 proposalId = proposalCount++;
        
        proposals[proposalId] = Proposal({
            proposer: msg.sender,
            target: payable(address(this)),
            amount: 0,
            description: string(abi.encodePacked("Add member: ", toAsciiString(newMember))),
            approvalCount: 0,
            rejectionCount: 0,
            executed: false,
            cancelled: false,
            createdAt: block.timestamp
        });
        
        emit ProposalCreated(
            proposalId,
            msg.sender,
            address(this),
            0,
            proposals[proposalId].description
        );
        
        return proposalId;
    }
    
    /**
     * @notice Internal function to add a member (called via proposal execution)
     * @param newMember Address to add as member
     */
    function addMemberInternal(address newMember) external {
        require(msg.sender == address(this), "Can only be called via proposal");
        require(!isMember[newMember], "Already a member");
        
        isMember[newMember] = true;
        members.push(newMember);
        memberCount++;
        
        emit MemberAdded(newMember, memberCount);
    }
    
    /**
     * @notice Creates a proposal to remove a member
     * @param memberToRemove Address of the member to remove
     * @return proposalId The ID of the created proposal
     */
    function proposeRemoveMember(address memberToRemove) external onlyMember returns (uint256) {
        require(isMember[memberToRemove], "Not a member");
        require(memberCount > 1, "Cannot remove last member");
        
        uint256 proposalId = proposalCount++;
        
        proposals[proposalId] = Proposal({
            proposer: msg.sender,
            target: payable(address(this)),
            amount: 0,
            description: string(abi.encodePacked("Remove member: ", toAsciiString(memberToRemove))),
            approvalCount: 0,
            rejectionCount: 0,
            executed: false,
            cancelled: false,
            createdAt: block.timestamp
        });
        
        emit ProposalCreated(
            proposalId,
            msg.sender,
            address(this),
            0,
            proposals[proposalId].description
        );
        
        return proposalId;
    }
    
    /**
     * @notice Internal function to remove a member
     * @param memberToRemove Address to remove
     */
    function removeMemberInternal(address memberToRemove) external {
        require(msg.sender == address(this), "Can only be called via proposal");
        require(isMember[memberToRemove], "Not a member");
        require(memberCount > 1, "Cannot remove last member");
        
        isMember[memberToRemove] = false;
        
        // Remove from members array
        for (uint256 i = 0; i < members.length; i++) {
            if (members[i] == memberToRemove) {
                members[i] = members[members.length - 1];
                members.pop();
                break;
            }
        }
        
        memberCount--;
        
        // Adjust threshold if needed
        if (approvalThreshold > memberCount) {
            uint256 oldThreshold = approvalThreshold;
            approvalThreshold = memberCount;
            emit ThresholdChanged(oldThreshold, approvalThreshold);
        }
        
        emit MemberRemoved(memberToRemove, memberCount);
    }
    
    // ============ Proposal Management ============
    
    /**
     * @notice Creates a new spending proposal
     * @param target Address to send funds to
     * @param amount Amount of ETH to send (in wei)
     * @param description Description of the proposal
     * @return proposalId The ID of the created proposal
     */
    function createProposal(
        address payable target,
        uint256 amount,
        string calldata description
    ) external onlyMember returns (uint256) {
        // Security checks
        require(target != address(0), "Invalid target address");
        require(amount > 0, "Amount must be positive");
        require(amount <= address(this).balance, "Insufficient treasury balance");
        require(bytes(description).length > 0, "Description required");
        require(bytes(description).length <= 500, "Description too long");
        
        uint256 proposalId = proposalCount++;
        
        proposals[proposalId] = Proposal({
            proposer: msg.sender,
            target: target,
            amount: amount,
            description: description,
            approvalCount: 0,
            rejectionCount: 0,
            executed: false,
            cancelled: false,
            createdAt: block.timestamp
        });
        
        emit ProposalCreated(proposalId, msg.sender, target, amount, description);
        
        return proposalId;
    }
    
    /**
     * @notice Cast or change a vote on a proposal
     * @param proposalId ID of the proposal
     * @param approve True to approve, false to reject
     */
    function vote(uint256 proposalId, bool approve) 
        external 
        onlyMember 
        validProposal(proposalId) 
    {
        Proposal storage proposal = proposals[proposalId];
        
        // Security: Prevent proposer from voting on their own proposal
        require(proposal.proposer != msg.sender, "Proposer cannot vote on own proposal");
        
        // Check if member has already voted
        if (hasVoted[proposalId][msg.sender]) {
            bool oldVote = votes[proposalId][msg.sender];
            
            // Only process if vote actually changed
            if (oldVote != approve) {
                // Revert old vote
                if (oldVote) {
                    proposal.approvalCount--;
                } else {
                    proposal.rejectionCount--;
                }
                
                // Apply new vote
                if (approve) {
                    proposal.approvalCount++;
                } else {
                    proposal.rejectionCount++;
                }
                
                votes[proposalId][msg.sender] = approve;
                
                emit VoteChanged(proposalId, msg.sender, oldVote, approve);
            }
        } else {
            // First time voting
            hasVoted[proposalId][msg.sender] = true;
            votes[proposalId][msg.sender] = approve;
            
            if (approve) {
                proposal.approvalCount++;
            } else {
                proposal.rejectionCount++;
            }
            
            emit VoteCast(proposalId, msg.sender, approve);
        }
        
        // Auto-execute if threshold reached
        if (proposal.approvalCount >= approvalThreshold && !proposal.executed) {
            _executeProposal(proposalId);
        }
    }
    
    /**
     * @notice Executes a proposal that has reached approval threshold
     * @param proposalId ID of the proposal to execute
     */
    function executeProposal(uint256 proposalId) 
        external 
        onlyMember 
        validProposal(proposalId)
        nonReentrant
    {
        Proposal storage proposal = proposals[proposalId];
        
        // Security: Verify approval threshold
        require(
            proposal.approvalCount >= approvalThreshold,
            "Insufficient approvals"
        );
        
        _executeProposal(proposalId);
    }
    
    /**
     * @notice Internal function to execute a proposal
     * @param proposalId ID of the proposal
     */
    function _executeProposal(uint256 proposalId) private {
        Proposal storage proposal = proposals[proposalId];
        
        // Security: Check again that it's not executed (in case called from vote)
        require(!proposal.executed, "Already executed");
        
        // Mark as executed before external call (Checks-Effects-Interactions pattern)
        proposal.executed = true;
        
        // Security: Verify sufficient balance
        require(address(this).balance >= proposal.amount, "Insufficient balance");
        
        // Execute the transaction
        (bool success, ) = proposal.target.call{value: proposal.amount}("");
        
        emit ProposalExecuted(proposalId, msg.sender, success);
        
        if (success && proposal.amount > 0) {
            emit FundsWithdrawn(proposal.target, proposal.amount);
        }
        
        // Security: Always check success for critical operations
        require(success, "Proposal execution failed");
    }
    
    /**
     * @notice Allows proposer to cancel their proposal before execution
     * @param proposalId ID of the proposal to cancel
     */
    function cancelProposal(uint256 proposalId) 
        external 
        validProposal(proposalId) 
    {
        Proposal storage proposal = proposals[proposalId];
        
        // Security: Only proposer can cancel
        require(
            proposal.proposer == msg.sender,
            "Only proposer can cancel"
        );
        
        proposal.cancelled = true;
        
        emit ProposalCancelled(proposalId, msg.sender);
    }
    
    /**
     * @notice Creates a proposal to change the approval threshold
     * @param newThreshold New approval threshold
     * @return proposalId The ID of the created proposal
     */
    function proposeThresholdChange(uint256 newThreshold) 
        external 
        onlyMember 
        returns (uint256) 
    {
        require(newThreshold > 0, "Threshold must be positive");
        require(newThreshold <= memberCount, "Threshold exceeds member count");
        require(newThreshold != approvalThreshold, "Same as current threshold");
        
        uint256 proposalId = proposalCount++;
        
        proposals[proposalId] = Proposal({
            proposer: msg.sender,
            target: payable(address(this)),
            amount: 0,
            description: string(abi.encodePacked(
                "Change threshold to: ",
                uint2str(newThreshold)
            )),
            approvalCount: 0,
            rejectionCount: 0,
            executed: false,
            cancelled: false,
            createdAt: block.timestamp
        });
        
        emit ProposalCreated(
            proposalId,
            msg.sender,
            address(this),
            0,
            proposals[proposalId].description
        );
        
        return proposalId;
    }
    
    /**
     * @notice Internal function to change threshold
     * @param newThreshold New threshold value
     */
    function changeThresholdInternal(uint256 newThreshold) external {
        require(msg.sender == address(this), "Can only be called via proposal");
        require(newThreshold > 0, "Threshold must be positive");
        require(newThreshold <= memberCount, "Threshold exceeds member count");
        
        uint256 oldThreshold = approvalThreshold;
        approvalThreshold = newThreshold;
        
        emit ThresholdChanged(oldThreshold, newThreshold);
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Get proposal details
     * @param proposalId ID of the proposal
     * @return Proposal struct
     */
    function getProposal(uint256 proposalId) 
        external 
        view 
        returns (Proposal memory) 
    {
        require(proposalId < proposalCount, "Proposal does not exist");
        return proposals[proposalId];
    }
    
    /**
     * @notice Get all member addresses
     * @return Array of member addresses
     */
    function getMembers() external view returns (address[] memory) {
        return members;
    }
    
    /**
     * @notice Get treasury balance
     * @return Balance in wei
     */
    function getTreasuryBalance() external view returns (uint256) {
        return address(this).balance;
    }
    
    /**
     * @notice Check if address has voted on a proposal
     * @param proposalId ID of the proposal
     * @param voter Address to check
     * @return hasVoted, vote (true = approve, false = reject)
     */
    function getVote(uint256 proposalId, address voter) 
        external 
        view 
        returns (bool, bool) 
    {
        return (hasVoted[proposalId][voter], votes[proposalId][voter]);
    }
    
    /**
     * @notice Get count of active proposals
     * @return Number of proposals that are not executed or cancelled
     */
    function getActiveProposalCount() external view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < proposalCount; i++) {
            if (!proposals[i].executed && !proposals[i].cancelled) {
                count++;
            }
        }
        return count;
    }
    
    // ============ Utility Functions ============
    
    /**
     * @notice Converts address to string
     * @param addr Address to convert
     * @return String representation
     */
    function toAsciiString(address addr) internal pure returns (string memory) {
        bytes memory s = new bytes(40);
        for (uint256 i = 0; i < 20; i++) {
            bytes1 b = bytes1(uint8(uint256(uint160(addr)) / (2**(8*(19 - i)))));
            bytes1 hi = bytes1(uint8(b) / 16);
            bytes1 lo = bytes1(uint8(b) - 16 * uint8(hi));
            s[2*i] = char(hi);
            s[2*i+1] = char(lo);
        }
        return string(abi.encodePacked("0x", string(s)));
    }
    
    function char(bytes1 b) internal pure returns (bytes1 c) {
        if (uint8(b) < 10) return bytes1(uint8(b) + 0x30);
        else return bytes1(uint8(b) + 0x57);
    }
    
    /**
     * @notice Converts uint to string
     */
    function uint2str(uint256 _i) internal pure returns (string memory str) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 length;
        while (j != 0) {
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        uint256 k = length;
        j = _i;
        while (j != 0) {
            bstr[--k] = bytes1(uint8(48 + j % 10));
            j /= 10;
        }
        str = string(bstr);
    }
}