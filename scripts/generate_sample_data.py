#!/usr/bin/env python3
import os
import argparse
import json
from src.data.generator import generate_sensor_telemetry, generate_synthetic_defect_images

def main():
    parser = argparse.ArgumentParser(description="Generate synthetic industrial telemetry and defect image datasets.")
    parser.add_argument("--samples", type=int, default=1000, help="Number of telemetry samples")
    parser.add_argument("--images", type=int, default=100, help="Number of optical inspection images")
    parser.add_argument("--outdir", default="data/sample", help="Output directory")
    args = parser.parse_args()

    os.makedirs(args.outdir, exist_ok=True)
    
    print(f"[*] Generating {args.samples} sensor telemetry records...")
    df = generate_sensor_telemetry(n_samples=args.samples)
    telemetry_file = os.path.join(args.outdir, "sensor_telemetry.csv")
    df.to_csv(telemetry_file, index=False)
    print(f"[✓] Saved telemetry to {telemetry_file}")

    print(f"[*] Generating {args.images} synthetic defect images...")
    images, labels = generate_synthetic_defect_images(n_samples=args.images)
    metadata = {
        "count": args.images,
        "classes": ["normal", "crack", "pitting", "burn_mark"],
        "shape": list(images.shape),
    }
    with open(os.path.join(args.outdir, "images_metadata.json"), "w") as f:
        json.dump(metadata, f, indent=2)
    print(f"[✓] Saved image metadata to {os.path.join(args.outdir, 'images_metadata.json')}")
    print("[*] Sample data generation finished successfully!")

if __name__ == "__main__":
    main()
