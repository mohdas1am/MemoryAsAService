mod handlers;
mod models;
mod state;

use axum::{
    routing::{get, post, delete},
    Router,
};
use std::net::SocketAddr;
use crate::state::AppState;
use crate::handlers::{allocate_handler, deallocate_handler, health_check, metrics_handler, stats_handler};

#[tokio::main]
async fn main() {
    // Initialize logging
    tracing_subscriber::fmt::init();

    let state = AppState::new();

    let app = Router::new()
        .route("/health", get(health_check))
        .route("/metrics", get(metrics_handler))
        .route("/stats", get(stats_handler))
        .route("/allocate", post(allocate_handler))
        .route("/allocate/:id", delete(deallocate_handler))
        .with_state(state);

    let addr = SocketAddr::from(([127, 0, 0, 1], 3000));
    println!("Listening on {}", addr);
    
    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
