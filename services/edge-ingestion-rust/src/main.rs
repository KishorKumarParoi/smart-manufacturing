use actix_cors::Cors;
use actix_web::{get, post, web, App, HttpResponse, HttpServer, Responder};
use chrono::Utc;
use log::{info, warn};
use serde::{Deserialize, Serialize};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Instant;

static PACKETS_PROCESSED: AtomicU64 = AtomicU64::new(0);
static ANOMALIES_DETECTED: AtomicU64 = AtomicU64::new(0);
static START_TIME: std::sync::OnceLock<Instant> = std::sync::OnceLock::new();

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SensorReading {
    #[serde(default)]
    pub timestamp_sec: f64,
    pub vibration_x: f64,
    pub vibration_y: f64,
    pub vibration_z: f64,
    pub temperature_c: f64,
    pub pressure_bar: f64,
    pub spindle_rpm: f64,
    pub acoustic_emission_db: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IngestPayload {
    pub machine_id: String,
    pub readings: Vec<SensorReading>,
    #[serde(default)]
    pub edge_gateway_id: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct IngestResponse {
    pub status: String,
    pub machine_id: String,
    pub readings_ingested: usize,
    pub latency_micros: u128,
    pub fast_anomaly_flag: bool,
    pub rms_vibration: f64,
    pub peak_temperature_c: f64,
    pub processed_timestamp: String,
}

#[derive(Debug, Serialize)]
pub struct HealthStatus {
    pub status: String,
    pub service: String,
    pub version: String,
    pub uptime_seconds: u64,
    pub total_packets_processed: u64,
    pub total_anomalies_flagged: u64,
    pub engine: String,
}

pub struct AppState {
    pub redis_client: Option<redis::aio::ConnectionManager>,
}

/// Computes fast statistical metrics over high-frequency vibration and temperature
pub fn compute_metrics(readings: &[SensorReading]) -> (f64, f64, bool) {
    if readings.is_empty() {
        return (0.0, 0.0, false);
    }

    let mut sum_vibration_sq = 0.0;
    let mut max_temp = f64::MIN;

    for r in readings {
        let v_mag_sq = r.vibration_x * r.vibration_x
            + r.vibration_y * r.vibration_y
            + r.vibration_z * r.vibration_z;
        sum_vibration_sq += v_mag_sq;
        if r.temperature_c > max_temp {
            max_temp = r.temperature_c;
        }
    }

    let rms_vibration = (sum_vibration_sq / (readings.len() as f64)).sqrt();

    // Fast-path edge anomaly tripwires:
    // 1. RMS vibration exceeding 1.25g (severe mechanical spindle unbalance)
    // 2. Temperature exceeding 85.0 C (thermal bearing runaway)
    let is_anomaly = rms_vibration > 1.25 || max_temp > 85.0;

    (rms_vibration, max_temp, is_anomaly)
}

#[get("/health")]
async fn health_check() -> impl Responder {
    let uptime = START_TIME.get().map(|t| t.elapsed().as_secs()).unwrap_or(0);
    HttpResponse::Ok().json(HealthStatus {
        status: "healthy".to_string(),
        service: "smart-mfg-edge-ingestion-rust".to_string(),
        version: "0.1.0".to_string(),
        uptime_seconds: uptime,
        total_packets_processed: PACKETS_PROCESSED.load(Ordering::Relaxed),
        total_anomalies_flagged: ANOMALIES_DETECTED.load(Ordering::Relaxed),
        engine: "Rust Axum/Actix SIMD-ready".to_string(),
    })
}

#[get("/metrics")]
async fn prometheus_metrics() -> impl Responder {
    let packets = PACKETS_PROCESSED.load(Ordering::Relaxed);
    let anomalies = ANOMALIES_DETECTED.load(Ordering::Relaxed);
    let uptime = START_TIME.get().map(|t| t.elapsed().as_secs()).unwrap_or(0);

    let output = format!(
        "# HELP edge_ingest_packets_total Total telemetry packets ingested\n\
         # TYPE edge_ingest_packets_total counter\n\
         edge_ingest_packets_total {}\n\
         # HELP edge_ingest_anomalies_total Total edge anomalies flagged\n\
         # TYPE edge_ingest_anomalies_total counter\n\
         edge_ingest_anomalies_total {}\n\
         # HELP edge_ingest_uptime_seconds Ingestion server uptime in seconds\n\
         # TYPE edge_ingest_uptime_seconds gauge\n\
         edge_ingest_uptime_seconds {}\n",
        packets, anomalies, uptime
    );

    HttpResponse::Ok()
        .content_type("text/plain; version=0.0.4")
        .body(output)
}

#[post("/api/v1/ingest")]
async fn ingest_telemetry(
    data: web::Json<IngestPayload>,
    state: web::Data<Arc<AppState>>,
) -> impl Responder {
    let start = Instant::now();
    let count = data.readings.len();

    let (rms_vibration, max_temp, is_anomaly) = compute_metrics(&data.readings);

    PACKETS_PROCESSED.fetch_add(count as u64, Ordering::Relaxed);
    if is_anomaly {
        ANOMALIES_DETECTED.fetch_add(1, Ordering::Relaxed);
        warn!(
            "[EDGE ALERT] Machine {} triggered edge anomaly tripwire! RMS Vib: {:.3}, Max Temp: {:.1}C",
            data.machine_id, rms_vibration, max_temp
        );
    }

    // Optional Redis in-memory cache update
    if let Some(mut con) = state.redis_client.clone() {
        let redis_key = format!("mfg:telemetry:{}:latest", data.machine_id);
        if let Ok(serialized) = serde_json::to_string(&data.readings) {
            let _: Result<(), _> = redis::cmd("SETEX")
                .arg(&redis_key)
                .arg(60) // 60-second TTL
                .arg(serialized)
                .query_async(&mut con)
                .await;
        }
    }

    let elapsed = start.elapsed().as_micros();

    HttpResponse::Ok().json(IngestResponse {
        status: "ingested".to_string(),
        machine_id: data.machine_id.clone(),
        readings_ingested: count,
        latency_micros: elapsed,
        fast_anomaly_flag: is_anomaly,
        rms_vibration,
        peak_temperature_c: max_temp,
        processed_timestamp: Utc::now().to_rfc3339(),
    })
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    env_logger::init_from_env(env_logger::Env::default().default_filter_or("info"));
    START_TIME.get_or_init(Instant::now);

    let port = std::env::var("PORT").unwrap_or_else(|_| "8082".to_string());
    let bind_addr = format!("0.0.0.0:{}", port);

    // Initialize Redis client if available
    let redis_host = std::env::var("REDIS_HOST").unwrap_or_else(|_| "127.0.0.1".to_string());
    let redis_port = std::env::var("REDIS_PORT").unwrap_or_else(|_| "6379".to_string());
    let redis_url = format!("redis://{}:{}", redis_host, redis_port);

    let redis_client = match redis::Client::open(redis_url.as_str()) {
        Ok(client) => match client.get_connection_manager().await {
            Ok(mgr) => {
                info!("Connected to Redis cache at {}", redis_url);
                Some(mgr)
            }
            Err(e) => {
                warn!("Redis cache connection failed (running in memory mode): {}", e);
                None
            }
        },
        Err(e) => {
            warn!("Redis client initialization error: {}", e);
            None
        }
    };

    let app_state = Arc::new(AppState { redis_client });

    info!("Starting Rust Edge Ingestion Service on {}", bind_addr);

    HttpServer::new(move || {
        let cors = Cors::permissive();
        App::new()
            .wrap(cors)
            .app_data(web::Data::new(app_state.clone()))
            .service(health_check)
            .service(prometheus_metrics)
            .service(ingest_telemetry)
    })
    .bind(&bind_addr)?
    .run()
    .await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_normal_metrics_computation() {
        let readings = vec![
            SensorReading {
                timestamp_sec: 1.0,
                vibration_x: 0.1,
                vibration_y: 0.1,
                vibration_z: 0.1,
                temperature_c: 45.0,
                pressure_bar: 120.0,
                spindle_rpm: 3000.0,
                acoustic_emission_db: 40.0,
            },
            SensorReading {
                timestamp_sec: 2.0,
                vibration_x: 0.12,
                vibration_y: 0.11,
                vibration_z: 0.09,
                temperature_c: 46.0,
                pressure_bar: 120.5,
                spindle_rpm: 3005.0,
                acoustic_emission_db: 41.0,
            },
        ];

        let (rms, max_temp, is_anomaly) = compute_metrics(&readings);
        assert!(!is_anomaly);
        assert!(rms < 0.5);
        assert_eq!(max_temp, 46.0);
    }

    #[test]
    fn test_anomaly_detection_vibration_spike() {
        let readings = vec![SensorReading {
            timestamp_sec: 1.0,
            vibration_x: 1.5,
            vibration_y: 1.2,
            vibration_z: 0.8,
            temperature_c: 50.0,
            pressure_bar: 120.0,
            spindle_rpm: 3000.0,
            acoustic_emission_db: 65.0,
        }];

        let (rms, _, is_anomaly) = compute_metrics(&readings);
        assert!(is_anomaly);
        assert!(rms > 1.25);
    }

    #[test]
    fn test_anomaly_detection_thermal_runaway() {
        let readings = vec![SensorReading {
            timestamp_sec: 1.0,
            vibration_x: 0.2,
            vibration_y: 0.2,
            vibration_z: 0.2,
            temperature_c: 92.5, // Exceeds 85C threshold
            pressure_bar: 120.0,
            spindle_rpm: 3000.0,
            acoustic_emission_db: 42.0,
        }];

        let (_, max_temp, is_anomaly) = compute_metrics(&readings);
        assert!(is_anomaly);
        assert_eq!(max_temp, 92.5);
    }
}
