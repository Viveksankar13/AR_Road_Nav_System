using System.Collections.Generic;
using UnityEngine;
using UnityEngine.XR.ARFoundation;
using UnityEngine.XR.ARSubsystems;

public class PotholeVisualizer : MonoBehaviour
{
    [SerializeField]
    private ARRaycastManager raycastManager;
    
    [SerializeField]
    private GameObject potholeWarningPrefab; // The red box/icon

    [SerializeField]
    private Camera arCamera;

    // Start is called before the first frame update
    void Start()
    {
        if (raycastManager == null)
            raycastManager = FindObjectOfType<ARRaycastManager>();
            
        if (arCamera == null)
            arCamera = Camera.main;
    }

    /// <summary>
    /// Call this when a pothole is detected on screen (2D pixel coordinates).
    /// </summary>
    /// <param name="screenPosition">Center of the detection box in screen pixels.</param>
    public void PlaceWarningMarker(Vector2 screenPosition)
    {
        // 1. Raycast against the estimated planes (Road surface)
        List<ARRaycastHit> hits = new List<ARRaycastHit>();
        
        // Prioritize: Plane (Road) -> Feature Point -> Depth
        // Note: Using PlaneWithinPolygon for best accuracy on detected surfaces
        if (raycastManager.Raycast(screenPosition, hits, TrackableType.PlaneWithinPolygon))
        {
            Pose hitPose = hits[0].pose;
            Instantiate(potholeWarningPrefab, hitPose.position, hitPose.rotation);
        }
        else
        {
            // Fallback: If no plane detected yet, try feature point or approximate depth
            // For now, project forward on ground level relative to camera forward vector?
            // Safer to just wait for plane detection to avoid floating markers.
            Debug.LogWarning("No road surface detected at screen position: " + screenPosition);
        }
    }

    /// <summary>
    /// Updates the position of markers to stick to the world.
    /// In AR Foundation, instantiated GameObjects stay at world coords automatically
    /// as long as the session tracking is stable.
    /// </summary>
}
