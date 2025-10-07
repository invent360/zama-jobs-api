use dashmap::DashMap;
use job_api::generated::rpc::jobs::{
    job_service_server::JobService, GetJobRequest, GetJobResponse, Job, JobCompletionEvent,
    JobIdRequest, ListJobsRequest, ListJobsResponse, SubmitJobRequest, SubmitJobResponse,
};
use std::sync::Arc;
use tokio::sync::mpsc;
use tokio_stream::wrappers::ReceiverStream;
use tonic::{Request, Response, Status};
use tracing::{error, info};
use uuid::Uuid;

use crate::{
    message::MessageBroker,
    model::{JobEvent, JobModel, JobStatus},
};

#[derive(Clone)]
pub struct JobServiceImpl {
    jobs: Arc<DashMap<Uuid, JobModel>>,
    message_broker: Arc<MessageBroker>,
    completion_notifiers: Arc<DashMap<Uuid, mpsc::Sender<JobCompletionEvent>>>,
}

impl JobServiceImpl {
    pub fn new(message_broker: Arc<MessageBroker>) -> Self {
        Self {
            jobs: Arc::new(DashMap::new()),
            message_broker,
            completion_notifiers: Arc::new(DashMap::new()),
        }
    }

    pub fn handle_completion(&self, event: crate::message::JobCompletionEvent) {
        let job_id = event.job_id;

        // Update job in storage
        if let Some(mut job) = self.jobs.get_mut(&job_id) {
            job.status = event.status;
            job.result = event.result.clone();
            job.error = event.error.clone();
            job.completed_at = Some(chrono::Utc::now());

            if let Some(created_at) = Some(job.created_at.timestamp_millis()) {
                job.processing_time = Some(event.completed_at - created_at);
            }
        }

        // Notify websocket listeners
        if let Some(notifier) = self.completion_notifiers.get(&job_id) {
            let grpc_event = JobCompletionEvent {
                job_id: job_id.to_string(),
                status: Into::<job_api::generated::rpc::jobs::JobStatus>::into(event.status).into(),
                result: event.result,
                error: event.error,
                completed_at: event.completed_at,
            };

            let _ = notifier.try_send(grpc_event);
        }
    }
}

#[tonic::async_trait]
impl JobService for JobServiceImpl {
    async fn submit_job(
        &self,
        request: Request<SubmitJobRequest>,
    ) -> Result<Response<SubmitJobResponse>, Status> {
        let req = request.into_inner();
        let job = JobModel::new(req.name, req.payload);
        let job_id = job.id;

        // Store job
        self.jobs.insert(job_id, job.clone());

        // Submit to NATS
        let event = JobEvent::new(job_id, JobStatus::Pending)
            .with_payload(job.payload);

        if let Err(e) = self.message_broker.submit_job(event).await {
            error!("Failed to submit job to NATS: {}", e);
            return Err(Status::internal("Failed to submit job"));
        }

        info!("Job {} submitted successfully", job_id);

        Ok(Response::new(SubmitJobResponse {
            job_id: job_id.to_string(),
            status: Into::<job_api::generated::rpc::jobs::JobStatus>::into(JobStatus::Pending).into(),
        }))
    }

    async fn get_job(
        &self,
        request: Request<GetJobRequest>,
    ) -> Result<Response<GetJobResponse>, Status> {
        let req = request.into_inner();

        let job = if let Some(job_id_str) = req.job_id {
            let job_id = Uuid::parse_str(&job_id_str)
                .map_err(|_| Status::invalid_argument("Invalid job ID"))?;
            self.jobs
                .get(&job_id)
                .map(|j| j.clone())
                .ok_or_else(|| Status::not_found("Job not found"))?
        } else if let Some(name) = req.name {
            self.jobs
                .iter()
                .find(|entry| entry.name == name)
                .map(|entry| entry.value().clone())
                .ok_or_else(|| Status::not_found("Job not found"))?
        } else {
            return Err(Status::invalid_argument("Job ID or name required"));
        };

        Ok(Response::new(GetJobResponse {
            job: Some(Job {
                id: Some(job.id.to_string()),
                name: job.name,
                created_at: Some(job.created_at.timestamp_millis()),
                processing_time: job.processing_time,
                completed_at: job.completed_at.map(|dt| dt.timestamp_millis()),
                status: Into::<job_api::generated::rpc::jobs::JobStatus>::into(job.status).into(),
                result: job.result,
                error: job.error,
            }),
        }))
    }

    async fn list_jobs(
        &self,
        _request: Request<ListJobsRequest>,
    ) -> Result<Response<ListJobsResponse>, Status> {
        let jobs: Vec<Job> = self
            .jobs
            .iter()
            .map(|entry| {
                let job = entry.value();
                Job {
                    id: Some(job.id.to_string()),
                    name: job.name.clone(),
                    created_at: Some(job.created_at.timestamp_millis()),
                    processing_time: job.processing_time,
                    completed_at: job.completed_at.map(|dt| dt.timestamp_millis()),
                    status: Into::<job_api::generated::rpc::jobs::JobStatus>::into(job.status).into(),
                    result: job.result.clone(),
                    error: job.error.clone(),
                }
            })
            .collect();

        Ok(Response::new(ListJobsResponse { jobs }))
    }

    async fn cancel_job(
        &self,
        request: Request<JobIdRequest>,
    ) -> Result<Response<()>, Status> {
        let job_id = Uuid::parse_str(&request.into_inner().job_id)
            .map_err(|_| Status::invalid_argument("Invalid job ID"))?;

        if self.jobs.remove(&job_id).is_none() {
            return Err(Status::not_found("Job not found"));
        }

        Ok(Response::new(()))
    }

    type StreamJobUpdatesStream = ReceiverStream<Result<JobCompletionEvent, Status>>;

    async fn stream_job_updates(
        &self,
        request: Request<tonic::Streaming<JobIdRequest>>,
    ) -> Result<Response<Self::StreamJobUpdatesStream>, Status> {
        let mut stream = request.into_inner();
        let (tx, rx) = mpsc::channel(100);

        let jobs = self.jobs.clone();
        let notifiers = self.completion_notifiers.clone();

        // Handle incoming job ID subscriptions
        tokio::spawn(async move {
            while let Ok(Some(req)) = stream.message().await {
                if let Ok(job_id) = Uuid::parse_str(&req.job_id) {
                    // Register notifier for this job
                    let (notif_tx, mut notif_rx) = mpsc::channel(10);
                    notifiers.insert(job_id, notif_tx);

                    let tx_clone = tx.clone();

                    // Forward completion events to the client
                    tokio::spawn(async move {
                        while let Some(event) = notif_rx.recv().await {
                            let _ = tx_clone.send(Ok(event)).await;
                        }
                    });

                    // Check if job is already completed
                    if let Some(job) = jobs.get(&job_id) {
                        if matches!(job.status, JobStatus::Completed | JobStatus::Failed) {
                            let event = JobCompletionEvent {
                                job_id: job_id.to_string(),
                                status: Into::<job_api::generated::rpc::jobs::JobStatus>::into(job.status).into(),
                                result: job.result.clone(),
                                error: job.error.clone(),
                                completed_at: job.completed_at
                                    .map(|dt| dt.timestamp_millis())
                                    .unwrap_or(0),
                            };
                            let _ = tx.send(Ok(event)).await;
                        }
                    }
                }
            }
        });

        Ok(Response::new(ReceiverStream::new(rx)))
    }
}

