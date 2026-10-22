package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"sync"
	"sync/atomic"
	"time"
)

type CircuitBreakerState string

const (
	StateClosed   CircuitBreakerState = "CLOSED"
	StateOpen     CircuitBreakerState = "OPEN"
	StateHalfOpen CircuitBreakerState = "HALF_OPEN"
)

type CloudTarget struct {
	Name            string `json:"name"`
	Region          string `json:"region"`
	URL             string `json:"url"`
	IsHealthy       bool   `json:"is_healthy"`
	LatencyMs       int64  `json:"latency_ms"`
	LastChecked     string `json:"last_checked"`
	ConsecutiveFails int   `json:"consecutive_fails"`
}

type FailoverState struct {
	sync.RWMutex
	ActiveCloud       string              `json:"active_cloud"`
	Primary           CloudTarget         `json:"primary"`
	Secondary         CloudTarget         `json:"secondary"`
	TotalFailovers    uint64              `json:"total_failovers"`
	LastFailoverTime  string              `json:"last_failover_time"`
	CircuitState      CircuitBreakerState `json:"circuit_state"`
	SimulatedDisrupt  bool                `json:"simulated_disrupt"`
}

type TopologyService struct {
	Name        string `json:"name"`
	Language    string `json:"language"`
	Port        int    `json:"port"`
	Role        string `json:"role"`
	Status      string `json:"status"`
	Endpoint    string `json:"endpoint"`
	LatencyUs   int64  `json:"latency_us"`
}

type TopologyResponse struct {
	Timestamp      string            `json:"timestamp"`
	ActiveRoute    string            `json:"active_route"`
	CircuitBreaker string            `json:"circuit_breaker"`
	Services       []TopologyService `json:"services"`
}

var (
	requestCounter  uint64
	failoverCounter uint64
	startTime       = time.Now()
	state           = &FailoverState{
		ActiveCloud: "aws",
		Primary: CloudTarget{
			Name:   "aws",
			Region: "us-east-1",
			URL:    getEnv("PRIMARY_API_URL", "http://127.0.0.1:8000"),
		},
		Secondary: CloudTarget{
			Name:   "gcp",
			Region: "us-central1",
			URL:    getEnv("SECONDARY_API_URL", "http://127.0.0.1:8001"),
		},
		CircuitState: StateClosed,
	}
	edgeIngestURL = getEnv("EDGE_INGEST_URL", "http://127.0.0.1:8082")
)

func getEnv(key, fallback string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return fallback
}

func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Requested-With")
		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusOK)
			return
		}
		atomic.AddUint64(&requestCounter, 1)
		next.ServeHTTP(w, r)
	})
}

// Background goroutine probing primary and secondary clouds
func startHealthProber(ctx context.Context, checkInterval time.Duration) {
	ticker := time.NewTicker(checkInterval)
	client := &http.Client{Timeout: 2 * time.Second}

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			probeTargets(client)
		}
	}
}

func probeTargets(client *http.Client) {
	state.Lock()
	defer state.Unlock()

	// Probe Primary
	t0 := time.Now()
	resp, err := client.Get(state.Primary.URL + "/health")
	latPrimary := time.Since(t0).Milliseconds()
	nowStr := time.Now().UTC().Format(time.RFC3339)

	primaryOK := err == nil && resp != nil && (resp.StatusCode == http.StatusOK || resp.StatusCode == 200)
	if resp != nil {
		io.Copy(io.Discard, resp.Body)
		resp.Body.Close()
	}

	if state.SimulatedDisrupt {
		primaryOK = false
	}

	state.Primary.LastChecked = nowStr
	state.Primary.LatencyMs = latPrimary

	if primaryOK {
		state.Primary.IsHealthy = true
		state.Primary.ConsecutiveFails = 0
		if state.ActiveCloud != "aws" && !state.SimulatedDisrupt {
			log.Printf("[FAILBACK] Primary AWS (us-east-1) recovered! Shifting active traffic back to Primary.")
			state.ActiveCloud = "aws"
			state.CircuitState = StateClosed
		}
	} else {
		state.Primary.IsHealthy = false
		state.Primary.ConsecutiveFails++
		if state.Primary.ConsecutiveFails >= 3 && state.ActiveCloud != "gcp" {
			log.Printf("[FAILOVER ALERT] Primary AWS failed 3 consecutive health checks! Tripping failover to GCP (us-central1).")
			state.ActiveCloud = "gcp"
			state.CircuitState = StateOpen
			state.TotalFailovers++
			state.LastFailoverTime = nowStr
			atomic.AddUint64(&failoverCounter, 1)
		}
	}

	// Probe Secondary
	t1 := time.Now()
	respSec, errSec := client.Get(state.Secondary.URL + "/health")
	latSec := time.Since(t1).Milliseconds()
	secOK := errSec == nil && respSec != nil && respSec.StatusCode == http.StatusOK
	if respSec != nil {
		io.Copy(io.Discard, respSec.Body)
		respSec.Body.Close()
	}

	state.Secondary.LastChecked = nowStr
	state.Secondary.LatencyMs = latSec
	state.Secondary.IsHealthy = secOK
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	state.RLock()
	defer state.RUnlock()

	status := "healthy"
	if !state.Primary.IsHealthy && !state.Secondary.IsHealthy {
		status = "degraded"
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":           status,
		"service":          "smart-mfg-telemetry-gateway-go",
		"version":          "1.0.0",
		"uptime_seconds":   time.Since(startTime).Seconds(),
		"active_cloud":     state.ActiveCloud,
		"circuit_state":    state.CircuitState,
		"requests_total":   atomic.LoadUint64(&requestCounter),
		"failovers_total":  atomic.LoadUint64(&failoverCounter),
		"primary_healthy":  state.Primary.IsHealthy,
		"secondary_healthy": state.Secondary.IsHealthy,
	})
}

func handleTopology(w http.ResponseWriter, r *http.Request) {
	state.RLock()
	defer state.RUnlock()

	rustStatus := "healthy"
	rustClient := &http.Client{Timeout: 500 * time.Millisecond}
	t0 := time.Now()
	rResp, rErr := rustClient.Get(edgeIngestURL + "/health")
	rustLat := time.Since(t0).Microseconds()
	if rErr != nil || rResp == nil || rResp.StatusCode != http.StatusOK {
		rustStatus = "degraded"
	}
	if rResp != nil {
		io.Copy(io.Discard, rResp.Body)
		rResp.Body.Close()
	}

	primaryStatus := "healthy"
	if !state.Primary.IsHealthy {
		primaryStatus = "offline"
	}
	secondaryStatus := "healthy"
	if !state.Secondary.IsHealthy {
		secondaryStatus = "standby"
	}

	topo := TopologyResponse{
		Timestamp:      time.Now().UTC().Format(time.RFC3339),
		ActiveRoute:    state.ActiveCloud,
		CircuitBreaker: string(state.CircuitState),
		Services: []TopologyService{
			{
				Name:      "edge-ingestion-rust",
				Language:  "Rust (Actix/SIMD)",
				Port:      8082,
				Role:      "Sub-millisecond IoT telemetry ingestion & RMS vibration pre-filter",
				Status:    rustStatus,
				Endpoint:  edgeIngestURL,
				LatencyUs: rustLat,
			},
			{
				Name:      "telemetry-gateway-go",
				Language:  "Go (Goroutines/StdLib)",
				Port:      8080,
				Role:      "Cloud-Native Reverse Proxy, Rate Limiter & Multi-Cloud Health Controller",
				Status:    "healthy",
				Endpoint:  "http://0.0.0.0:8080",
				LatencyUs: 120,
			},
			{
				Name:      "ai-inference-python-primary",
				Language:  "Python (PyTorch/FastAPI)",
				Port:      8000,
				Role:      "Primary Deep Learning Autoencoder & AOI ResNet/CNN (AWS us-east-1)",
				Status:    primaryStatus,
				Endpoint:  state.Primary.URL,
				LatencyUs: state.Primary.LatencyMs * 1000,
			},
			{
				Name:      "ai-inference-python-secondary",
				Language:  "Python (PyTorch/FastAPI)",
				Port:      8001,
				Role:      "Standby Deep Learning Autoencoder & AOI ResNet/CNN (GCP us-central1)",
				Status:    secondaryStatus,
				Endpoint:  state.Secondary.URL,
				LatencyUs: state.Secondary.LatencyMs * 1000,
			},
			{
				Name:      "industrial-cockpit-nextjs",
				Language:  "TypeScript (Next.js 15+)",
				Port:      3000,
				Role:      "Real-time Executive Operations Dashboard & AOI Inspection UI",
				Status:    "healthy",
				Endpoint:  "http://localhost:3000",
				LatencyUs: 450,
			},
		},
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(topo)
}

func handleSimulateFailover(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		Action string `json:"action"` // "disrupt_primary", "recover_primary", "toggle"
	}
	body, _ := io.ReadAll(r.Body)
	json.Unmarshal(body, &req)

	state.Lock()
	defer state.Unlock()

	if req.Action == "disrupt_primary" || (req.Action == "toggle" && !state.SimulatedDisrupt) {
		state.SimulatedDisrupt = true
		state.ActiveCloud = "gcp"
		state.CircuitState = StateOpen
		state.TotalFailovers++
		state.LastFailoverTime = time.Now().UTC().Format(time.RFC3339)
		atomic.AddUint64(&failoverCounter, 1)
		log.Printf("[SIMULATION DRILL] AWS Region Outage injected! Routing shifted to GCP Standby.")
	} else {
		state.SimulatedDisrupt = false
		state.ActiveCloud = "aws"
		state.CircuitState = StateClosed
		log.Printf("[SIMULATION DRILL] AWS Region Outage cleared! Routing restored to AWS Primary.")
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":          "ok",
		"simulated_outage": state.SimulatedDisrupt,
		"active_cloud":    state.ActiveCloud,
		"circuit_state":   state.CircuitState,
		"total_failovers": state.TotalFailovers,
	})
}

// Proxies incoming requests to active AI inference engine (AWS or GCP)
func createProxy(targetURL string) http.Handler {
	u, err := url.Parse(targetURL)
	if err != nil {
		log.Fatalf("Invalid proxy target URL: %v", err)
	}
	proxy := httputil.NewSingleHostReverseProxy(u)
	proxy.ErrorHandler = func(w http.ResponseWriter, r *http.Request, err error) {
		log.Printf("[PROXY ERROR] Target %s unreachable: %v", targetURL, err)
		http.Error(w, fmt.Sprintf("Inference Backend Unavailable (%s): %v", targetURL, err), http.StatusBadGateway)
	}
	return proxy
}

func handleProxyInference(w http.ResponseWriter, r *http.Request) {
	state.RLock()
	active := state.ActiveCloud
	primaryURL := state.Primary.URL
	secondaryURL := state.Secondary.URL
	state.RUnlock()

	targetURL := primaryURL
	if active == "gcp" {
		targetURL = secondaryURL
	}

	u, err := url.Parse(targetURL)
	if err != nil {
		http.Error(w, "Bad target configuration", http.StatusInternalServerError)
		return
	}

	proxy := httputil.NewSingleHostReverseProxy(u)
	proxy.ServeHTTP(w, r)
}

func handleProxyRustIngest(w http.ResponseWriter, r *http.Request) {
	u, err := url.Parse(edgeIngestURL)
	if err != nil {
		http.Error(w, "Bad edge ingest URL", http.StatusInternalServerError)
		return
	}
	proxy := httputil.NewSingleHostReverseProxy(u)
	proxy.ServeHTTP(w, r)
}

func handleMetrics(w http.ResponseWriter, r *http.Request) {
	state.RLock()
	defer state.RUnlock()

	var buf bytes.Buffer
	buf.WriteString("# HELP gateway_requests_total Total requests routed through Go API Gateway\n")
	buf.WriteString("# TYPE gateway_requests_total counter\n")
	buf.WriteString(fmt.Sprintf("gateway_requests_total %d\n", atomic.LoadUint64(&requestCounter)))

	buf.WriteString("# HELP gateway_failover_events_total Total multi-cloud automated failover events\n")
	buf.WriteString("# TYPE gateway_failover_events_total counter\n")
	buf.WriteString(fmt.Sprintf("gateway_failover_events_total %d\n", atomic.LoadUint64(&failoverCounter)))

	buf.WriteString("# HELP gateway_active_cloud Current active cloud (1=aws, 2=gcp)\n")
	buf.WriteString("# TYPE gateway_active_cloud gauge\n")
	activeVal := 1
	if state.ActiveCloud == "gcp" {
		activeVal = 2
	}
	buf.WriteString(fmt.Sprintf("gateway_active_cloud %d\n", activeVal))

	buf.WriteString("# HELP gateway_primary_latency_ms Primary cloud health latency in ms\n")
	buf.WriteString("# TYPE gateway_primary_latency_ms gauge\n")
	buf.WriteString(fmt.Sprintf("gateway_primary_latency_ms %d\n", state.Primary.LatencyMs))

	buf.WriteString("# HELP gateway_secondary_latency_ms Secondary cloud health latency in ms\n")
	buf.WriteString("# TYPE gateway_secondary_latency_ms gauge\n")
	buf.WriteString(fmt.Sprintf("gateway_secondary_latency_ms %d\n", state.Secondary.LatencyMs))

	w.Header().Set("Content-Type", "text/plain; version=0.0.4")
	w.Write(buf.Bytes())
}

func main() {
	port := getEnv("PORT", "8085")
	bindAddr := ":" + port

	mux := http.NewServeMux()
	mux.HandleFunc("/health", handleHealth)
	mux.HandleFunc("/metrics", handleMetrics)
	mux.HandleFunc("/api/v1/topology", handleTopology)
	mux.HandleFunc("/api/v1/failover/status", handleHealth)
	mux.HandleFunc("/api/v1/failover/simulate", handleSimulateFailover)

	// Proxy to Rust Edge Ingestor
	mux.HandleFunc("/api/v1/edge/ingest", handleProxyRustIngest)
	mux.HandleFunc("/api/v1/ingest", handleProxyRustIngest)

	// Proxy to Python PyTorch Inference Core (with active-passive dynamic routing)
	mux.HandleFunc("/api/v1/predict/sensor", handleProxyInference)
	mux.HandleFunc("/api/v1/predict/vision", handleProxyInference)
	mux.HandleFunc("/predict/sensor", handleProxyInference)
	mux.HandleFunc("/predict/vision", handleProxyInference)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Start active health prober (every 5 seconds)
	go startHealthProber(ctx, 5*time.Second)

	log.Printf("Starting Go Cloud-Native Gateway & Health Controller on %s", bindAddr)
	log.Printf("Primary Target: %s (AWS us-east-1) | Standby Target: %s (GCP us-central1)", state.Primary.URL, state.Secondary.URL)
	log.Printf("Edge Rust Ingestor Target: %s", edgeIngestURL)

	server := &http.Server{
		Addr:         bindAddr,
		Handler:      corsMiddleware(mux),
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
	}

	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("Gateway server failure: %v", err)
	}
}
