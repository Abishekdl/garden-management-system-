# blip_processor.py
import torch
from PIL import Image, ImageDraw, ImageFont
import os
import sys
from transformers import AutoProcessor, BlipForConditionalGeneration
from geopy.geocoders import Nominatim
from geopy.exc import GeocoderTimedOut, GeocoderServiceError

# --- Configuration ---
CURRENT_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
FINE_TUNED_MODEL_PATH = os.path.join(CURRENT_SCRIPT_DIR, "fine_tuned_blip_garden_monitor")
DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
MAX_NEW_TOKENS = 50

# --- Load Fine-Tuned Model and Processor ---
try:
    ft_processor = AutoProcessor.from_pretrained(FINE_TUNED_MODEL_PATH)
    ft_model = BlipForConditionalGeneration.from_pretrained(FINE_TUNED_MODEL_PATH).to(DEVICE)
    ft_model.eval()
    print("✅ SUCCESS: Fine-tuned model loaded.")
except Exception as e:
    print(f"❌ ERROR: Failed to load fine-tuned model from '{FINE_TUNED_MODEL_PATH}'. {e}")
    sys.exit(1)

# --- Font Loading ---
try:
    font = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 28)
except IOError:
    font = ImageFont.load_default()
    print("⚠️ WARNING: Arial font not found. Using default font.")

def get_address_from_coords(latitude, longitude):
    """Converts latitude and longitude to a human-readable address using Nominatim."""
    from geopy.geocoders import Nominatim
    geolocator = Nominatim(user_agent="garden_app_monitor")
    try:
        location = geolocator.reverse((latitude, longitude), exactly_one=True)
        if location and location.raw:
            address = location.raw.get('address', {})
            for key in ['name', 'locality', 'suburb', 'city', 'town', 'village']:
                if key in address:
                    return address[key]
            return location.address
        else:
            return f"Address not found for {latitude}, {longitude}"
    except Exception as e:
        return f"An unexpected error occurred during geocoding: {e}"

def add_text_to_image(image_pil, text):
    # This function remains the same
    draw = ImageDraw.Draw(image_pil, "RGBA")
    return image_pil

# ## --- UPDATED: Simplified to one caption generation function --- ##
def generate_caption(image_pil):
    """Generates a single caption using the fine-tuned model."""
    try:
        inputs = ft_processor(images=image_pil, return_tensors="pt").to(DEVICE)
        with torch.no_grad():
            generated_ids = ft_model.generate(pixel_values=inputs.pixel_values, max_new_tokens=MAX_NEW_TOKENS)
        caption = ft_processor.batch_decode(generated_ids, skip_special_tokens=True)[0]
        return caption.strip()
    except Exception as e:
        return f"Error in captioning: {e}"
