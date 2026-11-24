from ultralytics import YOLO
import sys

def export_to_tflite(model_path="best.pt", data_yaml="pothole_data.yaml"):
    """
    Export a trained YOLOv11 model to TFLite INT8 format.
    INT8 quantization makes the model significantly faster on mobile CPUs (like Helio G80)
    while maintaining almost identical accuracy.
    """
    print(f"Loading '{model_path}'...")
    try:
        model = YOLO(model_path)
        
        print("\nStarting TFLite export with INT8 Quantization...")
        print("This may take 1-3 minutes. It uses the dataset to calibrate the compression...")
        
        # Export to TFLite using int8 quantization for mobile speed
        # The data.yaml gives it images to "calibrate" the INT8 precision loss
        success = model.export(
            format="tflite", 
            int8=True, 
            data=data_yaml,
            imgsz=640
        )
        
        print(f"\nModel exported successfully! Saved as TFLite format.")
        print(f"You can now copy the .tflite file into your Flutter app's assets folder.")
    except Exception as e:
        print(f"\nError exporting model: {e}")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        model_path = sys.argv[1]
        export_to_tflite(model_path)
    else:
        export_to_tflite()
