# Garden App

A comprehensive Flutter mobile app and Flask backend system for reporting and managing garden maintenance issues at VIT Vellore Campus. The project includes a Flutter client (mobile) for students and staff, a Python Flask server with AI-powered image captioning, and a web-based admin panel for monitoring and analytics.

**Quick summary**
- **Client:** Flutter app under `lib/` (entry: `lib/main.dart`). Uses Firebase (FCM + Firestore), local notifications, camera, GPS location services, and Google Maps integration.
- **Server:** Flask app under `server/` (entry: `server/app.py`). Uses Firebase Admin SDK, fine-tuned BLIP AI model for image captioning, stores media files locally, and provides REST APIs for mobile app and admin panel.
- **Admin Panel:** Web-based dashboard (`server/admin_panel_enhanced.html`) for staff management, task monitoring, analytics, and reporting.

**Project layout (important paths)**
- `pubspec.yaml`: Flutter dependencies and metadata.
- `lib/`: Flutter app source (pages, services, widgets).
- `lib/main.dart`: App entry — Firebase init, notification setup, ServerConfig auto-config.
- `lib/firebase_options.dart`: Generated Firebase configuration (contains API keys for Android/macos).
- `server/app.py`: Flask backend — upload endpoints, admin API, notifications.
- `server/requirements.txt`: Python dependencies for the server (Flask, torch, Pillow, transformers, firebase-admin, opencv-python, reportlab, ...).
- `server/serviceAccountKey.json`: REQUIRED for Firebase Admin SDK (sensitive — not committed to public repos).
- `uploads/`, `processed/`, `completed/`: Local media folders used by the server.

**What the server does**
- **Student Uploads** (`/upload/image`): Accepts images/videos with GPS data, performs AI captioning using fine-tuned BLIP model, creates tasks in Firestore, and assigns to staff using round-robin load balancing.
- **Task Completion** (`/complete_task`): Staff upload completion photos, system updates task status, sends FCM notifications to students with completion images, and saves notification history.
- **Admin Panel** (`/admin*` routes): Provides web dashboard for staff workload monitoring, task queue management, analytics, media gallery, PDF report generation, and broadcast notifications.
- **FCM Management**: Token registration, validation, refresh flow, and diagnostic endpoints for troubleshooting notifications.
- **Location Services**: VIT campus-specific location mapping with building/block detection.
- **Media Serving**: Serves uploaded, processed, and completed media files with proper CORS headers for mobile compatibility.

## Key Features

### For Students
- 📸 **Photo/Video Capture**: Take photos or record videos of garden issues directly from the app
- 📍 **GPS Location Tagging**: Automatic GPS coordinates and address capture with VIT campus block detection
- 🤖 **AI-Powered Captioning**: Fine-tuned BLIP model automatically describes the issue
- 📝 **Optional Location Details**: Add floor number and nearby classroom/room information
- 📊 **History Tracking**: View all submitted reports with status updates
- 🔔 **Push Notifications**: Receive notifications when tasks are completed with completion photos
- 🗺️ **Map Integration**: View task locations on Google Maps

### For Staff
- 📋 **Task Dashboard**: View assigned tasks (pending/completed) with real-time updates
- 📏 **Distance Calculation**: See distance from current location to task location
- ✅ **Task Completion**: Upload completion photos and mark tasks as done
- 🔔 **Task Notifications**: Receive notifications for newly assigned tasks
- 👥 **Load Balancing**: Tasks automatically distributed using round-robin algorithm

### For Admins (Web Panel)
- 📊 **Analytics Dashboard**: Real-time statistics on tasks, completion rates, and user activity
- 👨‍💼 **Staff Management**: Create staff accounts, monitor workload, activate/deactivate staff
- 📸 **Media Gallery**: Browse all uploaded, processed, and completed media files
- 📄 **PDF Reports**: Generate detailed reports for any time period
- 📢 **Broadcast Notifications**: Send notifications to all staff, all students, or specific users
- 🔍 **Task Monitoring**: View all tasks with filtering by status, staff, or student

## Environment & Prerequisites

### Mobile App (Flutter)
- Flutter SDK 3.8.1 or higher
- Dart SDK (comes with Flutter)
- Android Studio or VS Code with Flutter extensions
- Android device or emulator for testing
- Install Flutter: https://flutter.dev

### Backend Server (Python)
- Python 3.8 or higher (Python 3.12 recommended)
- Virtual environment (venv or conda)
- Firebase project with Firestore and FCM enabled
- Service account key JSON file from Firebase Console

### Firebase Setup
- Create a Firebase project at https://console.firebase.google.com
- Enable Firestore Database
- Enable Cloud Messaging (FCM)
- Download service account key and save as `server/serviceAccountKey.json`
- Configure Flutter app with Firebase using FlutterFire CLI

## Security & Sensitive Data

⚠️ **IMPORTANT**: The following files contain sensitive credentials and should NEVER be committed to public repositories:

- `server/serviceAccountKey.json` - Firebase Admin SDK private key
- `lib/firebase_options.dart` - Contains Firebase API keys (already in repo, but be cautious)
- `.env` files if you create them for environment variables

**Best Practices:**
- Add `serviceAccountKey.json` to `.gitignore`
- Use environment variables for production deployments
- Rotate Firebase keys if accidentally exposed
- Set `SERVER_BASE_URL` environment variable to your actual server domain/IP
- Default dev tunnel URL in code is for development only

## Installation & Setup

### 1. Clone the Repository

```bash
git clone https://github.com/Abishekdl/garden-management-system-.git
cd garden_app
```

### 2. Backend Server Setup (Windows)

#### Step 1: Navigate to server directory
```powershell
cd server
```

#### Step 2: Create and activate virtual environment
```powershell
python -m venv venv
.\venv\Scripts\Activate.ps1
```

#### Step 3: Install dependencies
```powershell
pip install --upgrade pip
pip install -r requirements.txt
```

**Note on PyTorch**: The `requirements.txt` includes PyTorch. For CPU-only installation (smaller download):
```powershell
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
```

For GPU support, visit https://pytorch.org and select your CUDA version.

#### Step 4: Configure Firebase
1. Go to [Firebase Console](https://console.firebase.google.com)
2. Create a new project or select existing one
3. Enable Firestore Database and Cloud Messaging
4. Go to Project Settings → Service Accounts
5. Click "Generate New Private Key"
6. Save the downloaded JSON file as `server/serviceAccountKey.json`

#### Step 5: Set server URL (optional)
```powershell
$env:SERVER_BASE_URL = 'http://your-server-ip:5000'
```

Or edit `server/app.py` line 17 to set your server URL.

#### Step 6: Download and Setup AI Model ⚠️ IMPORTANT

The AI model is **NOT included in the repository** due to its large size (~1GB).

**📥 Option 1: Get Fine-Tuned Model (Recommended)**

Contact the project maintainer to obtain the `fine_tuned_blip_garden_monitor` folder, then place it in `server/` directory:

```
server/
└── fine_tuned_blip_garden_monitor/
    ├── config.json
    ├── model.safetensors
    ├── preprocessor_config.json
    ├── tokenizer_config.json
    ├── tokenizer.json
    └── vocab.txt
```

**🔄 Option 2: Use Base BLIP Model (Alternative)**

If you don't have the fine-tuned model, use Hugging Face's base model:

Edit `server/blip_processor.py` (line ~10):
```python
# Change from:
FINE_TUNED_MODEL_PATH = os.path.join(CURRENT_SCRIPT_DIR, "fine_tuned_blip_garden_monitor")

# To:
FINE_TUNED_MODEL_PATH = "Salesforce/blip-image-captioning-base"
```

First run will auto-download the model (~1GB) from Hugging Face.

**Note**: Base model gives generic captions. Fine-tuned model is trained for garden maintenance issues.

**☁️ Option 3: Host on Cloud Storage**

For team collaboration, host the model on:
- Google Drive (share folder link)
- AWS S3 / Azure Blob Storage
- Hugging Face Hub
- Git LFS (if your GitHub plan supports large files)

**✅ Verify Model Setup:**
```powershell
# Check if model folder exists
ls server/fine_tuned_blip_garden_monitor/

# Test the model
cd server
python -c "from blip_processor import generate_caption; print('Model loaded successfully!')"
```

#### Step 7: Run the server
```powershell
python app.py
```

The server will start on `http://localhost:5000` (or your configured URL).

**Access Admin Panel**: Open browser to `http://localhost:5000/admin`

### 3. Flutter App Setup

#### Step 1: Install Flutter dependencies
```bash
cd ..  # Back to project root
flutter pub get
```

#### Step 2: Configure Firebase for Flutter
The project already includes `lib/firebase_options.dart`, but if you need to reconfigure:

```bash
# Install FlutterFire CLI
dart pub global activate flutterfire_cli

# Configure Firebase
flutterfire configure
```

#### Step 2.5: Create Firebase Configuration Files

Firebase configuration files are not included in the repository (they're project-specific). Create them from examples:

```bash
# Copy example files
cp .firebaserc.example .firebaserc
cp firebase.json.example firebase.json
cp firestore.rules.example firestore.rules
cp firestore.indexes.json.example firestore.indexes.json

# Edit .firebaserc and replace 'your-project-id-here' with your actual Firebase project ID
```

**Deploy Firestore rules and indexes:**
```bash
# Install Firebase CLI
npm install -g firebase-tools

# Login to Firebase
firebase login

# Deploy rules and indexes
firebase deploy --only firestore:rules
firebase deploy --only firestore:indexes
```

**Important**: The example Firestore rules are permissive for development. Update them with proper authentication for production!

#### Step 3: Update server URL in app
Edit `lib/utils/server_config.dart` line 5:
```dart
static String _baseUrl = 'http://your-server-ip:5000';
```

#### Step 4: Run the app
```bash
# List available devices
flutter devices

# Run on connected device/emulator
flutter run

# Or specify device
flutter run -d <device-id>
```

### 4. Create Staff Accounts

Staff accounts must be created through the admin panel or directly in Firestore:

**Option 1: Admin Panel**
1. Open `http://localhost:5000/admin`
2. Go to Staff Management section
3. Click "Create Staff"
4. Enter Staff ID, Name, and Password

**Option 2: Firestore Console**
1. Go to Firebase Console → Firestore Database
2. Create collection `staff`
3. Add document with ID as staff ID (e.g., `staff1`)
4. Add fields:
   - `name`: "Staff Name"
   - `password`: "password123"
   - `active`: true
   - `createdAt`: (timestamp)
