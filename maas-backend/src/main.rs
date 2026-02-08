mod config;
mod handlers;
mod models;
mod slab;
mod state;

use axum::{
    routing::{get, post, delete},
    Router,
};
use std::net::SocketAddr;
use std::sync::Arc;
use tracing::info;
use crate::config::Config;
use crate::slab::SlabAllocator;
use crate::state::AppState;
use crate::handlers::{allocate_handler, deallocate_handler, health_check, metrics_handler, stats_handler};

#[tokio::main]
async fn main() {
    // Initialize logging
    tracing_subscriber::fmt::init();

    // Load configuration
    let config = Config::load().expect("Failed to load configuration");
    info!("Loaded configuration: {:?}", config);

    // Initialize slab allocator
    let allocator = Arc::new(SlabAllocator::new(
        config.memory.slab_sizes.clone(),
        config.memory.max_pool_size,
        config.memory.initial_slabs_per_size,
    ));

    // Initialize application state
    let state = AppState::new(allocator.clone());

    // Build API routes
    let app = Router::new()
        .route("/health", get(health_check))
        .route("/metrics", get(metrics_handler))
        .route("/stats", get(stats_handler))
        .route("/allocate", post(allocate_handler))
        .route("/allocate/:id", delete(deallocate_handler))
        .with_state(state);

    let addr: SocketAddr = format!("{}:{}", config.server.host, config.server.port)
        .parse()
        .expect("Invalid server address");
    info!("Memory-as-a-Service v{} starting on {}", env!("CARGO_PKG_VERSION"), addr);
    info!("   Max pool size: {} MB", config.memory.max_pool_size / 1_048_576);
    info!("   Slab sizes: {:?}", config.memory.slab_sizes);
    info!("   Metrics exposed at: http://{}/metrics", addr);
    
    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
