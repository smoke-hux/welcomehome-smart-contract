// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/PropertyGovernance.sol";
import "../src/PropertyFactory.sol";
import "../src/SecureWelcomeHomeProperty.sol";
import "../src/PropertyTokenHandler.sol";
import "../src/MockKYCRegistry.sol";
import "../src/OwnershipRegistry.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockPaymentToken is ERC20 {
    constructor() ERC20("Mock HBAR", "HBAR") {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

contract PropertyGovernanceTest is Test {
    PropertyGovernance public governance;
    PropertyFactory public propertyFactory;
    MockPaymentToken public paymentToken;

    address public admin;
    address public voter1;
    address public voter2;
    address public feeCollector;

    uint256 public propertyId;
    address public propertyToken;

    function setUp() public {
        admin = address(this);
        voter1 = makeAddr("voter1");
        voter2 = makeAddr("voter2");
        feeCollector = makeAddr("feeCollector");

        paymentToken = new MockPaymentToken();
        MockKYCRegistry kycRegistry = new MockKYCRegistry();
        OwnershipRegistry ownershipRegistry = new OwnershipRegistry();

        propertyFactory = new PropertyFactory(feeCollector, address(kycRegistry), address(ownershipRegistry));
        governance = new PropertyGovernance(address(propertyFactory));

        // Grant necessary roles for property creation
        propertyFactory.grantRole(propertyFactory.PROPERTY_CREATOR_ROLE(), admin);

        // Grant ownership registry roles to property factory (needs both to register and grant roles)
        ownershipRegistry.grantRole(0x00, address(propertyFactory)); // DEFAULT_ADMIN_ROLE
        ownershipRegistry.grantRole(ownershipRegistry.REGISTRY_MANAGER_ROLE(), address(propertyFactory));

        // Create property for governance testing
        vm.deal(admin, 10 ether);
        PropertyFactory.PropertyDeploymentParams memory params = PropertyFactory.PropertyDeploymentParams({
            name: "Test Property",
            symbol: "TEST",
            ipfsHash: "QmTest123",
            totalValue: 1000000 * 10**18,
            maxTokens: 1000000 * 10**18,
            propertyType: PropertyFactory.PropertyType.RESIDENTIAL,
            location: "Test Location",
            paymentToken: address(paymentToken)
        });

        propertyId = propertyFactory.deployProperty{value: 1 ether}(params);
        PropertyFactory.PropertyInfo memory property = propertyFactory.getProperty(propertyId);
        propertyToken = property.tokenContract;

        // PropertyFactory now grants DEFAULT_ADMIN_ROLE back to caller (test contract)
        // Give voters tokens directly (MVP approach - skip complex token purchase flow)
        SecureWelcomeHomeProperty token = SecureWelcomeHomeProperty(propertyToken);
        token.grantRole(token.MINTER_ROLE(), admin);
        token.mint(admin, 200 * 10**18);   // Test contract needs tokens to create proposals (100+ required)
        token.mint(voter1, 500 * 10**18); // 50% voting power
        token.mint(voter2, 300 * 10**18); // 30% voting power
    }

    function testBasicGovernanceFlow() public {
        // 1. Create proposal
        uint256 proposalId = governance.createProposal(
            propertyId,
            "Property Maintenance",
            "Repair roof and paint exterior walls",
            "QmProposal123",
            PropertyGovernance.ProposalType.MAINTENANCE
        );

        assertEq(proposalId, 0);
        assertEq(governance.proposalCount(), 1);

        // 2. Wait for voting period to start
        vm.warp(block.timestamp + 1 days + 1);

        // 3. Vote
        vm.prank(voter1);
        governance.vote(proposalId, 1); // FOR

        vm.prank(voter2);
        governance.vote(proposalId, 1); // FOR

        // 4. Wait for voting period to end
        vm.warp(block.timestamp + 7 days + 1);

        // 5. Execute proposal
        governance.executeProposal(proposalId);

        // 6. Verify execution
        PropertyGovernance.ProposalView memory proposal = governance.getProposalInfo(proposalId);
        assertEq(uint256(proposal.status), uint256(PropertyGovernance.ProposalStatus.EXECUTED));
        assertTrue(proposal.executed);
    }

    function testVotingPower() public {
        uint256 proposalId = governance.createProposal(
            propertyId,
            "Test Proposal",
            "Test description",
            "QmTest",
            PropertyGovernance.ProposalType.MAINTENANCE
        );

        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(voter1);
        governance.vote(proposalId, 1); // 500 tokens FOR

        PropertyGovernance.ProposalVotes memory votes = governance.getProposalVotes(proposalId);
        assertEq(votes.forVotes, 500 * 10**18);
        assertEq(votes.totalVotes, 500 * 10**18);
    }

    function testProposalRejection() public {
        uint256 proposalId = governance.createProposal(
            propertyId,
            "Bad Proposal",
            "This should be rejected",
            "QmBad",
            PropertyGovernance.ProposalType.SALE
        );

        vm.warp(block.timestamp + 1 days + 1);

        // Vote against
        vm.prank(voter1);
        governance.vote(proposalId, 0); // AGAINST

        vm.prank(voter2);
        governance.vote(proposalId, 0); // AGAINST

        vm.warp(block.timestamp + 7 days + 1);
        governance.updateProposalStatus(proposalId);

        PropertyGovernance.ProposalView memory proposal = governance.getProposalInfo(proposalId);
        assertEq(uint256(proposal.status), uint256(PropertyGovernance.ProposalStatus.DEFEATED));
    }

    function testCannotVoteTwice() public {
        uint256 proposalId = governance.createProposal(
            propertyId,
            "Test",
            "Test",
            "QmTest",
            PropertyGovernance.ProposalType.MAINTENANCE
        );

        vm.warp(block.timestamp + 1 days + 1);

        vm.startPrank(voter1);
        governance.vote(proposalId, 1);

        vm.expectRevert(PropertyGovernance.AlreadyVoted.selector);
        governance.vote(proposalId, 0);
        vm.stopPrank();
    }
}