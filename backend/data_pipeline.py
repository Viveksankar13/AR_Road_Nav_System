import cv2
import numpy as np
import os
from pathlib import Path

def preprocess_image(image_path, target_size=(640, 640)):
    """
    Reads an image, applies Gaussian blur, resizes, and normalizes it.
    
    Args:
        image_path (str): Path to the input image.
        target_size (tuple): Target size (width, height).
        
    Returns:
        np.ndarray: Preprocessed image.
    """
    # Read image
    img = cv2.imread(str(image_path))
    if img is None:
        raise ValueError(f"Could not read image at {image_path}")

    # Gaussian Blur to reduce noise
    # Kernel size (5, 5) is standard, sigmaX=0 means calculated from kernel size
    img_blurred = cv2.GaussianBlur(img, (5, 5), 0)

    # Resize
    img_resized = cv2.resize(img_blurred, target_size)

    # Normalize pixel values to [0, 1]
    img_normalized = img_resized.astype(np.float32) / 255.0

    return img_normalized

def process_dataset(input_dir, output_dir):
    """
    Process all images in input_dir and save to output_dir.
    """
    input_path = Path(input_dir)
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)

    for img_file in input_path.glob('*.[jJ][pP]*[gG]'): # simplistic glob for jpg/jpeg/png
        try:
            processed_img = preprocess_image(str(img_file))
            # Convert back to 0-255 for saving, or save as .npy if needed for specific training pipelines that expect float
            # For standard YOLOv8, it handles normalization internally usually, but user asked for this stage.
            # We will save as standard image for compatibility with standard YOLO loaders, 
            # but noting that the 'normalization' step returns float 0-1.
            # If we save as image, we lose the float precision unless we save as .npy or TIFF.
            # For visualization/standard dataset structure, we usually keep them as images.
            # Let's save as pre-processed images (blurred/resized).
            
            # To save as viewable image:
            save_img = (processed_img * 255).astype(np.uint8)
            cv2.imwrite(str(output_path / img_file.name), save_img)
            print(f"Processed {img_file.name}")
        except Exception as e:
            print(f"Error processing {img_file.name}: {e}")

if __name__ == "__main__":
    # Example usage
    # Ensure 'raw_data' and 'processed_data' directories exist or are created
    # process_dataset("raw_data", "processed_data")
    print("Data pipeline script ready. Use process_dataset(input, output) to run.")
