use dashmap::DashMap;
use std::sync::Arc;
use tokio::sync::mpsc;
use uuid::Uuid;

use crate::message::JobCompletionEvent;

pub struct WebSocketService {
    subscribers: Arc<DashMap<Uuid, Vec<mpsc::Sender<JobCompletionEvent>>>>,
}

impl WebSocketService {
    pub fn new() -> Self {
        Self {
            subscribers: Arc::new(DashMap::new()),
        }
    }

    pub fn subscribe(&self, job_id: Uuid) -> mpsc::Receiver<JobCompletionEvent> {
        let (tx, rx) = mpsc::channel(10);

        self.subscribers
            .entry(job_id)
            .or_insert_with(Vec::new)
            .push(tx);

        rx
    }

    pub async fn notify_completion(&self, event: JobCompletionEvent) {
        if let Some(mut subscribers) = self.subscribers.get_mut(&event.job_id) {
            // Remove closed channels
            subscribers.retain(|tx| !tx.is_closed());

            // Send to all active subscribers
            for tx in subscribers.iter() {
                let _ = tx.send(event.clone()).await;
            }

            // Remove entry if no subscribers left
            if subscribers.is_empty() {
                drop(subscribers);
                self.subscribers.remove(&event.job_id);
            }
        }
    }

    pub fn unsubscribe(&self, job_id: Uuid) {
        self.subscribers.remove(&job_id);
    }
}