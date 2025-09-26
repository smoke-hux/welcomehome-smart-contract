// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/// @title MockKYCRegistry
/// @notice MVP implementation of KYC verification system for property investment platform
/// @dev Simple approved/denied status tracking for accredited investors
contract MockKYCRegistry is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant KYC_MANAGER_ROLE = keccak256("KYC_MANAGER_ROLE");
    bytes32 public constant KYC_REVIEWER_ROLE = keccak256("KYC_REVIEWER_ROLE");

    enum KYCStatus { NONE, PENDING, APPROVED, DENIED, EXPIRED }
    enum InvestorType { RETAIL, ACCREDITED, INSTITUTIONAL }

    struct KYCRecord {
        KYCStatus status;
        InvestorType investorType;
        uint256 approvedAt;
        uint256 expiresAt;
        address approvedBy;
        string documentHash; // IPFS hash of KYC documents
        string rejectionReason;
        uint256 submittedAt;
        bool isActive;
    }

    struct KYCStats {
        uint256 totalSubmissions;
        uint256 totalApproved;
        uint256 totalDenied;
        uint256 totalPending;
        uint256 totalExpired;
    }

    mapping(address => KYCRecord) public kycRecords;
    mapping(address => bool) public accreditedInvestors; // Quick lookup for PropertyTokenHandler
    address[] public approvedUsers;
    address[] public pendingUsers;

    KYCStats public globalStats;
    uint256 public constant KYC_VALIDITY_PERIOD = 365 days; // 1 year validity

    event KYCSubmitted(address indexed user, string documentHash, uint256 submittedAt);
    event KYCApproved(address indexed user, InvestorType investorType, address approvedBy, uint256 expiresAt);
    event KYCDenied(address indexed user, string reason, address reviewedBy);
    event KYCExpired(address indexed user, uint256 expiredAt);
    event KYCUpdated(address indexed user, KYCStatus oldStatus, KYCStatus newStatus);

    error KYCAlreadySubmitted();
    error KYCNotSubmitted();
    error KYCAlreadyProcessed();
    error InvalidKYCStatus();
    error UnauthorizedReviewer();
    error ZeroAddress();
    error InvalidDocumentHash();
    error KYCAlreadyExpired();

    modifier validAddress(address addr) {
        if (addr == address(0)) revert ZeroAddress();
        _;
    }

    modifier validDocumentHash(string memory hash) {
        if (bytes(hash).length == 0) revert InvalidDocumentHash();
        _;
    }

    modifier kycExists(address user) {
        if (kycRecords[user].submittedAt == 0) revert KYCNotSubmitted();
        _;
    }

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(KYC_MANAGER_ROLE, msg.sender);
        _grantRole(KYC_REVIEWER_ROLE, msg.sender);
    }

    /// @notice Submit KYC documentation for review (mock implementation)
    function submitKYC(
        string memory documentHash,
        InvestorType investorType
    )
        external
        validDocumentHash(documentHash)
        whenNotPaused
    {
        if (kycRecords[msg.sender].submittedAt != 0) revert KYCAlreadySubmitted();

        kycRecords[msg.sender] = KYCRecord({
            status: KYCStatus.PENDING,
            investorType: investorType,
            approvedAt: 0,
            expiresAt: 0,
            approvedBy: address(0),
            documentHash: documentHash,
            rejectionReason: "",
            submittedAt: block.timestamp,
            isActive: true
        });

        pendingUsers.push(msg.sender);
        globalStats.totalSubmissions++;
        globalStats.totalPending++;

        emit KYCSubmitted(msg.sender, documentHash, block.timestamp);
    }

    /// @notice Approve KYC application (admin function)
    function approveKYC(address user)
        external
        onlyRole(KYC_REVIEWER_ROLE)
        validAddress(user)
        kycExists(user)
    {
        KYCRecord storage record = kycRecords[user];

        if (record.status != KYCStatus.PENDING) revert KYCAlreadyProcessed();

        uint256 expiresAt = block.timestamp + KYC_VALIDITY_PERIOD;

        record.status = KYCStatus.APPROVED;
        record.approvedAt = block.timestamp;
        record.expiresAt = expiresAt;
        record.approvedBy = msg.sender;

        // Set accredited investor status based on investor type
        if (record.investorType == InvestorType.ACCREDITED || record.investorType == InvestorType.INSTITUTIONAL) {
            accreditedInvestors[user] = true;
        }

        approvedUsers.push(user);
        _removeFromPendingList(user);

        globalStats.totalApproved++;
        globalStats.totalPending--;

        emit KYCApproved(user, record.investorType, msg.sender, expiresAt);
    }

    /// @notice Deny KYC application
    function denyKYC(address user, string memory reason)
        external
        onlyRole(KYC_REVIEWER_ROLE)
        validAddress(user)
        kycExists(user)
    {
        KYCRecord storage record = kycRecords[user];

        if (record.status != KYCStatus.PENDING) revert KYCAlreadyProcessed();

        record.status = KYCStatus.DENIED;
        record.rejectionReason = reason;

        _removeFromPendingList(user);

        globalStats.totalDenied++;
        globalStats.totalPending--;

        emit KYCDenied(user, reason, msg.sender);
    }

    /// @notice Check if user is approved and KYC is still valid
    function isKYCApproved(address user) external view returns (bool) {
        KYCRecord memory record = kycRecords[user];
        return record.status == KYCStatus.APPROVED && block.timestamp < record.expiresAt;
    }

    /// @notice Check if user is accredited investor
    function isAccreditedInvestor(address user) external view returns (bool) {
        return accreditedInvestors[user] && this.isKYCApproved(user);
    }

    /// @notice Get user's complete KYC record
    function getKYCRecord(address user) external view returns (KYCRecord memory) {
        return kycRecords[user];
    }

    /// @notice Get KYC status for a user
    function getKYCStatus(address user) external view returns (KYCStatus) {
        KYCRecord memory record = kycRecords[user];

        // Check if approved KYC has expired
        if (record.status == KYCStatus.APPROVED && block.timestamp >= record.expiresAt) {
            return KYCStatus.EXPIRED;
        }

        return record.status;
    }

    /// @notice Get all pending KYC applications
    function getPendingApplications() external view returns (address[] memory) {
        return pendingUsers;
    }

    /// @notice Get all approved users
    function getApprovedUsers() external view returns (address[] memory) {
        return approvedUsers;
    }

    /// @notice Get global KYC statistics
    function getGlobalStats() external view returns (KYCStats memory) {
        return globalStats;
    }

    /// @notice Admin function to manually set accredited investor status (for testing)
    function setAccreditedInvestor(address user, bool status)
        external
        onlyRole(KYC_MANAGER_ROLE)
        validAddress(user)
    {
        accreditedInvestors[user] = status;

        if (status && kycRecords[user].status != KYCStatus.APPROVED) {
            // Auto-approve KYC if setting as accredited
            kycRecords[user] = KYCRecord({
                status: KYCStatus.APPROVED,
                investorType: InvestorType.ACCREDITED,
                approvedAt: block.timestamp,
                expiresAt: block.timestamp + KYC_VALIDITY_PERIOD,
                approvedBy: msg.sender,
                documentHash: "mock-approval",
                rejectionReason: "",
                submittedAt: block.timestamp,
                isActive: true
            });

            if (kycRecords[user].submittedAt == block.timestamp) {
                globalStats.totalSubmissions++;
                globalStats.totalApproved++;
            }

            approvedUsers.push(user);
        }
    }

    /// @notice Expire KYC for users (automated or manual)
    function expireKYC(address user)
        external
        onlyRole(KYC_MANAGER_ROLE)
        validAddress(user)
    {
        KYCRecord storage record = kycRecords[user];

        if (record.status == KYCStatus.APPROVED) {
            record.status = KYCStatus.EXPIRED;
            accreditedInvestors[user] = false;

            globalStats.totalApproved--;
            globalStats.totalExpired++;

            emit KYCExpired(user, block.timestamp);
        }
    }

    /// @notice Batch approve multiple users (for testing/migration)
    function batchApprove(address[] memory users, InvestorType[] memory investorTypes)
        external
        onlyRole(KYC_MANAGER_ROLE)
    {
        require(users.length == investorTypes.length, "Array length mismatch");

        for (uint256 i = 0; i < users.length; i++) {
            if (users[i] != address(0) && kycRecords[users[i]].status != KYCStatus.APPROVED) {
                uint256 expiresAt = block.timestamp + KYC_VALIDITY_PERIOD;

                kycRecords[users[i]] = KYCRecord({
                    status: KYCStatus.APPROVED,
                    investorType: investorTypes[i],
                    approvedAt: block.timestamp,
                    expiresAt: expiresAt,
                    approvedBy: msg.sender,
                    documentHash: "batch-approval",
                    rejectionReason: "",
                    submittedAt: block.timestamp,
                    isActive: true
                });

                if (investorTypes[i] == InvestorType.ACCREDITED || investorTypes[i] == InvestorType.INSTITUTIONAL) {
                    accreditedInvestors[users[i]] = true;
                }

                approvedUsers.push(users[i]);
                globalStats.totalSubmissions++;
                globalStats.totalApproved++;

                emit KYCApproved(users[i], investorTypes[i], msg.sender, expiresAt);
            }
        }
    }

    /// @notice Remove user from pending list
    function _removeFromPendingList(address user) internal {
        for (uint256 i = 0; i < pendingUsers.length; i++) {
            if (pendingUsers[i] == user) {
                pendingUsers[i] = pendingUsers[pendingUsers.length - 1];
                pendingUsers.pop();
                break;
            }
        }
    }

    /// @notice Emergency pause function
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpause function
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /// @notice Check if KYC system is properly configured
    function isKYCSystemActive() external view returns (bool) {
        return !paused();
    }

    /// @notice Frontend helper function to get user's complete KYC status
    function getUserKYCInfo(address user) external view returns (
        KYCStatus status,
        InvestorType investorType,
        bool isAccredited,
        uint256 approvedAt,
        uint256 expiresAt,
        bool isExpired
    ) {
        KYCRecord memory record = kycRecords[user];
        bool expired = (record.status == KYCStatus.APPROVED && block.timestamp >= record.expiresAt);

        return (
            expired ? KYCStatus.EXPIRED : record.status,
            record.investorType,
            accreditedInvestors[user] && this.isKYCApproved(user),
            record.approvedAt,
            record.expiresAt,
            expired
        );
    }

    /// @notice Get user eligibility for token purchases
    function canUserPurchaseTokens(address user) external view returns (
        bool canPurchase,
        string memory reason
    ) {
        if (!this.isKYCApproved(user)) {
            return (false, "KYC not approved or expired");
        }

        if (!this.isAccreditedInvestor(user)) {
            return (false, "User is not an accredited investor");
        }

        return (true, "");
    }

    /// @notice Get paginated list of approved users for admin interface
    function getApprovedUsersPaginated(uint256 offset, uint256 limit) external view returns (
        address[] memory users,
        uint256 totalCount
    ) {
        uint256 end = offset + limit;
        if (end > approvedUsers.length) {
            end = approvedUsers.length;
        }

        users = new address[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            users[i - offset] = approvedUsers[i];
        }

        return (users, approvedUsers.length);
    }
}