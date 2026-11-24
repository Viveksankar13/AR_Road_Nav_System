"""
Prepare the Roboflow exported dataset for training.
- Creates train/val split (80/20) from the single 'train' folder
- Updates data.yaml with correct paths
"""
import os
import shutil
import random
from pathlib import Path

def prepare_dataset():
    # Paths
    base = Path(r"c:\Users\ASUS\.gemini\antigravity\scratch\ar_road_nav_system\backend")
    roboflow_dir = base / "Pothole Detection.yolov11"
    dataset_dir = base / "dataset"
    
    src_images = roboflow_dir / "train" / "images"
    src_labels = roboflow_dir / "train" / "labels"
    
    # Create output directories
    for split in ["train", "valid"]:
        (dataset_dir / split / "images").mkdir(parents=True, exist_ok=True)
        (dataset_dir / split / "labels").mkdir(parents=True, exist_ok=True)
    
    # Get all image files
    image_files = sorted([f for f in src_images.iterdir() if f.suffix.lower() in ('.jpg', '.jpeg', '.png')])
    print(f"Found {len(image_files)} images")
    
    # Shuffle and split 80/20
    random.seed(42)  # For reproducibility
    random.shuffle(image_files)
    
    split_idx = int(len(image_files) * 0.8)
    train_files = image_files[:split_idx]
    val_files = image_files[split_idx:]
    
    print(f"Train: {len(train_files)} images")
    print(f"Valid: {len(val_files)} images")
    
    # Copy files
    for split_name, files in [("train", train_files), ("valid", val_files)]:
        for img_path in files:
            # Copy image
            dst_img = dataset_dir / split_name / "images" / img_path.name
            shutil.copy2(img_path, dst_img)
            
            # Copy corresponding label
            label_name = img_path.stem + ".txt"
            src_label = src_labels / label_name
            if src_label.exists():
                dst_label = dataset_dir / split_name / "labels" / label_name
                shutil.copy2(src_label, dst_label)
            else:
                print(f"  ⚠️ Missing label for: {img_path.name}")
    
    # Write data.yaml
    data_yaml = dataset_dir / "data.yaml"
    data_yaml.write_text(
        f"# YOLOv11 Dataset Configuration for Pothole Detection\n"
        f"# Auto-generated from Roboflow export\n\n"
        f"path: {dataset_dir.as_posix()}\n"
        f"train: train/images\n"
        f"val: valid/images\n\n"
        f"nc: 1\n"
        f"names: ['pothole']\n"
    )
    
    print(f"\n[OK] Dataset prepared at: {dataset_dir}")
    print(f"[OK] data.yaml written at: {data_yaml}")
    print(f"\nTo train, run:")
    print(f'  python train_gpu.py --data "{data_yaml}"')


if __name__ == "__main__":
    prepare_dataset()
