use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::status::JobStatus;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JobModel {
    pub id: Uuid,
    pub name: String,
    pub status: JobStatus,
    pub payload: String,
    pub result: Option<String>,
    pub error: Option<String>,
    pub created_at: DateTime<Utc>,
    pub processing_time: Option<i64>,
    pub completed_at: Option<DateTime<Utc>>,
}

impl JobModel {
    pub fn new(name: String, payload: String) -> Self {
        Self {
            id: Uuid::new_v4(),
            name,
            status: JobStatus::Pending,
            payload,
            result: None,
            error: None,
            created_at: Utc::now(),
            processing_time: None,
            completed_at: None,
        }
    }
}