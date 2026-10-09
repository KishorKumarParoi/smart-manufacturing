import os
from datetime import datetime
from flask import Flask, render_template, request, jsonify
import joblib
import pandas as pd

app = Flask(__name__, template_folder="src/templates", static_folder="src/static")

MODEL_PATH = "artifacts/models/model.pkl"
SCALER_PATH = "artifacts/processed/scaler.pkl"

# Feature definitions
FEATURES = [
    "Operation_Mode",
    "Temperature_C",
    "Vibration_Hz",
    "Power_Consumption_kW",
    "Network_Latency_ms",
    "Packet_Loss_%",
    "Quality_Control_Defect_Rate_%",
    "Production_Speed_units_per_hr",
    "Predictive_Maintenance_Score",
    "Error_Rate_%",
    "Year",
    "Month",
    "Day",
    "Hour",
]

FEATURE_METADATA = {
    "Operation_Mode": {
        "label": "Operating Mode",
        "unit": "State",
        "type": "select",
        "options": ["Active", "Idle", "Maintenance"],
    },
    "Temperature_C": {
        "label": "Chamber Temperature",
        "unit": "°C",
        "min": 20.0,
        "max": 120.0,
        "step": 0.1,
        "default": 77.4,
    },
    "Vibration_Hz": {
        "label": "Spindle Vibration",
        "unit": "Hz",
        "min": 0.1,
        "max": 10.0,
        "step": 0.05,
        "default": 1.55,
    },
    "Power_Consumption_kW": {
        "label": "Power Consumption",
        "unit": "kW",
        "min": 0.5,
        "max": 25.0,
        "step": 0.1,
        "default": 9.26,
    },
    "Network_Latency_ms": {
        "label": "IoT Network Latency",
        "unit": "ms",
        "min": 0.5,
        "max": 100.0,
        "step": 0.1,
        "default": 20.4,
    },
    "Packet_Loss_%": {
        "label": "Sensor Packet Loss",
        "unit": "%",
        "min": 0.0,
        "max": 15.0,
        "step": 0.05,
        "default": 2.75,
    },
    "Quality_Control_Defect_Rate_%": {
        "label": "QC Defect Rate",
        "unit": "%",
        "min": 0.0,
        "max": 20.0,
        "step": 0.1,
        "default": 3.53,
    },
    "Production_Speed_units_per_hr": {
        "label": "Production Speed",
        "unit": "units/hr",
        "min": 10.0,
        "max": 600.0,
        "step": 1.0,
        "default": 465.0,
    },
    "Predictive_Maintenance_Score": {
        "label": "Health Degradation Score",
        "unit": "Index (0-1)",
        "min": 0.0,
        "max": 1.0,
        "step": 0.01,
        "default": 0.24,
    },
    "Error_Rate_%": {
        "label": "Controller Error Rate",
        "unit": "%",
        "min": 0.0,
        "max": 30.0,
        "step": 0.1,
        "default": 0.51,
    },
    "Year": {"label": "Log Year", "unit": "Year", "default": datetime.now().year},
    "Month": {"label": "Log Month", "unit": "Month", "default": datetime.now().month},
    "Day": {"label": "Log Day", "unit": "Day", "default": datetime.now().day},
    "Hour": {"label": "Log Hour", "unit": "Hour", "default": datetime.now().hour},
}

LABELS = {0: "High", 1: "Low", 2: "Medium"}

MODE_MAPPING = {
    "active": 0,
    "0": 0,
    0: 0,
    "idle": 1,
    "1": 1,
    1: 1,
    "maintenance": 2,
    "2": 2,
    2: 2,
}

PRESETS = {
    "optimal": {
        "name": "🟢 Optimal Production (High Efficiency)",
        "desc": "Low error rate, peak speed, stable temperatures",
        "values": {
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
            "Year": 2024,
            "Month": 1,
            "Day": 1,
            "Hour": 12,
        },
    },
    "moderate": {
        "name": "🟡 Moderate Thermal Drift (Medium Efficiency)",
        "desc": "Intermediate error rate, moderate throughput with minor latency",
        "values": {
            "Operation_Mode": "Active",
            "Temperature_C": 40.5,
            "Vibration_Hz": 0.30,
            "Power_Consumption_kW": 4.07,
            "Network_Latency_ms": 29.15,
            "Packet_Loss_%": 1.16,
            "Quality_Control_Defect_Rate_%": 4.58,
            "Production_Speed_units_per_hr": 329.5,
            "Predictive_Maintenance_Score": 0.98,
            "Error_Rate_%": 2.74,
            "Year": 2024,
            "Month": 1,
            "Day": 1,
            "Hour": 12,
        },
    },
    "critical": {
        "name": "🔴 Error & Vibration Spike (Low Efficiency)",
        "desc": "High controller error rate, degraded mechanical efficiency",
        "values": {
            "Operation_Mode": "Idle",
            "Temperature_C": 74.1,
            "Vibration_Hz": 3.50,
            "Power_Consumption_kW": 8.61,
            "Network_Latency_ms": 10.65,
            "Packet_Loss_%": 0.21,
            "Quality_Control_Defect_Rate_%": 7.75,
            "Production_Speed_units_per_hr": 477.6,
            "Predictive_Maintenance_Score": 0.34,
            "Error_Rate_%": 14.96,
            "Year": 2024,
            "Month": 1,
            "Day": 1,
            "Hour": 12,
        },
    },
}

# Lazy loading — non-fatal if model artifacts are missing on startup
model = None
scaler = None
model_load_error = None


def get_artifacts():
    global model, scaler, model_load_error
    if model is not None and scaler is not None:
        return model, scaler
    try:
        if not os.path.exists(MODEL_PATH) or not os.path.exists(SCALER_PATH):
            try:
                from src.model_training import ModelTraining

                trainer = ModelTraining("artifacts/processed/", "artifacts/models/")
                trainer.run()
            except Exception as train_err:
                model_load_error = f"Model training failed: {train_err}"
                return None, None
        model = joblib.load(MODEL_PATH)
        scaler = joblib.load(SCALER_PATH)
        if hasattr(model, "__dict__") and not hasattr(model, "multi_class"):
            setattr(model, "multi_class", "auto")
        model_load_error = None
    except Exception as e:
        model_load_error = str(e)
        return None, None
    return model, scaler


def predict_efficiency(form_data):
    clf, scl = get_artifacts()

    # Process inputs
    row = []
    cleaned_inputs = {}
    now = datetime.now()

    for feat in FEATURES:
        val = form_data.get(feat, None)
        if feat == "Operation_Mode":
            val_str = str(val).strip().lower() if val is not None else "active"
            num_val = MODE_MAPPING.get(val_str, 0)
            cleaned_inputs[feat] = (
                "Active"
                if num_val == 0
                else ("Idle" if num_val == 1 else "Maintenance")
            )
            row.append(float(num_val))
        elif feat in ["Year", "Month", "Day", "Hour"]:
            default_val = getattr(now, feat.lower())
            final_val = int(val) if val not in [None, ""] else default_val
            cleaned_inputs[feat] = final_val
            row.append(float(final_val))
        else:
            default_val = FEATURE_METADATA[feat].get("default", 0.0)
            final_val = float(val) if val not in [None, ""] else default_val
            cleaned_inputs[feat] = final_val
            row.append(final_val)

    # Scale with feature names to suppress warnings
    df_input = pd.DataFrame([row], columns=FEATURES)
    scaled_array = scl.transform(df_input)

    pred_idx = int(clf.predict(scaled_array)[0])
    label_name = LABELS.get(pred_idx, "Unknown")

    # Probabilities
    probs = (
        clf.predict_proba(scaled_array)[0]
        if hasattr(clf, "predict_proba")
        else [0.0, 0.0, 0.0]
    )
    prob_dict = {
        "High": round(float(probs[0]) * 100, 2),
        "Low": round(float(probs[1]) * 100, 2),
        "Medium": round(float(probs[2]) * 100, 2),
    }
    confidence = prob_dict.get(label_name, 0.0)

    # Diagnostic recommendation
    if label_name == "High":
        recommendation = "✅ Peak Performance: Machine operational profile is optimal. Maintain current schedule."
        status_color = "emerald"
    elif label_name == "Medium":
        recommendation = "⚠️ Moderate Drift: Monitor spindle vibration and controller error rates closely."
        status_color = "amber"
    else:
        recommendation = "🚨 Efficiency Drop: High error rate or mechanical friction detected. Immediate inspection recommended."
        status_color = "rose"

    return {
        "status": "success",
        "prediction": label_name,
        "confidence": confidence,
        "status_color": status_color,
        "probabilities": prob_dict,
        "recommendation": recommendation,
        "inputs": cleaned_inputs,
    }


@app.route("/", methods=["GET", "POST"])
def index():
    result = None
    initial_values = PRESETS["optimal"]["values"].copy()

    if request.method == "POST":
        try:
            result = predict_efficiency(request.form)
            initial_values.update(result["inputs"])
        except Exception as e:
            result = {
                "status": "error",
                "prediction": "Error",
                "confidence": 0,
                "status_color": "rose",
                "probabilities": {"High": 0, "Medium": 0, "Low": 0},
                "recommendation": f"Inference failure: {str(e)}",
                "inputs": initial_values,
            }

    return render_template(
        "index.html",
        result=result,
        features=FEATURES,
        metadata=FEATURE_METADATA,
        presets=PRESETS,
        current_values=initial_values,
    )


@app.route("/api/predict", methods=["POST"])
def api_predict():
    try:
        data = request.get_json(silent=True) or request.form
        result = predict_efficiency(data)
        return jsonify(result), 200
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 400


@app.route("/api/presets", methods=["GET"])
def api_presets():
    return jsonify(PRESETS), 200


@app.route("/api/health", methods=["GET"])
def health():
    clf, scl = get_artifacts()
    return (
        jsonify(
            {
                "status": "healthy",
                "service": "Smart Manufacturing AI Inference Server",
                "model_loaded": clf is not None,
                "model_error": model_load_error,
                "timestamp": datetime.now().isoformat(),
            }
        ),
        200,
    )


if __name__ == "__main__":
    # Non-fatal startup: log model load result but always start the server
    try:
        get_artifacts()
        if model is not None:
            print(f"[✓] Model loaded from {MODEL_PATH}")
        else:
            print(
                f"[!] Model not loaded: {model_load_error} — /predict will return 503"
            )
    except Exception as e:
        print(f"[!] Startup model load error (non-fatal): {e}")
    port = int(os.environ.get("PORT", 5000))
    debug_mode = os.environ.get("FLASK_DEBUG", "0").lower() in ("1", "true")
    app.run(debug=debug_mode, host="0.0.0.0", port=port)
