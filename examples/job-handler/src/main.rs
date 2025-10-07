mod message;
mod model;
mod service;

use futures::StreamExt;
use job_api::generated::rpc::jobs::job_service_server::JobServiceServer;
use std::sync::Arc;
use tonic::transport::Server;
use tracing::{error, info};
use tracing_subscriber;

use crate::{
    message::MessageBroker,
    service::JobServiceImpl,
};




#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    tracing_subscriber::fmt::init();

    let nats_url = std::env::var("NATS_URL").unwrap_or_else(|_| "nats://localhost:4222".to_string());
    let grpc_port = std::env::var("GRPC_PORT").unwrap_or_else(|_| "50051".to_string());

    // Initialize message broker
    let message_broker = Arc::new(MessageBroker::new(&nats_url).await?);

    // Create service
    let job_service = Arc::new(JobServiceImpl::new(message_broker.clone()));

    // Start completion listener
    let listener_service = job_service.clone();
    let listener_broker = message_broker.clone();
    tokio::spawn(async move {
        info!("Starting job completion listener");

        match listener_broker.listen_for_completions().await {
            Ok(mut subscriber) => {
                while let Some(msg) = subscriber.next().await {
                    match serde_json::from_slice::<crate::message::JobCompletionEvent>(&msg.payload) {
                        Ok(event) => {
                            info!("Received completion event for job {}", event.job_id);
                            listener_service.handle_completion(event);
                        }
                        Err(e) => {
                            error!("Failed to parse completion event: {}", e);
                        }
                    }
                }
            }
            Err(e) => {
                error!("Failed to subscribe to completions: {}", e);
            }
        }
    });

    // Start gRPC server
    let addr = format!("0.0.0.0:{}", grpc_port).parse()?;

    info!("Starting gRPC server on {}", addr);

    Server::builder()
        .add_service(JobServiceServer::new(job_service.as_ref().clone()))
        .serve(addr)
        .await?;

    Ok(())
}