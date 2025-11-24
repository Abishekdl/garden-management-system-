# download_model.py
from transformers import AutoProcessor, BlipForConditionalGeneration
import os

def download_blip_base_model():
    """
    Downloads the BLIP base model and processor from Hugging Face
    and saves them to a local directory named 'blip-base-local'.
    """
    model_name = "Salesforce/blip-image-captioning-base"
    local_dir = "blip-base-local"

    if os.path.exists(local_dir):
        print(f"Directory '{local_dir}' already exists. Assuming model is downloaded.")
        return

    print(f"Downloading model '{model_name}' to local directory '{local_dir}'...")
    print("This may take a while depending on your internet connection.")

    try:
        # Download and save the processor
        processor = AutoProcessor.from_pretrained(model_name)
        processor.save_pretrained(local_dir)
        print("Processor downloaded successfully.")

        # Download and save the model
        model = BlipForConditionalGeneration.from_pretrained(model_name)
        model.save_pretrained(local_dir)
        print("Model downloaded successfully.")

        print("\nDownload complete!")
        print(f"Model and processor are saved in the '{local_dir}' directory.")

    except Exception as e:
        print(f"\nAn error occurred during download: {e}")
        print("Please check your internet connection and try again.")

if __name__ == "__main__":
    download_blip_base_model()