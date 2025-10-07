use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
pub enum JobStatus {
    Unknown,
    Pending,
    Processing,
    Completed,
    Failed,
}

impl From<job_api::generated::rpc::jobs::JobStatus> for JobStatus {
    fn from(status: job_api::generated::rpc::jobs::JobStatus) -> Self {
        match status {
            job_api::generated::rpc::jobs::JobStatus::Unknown => JobStatus::Unknown,
            job_api::generated::rpc::jobs::JobStatus::Pending => JobStatus::Pending,
            job_api::generated::rpc::jobs::JobStatus::Processing => JobStatus::Processing,
            job_api::generated::rpc::jobs::JobStatus::Completed => JobStatus::Completed,
            job_api::generated::rpc::jobs::JobStatus::Failed => JobStatus::Failed,
        }
    }
}

impl From<JobStatus> for job_api::generated::rpc::jobs::JobStatus {
    fn from(status: JobStatus) -> Self {
        match status {
            JobStatus::Unknown => job_api::generated::rpc::jobs::JobStatus::Unknown,
            JobStatus::Pending => job_api::generated::rpc::jobs::JobStatus::Pending,
            JobStatus::Processing => job_api::generated::rpc::jobs::JobStatus::Processing,
            JobStatus::Completed => job_api::generated::rpc::jobs::JobStatus::Completed,
            JobStatus::Failed => job_api::generated::rpc::jobs::JobStatus::Failed,
        }
    }
}