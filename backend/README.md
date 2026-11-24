# AR Road Navigation System - Python Backend

This backend provides a **REST API** for the mobile application to perform object detection (if not running on-device) and log sensor data.

## Features
- **Object Detection API** (`/detect`): Accepts images, returns YOLOv11 bounding boxes (JSON).
- **Sensor Logging API** (`/log_deployment_data`): Archives GPS, Speed, and Vibration data.

## Setup
1.  **Install Dependencies**:
    ```bash
    pip install -r requirements.txt
    ```

2.  **Run Server**:
    ```bash
    python server.py
    ```
    The server will start at `http://0.0.0.0:8000`.

3.  **API Docs**:
    Visit `http://localhost:8000/docs` to see the automated Swagger documentation.
