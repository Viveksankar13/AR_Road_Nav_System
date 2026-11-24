from ultralytics import YOLO

def train_yolo(data_yaml_path, epochs=50, img_size=640):
    """
    Train YOLOv11 Nano model.
    """
    # Load a model
    model = YOLO("yolo11n.pt")  # load a pretrained YOLOv11 nano model

    # Train the model
    results = model.train(
        data=data_yaml_path, 
        epochs=epochs, 
        imgsz=img_size, 
        plots=True,
        batch=8,
        name='pothole_detector'
    )
    
    # Evaluate performance
    metrics = model.val()
    print(metrics)

    # Save the model
    model.export(format="onnx") # Only export if strictly needed here, usually separate step.

if __name__ == "__main__":
    # Example: train_yolo("pothole_data.yaml")
    print("Training script ready. Configure 'pothole_data.yaml' first.")
