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

### AI Model Requirements
- PyTorch (CPU or GPU version)
- Transformers library
- Fine-tuned BLIP model (included in `server/fine_tuned_blip_garden_monitor/`)
- OpenCV for video frame extraction
- Minimum 4GB RAM (8GB+ recommended for AI processing)

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
git clone <your-repo-url>
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

#### Step 6: Run the server
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

## Project Structure

```
garden_app/
├── lib/                          # Flutter app source code
│   ├── main.dart                 # App entry point with Firebase & notification setup
│   ├── firebase_options.dart    # Firebase configuration
│   ├── pages/                    # UI screens
│   │   ├── splash_page.dart     # App splash screen
│   │   ├── role_selection_page.dart  # Student/Staff role selection
│   │   ├── login_page.dart      # Student login
│   │   ├── staff_login_page.dart # Staff login
│   │   ├── camera_page.dart     # Photo/video capture for students
│   │   ├── history_page.dart    # Student report history
│   │   ├── staff_dashboard_page.dart  # Staff task dashboard
│   │   ├── task_detail_page.dart # Task details with map
│   │   └── ...
│   ├── services/                 # Business logic services
│   │   ├── notification_service.dart  # FCM token management
│   │   ├── local_notification_service.dart  # Local notifications
│   │   ├── location_service.dart # GPS & geocoding
│   │   └── notification_manager.dart  # Notification coordination
│   ├── utils/                    # Utility classes
│   │   ├── server_config.dart   # Server URL configuration
│   │   ├── vit_location_mapper.dart  # VIT campus location mapping
│   │   └── ...
│   └── widgets/                  # Reusable UI components
│
├── server/                       # Flask backend
│   ├── app.py                   # Main Flask application
│   ├── blip_processor.py        # AI image captioning
│   ├── requirements.txt         # Python dependencies
│   ├── serviceAccountKey.json   # Firebase Admin SDK key (DO NOT COMMIT)
│   ├── admin_panel_enhanced.html # Admin web dashboard
│   ├── admin_styles.css         # Admin panel styles
│   ├── admin_script.js          # Admin panel JavaScript
│   ├── fine_tuned_blip_garden_monitor/  # AI model files
│   ├── uploads/                 # Original uploaded media
│   ├── processed/               # AI-processed media
│   └── completed/               # Task completion photos
│
├── pubspec.yaml                 # Flutter dependencies
├── README.md                    # This file
└── .gitignore                   # Git ignore rules
```

## API Endpoints

### Student Endpoints
- `POST /upload/image` - Upload photo/video with GPS data
- `GET /processed/<filename>` - Retrieve processed media
- `GET /completed/<filename>` - Retrieve completion photos

### Staff Endpoints
- `POST /complete_task` - Mark task as completed with photo
- `POST /staff/login` - Staff authentication
- `POST /update_fcm_token` - Update FCM token

### Admin Endpoints
- `GET /admin` - Admin panel dashboard
- `GET /staff/workload` - Staff workload statistics
- `GET /admin/all_tasks` - All tasks with filters
- `GET /admin/all_students` - Student list with activity
- `GET /admin/all_staff` - Staff list with task counts
- `GET /admin/analytics` - System analytics
- `POST /admin/generate_report` - Generate PDF report
- `POST /admin/send_notification` - Broadcast notifications
- `GET /admin/media_gallery` - All media files

### Utility Endpoints
- `GET /health` - Server health check
- `POST /trigger_token_refresh` - Force FCM token refresh

## Deployment Notes

### Heavy Dependencies
- **PyTorch & Transformers**: The AI model requires significant resources (4GB+ RAM). For production:
  - Use a dedicated server with sufficient RAM/CPU
  - Consider GPU acceleration for faster processing
  - Or move AI processing to a separate microservice
  
- **OpenCV**: Required for video frame extraction. On Windows, it may require Visual C++ redistributables.

### Production Deployment
⚠️ **DO NOT use Flask's built-in server in production!**

**Recommended Production Setup:**
1. Use a WSGI server (Gunicorn on Linux, Waitress on Windows)
2. Set up reverse proxy (Nginx or Apache)
3. Use environment variables for configuration
4. Enable HTTPS with SSL certificates
5. Set up proper logging and monitoring
6. Use a process manager (systemd, supervisor, or PM2)

**Example with Gunicorn (Linux):**
```bash
pip install gunicorn
gunicorn -w 4 -b 0.0.0.0:5000 app:app
```

**Example with Waitress (Windows):**
```bash
pip install waitress
waitress-serve --host=0.0.0.0 --port=5000 app:app
```

## Usage Guide

### For Students
1. **First Time Setup**:
   - Open the app
   - Select "Student" role
   - Enter your name and register number
   - Grant camera and location permissions

2. **Reporting an Issue**:
   - Tap camera icon on home screen
   - Take a photo (tap) or video (hold button)
   - Optionally add floor and room details
   - Submit - AI will automatically caption the issue
   - View in History tab

3. **Tracking Reports**:
   - Go to History tab
   - See all your reports with status
   - Tap on any report to view details
   - Receive notifications when completed

### For Staff
1. **Login**:
   - Select "Staff" role
   - Enter staff ID and password
   - Grant notification permissions

2. **Managing Tasks**:
   - View pending tasks in Dashboard
   - See distance to each task location
   - Tap task to view details and map
   - Navigate to location using map apps

3. **Completing Tasks**:
   - Open task details
   - Tap "Complete Task"
   - Take completion photo
   - Submit - student receives notification

### For Admins
1. **Access Admin Panel**:
   - Open browser to `http://your-server:5000/admin`
   
2. **Monitor System**:
   - View real-time statistics on dashboard
   - Check staff workload distribution
   - Browse all tasks and filter by status
   
3. **Manage Staff**:
   - Create new staff accounts
   - View individual staff performance
   - Activate/deactivate staff members
   
4. **Generate Reports**:
   - Select time period
   - Click "Generate Report"
   - Download PDF with analytics

## Troubleshooting

### Common Issues

**1. FCM Notifications Not Working**
- Check server logs for FCM errors
- Verify `serviceAccountKey.json` matches Firebase project ID (`garden-main`)
- Ensure FCM is enabled in Firebase Console
- Check if FCM token is registered in Firestore
- Try force refreshing token from app settings

**2. Server Connection Failed**
- Verify server is running: `http://localhost:5000/health`
- Check `SERVER_BASE_URL` in `server/app.py`
- Update `_baseUrl` in `lib/utils/server_config.dart`
- Ensure firewall allows port 5000
- For Android emulator, use `http://10.0.2.2:5000`

**3. Images/Videos Not Loading (404)**
- Confirm files exist in `uploads/`, `processed/`, or `completed/` folders
- Check file permissions
- Verify URL uses correct `SERVER_BASE_URL`
- Check server logs for file serving errors

**4. AI Captioning Fails**
- Ensure PyTorch and Transformers are installed correctly
- Check if model files exist in `fine_tuned_blip_garden_monitor/`
- Verify sufficient RAM (4GB+ required)
- Check server logs for AI processing errors
- For videos, OpenCV must be installed for frame extraction

**5. Location Not Working**
- Grant location permissions in app settings
- Enable GPS/Location Services on device
- Check if location services are enabled in device settings
- For VIT campus, ensure GPS has clear sky view

**6. Staff Login Issues**
- Verify staff account exists in Firestore `staff` collection
- Check staff ID and password are correct
- Ensure `active` field is set to `true`
- Check server logs for authentication errors

### Debug Mode
Enable detailed logging:
- **Flutter**: Check console output when running `flutter run`
- **Server**: All requests are logged with 🚀, ✅, ❌ emojis for easy tracking
- **Firebase**: Check Firestore console for data structure

### Getting Help
- Check server logs in terminal
- Check Flutter logs: `flutter logs`
- Review Firebase Console for errors
- Ensure all dependencies are installed correctly

## Technologies Used

### Frontend (Flutter)
- **firebase_core** & **firebase_messaging** - Push notifications
- **cloud_firestore** - Real-time database
- **camera** - Photo/video capture
- **geolocator** & **geocoding** - GPS location services
- **google_maps_flutter** - Map integration
- **flutter_local_notifications** - Local notification display
- **http** - REST API communication
- **shared_preferences** - Local data storage

### Backend (Python/Flask)
- **Flask** - Web framework
- **PyTorch** - Deep learning framework
- **Transformers** - BLIP model for image captioning
- **firebase-admin** - Firebase Admin SDK
- **opencv-python** - Video processing
- **Pillow** - Image processing
- **geopy** - Geocoding services
- **reportlab** - PDF generation
- **flask-cors** - CORS support

### Infrastructure
- **Firebase Firestore** - NoSQL database
- **Firebase Cloud Messaging** - Push notifications
- **Firebase Admin SDK** - Server-side Firebase operations

## Contributing

This is a VIT Vellore campus project. For contributions:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

[Add your license here]

## Acknowledgments

- VIT Vellore for project support
- Firebase for backend infrastructure
- Hugging Face for BLIP model
- Flutter team for excellent mobile framework

## Contact

For questions or support:
- Project Lead: [Your Name]
- Email: [Your Email]
- Institution: VIT Vellore

---

**Note**: This project is designed specifically for VIT Vellore Campus with custom location mapping for campus buildings and blocks. Adapt the location services in `lib/utils/vit_location_mapper.dart` for other campuses or locations.
