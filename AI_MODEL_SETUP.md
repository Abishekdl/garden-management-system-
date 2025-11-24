# AI Model Setup Guide

## ⚠️ Important: Model Not Included in Repository

The fine-tuned BLIP model (`fine_tuned_blip_garden_monitor`) is **~1GB in size** and is **NOT included** in this GitHub repository to keep the repo size manageable.

---

## 📥 Option 1: Get the Fine-Tuned Model (Recommended)

### Step 1: Obtain the Model
Contact the project maintainer to get the `fine_tuned_blip_garden_monitor` folder.

### Step 2: Place in Server Directory
```
server/
└── fine_tuned_blip_garden_monitor/
    ├── config.json
    ├── generation_config.json
    ├── model.safetensors
    ├── preprocessor_config.json
    ├── special_tokens_map.json
    ├── tokenizer_config.json
    ├── tokenizer.json
    └── vocab.txt
```

### Step 3: Verify Setup
```powershell
# Windows
dir server\fine_tuned_blip_garden_monitor

# Linux/Mac
ls server/fine_tuned_blip_garden_monitor/
```

You should see all the files listed above.

---

## 🔄 Option 2: Use Base BLIP Model (Alternative)

If you don't have access to the fine-tuned model, you can use the base BLIP model from Hugging Face.

### Step 1: Edit blip_processor.py

Open `server/blip_processor.py` and find this line (around line 10):

```python
FINE_TUNED_MODEL_PATH = os.path.join(CURRENT_SCRIPT_DIR, "fine_tuned_blip_garden_monitor")
```

Change it to:

```python
FINE_TUNED_MODEL_PATH = "Salesforce/blip-image-captioning-base"
```

### Step 2: First Run Downloads Model

When you first run the server, it will automatically download the base model (~1GB) from Hugging Face:

```powershell
cd server
python app.py
```

You'll see:
```
Downloading model from Hugging Face...
This may take a few minutes...
```

The model will be cached in `~/.cache/huggingface/` for future use.

### Differences Between Models

| Feature | Fine-Tuned Model | Base Model |
|---------|------------------|------------|
| Size | ~1GB | ~1GB |
| Training | Trained on garden maintenance images | General image captioning |
| Accuracy | High for garden issues | Generic descriptions |
| Example Output | "Broken irrigation pipe near garden bed" | "A pipe on the ground" |

---

## ☁️ Option 3: Host Model on Cloud Storage

For team collaboration, consider hosting the model on cloud storage:

### Google Drive

1. **Upload the model folder** to Google Drive
2. **Share the folder** with your team
3. **Get shareable link**

**Download script:**
```powershell
# Install gdown
pip install gdown

# Download (replace FILE_ID with your Google Drive file ID)
gdown --folder https://drive.google.com/drive/folders/YOUR_FOLDER_ID -O server/fine_tuned_blip_garden_monitor
```

### AWS S3

```bash
# Upload to S3
aws s3 cp server/fine_tuned_blip_garden_monitor/ s3://your-bucket/models/fine_tuned_blip_garden_monitor/ --recursive

# Download from S3
aws s3 cp s3://your-bucket/models/fine_tuned_blip_garden_monitor/ server/fine_tuned_blip_garden_monitor/ --recursive
```

### Hugging Face Hub

Upload your fine-tuned model to Hugging Face:

```python
from transformers import BlipForConditionalGeneration, AutoProcessor

# Load your model
model = BlipForConditionalGeneration.from_pretrained("server/fine_tuned_blip_garden_monitor")
processor = AutoProcessor.from_pretrained("server/fine_tuned_blip_garden_monitor")

# Push to Hugging Face
model.push_to_hub("your-username/garden-blip-model")
processor.push_to_hub("your-username/garden-blip-model")
```

Then in `blip_processor.py`:
```python
FINE_TUNED_MODEL_PATH = "your-username/garden-blip-model"
```

---

## ✅ Testing the Model

After setup, test if the model works:

### Test 1: Import Test
```powershell
cd server
python

# In Python shell:
>>> from blip_processor import generate_caption
>>> print("Model loaded successfully!")
>>> exit()
```

### Test 2: Caption Generation Test
```python
from blip_processor import generate_caption
from PIL import Image

# Use any test image
img = Image.open("test_image.jpg")
caption = generate_caption(img)
print(f"Generated caption: {caption}")
```

### Test 3: Server Test
```powershell
# Start the server
python app.py

# Upload a test image through the app
# Check server logs for AI caption generation
```

---

## 🐛 Troubleshooting

### Error: "Model not found"
```
FileNotFoundError: [Errno 2] No such file or directory: 'server/fine_tuned_blip_garden_monitor'
```

**Solution**: 
- Verify model folder exists in `server/` directory
- Or switch to base model (Option 2)

### Error: "Out of memory"
```
RuntimeError: CUDA out of memory
```

**Solution**:
- Use CPU instead of GPU (edit `blip_processor.py`, set `DEVICE = "cpu"`)
- Close other applications
- Increase system RAM

### Error: "Model loading takes too long"
```
Model loading is slow on first run
```

**Solution**:
- First load always takes time (~1-2 minutes)
- Subsequent loads are faster (model cached)
- Use SSD instead of HDD for faster loading

### Error: "Invalid model format"
```
OSError: Unable to load weights from pytorch checkpoint file
```

**Solution**:
- Re-download the model (might be corrupted)
- Verify all model files are present
- Check PyTorch version compatibility

---

## 📊 Model Information

### Fine-Tuned Model Details
- **Base Model**: Salesforce BLIP (Bootstrapping Language-Image Pre-training)
- **Fine-tuning Dataset**: Garden maintenance images from VIT Vellore
- **Training**: Custom fine-tuning for garden issue detection
- **Output**: Descriptive captions for garden maintenance issues

### Model Files Explained
- `config.json` - Model configuration
- `model.safetensors` - Model weights (main file, ~1GB)
- `preprocessor_config.json` - Image preprocessing settings
- `tokenizer_config.json` - Text tokenizer configuration
- `tokenizer.json` - Tokenizer vocabulary
- `vocab.txt` - Word vocabulary

---

## 🔐 Security Note

If hosting the model on cloud storage:
- ✅ Use private buckets/folders
- ✅ Implement access controls
- ✅ Use signed URLs for downloads
- ❌ Don't make model publicly accessible without permission

---

## 📞 Need Help?

- **Can't get the model?** Contact project maintainer
- **Model not working?** Check troubleshooting section above
- **Want to fine-tune your own?** See Hugging Face BLIP documentation

---

**Remember**: The model is essential for AI-powered image captioning. Without it, the app will fail to generate captions for uploaded images!
