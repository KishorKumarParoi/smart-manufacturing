package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestHandleHealth(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	w := httptest.NewRecorder()

	handleHealth(w, req)

	res := w.Result()
	if res.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d", res.StatusCode)
	}

	var data map[string]interface{}
	if err := json.NewDecoder(res.Body).Decode(&data); err != nil {
		t.Fatalf("failed to parse json: %v", err)
	}

	if data["service"] != "smart-mfg-telemetry-gateway-go" {
		t.Errorf("unexpected service name: %v", data["service"])
	}
	if data["active_cloud"] != "aws" {
		t.Errorf("expected active_cloud=aws, got %v", data["active_cloud"])
	}
}

func TestHandleMetrics(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/metrics", nil)
	w := httptest.NewRecorder()

	handleMetrics(w, req)

	res := w.Result()
	if res.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d", res.StatusCode)
	}

	body := w.Body.String()
	if !strings.Contains(body, "gateway_requests_total") {
		t.Errorf("expected metrics output to contain gateway_requests_total, got: %s", body)
	}
	if !strings.Contains(body, "gateway_active_cloud") {
		t.Errorf("expected metrics output to contain gateway_active_cloud, got: %s", body)
	}
}

func TestSimulateFailover(t *testing.T) {
	// 1. Simulate disruption
	disruptReq := httptest.NewRequest(http.MethodPost, "/api/v1/failover/simulate", strings.NewReader(`{"action":"disrupt_primary"}`))
	w := httptest.NewRecorder()
	handleSimulateFailover(w, disruptReq)

	res := w.Result()
	if res.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d", res.StatusCode)
	}

	var data map[string]interface{}
	json.NewDecoder(res.Body).Decode(&data)
	if data["active_cloud"] != "gcp" {
		t.Errorf("expected active_cloud to switch to gcp, got %v", data["active_cloud"])
	}
	if data["circuit_state"] != "OPEN" {
		t.Errorf("expected circuit_state to be OPEN, got %v", data["circuit_state"])
	}

	// 2. Recover primary
	recoverReq := httptest.NewRequest(http.MethodPost, "/api/v1/failover/simulate", strings.NewReader(`{"action":"recover_primary"}`))
	wRec := httptest.NewRecorder()
	handleSimulateFailover(wRec, recoverReq)

	var dataRec map[string]interface{}
	json.NewDecoder(wRec.Result().Body).Decode(&dataRec)
	if dataRec["active_cloud"] != "aws" {
		t.Errorf("expected active_cloud to switch back to aws, got %v", dataRec["active_cloud"])
	}
	if dataRec["circuit_state"] != "CLOSED" {
		t.Errorf("expected circuit_state to be CLOSED, got %v", dataRec["circuit_state"])
	}
}
