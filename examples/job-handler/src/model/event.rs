use chrono::Utc;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::status::JobStatus;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JobEvent {
    pub job_id: Uuid,
    pub status: JobStatus,
    pub payload: Option<String>,
    pub result: Option<String>,
    pub error: Option<String>,
    pub timestamp: i64,
}

impl JobEvent {
    pub fn new(job_id: Uuid, status: JobStatus) -> Self {
        Self {
            job_id,
            status,
            payload: None,
            result: None,
            error: None,
            timestamp: Utc::now().timestamp(),
        }
    }

    pub fn with_payload(mut self, payload: String) -> Self {
        self.payload = Some(payload);
        self
    }
}