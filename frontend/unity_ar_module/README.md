# Unity AR Module Setup

To complete the Unity setup for this module, follow these steps:

1.  **Open Unity Hub** and create a new 3D (Core) project named `ARRoadNav`.
2.  **Package Manager**: Install the following packages:
    *   `AR Foundation`
    *   `ARCore Extensions` (for Geospatial API)
    *   `Unity Sentis` (for running ONNX models)
3.  **Project Settings -> XR Plug-in Management**:
    *   Enable `ARCore` provider (Android) and `ARKit` (iOS).
4.  **Scene Setup**:
    *   Delete the default camera.
    *   Add `XR Origin` (with AR Camera).
    *   Add `AR Session`.
    *   Add `AR Plane Manager` to the XR Origin.
    *   Add `AR Raycast Manager` to the XR Origin.
    *   **Crucial**: Add `AR Occlusion Manager` to the AR Camera for depth occlusion (prevents glitchy overlays).
5.  **Scripts**:
    *   Copy the scripts from `Assets/Scripts` into your Unity project's Scripts folder.
    *   Attach `PotholeVisualizer` to a GameObject in the scene.
    *   Assign the `AR Raycast Manager` and a Prefab (create a simple Red Cube for testing) to the script slots.
6.  **Build**:
    *   Switch platform to Android/iOS.
    *   Build and export to verify basic AR plane detection works.
