"""
GPU Training Script for Pothole Detection (YOLOv11)
Optimized for NVIDIA RTX 3050 Laptop GPU (4GB VRAM)

Usage:
    python train_gpu.py                          # Train with defaults
    python train_gpu.py --epochs 100             # Custom epochs
    python train_gpu.py --model yolov8n.pt       # Use YOLOv8 instead
    python train_gpu.py --data path/to/data.yaml # Custom dataset path
"""

import argparse
import torch
from ultralytics import YOLO


def check_gpu():
    """Verify GPU is available and print info."""
    print("=" * 60)
    print("GPU STATUS CHECK")
    print("=" * 60)
    
    if torch.cuda.is_available():
        gpu_name = torch.cuda.get_device_name(0)
        vram_total = torch.cuda.get_device_properties(0).total_memory / (1024**3)
        print(f"  [OK] GPU Found: {gpu_name}")
        print(f"  [OK] VRAM: {vram_total:.1f} GB total")
        print(f"  [OK] PyTorch CUDA: {torch.version.cuda}")
        print(f"  [OK] Device: cuda:0")
        return True
    else:
        print("  [!!] No CUDA GPU detected!")
        print("  [!!] Training will fall back to CPU (much slower)")
        return False


def train(data_yaml, model_name="yolo11n.pt", epochs=50, batch_size=8, img_size=640):
    """
    Train YOLO model with GPU acceleration.
    
    Args:
        data_yaml: Path to dataset YAML config
        model_name: Pretrained model to start from (yolo11n.pt or yolov8n.pt)
        epochs: Number of training epochs
        batch_size: Batch size (8 is safe for 4GB VRAM)
        img_size: Input image size
    """
    has_gpu = check_gpu()
    
    print(f"\n{'=' * 60}")
    print("TRAINING CONFIGURATION")
    print(f"{'=' * 60}")
    print(f"  Model:      {model_name}")
    print(f"  Dataset:    {data_yaml}")
    print(f"  Epochs:     {epochs}")
    print(f"  Batch Size: {batch_size}")
    print(f"  Image Size: {img_size}")
    print(f"  Device:     {'GPU (cuda:0)' if has_gpu else 'CPU'}")
    print(f"{'=' * 60}\n")
    
    # Load pretrained model
    model = YOLO(model_name)
    
    # Train - ultralytics auto-detects GPU, but we set device explicitly
    results = model.train(
        data=data_yaml,
        epochs=epochs,
        imgsz=img_size,
        batch=batch_size,
        device=0 if has_gpu else "cpu",  # Force GPU 0
        
        # Memory optimization for 4GB VRAM
        workers=4,         # Data loading workers
        cache=True,        # Cache images in RAM for faster training
        
        # Training settings
        patience=20,       # Early stopping patience
        save=True,         # Save checkpoints
        save_period=10,    # Save checkpoint every 10 epochs
        plots=True,        # Generate training plots
        
        # Output
        project="runs/detect",
        name="pothole_detector",
        exist_ok=True,     # Overwrite existing run
    )
    
    # Validate
    print(f"\n{'=' * 60}")
    print("RUNNING VALIDATION...")
    print(f"{'=' * 60}")
    metrics = model.val()
    
    # Print results
    print(f"\n{'=' * 60}")
    print("TRAINING COMPLETE!")
    print(f"{'=' * 60}")
    print(f"  mAP50:     {metrics.box.map50:.4f}")
    print(f"  mAP50-95:  {metrics.box.map:.4f}")
    print(f"  Precision: {metrics.box.mp:.4f}")
    print(f"  Recall:    {metrics.box.mr:.4f}")
    print(f"\n  Best model saved to:")
    print(f"     runs/detect/pothole_detector/weights/best.pt")
    print(f"\n  To use in your server, copy best.pt to backend/:")
    print(f"     copy runs\\detect\\pothole_detector\\weights\\best.pt best.pt")
    print(f"{'=' * 60}")
    
    return results


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Train YOLO Pothole Detector (GPU)")
    parser.add_argument("--data", type=str, default="pothole_data.yaml",
                        help="Path to dataset YAML (default: pothole_data.yaml)")
    parser.add_argument("--model", type=str, default="yolo11n.pt",
                        help="Pretrained model: yolo11n.pt (v11) or yolov8n.pt (v8)")
    parser.add_argument("--epochs", type=int, default=50,
                        help="Number of training epochs (default: 50)")
    parser.add_argument("--batch", type=int, default=8,
                        help="Batch size - keep <=8 for 4GB VRAM (default: 8)")
    parser.add_argument("--imgsz", type=int, default=640,
                        help="Input image size (default: 640)")
    
    args = parser.parse_args()
    train(args.data, args.model, args.epochs, args.batch, args.imgsz)
