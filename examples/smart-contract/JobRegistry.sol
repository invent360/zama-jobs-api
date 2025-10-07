// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title ZamaJobRegistry
 * @notice Minimal implementation of on-chain job confirmation registry
 * @dev This is a simplified example focusing on core security features
 */
contract ZamaJobRegistry {
    address public immutable operator;
    uint256 public constant CONFIRMATION_DELAY = 5 minutes;

    mapping(bytes32 => JobConfirmation) public confirmations;
    mapping(bytes32 => bool) public processedJobs;
    mapping(address => uint256) public nonces;

    struct JobConfirmation {
        bytes32 jobId;
        address tenant;
        bytes32 resultHash;
        uint256 timestamp;
        uint256 gasUsed;
        JobStatus status;
    }

    enum JobStatus {
        Pending,
        Success,
        Failed
    }

    event JobConfirmed(
        bytes32 indexed jobId,
        address indexed tenant,
        bytes32 resultHash,
        uint256 timestamp,
        JobStatus status
    );

    error Unauthorized();
    error JobAlreadyProcessed(bytes32 jobId);
    error InvalidSignature();
    error InvalidNonce(uint256 expected, uint256 provided);

    modifier onlyOperator() {
        if (msg.sender != operator) revert Unauthorized();
        _;
    }

    modifier nonReplayable(bytes32 jobId) {
        if (processedJobs[jobId]) revert JobAlreadyProcessed(jobId);
        _;
    }

    constructor(address _operator) {
        operator = _operator;
    }

    /**
     * @notice Confirm a single job completion
     * @param jobId Unique job identifier
     * @param tenant Address of the job owner
     * @param resultHash Hash of the job result
     * @param gasUsed Gas consumed by the job
     * @param status Final job status
     * @param nonce Tenant's current nonce for replay protection
     * @param signature Tenant's signature authorizing confirmation
     */
    function confirmJob(
        bytes32 jobId,
        address tenant,
        bytes32 resultHash,
        uint256 gasUsed,
        JobStatus status,
        uint256 nonce,
        bytes calldata signature
    ) external onlyOperator nonReplayable(jobId) {
        // Verify nonce
        if (nonces[tenant] != nonce) {
            revert InvalidNonce(nonces[tenant], nonce);
        }

        // Verify signature
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                jobId,
                tenant,
                resultHash,
                gasUsed,
                uint8(status),
                nonce,
                block.chainid
            )
        );

        if (!_verifySignature(messageHash, signature, tenant)) {
            revert InvalidSignature();
        }

        // Store confirmation
        confirmations[jobId] = JobConfirmation({
            jobId: jobId,
            tenant: tenant,
            resultHash: resultHash,
            timestamp: block.timestamp,
            gasUsed: gasUsed,
            status: status
        });

        // Update state
        processedJobs[jobId] = true;
        nonces[tenant]++;

        emit JobConfirmed(jobId, tenant, resultHash, block.timestamp, status);
    }

    /**
     * @notice Batch confirm multiple jobs
     * @param jobIds Array of job identifiers
     * @param jobs Array of job confirmations
     */
    function confirmJobBatch(
        bytes32[] calldata jobIds,
        JobConfirmation[] calldata jobs
    ) external onlyOperator {
        require(jobIds.length == jobs.length, "Length mismatch");
        require(jobIds.length <= 100, "Batch too large");

        for (uint256 i = 0; i < jobIds.length; i++) {
            if (!processedJobs[jobIds[i]]) {
                confirmations[jobIds[i]] = jobs[i];
                processedJobs[jobIds[i]] = true;

                emit JobConfirmed(
                    jobIds[i],
                    jobs[i].tenant,
                    jobs[i].resultHash,
                    block.timestamp,
                    jobs[i].status
                );
            }
        }
    }

    /**
     * @notice Get confirmation details for a job
     * @param jobId The job identifier
     * @return confirmation The job confirmation details
     */
    function getConfirmation(bytes32 jobId)
        external
        view
        returns (JobConfirmation memory)
    {
        return confirmations[jobId];
    }

    /**
     * @notice Check if a job has been processed
     * @param jobId The job identifier
     * @return processed Whether the job has been confirmed
     */
    function isJobProcessed(bytes32 jobId) external view returns (bool) {
        return processedJobs[jobId];
    }

    /**
     * @notice Internal signature verification
     */
    function _verifySignature(
        bytes32 messageHash,
        bytes calldata signature,
        address expectedSigner
    ) private pure returns (bool) {
        bytes32 ethSignedHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );

        (bytes32 r, bytes32 s, uint8 v) = _splitSignature(signature);
        address recoveredSigner = ecrecover(ethSignedHash, v, r, s);

        return recoveredSigner == expectedSigner;
    }

    /**
     * @notice Split signature into r, s, v components
     */
    function _splitSignature(bytes calldata sig)
        private
        pure
        returns (bytes32 r, bytes32 s, uint8 v)
    {
        require(sig.length == 65, "Invalid signature length");

        assembly {
            r := calldataload(sig.offset)
            s := calldataload(add(sig.offset, 32))
            v := byte(0, calldataload(add(sig.offset, 64)))
        }

        // Handle both possible v values
        if (v < 27) {
            v += 27;
        }
    }
}