use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::model::JobStatus;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JobCompletionEvent {
    pub job_id: Uuid,
    pub status: JobStatus,
    pub result: Option<String>,
    pub error: Option<String>,
    pub completed_at: i64,
}

impl JobCompletionEvent {
    pub fn new(job_id: Uuid, status: JobStatus) -> Self {
        Self {
            job_id,
            status,
            result: None,
            error: None,
            completed_at: chrono::Utc::now().timestamp(),
        }
    }

    pub fn with_result(mut self, result: String) -> Self {
        self.result = Some(result);
        self
    }

    pub fn with_error(mut self, error: String) -> Self {
        self.error = Some(error);
        self.status = JobStatus::Failed;
        self
    }
}