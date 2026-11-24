from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional
import uvicorn
import os
import cv2
import numpy as np
from ultralytics import YOLO
import time
import json
from pathlib import Path

# Initialize FastAPI app
app = FastAPI(
    title="AR Road Nav Backend",
    description="Python Backend for YOLOv11 Pothole Detection & Road Navigation"
)

# CORS - allow mobile app and local development
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Load YOLO Model - try trained model first, fall back to pretrained
MODEL_PATHS = ["best.pt", "runs/detect/pothole_detector/weights/best.pt", "yolo11n.pt"]
model = None
for mp in MODEL_PATHS:
    if os.path.exists(mp):
        try:
            model = YOLO(mp)
            print(f"✅ Model loaded from {mp}")
            break
        except Exception as e:
            print(f"⚠️ Failed to load {mp}: {e}")

if model is None:
    try:
        model = YOLO("yolo11n.pt")
        print("✅ Loaded default YOLOv11n pretrained model")
    except Exception as e:
        print(f"❌ Could not load any model: {e}")

# Pothole database file
POTHOLE_DB = Path("pothole_reports.json")


# ─── Models ───────────────────────────────────────────────────────────
class DetectionResult(BaseModel):
    class_id: int
    class_name: str
    confidence: float
    bbox: List[float]  # [x_center, y_center, width, height] normalized


class PotholeReport(BaseModel):
    latitude: float
    longitude: float
    severity: str = "medium"  # low, medium, high
    timestamp: Optional[float] = None


class SensorData(BaseModel):
    latitude: float
    longitude: float
    speed: float
    accelerometer_z: float
    timestamp: float


# ─── Helpers ──────────────────────────────────────────────────────────
def load_pothole_db() -> List[dict]:
    if POTHOLE_DB.exists():
        with open(POTHOLE_DB, "r") as f:
            return json.load(f)
    return []


def save_pothole_db(data: List[dict]):
    with open(POTHOLE_DB, "w") as f:
        json.dump(data, f, indent=2)


# ─── Endpoints ────────────────────────────────────────────────────────
@app.get("/")
def read_root():
    return {
        "status": "running",
        "service": "AR Road Nav Backend",
        "model_loaded": model is not None,
    }


@app.post("/detect", response_model=List[DetectionResult])
async def detect_potholes(file: UploadFile = File(...)):
    """
    Receives an image file, runs YOLO inference, and returns detections.
    """
    if model is None:
        raise HTTPException(status_code=503, detail="Model not loaded")

    # Read image file
    try:
        contents = await file.read()
        nparr = np.frombuffer(contents, np.uint8)
        img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        if img is None:
            raise ValueError("Could not decode image")
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Invalid image data: {e}")

    # Run Inference
    results = model(img, conf=0.25)

    detections = []
    for result in results:
        boxes = result.boxes
        for box in boxes:
            cls_id = int(box.cls[0])
            cls_name = model.names[cls_id]
            conf = float(box.conf[0])
            xywh = box.xywhn[0].tolist()

            detections.append(DetectionResult(
                class_id=cls_id,
                class_name=cls_name,
                confidence=conf,
                bbox=xywh,
            ))

    return detections


@app.post("/report_pothole")
async def report_pothole(report: PotholeReport):
    """
    Report a pothole location detected by the mobile app.
    """
    db = load_pothole_db()
    entry = {
        "latitude": report.latitude,
        "longitude": report.longitude,
        "severity": report.severity,
        "timestamp": report.timestamp or time.time(),
        "reported_at": time.strftime("%Y-%m-%d %H:%M:%S"),
    }
    db.append(entry)
    save_pothole_db(db)
    return {"status": "reported", "total_reports": len(db)}


@app.get("/get_potholes")
async def get_potholes(
    lat: Optional[float] = None,
    lng: Optional[float] = None,
    radius_km: float = 5.0,
):
    """
    Get reported potholes. Optionally filter by proximity to a location.
    """
    db = load_pothole_db()

    if lat is not None and lng is not None:
        # Simple distance filter (approximate km using Euclidean on degrees)
        # 1 degree ≈ 111 km
        filtered = []
        for p in db:
            dlat = abs(p["latitude"] - lat)
            dlng = abs(p["longitude"] - lng)
            dist_km = ((dlat ** 2 + dlng ** 2) ** 0.5) * 111.0
            if dist_km <= radius_km:
                filtered.append(p)
        return {"potholes": filtered, "count": len(filtered)}

    return {"potholes": db, "count": len(db)}


@app.post("/log_sensor_data")
async def log_data(data: SensorData):
    """
    Receive sensor logs (GPS, vibration) from the mobile app.
    """
    log_file = "sensor_logs.csv"
    timestamp_str = time.strftime(
        "%Y-%m-%d %H:%M:%S", time.localtime(data.timestamp)
    )
    log_line = (
        f"{timestamp_str},{data.latitude},{data.longitude},"
        f"{data.speed},{data.accelerometer_z}\n"
    )

    with open(log_file, "a") as f:
        f.write(log_line)

    return {"status": "logged"}


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
