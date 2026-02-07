use serde::Deserialize;
use std::env;

#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    pub server: ServerConfig,
    pub memory: MemoryConfig,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ServerConfig {
    pub host: String,
    pub port: u16,
}

#[derive(Debug, Clone, Deserialize)]
pub struct MemoryConfig {
    pub slab_sizes: Vec<usize>,
    pub max_pool_size: usize,
    pub initial_slabs_per_size: usize,
}

impl Config {
    pub fn load() -> Result<Self, config::ConfigError> {
        // Load .env file if it exists
        dotenv::dotenv().ok();

        let mut settings = config::Config::builder()
            .add_source(config::File::with_name("config").required(false))
            .add_source(config::Environment::default().separator("__"));

        // Override with environment variables
        if let Ok(host) = env::var("SERVER_HOST") {
            settings = settings.set_override("server.host", host)?;
        }
        if let Ok(port) = env::var("SERVER_PORT") {
            settings = settings.set_override("server.port", port)?;
        }
        if let Ok(max_pool) = env::var("MAX_POOL_SIZE") {
            settings = settings.set_override("memory.max_pool_size", max_pool)?;
        }

        settings.build()?.try_deserialize()
    }
}
