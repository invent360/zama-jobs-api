use async_nats::{Client, Subscriber};
use std::sync::Arc;
use tracing::info;

use super::events::JobCompletionEvent;
use crate::model::JobEvent;

const JOB_SUBMIT_SUBJECT: &str = "jobs.submit";
const JOB_COMPLETE_SUBJECT: &str = "jobs.complete";

#[derive(Clone)]
pub struct MessageBroker {
    client: Arc<Client>,
}

impl MessageBroker {
    pub async fn new(nats_url: &str) -> Result<Self, Box<dyn std::error::Error + Send + Sync>> {
        let client = async_nats::connect(nats_url).await?;
        info!("Connected to NATS at {}", nats_url);

        Ok(Self {
            client: Arc::new(client),
        })
    }

    pub async fn submit_job(&self, event: JobEvent) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let payload = serde_json::to_vec(&event)?;
        self.client
            .publish(JOB_SUBMIT_SUBJECT, payload.into())
            .await?;

        info!("Submitted job {} to NATS", event.job_id);
        Ok(())
    }

    pub async fn listen_for_completions(&self) -> Result<Subscriber, Box<dyn std::error::Error + Send + Sync>> {
        let subscriber = self.client.subscribe(JOB_COMPLETE_SUBJECT).await?;
        info!("Listening for job completions on {}", JOB_COMPLETE_SUBJECT);
        Ok(subscriber)
    }

    pub async fn publish_completion(&self, event: JobCompletionEvent) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let payload = serde_json::to_vec(&event)?;
        self.client
            .publish(JOB_COMPLETE_SUBJECT, payload.into())
            .await?;

        info!("Published completion for job {}", event.job_id);
        Ok(())
    }
}