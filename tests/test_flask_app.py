from main import app


@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as client:
        yield client


def test_health_check(client):
    response = client.get("/api/health")
    assert response.status_code == 200
    data = response.get_json()
    assert data["status"] == "healthy"
    assert "Smart Manufacturing" in data["service"]


def test_presets_endpoint(client):
    response = client.get("/api/presets")
    assert response.status_code == 200
    data = response.get_json()
    assert "optimal" in data
    assert "critical" in data


def test_index_page(client):
    response = client.get("/")
    assert response.status_code == 200
    assert b"Smart Manufacturing" in response.data


def test_predict_endpoint(client):
    payload = {
        "Operation_Mode": "Active",
        "Temperature_C": 77.4,
        "Vibration_Hz": 1.55,
        "Power_Consumption_kW": 9.26,
        "Network_Latency_ms": 20.4,
        "Packet_Loss_%": 2.75,
        "Quality_Control_Defect_Rate_%": 3.53,
        "Production_Speed_units_per_hr": 465.0,
        "Predictive_Maintenance_Score": 0.24,
        "Error_Rate_%": 0.51,
        "Year": 2026,
        "Month": 10,
        "Day": 8,
        "Hour": 14,
    }
    response = client.post("/api/predict", json=payload)
    assert response.status_code == 200
    data = response.get_json()
    assert data["status"] == "success"
    assert "prediction" in data
    assert "confidence" in data
