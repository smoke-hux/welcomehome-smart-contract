// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./PropertyFactory.sol";
import "./interfaces/IPropertyToken.sol";

/// @title PropertyGovernance
/// @notice Governance contract for property-specific voting and proposal management
/// @dev Handles voting, proposals, and execution for individual tokenized properties
contract PropertyGovernance is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant PROPOSAL_CREATOR_ROLE = keccak256("PROPOSAL_CREATOR_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    enum ProposalType {
        MAINTENANCE,        // Property maintenance and repairs
        IMPROVEMENT,        // Property improvements and upgrades
        REFINANCE,          // Refinancing or loan modifications
        SALE,               // Property sale or liquidation
        MANAGEMENT,         // Property management changes
        DIVIDEND,           // Dividend distribution changes
        OTHER               // Other governance decisions
    }

    enum ProposalStatus {
        PENDING,            // Proposal created, voting not started
        ACTIVE,             // Voting is active
        SUCCEEDED,          // Proposal passed
        DEFEATED,           // Proposal failed
        EXECUTED,           // Proposal executed
        EXPIRED             // Proposal expired without execution
    }

    struct Proposal {
        uint256 id;
        uint256 propertyId;
        address proposer;
        string title;
        string description;
        string ipfsHash;        // Detailed proposal documents
        ProposalType proposalType;
        ProposalStatus status;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        uint256 totalVotes;
        uint256 startTime;
        uint256 endTime;
        uint256 executionTime;
        uint256 quorumRequired;  // Minimum participation required
        uint256 majorityRequired; // Percentage needed to pass (in basis points)
        bool executed;
        mapping(address => Vote) votes;
        address[] voters;
    }

    struct Vote {
        bool hasVoted;
        uint8 support;      // 0 = against, 1 = for, 2 = abstain
        uint256 votes;      // Number of votes cast
        uint256 timestamp;
    }

    // View structs for avoiding stack too deep errors
    struct ProposalView {
        uint256 id;
        uint256 propertyId;
        address proposer;
        string title;
        string description;
        string ipfsHash;
        ProposalType proposalType;
        ProposalStatus status;
        bool executed;
    }

    struct ProposalVotes {
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        uint256 totalVotes;
        uint256 quorumRequired;
        uint256 majorityRequired;
    }

    struct ProposalTimings {
        uint256 startTime;
        uint256 endTime;
        uint256 executionTime;
    }

    struct ProposalParams {
        uint256 votingDelay;       // Delay before voting starts (in blocks)
        uint256 votingPeriod;      // Duration of voting (in blocks)
        uint256 proposalThreshold; // Minimum tokens needed to create proposal
        uint256 quorumNumerator;   // Quorum percentage (in basis points)
        uint256 majorityNumerator; // Majority percentage (in basis points)
    }

    PropertyFactory public immutable propertyFactory;

    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => uint256[]) public propertyProposals; // propertyId => proposalIds
    mapping(uint256 => ProposalParams) public propertyGovernanceParams;

    uint256 public proposalCount;
    uint256 public constant VOTING_DELAY = 1 days;
    uint256 public constant VOTING_PERIOD = 7 days;
    uint256 public constant EXECUTION_DELAY = 2 days;
    uint256 public constant BASIS_POINTS = 10000;

    // Default governance parameters
    ProposalParams public defaultParams = ProposalParams({
        votingDelay: 1 days,
        votingPeriod: 7 days,
        proposalThreshold: 100 ether, // 100 tokens minimum
        quorumNumerator: 1000,        // 10% quorum
        majorityNumerator: 5000       // 50% majority
    });

    event ProposalCreated(
        uint256 indexed proposalId,
        uint256 indexed propertyId,
        address indexed proposer,
        string title,
        ProposalType proposalType,
        uint256 startTime,
        uint256 endTime
    );

    event VoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        uint8 support,
        uint256 votes,
        uint256 timestamp
    );

    event ProposalExecuted(
        uint256 indexed proposalId,
        uint256 indexed propertyId,
        ProposalStatus status
    );

    event ProposalStatusUpdated(
        uint256 indexed proposalId,
        ProposalStatus oldStatus,
        ProposalStatus newStatus
    );

    event GovernanceParamsUpdated(
        uint256 indexed propertyId,
        ProposalParams params
    );

    error PropertyNotFound();
    error ProposalNotFound();
    error InsufficientTokens();
    error VotingNotActive();
    error AlreadyVoted();
    error ProposalNotSucceeded();
    error ExecutionTooEarly();
    error ProposalExpired();
    error InvalidProposalData();
    error UnauthorizedVoter();

    modifier validPropertyId(uint256 propertyId) {
        if (propertyId >= propertyFactory.propertyCount()) revert PropertyNotFound();
        _;
    }

    modifier validProposalId(uint256 proposalId) {
        if (proposalId >= proposalCount) revert ProposalNotFound();
        _;
    }

    constructor(address _propertyFactory) {
        propertyFactory = PropertyFactory(payable(_propertyFactory));

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PROPOSAL_CREATOR_ROLE, msg.sender);
        _grantRole(EXECUTOR_ROLE, msg.sender);
    }

    function _getGovernanceParams(uint256 propertyId) internal view returns (ProposalParams memory) {
        return propertyGovernanceParams[propertyId].votingPeriod != 0
            ? propertyGovernanceParams[propertyId]
            : defaultParams;
    }

    function _validateProposerEligibility(
        address tokenContract,
        address proposer,
        uint256 threshold
    ) internal view {
        uint256 proposerBalance = IPropertyToken(tokenContract).balanceOf(proposer);
        if (proposerBalance < threshold) {
            revert InsufficientTokens();
        }
    }

    function _calculateQuorumRequired(
        address tokenContract,
        uint256 quorumNumerator
    ) internal view returns (uint256) {
        uint256 totalSupply = IPropertyToken(tokenContract).totalSupply();
        return (totalSupply * quorumNumerator) / BASIS_POINTS;
    }


    function _initializeProposalBasic(
        uint256 proposalId,
        uint256 propertyId,
        string memory title,
        string memory description,
        string memory ipfsHash,
        ProposalType proposalType
    ) internal {
        proposals[proposalId].id = proposalId;
        proposals[proposalId].propertyId = propertyId;
        proposals[proposalId].proposer = msg.sender;
        proposals[proposalId].title = title;
        proposals[proposalId].description = description;
        proposals[proposalId].ipfsHash = ipfsHash;
        proposals[proposalId].proposalType = proposalType;
        proposals[proposalId].status = ProposalStatus.PENDING;
    }

    function _initializeProposalGovernance(
        uint256 proposalId,
        uint256 votingDelay,
        uint256 votingPeriod,
        uint256 quorumRequired,
        uint256 majorityRequired
    ) internal {
        proposals[proposalId].startTime = block.timestamp + votingDelay;
        proposals[proposalId].endTime = proposals[proposalId].startTime + votingPeriod;
        proposals[proposalId].quorumRequired = quorumRequired;
        proposals[proposalId].majorityRequired = majorityRequired;
    }

    function createProposal(
        uint256 propertyId,
        string memory title,
        string memory description,
        string memory ipfsHash,
        ProposalType proposalType
    )
        external
        nonReentrant
        whenNotPaused
        validPropertyId(propertyId)
        returns (uint256 proposalId)
    {
        if (bytes(title).length == 0 || bytes(description).length == 0) {
            revert InvalidProposalData();
        }

        address tokenContract = propertyFactory.getProperty(propertyId).tokenContract;
        ProposalParams memory params = _getGovernanceParams(propertyId);

        _validateProposerEligibility(tokenContract, msg.sender, params.proposalThreshold);

        proposalId = proposalCount++;

        _initializeProposalBasic(
            proposalId,
            propertyId,
            title,
            description,
            ipfsHash,
            proposalType
        );

        _initializeProposalGovernance(
            proposalId,
            params.votingDelay,
            params.votingPeriod,
            _calculateQuorumRequired(tokenContract, params.quorumNumerator),
            params.majorityNumerator
        );
        propertyProposals[propertyId].push(proposalId);

        emit ProposalCreated(
            proposalId,
            propertyId,
            msg.sender,
            title,
            proposalType,
            proposals[proposalId].startTime,
            proposals[proposalId].endTime
        );
    }

    function vote(
        uint256 proposalId,
        uint8 support
    )
        external
        nonReentrant
        whenNotPaused
        validProposalId(proposalId)
    {
        Proposal storage proposal = proposals[proposalId];

        if (block.timestamp < proposal.startTime || block.timestamp > proposal.endTime) {
            revert VotingNotActive();
        }

        if (proposal.votes[msg.sender].hasVoted) {
            revert AlreadyVoted();
        }

        // Update proposal status to ACTIVE if it was PENDING
        if (proposal.status == ProposalStatus.PENDING) {
            proposal.status = ProposalStatus.ACTIVE;
        }

        // Get voter's voting power
        address tokenContract = propertyFactory.getProperty(proposal.propertyId).tokenContract;
        uint256 voterPower = IPropertyToken(tokenContract).balanceOf(msg.sender);

        if (voterPower == 0) revert UnauthorizedVoter();

        // Record the vote
        proposal.votes[msg.sender] = Vote({
            hasVoted: true,
            support: support,
            votes: voterPower,
            timestamp: block.timestamp
        });

        proposal.voters.push(msg.sender);

        // Update vote tallies
        if (support == 0) {
            proposal.againstVotes += voterPower;
        } else if (support == 1) {
            proposal.forVotes += voterPower;
        } else if (support == 2) {
            proposal.abstainVotes += voterPower;
        }

        proposal.totalVotes += voterPower;

        emit VoteCast(proposalId, msg.sender, support, voterPower, block.timestamp);
    }

    function executeProposal(
        uint256 proposalId
    )
        external
        nonReentrant
        validProposalId(proposalId)
        onlyRole(EXECUTOR_ROLE)
    {
        Proposal storage proposal = proposals[proposalId];

        if (proposal.executed) revert ProposalNotFound();
        if (block.timestamp <= proposal.endTime) revert ExecutionTooEarly();

        // Update proposal status based on voting results
        _updateProposalStatus(proposalId);

        if (proposal.status != ProposalStatus.SUCCEEDED) {
            revert ProposalNotSucceeded();
        }

        // Check execution delay for sensitive proposals
        if (proposal.proposalType == ProposalType.SALE || proposal.proposalType == ProposalType.REFINANCE) {
            if (block.timestamp < proposal.endTime + EXECUTION_DELAY) {
                revert ExecutionTooEarly();
            }
        }

        proposal.executed = true;
        proposal.executionTime = block.timestamp;
        proposal.status = ProposalStatus.EXECUTED;

        emit ProposalExecuted(proposalId, proposal.propertyId, ProposalStatus.EXECUTED);
    }

    function updateProposalStatus(
        uint256 proposalId
    )
        external
        validProposalId(proposalId)
    {
        _updateProposalStatus(proposalId);
    }

    function _updateProposalStatus(uint256 proposalId) internal {
        Proposal storage proposal = proposals[proposalId];
        ProposalStatus oldStatus = proposal.status;

        if (proposal.executed) {
            proposal.status = ProposalStatus.EXECUTED;
        } else if (block.timestamp > proposal.endTime) {
            // Check if proposal succeeded
            if (proposal.totalVotes >= proposal.quorumRequired) {
                uint256 majorityThreshold = (proposal.totalVotes * proposal.majorityRequired) / BASIS_POINTS;
                if (proposal.forVotes > majorityThreshold) {
                    proposal.status = ProposalStatus.SUCCEEDED;
                } else {
                    proposal.status = ProposalStatus.DEFEATED;
                }
            } else {
                proposal.status = ProposalStatus.DEFEATED;
            }

            // Check if too much time has passed for execution
            if (proposal.status == ProposalStatus.SUCCEEDED &&
                block.timestamp > proposal.endTime + 30 days) {
                proposal.status = ProposalStatus.EXPIRED;
            }
        } else if (block.timestamp >= proposal.startTime) {
            proposal.status = ProposalStatus.ACTIVE;
        }

        if (oldStatus != proposal.status) {
            emit ProposalStatusUpdated(proposalId, oldStatus, proposal.status);
        }
    }

    function getProposalInfo(uint256 proposalId)
        external
        view
        validProposalId(proposalId)
        returns (ProposalView memory)
    {
        Proposal storage proposal = proposals[proposalId];
        ProposalView memory result;
        result.id = proposal.id;
        result.propertyId = proposal.propertyId;
        result.proposer = proposal.proposer;
        result.title = proposal.title;
        result.description = proposal.description;
        result.ipfsHash = proposal.ipfsHash;
        result.proposalType = proposal.proposalType;
        result.status = proposal.status;
        result.executed = proposal.executed;
        return result;
    }

    function getProposalVotes(uint256 proposalId)
        external
        view
        validProposalId(proposalId)
        returns (ProposalVotes memory)
    {
        Proposal storage proposal = proposals[proposalId];
        ProposalVotes memory result;
        result.forVotes = proposal.forVotes;
        result.againstVotes = proposal.againstVotes;
        result.abstainVotes = proposal.abstainVotes;
        result.totalVotes = proposal.totalVotes;
        result.quorumRequired = proposal.quorumRequired;
        result.majorityRequired = proposal.majorityRequired;
        return result;
    }

    function getProposalTimings(uint256 proposalId)
        external
        view
        validProposalId(proposalId)
        returns (ProposalTimings memory)
    {
        Proposal storage proposal = proposals[proposalId];
        ProposalTimings memory result;
        result.startTime = proposal.startTime;
        result.endTime = proposal.endTime;
        result.executionTime = proposal.executionTime;
        return result;
    }


    function getPropertyProposals(uint256 propertyId)
        external
        view
        validPropertyId(propertyId)
        returns (uint256[] memory)
    {
        return propertyProposals[propertyId];
    }

    function getVoterInfo(uint256 proposalId, address voter)
        external
        view
        validProposalId(proposalId)
        returns (bool hasVoted, uint8 support, uint256 votes, uint256 timestamp)
    {
        Vote storage voterRecord = proposals[proposalId].votes[voter];
        return (voterRecord.hasVoted, voterRecord.support, voterRecord.votes, voterRecord.timestamp);
    }

    function getActiveProposals(uint256 propertyId)
        external
        view
        validPropertyId(propertyId)
        returns (uint256[] memory activeProposals)
    {
        uint256[] memory allProposals = propertyProposals[propertyId];
        uint256 activeCount = 0;

        // Count active proposals
        for (uint256 i = 0; i < allProposals.length; i++) {
            Proposal storage proposal = proposals[allProposals[i]];
            if (proposal.status == ProposalStatus.ACTIVE || proposal.status == ProposalStatus.PENDING) {
                activeCount++;
            }
        }

        activeProposals = new uint256[](activeCount);
        uint256 index = 0;

        // Populate active proposals
        for (uint256 i = 0; i < allProposals.length; i++) {
            Proposal storage proposal = proposals[allProposals[i]];
            if (proposal.status == ProposalStatus.ACTIVE || proposal.status == ProposalStatus.PENDING) {
                activeProposals[index] = allProposals[i];
                index++;
            }
        }
    }

    function setGovernanceParams(
        uint256 propertyId,
        ProposalParams memory params
    )
        external
        validPropertyId(propertyId)
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        propertyGovernanceParams[propertyId] = params;
        emit GovernanceParamsUpdated(propertyId, params);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}