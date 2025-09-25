// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MockKYCRegistry.sol";

contract MockKYCRegistryTest is Test {
    MockKYCRegistry public kycRegistry;

    address public admin;
    address public kycManager;
    address public kycReviewer;
    address public user1;
    address public user2;
    address public user3;
    address public user4;

    string public constant DOCUMENT_HASH = "QmTest123DocumentHash";
    string public constant DENIAL_REASON = "Insufficient documentation";

    event KYCSubmitted(address indexed user, string documentHash, uint256 submittedAt);
    event KYCApproved(address indexed user, MockKYCRegistry.InvestorType investorType, address approvedBy, uint256 expiresAt);
    event KYCDenied(address indexed user, string reason, address reviewedBy);
    event KYCExpired(address indexed user, uint256 expiredAt);

    function setUp() public {
        admin = makeAddr("admin");
        kycManager = makeAddr("kycManager");
        kycReviewer = makeAddr("kycReviewer");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        user4 = makeAddr("user4");

        vm.startPrank(admin);

        // Deploy KYC registry
        kycRegistry = new MockKYCRegistry();

        // Grant roles
        kycRegistry.grantRole(kycRegistry.KYC_MANAGER_ROLE(), kycManager);
        kycRegistry.grantRole(kycRegistry.KYC_REVIEWER_ROLE(), kycReviewer);

        vm.stopPrank();
    }

    function testInitialSetup() public view {
        assertTrue(kycRegistry.hasRole(kycRegistry.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(kycRegistry.hasRole(kycRegistry.KYC_MANAGER_ROLE(), admin));
        assertTrue(kycRegistry.hasRole(kycRegistry.KYC_REVIEWER_ROLE(), admin));
        assertTrue(kycRegistry.hasRole(kycRegistry.KYC_MANAGER_ROLE(), kycManager));
        assertTrue(kycRegistry.hasRole(kycRegistry.KYC_REVIEWER_ROLE(), kycReviewer));

        assertEq(kycRegistry.KYC_VALIDITY_PERIOD(), 365 days);
        assertTrue(kycRegistry.isKYCSystemActive());

        // Check initial stats
        MockKYCRegistry.KYCStats memory stats = kycRegistry.getGlobalStats();
        assertEq(stats.totalSubmissions, 0);
        assertEq(stats.totalApproved, 0);
        assertEq(stats.totalDenied, 0);
        assertEq(stats.totalPending, 0);
        assertEq(stats.totalExpired, 0);
    }

    function testSubmitKYC() public {
        vm.startPrank(user1);

        vm.expectEmit(true, false, false, true);
        emit KYCSubmitted(user1, DOCUMENT_HASH, block.timestamp);

        kycRegistry.submitKYC(DOCUMENT_HASH, MockKYCRegistry.InvestorType.ACCREDITED);

        vm.stopPrank();

        // Verify KYC record
        MockKYCRegistry.KYCRecord memory record = kycRegistry.getKYCRecord(user1);
        assertEq(uint256(record.status), uint256(MockKYCRegistry.KYCStatus.PENDING));
        assertEq(uint256(record.investorType), uint256(MockKYCRegistry.InvestorType.ACCREDITED));
        assertEq(record.approvedAt, 0);
        assertEq(record.expiresAt, 0);
        assertEq(record.approvedBy, address(0));
        assertEq(record.documentHash, DOCUMENT_HASH);
        assertEq(record.rejectionReason, "");
        assertEq(record.submittedAt, block.timestamp);
        assertTrue(record.isActive);

        // Verify status
        assertEq(uint256(kycRegistry.getKYCStatus(user1)), uint256(MockKYCRegistry.KYCStatus.PENDING));
        assertFalse(kycRegistry.isKYCApproved(user1));
        assertFalse(kycRegistry.isAccreditedInvestor(user1));

        // Verify pending list
        address[] memory pendingUsers = kycRegistry.getPendingApplications();
        assertEq(pendingUsers.length, 1);
        assertEq(pendingUsers[0], user1);

        // Verify stats
        MockKYCRegistry.KYCStats memory stats = kycRegistry.getGlobalStats();
        assertEq(stats.totalSubmissions, 1);
        assertEq(stats.totalPending, 1);
        assertEq(stats.totalApproved, 0);
        assertEq(stats.totalDenied, 0);
    }

    function testCannotSubmitKYCTwice() public {
        vm.startPrank(user1);

        kycRegistry.submitKYC(DOCUMENT_HASH, MockKYCRegistry.InvestorType.RETAIL);

        vm.expectRevert(MockKYCRegistry.KYCAlreadySubmitted.selector);
        kycRegistry.submitKYC("AnotherHash", MockKYCRegistry.InvestorType.ACCREDITED);

        vm.stopPrank();
    }

    function testCannotSubmitKYCWithEmptyHash() public {
        vm.startPrank(user1);

        vm.expectRevert(MockKYCRegistry.InvalidDocumentHash.selector);
        kycRegistry.submitKYC("", MockKYCRegistry.InvestorType.RETAIL);

        vm.stopPrank();
    }

    function testCannotSubmitKYCWhenPaused() public {
        vm.startPrank(admin);
        kycRegistry.pause();
        vm.stopPrank();

        vm.startPrank(user1);

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        kycRegistry.submitKYC(DOCUMENT_HASH, MockKYCRegistry.InvestorType.RETAIL);

        vm.stopPrank();
    }

    function testApproveKYC() public {
        // First submit KYC
        vm.startPrank(user1);
        kycRegistry.submitKYC(DOCUMENT_HASH, MockKYCRegistry.InvestorType.ACCREDITED);
        vm.stopPrank();

        // Approve it
        vm.startPrank(kycReviewer);

        uint256 expectedExpiry = block.timestamp + kycRegistry.KYC_VALIDITY_PERIOD();

        vm.expectEmit(true, true, true, false);
        emit KYCApproved(user1, MockKYCRegistry.InvestorType.ACCREDITED, kycReviewer, expectedExpiry);

        kycRegistry.approveKYC(user1);

        vm.stopPrank();

        // Verify KYC record
        MockKYCRegistry.KYCRecord memory record = kycRegistry.getKYCRecord(user1);
        assertEq(uint256(record.status), uint256(MockKYCRegistry.KYCStatus.APPROVED));
        assertEq(record.approvedAt, block.timestamp);
        assertEq(record.expiresAt, expectedExpiry);
        assertEq(record.approvedBy, kycReviewer);

        // Verify status checks
        assertTrue(kycRegistry.isKYCApproved(user1));
        assertTrue(kycRegistry.isAccreditedInvestor(user1)); // ACCREDITED type
        assertTrue(kycRegistry.accreditedInvestors(user1));

        // Verify lists
        address[] memory pendingUsers = kycRegistry.getPendingApplications();
        assertEq(pendingUsers.length, 0);

        address[] memory approvedUsers = kycRegistry.getApprovedUsers();
        assertEq(approvedUsers.length, 1);
        assertEq(approvedUsers[0], user1);

        // Verify stats
        MockKYCRegistry.KYCStats memory stats = kycRegistry.getGlobalStats();
        assertEq(stats.totalSubmissions, 1);
        assertEq(stats.totalPending, 0);
        assertEq(stats.totalApproved, 1);
        assertEq(stats.totalDenied, 0);
    }

    function testApproveRetailInvestor() public {
        // Submit as retail investor
        vm.startPrank(user1);
        kycRegistry.submitKYC(DOCUMENT_HASH, MockKYCRegistry.InvestorType.RETAIL);
        vm.stopPrank();

        // Approve it
        vm.startPrank(kycReviewer);
        kycRegistry.approveKYC(user1);
        vm.stopPrank();

        // Retail investors should not be marked as accredited
        assertTrue(kycRegistry.isKYCApproved(user1));
        assertFalse(kycRegistry.isAccreditedInvestor(user1));
        assertFalse(kycRegistry.accreditedInvestors(user1));
    }

    function testApproveInstitutionalInvestor() public {
        // Submit as institutional investor
        vm.startPrank(user1);
        kycRegistry.submitKYC(DOCUMENT_HASH, MockKYCRegistry.InvestorType.INSTITUTIONAL);
        vm.stopPrank();

        // Approve it
        vm.startPrank(kycReviewer);
        kycRegistry.approveKYC(user1);
        vm.stopPrank();

        // Institutional investors should be marked as accredited
        assertTrue(kycRegistry.isKYCApproved(user1));
        assertTrue(kycRegistry.isAccreditedInvestor(user1));
        assertTrue(kycRegistry.accreditedInvestors(user1));
    }

    function testCannotApproveWithoutRole() public {
        vm.startPrank(user1);
        kycRegistry.submitKYC(DOCUMENT_HASH, MockKYCRegistry.InvestorType.RETAIL);
        vm.stopPrank();

        vm.startPrank(user2);
        vm.expectRevert();
        kycRegistry.approveKYC(user1);
        vm.stopPrank();
    }

    function testCannotApproveNonexistentKYC() public {
        vm.startPrank(kycReviewer);

        vm.expectRevert(MockKYCRegistry.KYCNotSubmitted.selector);
        kycRegistry.approveKYC(user1);

        vm.stopPrank();
    }

    function testCannotApproveAlreadyProcessed() public {
        // Submit and approve KYC
        vm.startPrank(user1);
        kycRegistry.submitKYC(DOCUMENT_HASH, MockKYCRegistry.InvestorType.RETAIL);
        vm.stopPrank();

        vm.startPrank(kycReviewer);
        kycRegistry.approveKYC(user1);

        // Try to approve again
        vm.expectRevert(MockKYCRegistry.KYCAlreadyProcessed.selector);
        kycRegistry.approveKYC(user1);

        vm.stopPrank();
    }

    function testDenyKYC() public {
        // Submit KYC
        vm.startPrank(user1);
        kycRegistry.submitKYC(DOCUMENT_HASH, MockKYCRegistry.InvestorType.RETAIL);
        vm.stopPrank();

        // Deny it
        vm.startPrank(kycReviewer);

        vm.expectEmit(true, false, false, true);
        emit KYCDenied(user1, DENIAL_REASON, kycReviewer);

        kycRegistry.denyKYC(user1, DENIAL_REASON);

        vm.stopPrank();

        // Verify record
        MockKYCRegistry.KYCRecord memory record = kycRegistry.getKYCRecord(user1);
        assertEq(uint256(record.status), uint256(MockKYCRegistry.KYCStatus.DENIED));
        assertEq(record.rejectionReason, DENIAL_REASON);

        // Verify status checks
        assertFalse(kycRegistry.isKYCApproved(user1));
        assertFalse(kycRegistry.isAccreditedInvestor(user1));

        // Verify lists
        address[] memory pendingUsers = kycRegistry.getPendingApplications();
        assertEq(pendingUsers.length, 0);

        // Verify stats
        MockKYCRegistry.KYCStats memory stats = kycRegistry.getGlobalStats();
        assertEq(stats.totalSubmissions, 1);
        assertEq(stats.totalPending, 0);
        assertEq(stats.totalApproved, 0);
        assertEq(stats.totalDenied, 1);
    }

    function testCannotDenyWithoutRole() public {
        vm.startPrank(user1);
        kycRegistry.submitKYC(DOCUMENT_HASH, MockKYCRegistry.InvestorType.RETAIL);
        vm.stopPrank();

        vm.startPrank(user2);
        vm.expectRevert();
        kycRegistry.denyKYC(user1, DENIAL_REASON);
        vm.stopPrank();
    }

    function testSetAccreditedInvestor() public {
        vm.startPrank(kycManager);

        kycRegistry.setAccreditedInvestor(user1, true);

        vm.stopPrank();

        // Verify user is now accredited with auto-approved KYC
        assertTrue(kycRegistry.isKYCApproved(user1));
        assertTrue(kycRegistry.isAccreditedInvestor(user1));

        MockKYCRegistry.KYCRecord memory record = kycRegistry.getKYCRecord(user1);
        assertEq(uint256(record.status), uint256(MockKYCRegistry.KYCStatus.APPROVED));
        assertEq(uint256(record.investorType), uint256(MockKYCRegistry.InvestorType.ACCREDITED));
        assertEq(record.documentHash, "mock-approval");
        assertEq(record.approvedBy, kycManager);
        assertEq(record.submittedAt, block.timestamp);
        assertEq(record.approvedAt, block.timestamp);

        // Verify stats updated
        MockKYCRegistry.KYCStats memory stats = kycRegistry.getGlobalStats();
        assertEq(stats.totalSubmissions, 1);
        assertEq(stats.totalApproved, 1);
    }

    function testCannotSetAccreditedWithoutRole() public {
        vm.startPrank(user1);

        vm.expectRevert();
        kycRegistry.setAccreditedInvestor(user2, true);

        vm.stopPrank();
    }

    function testExpireKYC() public {
        // Setup approved user
        vm.startPrank(kycManager);
        kycRegistry.setAccreditedInvestor(user1, true);
        vm.stopPrank();

        assertTrue(kycRegistry.isKYCApproved(user1));
        assertTrue(kycRegistry.isAccreditedInvestor(user1));

        // Expire KYC
        vm.startPrank(kycManager);

        vm.expectEmit(true, false, false, true);
        emit KYCExpired(user1, block.timestamp);

        kycRegistry.expireKYC(user1);

        vm.stopPrank();

        // Verify expiration
        MockKYCRegistry.KYCRecord memory record = kycRegistry.getKYCRecord(user1);
        assertEq(uint256(record.status), uint256(MockKYCRegistry.KYCStatus.EXPIRED));
        assertFalse(kycRegistry.accreditedInvestors(user1));
        assertFalse(kycRegistry.isKYCApproved(user1));
        assertFalse(kycRegistry.isAccreditedInvestor(user1));

        // Verify stats
        MockKYCRegistry.KYCStats memory stats = kycRegistry.getGlobalStats();
        assertEq(stats.totalApproved, 0);
        assertEq(stats.totalExpired, 1);
    }

    function testKYCExpirationByTime() public {
        // Submit and approve KYC
        vm.startPrank(user1);
        kycRegistry.submitKYC(DOCUMENT_HASH, MockKYCRegistry.InvestorType.ACCREDITED);
        vm.stopPrank();

        vm.startPrank(kycReviewer);
        kycRegistry.approveKYC(user1);
        vm.stopPrank();

        // Verify initially approved
        assertTrue(kycRegistry.isKYCApproved(user1));
        assertEq(uint256(kycRegistry.getKYCStatus(user1)), uint256(MockKYCRegistry.KYCStatus.APPROVED));

        // Warp time past expiration
        vm.warp(block.timestamp + kycRegistry.KYC_VALIDITY_PERIOD() + 1);

        // Verify expired
        assertFalse(kycRegistry.isKYCApproved(user1));
        assertFalse(kycRegistry.isAccreditedInvestor(user1)); // Should be false due to expiration
        assertEq(uint256(kycRegistry.getKYCStatus(user1)), uint256(MockKYCRegistry.KYCStatus.EXPIRED));
    }

    function testBatchApprove() public {
        address[] memory users = new address[](3);
        MockKYCRegistry.InvestorType[] memory investorTypes = new MockKYCRegistry.InvestorType[](3);

        users[0] = user1;
        users[1] = user2;
        users[2] = user3;

        investorTypes[0] = MockKYCRegistry.InvestorType.RETAIL;
        investorTypes[1] = MockKYCRegistry.InvestorType.ACCREDITED;
        investorTypes[2] = MockKYCRegistry.InvestorType.INSTITUTIONAL;

        vm.startPrank(kycManager);

        kycRegistry.batchApprove(users, investorTypes);

        vm.stopPrank();

        // Verify all users
        assertTrue(kycRegistry.isKYCApproved(user1));
        assertFalse(kycRegistry.isAccreditedInvestor(user1)); // RETAIL

        assertTrue(kycRegistry.isKYCApproved(user2));
        assertTrue(kycRegistry.isAccreditedInvestor(user2)); // ACCREDITED

        assertTrue(kycRegistry.isKYCApproved(user3));
        assertTrue(kycRegistry.isAccreditedInvestor(user3)); // INSTITUTIONAL

        // Verify approved users list
        address[] memory approvedUsers = kycRegistry.getApprovedUsers();
        assertEq(approvedUsers.length, 3);

        // Verify stats
        MockKYCRegistry.KYCStats memory stats = kycRegistry.getGlobalStats();
        assertEq(stats.totalSubmissions, 3);
        assertEq(stats.totalApproved, 3);
    }

    function testBatchApproveArrayLengthMismatch() public {
        address[] memory users = new address[](2);
        MockKYCRegistry.InvestorType[] memory investorTypes = new MockKYCRegistry.InvestorType[](3);

        users[0] = user1;
        users[1] = user2;

        investorTypes[0] = MockKYCRegistry.InvestorType.RETAIL;
        investorTypes[1] = MockKYCRegistry.InvestorType.ACCREDITED;
        investorTypes[2] = MockKYCRegistry.InvestorType.INSTITUTIONAL;

        vm.startPrank(kycManager);

        vm.expectRevert("Array length mismatch");
        kycRegistry.batchApprove(users, investorTypes);

        vm.stopPrank();
    }

    function testPauseUnpause() public {
        vm.startPrank(admin);

        kycRegistry.pause();
        assertFalse(kycRegistry.isKYCSystemActive());
        assertTrue(kycRegistry.paused());

        kycRegistry.unpause();
        assertTrue(kycRegistry.isKYCSystemActive());
        assertFalse(kycRegistry.paused());

        vm.stopPrank();
    }

    function testCannotPauseWithoutRole() public {
        vm.startPrank(user1);

        vm.expectRevert();
        kycRegistry.pause();

        vm.stopPrank();
    }

    function testMultipleKYCWorkflow() public {
        // Submit multiple KYC applications
        vm.startPrank(user1);
        kycRegistry.submitKYC(DOCUMENT_HASH, MockKYCRegistry.InvestorType.RETAIL);
        vm.stopPrank();

        vm.startPrank(user2);
        kycRegistry.submitKYC("Hash2", MockKYCRegistry.InvestorType.ACCREDITED);
        vm.stopPrank();

        vm.startPrank(user3);
        kycRegistry.submitKYC("Hash3", MockKYCRegistry.InvestorType.INSTITUTIONAL);
        vm.stopPrank();

        // Verify pending
        address[] memory pendingUsers = kycRegistry.getPendingApplications();
        assertEq(pendingUsers.length, 3);

        MockKYCRegistry.KYCStats memory stats = kycRegistry.getGlobalStats();
        assertEq(stats.totalSubmissions, 3);
        assertEq(stats.totalPending, 3);

        // Process applications
        vm.startPrank(kycReviewer);
        kycRegistry.approveKYC(user1);
        kycRegistry.approveKYC(user2);
        kycRegistry.denyKYC(user3, "Failed verification");
        vm.stopPrank();

        // Verify final states
        assertTrue(kycRegistry.isKYCApproved(user1));
        assertFalse(kycRegistry.isAccreditedInvestor(user1)); // RETAIL

        assertTrue(kycRegistry.isKYCApproved(user2));
        assertTrue(kycRegistry.isAccreditedInvestor(user2)); // ACCREDITED

        assertFalse(kycRegistry.isKYCApproved(user3));
        assertFalse(kycRegistry.isAccreditedInvestor(user3)); // DENIED

        // Verify lists
        pendingUsers = kycRegistry.getPendingApplications();
        assertEq(pendingUsers.length, 0);

        address[] memory approvedUsers = kycRegistry.getApprovedUsers();
        assertEq(approvedUsers.length, 2);

        // Verify final stats
        stats = kycRegistry.getGlobalStats();
        assertEq(stats.totalSubmissions, 3);
        assertEq(stats.totalPending, 0);
        assertEq(stats.totalApproved, 2);
        assertEq(stats.totalDenied, 1);
    }

    function testFuzzKYCWorkflow(uint8 investorTypeIndex, bool shouldApprove) public {
        // Bound investor type to valid range
        investorTypeIndex = uint8(bound(investorTypeIndex, 0, 2));
        MockKYCRegistry.InvestorType investorType = MockKYCRegistry.InvestorType(investorTypeIndex);

        // Submit KYC
        vm.startPrank(user1);
        kycRegistry.submitKYC(DOCUMENT_HASH, investorType);
        vm.stopPrank();

        // Process KYC
        vm.startPrank(kycReviewer);
        if (shouldApprove) {
            kycRegistry.approveKYC(user1);
            assertTrue(kycRegistry.isKYCApproved(user1));

            // Check accredited status based on investor type
            bool shouldBeAccredited = (investorType == MockKYCRegistry.InvestorType.ACCREDITED ||
                                     investorType == MockKYCRegistry.InvestorType.INSTITUTIONAL);
            assertEq(kycRegistry.isAccreditedInvestor(user1), shouldBeAccredited);
        } else {
            kycRegistry.denyKYC(user1, DENIAL_REASON);
            assertFalse(kycRegistry.isKYCApproved(user1));
            assertFalse(kycRegistry.isAccreditedInvestor(user1));
        }
        vm.stopPrank();
    }

    function testZeroAddressProtection() public {
        vm.startPrank(kycReviewer);

        vm.expectRevert(MockKYCRegistry.ZeroAddress.selector);
        kycRegistry.approveKYC(address(0));

        vm.expectRevert(MockKYCRegistry.ZeroAddress.selector);
        kycRegistry.denyKYC(address(0), DENIAL_REASON);

        vm.stopPrank();

        vm.startPrank(kycManager);

        vm.expectRevert(MockKYCRegistry.ZeroAddress.selector);
        kycRegistry.setAccreditedInvestor(address(0), true);

        vm.expectRevert(MockKYCRegistry.ZeroAddress.selector);
        kycRegistry.expireKYC(address(0));

        vm.stopPrank();
    }
}