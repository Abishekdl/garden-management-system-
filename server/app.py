# app.py
from flask import Flask, request, jsonify, send_from_directory, url_for, make_response, send_file
import os
from PIL import Image
from werkzeug.utils import secure_filename
import blip_processor
import uuid
import firebase_admin
from firebase_admin import credentials, firestore, messaging
from datetime import datetime
from google.cloud.firestore import FieldFilter
import requests
import io
import json

app = Flask(__name__)

# Configure server base URL - IMPORTANT: Set this to your actual server IP/domain
SERVER_BASE_URL = os.environ.get('SERVER_BASE_URL', 'https://zhgkq02n-5000.inc1.devtunnels.ms')
print(f"🌐 Server configured with base URL: {SERVER_BASE_URL}")
print(f"🔧 Server will be accessible at: {SERVER_BASE_URL}")
print(f"📱 Ensure Flutter app ServerConfig matches this URL")

# --- Initialize Firebase Admin SDK ---
try:
    # This key file must be in the same directory as app.py
    cred = credentials.Certificate("serviceAccountKey.json")
    firebase_admin.initialize_app(cred)
    print("✅ Firebase Admin SDK initialized successfully.")
except Exception as e:
    print(f"❌ ERROR: Failed to initialize Firebase Admin SDK: {e}")

# --- Folder and Extension Configuration ---
UPLOAD_FOLDER, PROCESSED_FOLDER, COMPLETED_FOLDER = 'uploads', 'processed', 'completed'
os.makedirs(UPLOAD_FOLDER, exist_ok=True)
os.makedirs(PROCESSED_FOLDER, exist_ok=True)
os.makedirs(COMPLETED_FOLDER, exist_ok=True)
app.config.update(UPLOAD_FOLDER=UPLOAD_FOLDER, PROCESSED_FOLDER=PROCESSED_FOLDER, COMPLETED_FOLDER=COMPLETED_FOLDER)

def allowed_file(filename):
    """Checks if a file has an allowed extension."""
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in {'png', 'jpg', 'jpeg', 'mp4', 'mov', 'avi', 'mkv'}

def is_video_file(filename):
    """Check if file is a video."""
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in {'mp4', 'mov', 'avi', 'mkv'}

# --- Firestore compatibility helper (filter vs where) ---
def fs_filter(query, field, op, value):
    """Use modern .filter(FieldFilter) if available, else fall back to .where()."""
    if hasattr(query, 'filter'):
        try:
            return query.filter(FieldFilter(field, op, value))
        except Exception:
            # In case the installed SDK exposes attribute but not compatible
            return query.where(field, op, value)
    return query.where(field, op, value)

def test_fcm_token(token, student_id):
    """Test if FCM token is valid without sending actual notification"""
    try:
        # Create a test message with dry_run=True (doesn't actually send)
        message = messaging.Message(
            notification=messaging.Notification(
                title='Test',
                body='FCM Token Validation Test'
            ),
            token=token
        )
        
        # Validate the message without sending
        response = messaging.send(message, dry_run=True)
        print(f"✅ FCM Token is valid for student {student_id}: {response}")
        return True
    except Exception as e:
        print(f"❌ FCM Token validation failed for student {student_id}: {e}")
        print(f"   Error type: {type(e).__name__}")
        return False

def send_completion_notification(student_id, completed_image_url, caption, staff_id=None, task_id=None):
    """Sends a push notification to a student when their task is completed with enhanced data."""
    db = firestore.client()
    try:
        student_ref = db.collection('students').document(student_id)
        student_doc = student_ref.get()
        if not student_doc.exists:
            print(f"Error: Student document for ID '{student_id}' not found.")
            return

        token = student_doc.to_dict().get('fcmToken')
        if not token:
            print(f"Error: FCM token not found for student '{student_id}'.")
            return

        staff_name = staff_id if staff_id else 'Garden Staff'
        print(f"Preparing to send notification to student: {student_id}")
        print(f"FCM token: {token[:20]}...{token[-10:]}")  # Show partial token for security
        print(f"Notification payload: completedImageUrl={completed_image_url}, caption={caption}, staffId={staff_id}, taskId={task_id}")
        
        # Test token validity first
        if not test_fcm_token(token, student_id):
            print(f"⚠️ FCM token validation failed, but continuing to save notification to database")
            print(f"🔄 Triggering token refresh for student {student_id}")
            # Try to trigger a token refresh by sending a refresh request
            try:
                refresh_response = requests.post(
                    f"{SERVER_BASE_URL}/trigger_token_refresh",
                    json={"studentId": student_id, "reason": "token_validation_failed"},
                    headers={"Content-Type": "application/json"},
                    timeout=5
                )
                if refresh_response.status_code == 200:
                    print(f"✅ Token refresh triggered for student {student_id}")
                else:
                    print(f"⚠️ Failed to trigger token refresh: {refresh_response.status_code}")
            except Exception as refresh_error:
                print(f"⚠️ Error triggering token refresh: {refresh_error}")
        message = messaging.Message(
            notification=messaging.Notification(
                title='🎉 Task Completed!',
                body=f'Your reported issue has been resolved by {staff_name}. Tap to see the completion photo.'
            ),
            token=token,
            data={
                'taskId': task_id if task_id else student_id,
                'type': 'task_completed',
                'completedImageUrl': completed_image_url,
                'caption': caption,
                'staffId': staff_id if staff_id else 'unknown',
                'staffName': staff_name,
                'completedAt': datetime.now().isoformat(),
                'click_action': 'FLUTTER_NOTIFICATION_CLICK'
            },
            # Enhanced Android configuration for better notification display
            android=messaging.AndroidConfig(
                notification=messaging.AndroidNotification(
                    icon='@drawable/notification_icon',
                    color='#4CAF50',  # Green color for completed tasks
                    sound='default',
                    channel_id='task_completed_channel'
                ),
                priority='high'
            ),
            # Enhanced iOS configuration
            apns=messaging.APNSConfig(
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(
                        alert=messaging.ApsAlert(
                            title='🎉 Task Completed!',
                            body=f'Your reported issue has been resolved by {staff_name}. Tap to see the completion photo.'
                        ),
                        badge=1,
                        sound='default'
                    )
                )
            )
        )

        try:
            response = messaging.send(message)
            print('✅ Successfully sent completion notification:', response)
        except messaging.UnregisteredError:
            print(f"❌ FCM Token is invalid or unregistered for student {student_id}")
            print(f"   Token: {token[:20]}...")
            print("   Solution: Student needs to re-login to generate fresh FCM token")
        except messaging.SenderIdMismatchError:
            print(f"❌ FCM Sender ID mismatch for student {student_id}")
            print("   Solution: Check Firebase project configuration and service account key")
        except messaging.QuotaExceededError:
            print(f"❌ FCM Quota exceeded for student {student_id}")
            print("   Solution: Check Firebase usage limits in console")
        except messaging.InvalidArgumentError as e:
            print(f"❌ FCM Invalid argument for student {student_id}: {e}")
            print("   Solution: Check message format and token validity")
        except Exception as send_error:
            print(f"❌ FCM Error sending completion notification to student {student_id}: {send_error}")
            print(f"   Error type: {type(send_error).__name__}")
            print(f"   Token: {token[:20]}...")
            print("   This might be due to invalid FCM token or Firebase project configuration")
            # Continue execution even if FCM fails - still save to database
            pass
        
        # Also save notification to student's notification collection for history
        try:
            notification_data = {
                # FIX 1: Changed .millisecond to .microsecond
                'id': f'completion_{task_id}_{datetime.now().microsecond}',
                'title': 'Task Completed!',
                'message': f'Your reported issue has been resolved by {staff_name}. Tap to see the completion photo.',
                'type': 'task_completed',
                'imageUrl': completed_image_url,
                'staffInfo': staff_name,
                'taskId': task_id,
                'timestamp': firestore.SERVER_TIMESTAMP,
                'read': False,
                'sender': staff_name
            }
            print(f'📝 DEBUG: Saving notification with imageUrl: {completed_image_url}')
            print(f'📝 DEBUG: Full notification data: {notification_data}')
            db.collection('notifications').document(student_id).collection('user_notifications').add(notification_data)
            print(f'✅ Notification saved to database for student {student_id}')
        except Exception as save_error:
            print(f'⚠️ Error saving notification to database: {save_error}')
            
    except Exception as e:
        print(f"Error sending completion notification: {e}")

def send_thank_you_notification_internal(student_id, task_id, staff_name='Garden Staff'):
    """Internal function to send thank you notification to student."""
    db = firestore.client()
    try:
        student_doc = db.collection('students').document(student_id).get()
        if not student_doc.exists:
            print(f"⚠️ Student {student_id} not found for thank you notification")
            return

        student_data = student_doc.to_dict()
        fcm_token = student_data.get('fcmToken')

        if fcm_token:
            try:
                message = messaging.Message(
                    notification=messaging.Notification(
                        title='🙏 Thank You for Your Report!',
                        body=f'Thank you for helping us maintain our garden. Your report has been addressed by {staff_name}.'
                    ),
                    data={
                        'type': 'thank_you',
                        'taskId': task_id,
                        'timestamp': datetime.now().isoformat()
                    },
                    token=fcm_token,
                    android=messaging.AndroidConfig(
                        notification=messaging.AndroidNotification(
                            icon='@drawable/notification_icon',
                            color='#2196F3',  # Blue color for thank you
                            sound='default',
                            channel_id='thank_you_channel'
                        ),
                        priority='high'
                    ),
                )
                response = messaging.send(message)
                print(f'✅ Thank you FCM notification sent: {response}')
            except Exception as fcm_error:
                print(f'⚠️ FCM error for thank you notification: {fcm_error}')

        # Save to database regardless of FCM success
        notification_ref = db.collection('notifications').document(student_id).collection('user_notifications')
        notification_ref.add({
            'id': f'thank_you_{task_id}_{datetime.now().microsecond}',
            'title': 'Thank You for Your Report!',
            'message': f'Thank you for helping us maintain our garden. Your report has been addressed by {staff_name}.',
            'type': 'thank_you',
            'taskId': task_id,
            'timestamp': firestore.SERVER_TIMESTAMP,
            'read': False,
            'sender': staff_name
        })
        print(f'✅ Thank you notification saved to database for student {student_id}')
        
    except Exception as e:
        print(f"❌ Error in send_thank_you_notification_internal: {e}")

def send_new_task_notification_to_staff(caption, location):
    """Sends a push notification to all staff members about a new task."""
    db = firestore.client()
    try:
        staff_docs = db.collection('staff').stream()
        tokens = [doc.to_dict().get('fcmToken') for doc in staff_docs if doc.to_dict().get('fcmToken')]
        
        if not tokens:
            print("⚠️ Warning: No staff tokens found to send notification.")
            print("   Staff members need to log in to receive notifications.")
            return

        # Send notification to each staff member individually
        success_count = 0
        failure_count = 0
        
        for token in tokens:
            try:
                message = messaging.Message(
                    notification=messaging.Notification(
                        title='New Task Reported!',
                        body=f'{caption} at {location}'
                    ),
                    token=token,
                    data={
                        'type': 'new_task',
                        'caption': caption,
                        'location': location
                    }
                )
                messaging.send(message)
                success_count += 1
            except Exception as send_error:
                failure_count += 1
                print(f"❌ Failed to send to staff token: {send_error}")
        
        print(f'✅ Successfully sent new task notification to {success_count} staff members.')
        if failure_count > 0:
            print(f'⚠️ Failed to send to {failure_count} staff members.')
    except Exception as e:
        print(f"❌ Error sending new task notification: {e}")
        print("   Continuing with upload despite notification failure.")


@app.route('/upload/image', methods=['POST'])
def upload_image():
    """Handles image uploads from students."""
    if 'file' not in request.files: return jsonify({'error': 'No file part'}), 400
    file = request.files['file']
    if file.filename == '': return jsonify({'error': 'No selected file'}), 400

    student_name = request.form.get('name', 'Unknown')
    register_number = request.form.get('register_number', 'Unknown')
    user_caption = request.form.get('user_caption', '')
    
    latitude = request.form.get('latitude')
    longitude = request.form.get('longitude')
    location_accuracy = request.form.get('location_accuracy')
    location_address = request.form.get('location_address', '')
    location_timestamp = request.form.get('location_timestamp')
    
    gps_data = None
    if latitude and longitude:
        try:
            gps_data = {
                'latitude': float(latitude),
                'longitude': float(longitude),
                'accuracy': float(location_accuracy) if location_accuracy else 0.0,
                'address': location_address,
                'timestamp': location_timestamp
            }
            print(f"📍 GPS data received: {latitude}, {longitude} - {location_address}")
        except ValueError as e:
            print(f"⚠️ Invalid GPS coordinates received: {e}")
            gps_data = None
    else:
        print("📍 No GPS data provided with upload")
    
    if file and allowed_file(file.filename):
        # Check if file is a video
        is_video = is_video_file(file.filename)
        
        # Use appropriate extension
        if is_video:
            file_ext = file.filename.rsplit('.', 1)[1].lower()
            unique_filename = f"{uuid.uuid4()}.{file_ext}"
        else:
            unique_filename = f"{uuid.uuid4()}.jpg"
            
        filepath = os.path.join(app.config['UPLOAD_FOLDER'], unique_filename)
        file.save(filepath)
        
        try:
            if is_video:
                # For videos, extract frame and generate AI caption
                print(f"✅ Video uploaded: {unique_filename}")
                
                # Copy video to processed folder
                import shutil
                processed_path = os.path.join(app.config['PROCESSED_FOLDER'], unique_filename)
                shutil.copy(filepath, processed_path)
                print(f"✅ Video copied to processed folder")
                
                # Extract first frame from video for AI caption generation
                try:
                    import cv2
                    video_capture = cv2.VideoCapture(filepath)
                    success, frame = video_capture.read()
                    video_capture.release()
                    
                    if success:
                        # Convert frame to PIL Image
                        frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                        frame_image = Image.fromarray(frame_rgb)
                        
                        # Generate AI caption from video frame
                        try:
                            caption = blip_processor.generate_caption(frame_image)
                            print(f"✅ AI Caption generated from video frame: {caption}")
                            
                            # Add user location details if provided
                            if user_caption:
                                caption = f"{caption} ({user_caption})"
                                print(f"✅ Combined caption with location details: {caption}")
                        except Exception as caption_error:
                            print(f"⚠️ AI Caption generation failed: {caption_error}")
                            caption = user_caption if user_caption else "Video upload - maintenance required"
                    else:
                        print(f"⚠️ Could not extract frame from video")
                        caption = user_caption if user_caption else "Video upload - maintenance required"
                        
                except ImportError:
                    print(f"⚠️ OpenCV not installed, cannot extract video frame")
                    caption = user_caption if user_caption else "Video upload - maintenance required"
                except Exception as video_error:
                    print(f"⚠️ Video frame extraction failed: {video_error}")
                    caption = user_caption if user_caption else "Video upload - maintenance required"
                
            else:
                # Process images with AI
                image = Image.open(filepath).convert("RGB")
                
                # Try to generate caption with error handling
                try:
                    caption = blip_processor.generate_caption(image)
                    print(f"✅ AI Caption generated: {caption}")
                except Exception as caption_error:
                    print(f"⚠️ AI Caption generation failed: {caption_error}")
                    caption = "Garden maintenance required - AI processing unavailable"
                
                # Try to create captioned image with error handling
                try:
                    captioned_image = blip_processor.add_text_to_image(image.copy(), f"Caption: {caption}")
                    captioned_image.save(os.path.join(app.config['PROCESSED_FOLDER'], unique_filename))
                    print(f"✅ Captioned image saved")
                except Exception as image_error:
                    print(f"⚠️ Image captioning failed: {image_error}")
                    # Save original image if captioning fails
                    image.save(os.path.join(app.config['PROCESSED_FOLDER'], unique_filename))
                    print(f"✅ Original image saved as fallback")
            
            # Use configured base URL instead of request.url_root to avoid localhost issues
            image_url = f"{SERVER_BASE_URL}/processed/{unique_filename}"
            print(f"Generated media_url: {image_url}")
            
            if gps_data and gps_data['address']:
                location = gps_data['address']
            else:
                location = "VIT Vellore Campus"
            
            db = firestore.client()
            task_id = str(uuid.uuid4())
            
            assigned_staff_id = assign_task_to_staff(db)
            
            task_data = {
                'taskId': task_id,
                'studentName': student_name,
                'registerNumber': register_number,
                'studentCaption': user_caption,
                'aiCaption': caption,
                'imageUrl': image_url,
                'location': location,
                'status': 'pending',
                'assignedTo': assigned_staff_id,
                'createdAt': firestore.SERVER_TIMESTAMP,
                'completedAt': None,
                'completionImageUrl': None,
                'gpsData': gps_data
            }
            
            db.collection('tasks').document(task_id).set(task_data)
            print(f"✅ Task {task_id} created and assigned to staff: {assigned_staff_id}")
            
            send_notification_to_assigned_staff(assigned_staff_id, caption, location, task_id)
            
            response_data = {
                'aiCaption': caption if caption else 'No caption generated',
                'caption': caption if caption else 'No caption generated',
                'image_url': image_url if image_url else '',  # Keep original for compatibility
                'imageUrl': image_url if image_url else '',   # Add Flutter-expected field
                'taskId': task_id if task_id else '',
                'assignedTo': assigned_staff_id if assigned_staff_id else 'staff1',
                'status': 'Task created and assigned successfully',
                'location': location if location else 'Unknown Location',
                'timestamp': datetime.now().isoformat() + 'Z',
                'studentName': student_name if student_name else 'Unknown',
                'register_number': register_number if register_number else 'Unknown',
                'gpsData': gps_data
            }
            
            print(f"📤 Sending response: {response_data}")
            return jsonify(response_data)
        except Exception as e:
            print(f"❌ Error processing upload: {e}")
            return jsonify({'error': str(e)}), 500
            
    return jsonify({'error': 'Invalid file'}), 400


def assign_task_to_staff(db):
    """Assigns task to staff member using round-robin or least-loaded strategy."""
    try:
        staff_collection = db.collection('staff').stream()
        staff_list = []
        
        for staff_doc in staff_collection:
            staff_data = staff_doc.to_dict()
            staff_id = staff_doc.id
            
            pending_tasks = db.collection('tasks').filter(FieldFilter('assignedTo', '==', staff_id)).filter(FieldFilter('status', '==', 'pending')).stream()
            task_count = sum(1 for _ in pending_tasks)
            
            staff_list.append({
                'id': staff_id,
                'taskCount': task_count,
                'hasToken': 'fcmToken' in staff_data
            })
        
        if not staff_list:
            return 'staff1'
        
        staff_list.sort(key=lambda x: (x['taskCount'], not x['hasToken']))
        
        assigned_staff = staff_list[0]['id']
        print(f"📋 Assigning task to {assigned_staff} (current load: {staff_list[0]['taskCount']} tasks)")
        return assigned_staff
        
    except Exception as e:
        print(f"⚠️ Error in task assignment: {e}. Defaulting to staff1")
        return 'staff1'

def send_notification_to_assigned_staff(staff_id, caption, location, task_id):
    """Sends notification to the specific staff member assigned to the task."""
    db = firestore.client()
    try:
        staff_doc = db.collection('staff').document(staff_id).get()
        
        if not staff_doc.exists:
            print(f"⚠️ Staff member {staff_id} not found in database")
            return
            
        staff_data = staff_doc.to_dict()
        token = staff_data.get('fcmToken')
        
        if not token:
            print(f"⚠️ No FCM token found for staff {staff_id}")
            return
        
        message = messaging.Message(
            notification=messaging.Notification(
                title='📋 New Task Assigned!',
                body=f'{caption} at {location}'
            ),
            token=token,
            data={
                'taskId': task_id,
                'type': 'new_task',
                'caption': caption,
                'location': location,
                'click_action': 'FLUTTER_NOTIFICATION_CLICK'
            },
            # Enhanced Android configuration for better notification display
            android=messaging.AndroidConfig(
                notification=messaging.AndroidNotification(
                    icon='@drawable/notification_icon',
                    color='#FF9800',  # Orange color for new tasks
                    sound='default',
                    channel_id='new_task_channel'
                ),
                priority='high'
            ),
            # Enhanced iOS configuration
            apns=messaging.APNSConfig(
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(
                        alert=messaging.ApsAlert(
                            title='📋 New Task Assigned!',
                            body=f'{caption} at {location}'
                        ),
                        badge=1,
                        sound='default'
                    )
                )
            )
        )
        
        response = messaging.send(message)
        print(f'✅ Notification sent to {staff_id}: {response}')
        
    except Exception as e:
        print(f"❌ Error sending notification to {staff_id}: {e}")


@app.route('/uploads/<filename>')
def serve_uploaded_file(filename):
    """Serve uploaded files from the uploads directory with mobile compatibility."""
    try:
        file_path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
        
        if not os.path.exists(file_path):
            return jsonify({'error': 'File not found'}), 404
        
        response = make_response(send_from_directory(app.config['UPLOAD_FOLDER'], filename))
        
        # Set headers for mobile compatibility
        response.headers['Content-Type'] = _get_content_type(filename)
        response.headers['Cache-Control'] = 'public, max-age=3600'
        response.headers['Access-Control-Allow-Origin'] = '*'
        response.headers['Access-Control-Allow-Methods'] = 'GET, OPTIONS'
        response.headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization'
        
        print(f"✅ Serving uploaded file: {filename} with content-type: {response.headers['Content-Type']}")
        return response
        
    except Exception as e:
        print(f"❌ Error serving uploaded file {filename}: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/processed/<filename>')
def serve_processed_file(filename):
    """Serve processed files from the processed directory with mobile compatibility."""
    try:
        file_path = os.path.join(app.config['PROCESSED_FOLDER'], filename)
        
        if not os.path.exists(file_path):
            return jsonify({'error': 'File not found'}), 404
        
        response = make_response(send_from_directory(app.config['PROCESSED_FOLDER'], filename))
        
        # Set headers for mobile compatibility
        response.headers['Content-Type'] = _get_content_type(filename)
        response.headers['Cache-Control'] = 'public, max-age=3600'
        response.headers['Access-Control-Allow-Origin'] = '*'
        response.headers['Access-Control-Allow-Methods'] = 'GET, OPTIONS'
        response.headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization'
        
        print(f"✅ Serving processed file: {filename} with content-type: {response.headers['Content-Type']}")
        return response
        
    except Exception as e:
        print(f"❌ Error serving processed file {filename}: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/completed/<filename>')
def serve_completed_file(filename):
    """Serve completed files from the completed directory with mobile compatibility."""
    try:
        file_path = os.path.join(app.config['COMPLETED_FOLDER'], filename)
        
        if not os.path.exists(file_path):
            return jsonify({'error': 'File not found'}), 404
        
        response = make_response(send_from_directory(app.config['COMPLETED_FOLDER'], filename))
        
        # Set headers for mobile compatibility
        response.headers['Content-Type'] = _get_content_type(filename)
        response.headers['Cache-Control'] = 'public, max-age=3600'
        response.headers['Access-Control-Allow-Origin'] = '*'
        response.headers['Access-Control-Allow-Methods'] = 'GET, OPTIONS'
        response.headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization'
        
        print(f"✅ Serving completed file: {filename} with content-type: {response.headers['Content-Type']}")
        return response
        
    except Exception as e:
        print(f"❌ Error serving completed file {filename}: {e}")
        return jsonify({'error': str(e)}), 500

def _get_content_type(filename):
    """Determine content type for image files."""
    import mimetypes
    content_type, _ = mimetypes.guess_type(filename)
    
    if content_type is None:
        # Default content types for common image formats
        if filename.lower().endswith(('.jpg', '.jpeg')):
            content_type = 'image/jpeg'
        elif filename.lower().endswith('.png'):
            content_type = 'image/png'
        elif filename.lower().endswith('.gif'):
            content_type = 'image/gif'
        elif filename.lower().endswith('.webp'):
            content_type = 'image/webp'
        else:
            content_type = 'application/octet-stream'
    
    return content_type

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({
        'status': 'healthy',
        'message': 'Garden App Server is running',
        'timestamp': datetime.now().isoformat(),
        'server_url': SERVER_BASE_URL
    }), 200

# ============================================================================
# ADMIN PANEL ROUTES - Serve admin panel files
# ============================================================================

@app.route('/admin_panel_enhanced.html')
def serve_admin_panel():
    """Serve the enhanced admin panel HTML file"""
    try:
        # Get the directory where app.py is located
        current_dir = os.path.dirname(os.path.abspath(__file__))
        return send_from_directory(current_dir, 'admin_panel_enhanced.html')
    except Exception as e:
        print(f"Error serving admin panel: {e}")
        return jsonify({'error': 'Admin panel not found'}), 404

@app.route('/admin_styles.css')
def serve_admin_styles():
    """Serve the admin panel CSS file"""
    try:
        current_dir = os.path.dirname(os.path.abspath(__file__))
        return send_from_directory(current_dir, 'admin_styles.css')
    except Exception as e:
        print(f"Error serving admin styles: {e}")
        return jsonify({'error': 'Admin styles not found'}), 404

@app.route('/admin_script.js')
def serve_admin_script():
    """Serve the admin panel JavaScript file"""
    try:
        current_dir = os.path.dirname(os.path.abspath(__file__))
        response = send_from_directory(current_dir, 'admin_script.js')
        # Disable caching for JavaScript to ensure latest version loads
        response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
        response.headers['Pragma'] = 'no-cache'
        response.headers['Expires'] = '0'
        return response
    except Exception as e:
        print(f"Error serving admin script: {e}")
        return jsonify({'error': 'Admin script not found'}), 404

@app.route('/admin')
@app.route('/admin/')
def redirect_to_admin():
    """Redirect /admin to admin panel"""
    from flask import redirect
    return redirect('/admin_panel_enhanced.html')

@app.route('/')
def redirect_to_admin_panel():
    """Redirect root to admin panel"""
    from flask import redirect
    return redirect('/admin_panel_enhanced.html')

# ============================================================================
# ADMIN API ENDPOINTS - Required by admin panel
# ============================================================================

@app.route('/staff/workload', methods=['GET'])
def get_staff_workload():
    """Get workload for all staff members"""
    try:
        db = firestore.client()
        staff_docs = db.collection('staff').stream()
        
        workload = []
        total_staff = 0
        active_staff = 0
        
        # Get ALL tasks first to calculate totals
        all_tasks_in_db = list(db.collection('tasks').stream())
        total_tasks_count = len(all_tasks_in_db)
        total_pending_count = len([t for t in all_tasks_in_db if t.to_dict().get('status') == 'pending'])
        total_completed_count = len([t for t in all_tasks_in_db if t.to_dict().get('status') == 'completed'])
        
        for staff_doc in staff_docs:
            total_staff += 1
            staff_data = staff_doc.to_dict()
            staff_id = staff_doc.id
            
            # Check if staff is active
            is_active = staff_data.get('active', True)
            if is_active:
                active_staff += 1
            
            # Count tasks for this staff member
            staff_tasks = [t for t in all_tasks_in_db if t.to_dict().get('assignedTo') == staff_id]
            pending_tasks = len([t for t in staff_tasks if t.to_dict().get('status') == 'pending'])
            completed_tasks = len([t for t in staff_tasks if t.to_dict().get('status') == 'completed'])
            
            workload.append({
                'staffId': staff_id,
                'name': staff_data.get('name', staff_id),
                'totalTasks': len(staff_tasks),
                'pendingTasks': pending_tasks,
                'completedTasks': completed_tasks,
                'active': is_active,
                'hasToken': bool(staff_data.get('fcmToken'))
            })
        
        response_data = {
            'workload': workload,
            'totalStaff': total_staff,
            'activeStaff': active_staff,
            'totalTasksInSystem': total_tasks_count,
            'totalPendingInSystem': total_pending_count,
            'totalCompletedInSystem': total_completed_count
        }
        
        # Debug logging
        print(f"📊 Staff Workload Response:")
        print(f"   Total Staff: {total_staff}")
        print(f"   Total Tasks in System: {total_tasks_count}")
        print(f"   Pending in System: {total_pending_count}")
        print(f"   Completed in System: {total_completed_count}")
        
        return jsonify(response_data), 200
        
    except Exception as e:
        print(f"Error getting staff workload: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/queue/status', methods=['GET'])
def get_queue_status():
    """Get status of task queue"""
    try:
        db = firestore.client()
        
        # Get tasks without assigned staff (queued)
        all_tasks = list(db.collection('tasks').stream())
        queued_tasks = [t for t in all_tasks if not t.to_dict().get('assignedTo') or t.to_dict().get('status') == 'queued']
        
        queue_data = []
        for task_doc in queued_tasks:
            task_data = task_doc.to_dict()
            created_at = task_data.get('createdAt')
            
            # Calculate wait time
            wait_time = 0
            if created_at:
                if hasattr(created_at, 'timestamp'):
                    wait_time = (datetime.now().timestamp() - created_at.timestamp()) / 60
            
            queue_data.append({
                'taskId': task_doc.id,
                'studentName': task_data.get('studentName', 'Unknown'),
                'aiCaption': task_data.get('aiCaption', 'No caption'),
                'location': task_data.get('location', 'Unknown'),
                'createdAt': created_at.isoformat() if hasattr(created_at, 'isoformat') else str(created_at),
                'waitTime': wait_time,
                'mediaType': 'video' if 'video' in task_data.get('imageUrl', '').lower() else 'image'
            })
        
        avg_wait = sum(t['waitTime'] for t in queue_data) / len(queue_data) if queue_data else 0
        max_wait = max((t['waitTime'] for t in queue_data), default=0)
        
        return jsonify({
            'queueLength': len(queue_data),
            'queuedTasks': queue_data,
            'averageWaitTime': avg_wait,
            'oldestTaskWaitTime': max_wait
        }), 200
        
    except Exception as e:
        print(f"Error getting queue status: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/admin/all_tasks', methods=['GET'])
def get_all_tasks_admin():
    """Get all tasks for admin panel"""
    try:
        db = firestore.client()
        tasks_docs = db.collection('tasks').stream()
        
        tasks = []
        for doc in tasks_docs:
            task_data = doc.to_dict()
            task_data['taskId'] = doc.id
            
            # Format timestamps
            if 'createdAt' in task_data and task_data['createdAt']:
                if hasattr(task_data['createdAt'], 'isoformat'):
                    task_data['createdAt'] = task_data['createdAt'].isoformat()
            
            tasks.append(task_data)
        
        return jsonify({'tasks': tasks, 'total': len(tasks)}), 200
        
    except Exception as e:
        print(f"Error getting all tasks: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/admin/recent_activity', methods=['GET'])
def get_recent_activity_admin():
    """Get recent activity for admin dashboard"""
    try:
        db = firestore.client()
        
        # Get recent tasks
        tasks_query = db.collection('tasks').order_by('createdAt', direction=firestore.Query.DESCENDING).limit(20)
        tasks = list(tasks_query.stream())
        
        activities = []
        for doc in tasks:
            task_data = doc.to_dict()
            created_at = task_data.get('createdAt')
            
            if created_at:
                activities.append({
                    'type': 'Task Created',
                    'description': f"{task_data.get('studentName', 'Unknown')} reported: {task_data.get('aiCaption', 'Issue')}",
                    'timestamp': created_at.isoformat() if hasattr(created_at, 'isoformat') else str(created_at),
                    'icon': '📋'
                })
        
        return jsonify({'activities': activities}), 200
        
    except Exception as e:
        print(f"Error getting recent activity: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/admin/all_students', methods=['GET'])
def get_all_students_admin():
    """Get all students for admin panel"""
    try:
        db = firestore.client()
        
        # Get all tasks to find unique students
        all_tasks = list(db.collection('tasks').stream())
        
        # Group tasks by student
        students_map = {}
        for task_doc in all_tasks:
            task_data = task_doc.to_dict()
            register_number = task_data.get('registerNumber')
            student_name = task_data.get('studentName')
            
            if register_number:
                if register_number not in students_map:
                    students_map[register_number] = {
                        'registerNumber': register_number,
                        'name': student_name or 'Unknown',
                        'totalReports': 0,
                        'lastActive': None
                    }
                
                students_map[register_number]['totalReports'] += 1
                
                # Update last active time
                created_at = task_data.get('createdAt')
                if created_at:
                    if not students_map[register_number]['lastActive'] or created_at > students_map[register_number]['lastActive']:
                        students_map[register_number]['lastActive'] = created_at
        
        # Convert to list
        students = list(students_map.values())
        
        # Format timestamps
        for student in students:
            if student['lastActive']:
                if hasattr(student['lastActive'], 'isoformat'):
                    student['lastActive'] = student['lastActive'].isoformat()
        
        # Debug logging
        print(f"📊 Students Response:")
        print(f"   Total Students: {len(students)}")
        print(f"   Students: {[s['name'] for s in students[:5]]}")  # Show first 5 names
        
        return jsonify({'students': students, 'total': len(students)}), 200
        
    except Exception as e:
        print(f"Error getting students: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/admin/all_staff', methods=['GET'])
def get_all_staff_admin():
    """Get all staff members with their task counts"""
    try:
        db = firestore.client()
        
        # Get all staff
        staff_docs = db.collection('staff').stream()
        staff_list = []
        
        for staff_doc in staff_docs:
            staff_data = staff_doc.to_dict()
            staff_id = staff_doc.id
            
            # Count tasks for this staff member
            all_tasks = db.collection('tasks').where('assignedTo', '==', staff_id).stream()
            tasks = list(all_tasks)
            
            pending_count = len([t for t in tasks if t.to_dict().get('status') == 'pending'])
            completed_count = len([t for t in tasks if t.to_dict().get('status') == 'completed'])
            total_count = len(tasks)
            
            staff_info = {
                'staffId': staff_id,
                'name': staff_data.get('name', 'Unknown'),
                'active': staff_data.get('active', True),
                'createdAt': staff_data.get('createdAt').isoformat() if staff_data.get('createdAt') else None,
                'lastLogin': staff_data.get('lastLogin').isoformat() if staff_data.get('lastLogin') else None,
                'taskCounts': {
                    'total': total_count,
                    'pending': pending_count,
                    'completed': completed_count
                }
            }
            
            staff_list.append(staff_info)
        
        # Sort by name
        staff_list.sort(key=lambda x: x['name'])
        
        return jsonify({'staff': staff_list, 'total': len(staff_list)}), 200
        
    except Exception as e:
        print(f"Error getting staff: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/admin/staff/<staff_id>/tasks', methods=['GET'])
def get_staff_tasks_admin(staff_id):
    """Get all tasks for a specific staff member"""
    try:
        db = firestore.client()
        
        # Get staff info
        staff_doc = db.collection('staff').document(staff_id).get()
        if not staff_doc.exists:
            return jsonify({'error': 'Staff member not found'}), 404
        
        staff_data = staff_doc.to_dict()
        
        # Get filter parameter (default to 'pending')
        status_filter = request.args.get('status', 'pending')
        
        # Get tasks for this staff member
        tasks_query = db.collection('tasks').where('assignedTo', '==', staff_id)
        
        if status_filter and status_filter != 'all':
            tasks_query = tasks_query.where('status', '==', status_filter)
        
        tasks_docs = tasks_query.order_by('createdAt', direction=firestore.Query.DESCENDING).stream()
        
        tasks = []
        for doc in tasks_docs:
            task_data = doc.to_dict()
            
            # Format timestamp
            created_at = task_data.get('createdAt')
            if created_at:
                task_data['timestamp'] = created_at.isoformat() if hasattr(created_at, 'isoformat') else str(created_at)
            
            task_info = {
                'id': doc.id,
                'taskId': task_data.get('taskId', doc.id),
                'studentName': task_data.get('studentName', 'Unknown'),
                'registerNumber': task_data.get('registerNumber', 'Unknown'),
                'studentCaption': task_data.get('studentCaption', ''),
                'aiCaption': task_data.get('aiCaption', ''),
                'imageUrl': task_data.get('imageUrl', ''),
                'completionImageUrl': task_data.get('completionImageUrl', ''),
                'location': task_data.get('location', 'Unknown'),
                'status': task_data.get('status', 'pending'),
                'assignedTo': task_data.get('assignedTo', ''),
                'createdAt': task_data.get('timestamp', ''),
                'completedAt': task_data.get('completedAt').isoformat() if task_data.get('completedAt') else None,
                'gpsData': task_data.get('gpsData')
            }
            
            tasks.append(task_info)
        
        return jsonify({
            'staff': {
                'staffId': staff_id,
                'name': staff_data.get('name', 'Unknown'),
                'active': staff_data.get('active', True)
            },
            'tasks': tasks,
            'total': len(tasks),
            'filter': status_filter
        }), 200
        
    except Exception as e:
        print(f"Error getting staff tasks: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({'error': str(e)}), 500

@app.route('/admin/media_gallery', methods=['GET'])
def get_media_gallery_admin():
    """Get all media files"""
    try:
        media_files = []
        
        folders = [
            ('uploads', UPLOAD_FOLDER),
            ('processed', PROCESSED_FOLDER),
            ('completed', COMPLETED_FOLDER)
        ]
        
        for folder_name, folder_path in folders:
            if os.path.exists(folder_path):
                for filename in os.listdir(folder_path):
                    file_path = os.path.join(folder_path, filename)
                    if os.path.isfile(file_path):
                        file_size = os.path.getsize(file_path)
                        file_ext = filename.rsplit('.', 1)[1].lower() if '.' in filename else ''
                        
                        media_type = 'video' if file_ext in ['mp4', 'mov', 'avi', 'mkv'] else 'image'
                        
                        media_files.append({
                            'filename': filename,
                            'folder': folder_name,
                            'url': f"{SERVER_BASE_URL}/{folder_name}/{filename}",
                            'size': file_size,
                            'type': media_type,
                            'modified': datetime.fromtimestamp(os.path.getmtime(file_path)).isoformat()
                        })
        
        return jsonify({'media': media_files, 'total': len(media_files)}), 200
        
    except Exception as e:
        print(f"Error getting media gallery: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/admin/analytics', methods=['GET'])
def get_analytics_admin():
    """Get analytics data"""
    try:
        db = firestore.client()
        all_tasks = list(db.collection('tasks').stream())
        
        total_tasks = len(all_tasks)
        completed_tasks = len([t for t in all_tasks if t.to_dict().get('status') == 'completed'])
        pending_tasks = len([t for t in all_tasks if t.to_dict().get('status') == 'pending'])
        
        completion_rate = (completed_tasks / total_tasks * 100) if total_tasks > 0 else 0
        
        return jsonify({
            'totalTasks': total_tasks,
            'completedTasks': completed_tasks,
            'pendingTasks': pending_tasks,
            'completionRate': round(completion_rate, 2),
            'avgResponseTime': 0,
            'activeUsers': 0
        }), 200
        
    except Exception as e:
        print(f"Error getting analytics: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/admin/generate_report', methods=['GET'])
def generate_report():
    """Generate PDF report"""
    try:
        # Check if reportlab is available
        try:
            from reportlab.lib.pagesizes import letter
            from reportlab.pdfgen import canvas
        except ImportError:
            return jsonify({'error': 'PDF generation library not installed. Run: pip install reportlab'}), 500
        
        range_param = request.args.get('range', 'all')
        
        # Get analytics data
        db = firestore.client()
        all_tasks = list(db.collection('tasks').stream())
        
        total_tasks = len(all_tasks)
        completed_tasks = len([t for t in all_tasks if t.to_dict().get('status') == 'completed'])
        pending_tasks = len([t for t in all_tasks if t.to_dict().get('status') == 'pending'])
        completion_rate = (completed_tasks / total_tasks * 100) if total_tasks > 0 else 0
        
        # Get student and staff counts
        students = list(db.collection('students').stream())
        staff = list(db.collection('staff').stream())
        
        # Create PDF
        buffer = io.BytesIO()
        p = canvas.Canvas(buffer, pagesize=letter)
        width, height = letter
        
        # Title
        p.setFont("Helvetica-Bold", 24)
        p.drawString(100, height - 100, "Garden App - Analytics Report")
        
        # Date
        p.setFont("Helvetica", 12)
        p.drawString(100, height - 130, f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        p.drawString(100, height - 150, f"Period: {range_param.title()}")
        
        # Metrics
        y_position = height - 200
        p.setFont("Helvetica-Bold", 14)
        p.drawString(100, y_position, "Key Metrics:")
        
        y_position -= 30
        p.setFont("Helvetica", 12)
        metrics = [
            f"Total Tasks: {total_tasks}",
            f"Completed Tasks: {completed_tasks}",
            f"Pending Tasks: {pending_tasks}",
            f"Completion Rate: {round(completion_rate, 2)}%",
            f"Total Students: {len(students)}",
            f"Total Staff: {len(staff)}",
            f"Active Users: {len(students) + len(staff)}"
        ]
        
        for metric in metrics:
            p.drawString(120, y_position, metric)
            y_position -= 25
        
        # Add task breakdown by status
        y_position -= 20
        p.setFont("Helvetica-Bold", 14)
        p.drawString(100, y_position, "Task Status Breakdown:")
        
        y_position -= 30
        p.setFont("Helvetica", 12)
        status_counts = {}
        for task in all_tasks:
            status = task.to_dict().get('status', 'unknown')
            status_counts[status] = status_counts.get(status, 0) + 1
        
        for status, count in status_counts.items():
            p.drawString(120, y_position, f"{status.title()}: {count}")
            y_position -= 20
        
        p.showPage()
        p.save()
        
        buffer.seek(0)
        return send_file(
            buffer, 
            mimetype='application/pdf', 
            as_attachment=True, 
            download_name=f'garden_report_{range_param}_{datetime.now().strftime("%Y%m%d_%H%M%S")}.pdf'
        )
        
    except Exception as e:
        print(f"Error generating report: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({'error': str(e)}), 500

@app.route('/staff/create', methods=['POST'])
def create_staff():
    """Create a new staff member (Admin only)"""
    try:
        data = request.get_json()
        staff_id = data.get('staffId')
        name = data.get('name')
        password = data.get('password', 'admin123')  # Default password if not provided
        
        if not staff_id or not name:
            return jsonify({'error': 'staffId and name are required'}), 400
        
        db = firestore.client()
        
        # Check if this ID is already registered as student
        student_doc = db.collection('students').document(staff_id).get()
        if student_doc.exists:
            return jsonify({'error': 'This ID is already registered as a student'}), 400
        
        # Check if staff already exists
        staff_ref = db.collection('staff').document(staff_id)
        if staff_ref.get().exists:
            return jsonify({'error': 'Staff member already exists'}), 400
        
        # Create staff with password
        staff_ref.set({
            'name': name,
            'password': password,
            'active': True,
            'createdAt': firestore.SERVER_TIMESTAMP
        })
        
        return jsonify({
            'message': 'Staff created successfully',
            'staffId': staff_id,
            'defaultPassword': password
        }), 200
        
    except Exception as e:
        print(f"Error creating staff: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/staff/activate/<staff_id>', methods=['POST'])
def activate_staff(staff_id):
    """Activate or deactivate a staff member"""
    try:
        data = request.get_json()
        active = data.get('active', True)
        
        db = firestore.client()
        staff_ref = db.collection('staff').document(staff_id)
        
        if not staff_ref.get().exists:
            return jsonify({'error': 'Staff not found'}), 404
        
        staff_ref.update({'active': active})
        
        return jsonify({'message': 'Staff status updated', 'active': active}), 200
        
    except Exception as e:
        print(f"Error updating staff status: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/queue/process', methods=['POST'])
def process_queue():
    """Process queued tasks and assign to staff"""
    try:
        db = firestore.client()
        
        # Get queued tasks
        all_tasks = list(db.collection('tasks').stream())
        queued_tasks = [t for t in all_tasks if not t.to_dict().get('assignedTo')]
        
        tasks_assigned = 0
        
        for task_doc in queued_tasks:
            # Assign to staff using round-robin
            assigned_staff = assign_task_to_staff(db)
            
            db.collection('tasks').document(task_doc.id).update({
                'assignedTo': assigned_staff,
                'status': 'pending'
            })
            
            tasks_assigned += 1
        
        return jsonify({'message': f'Assigned {tasks_assigned} tasks', 'tasksAssigned': tasks_assigned}), 200
        
    except Exception as e:
        print(f"Error processing queue: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/queue/clear', methods=['POST'])
def clear_queue():
    """Clear all queued tasks"""
    try:
        db = firestore.client()
        
        # Get queued tasks
        all_tasks = list(db.collection('tasks').stream())
        queued_tasks = [t for t in all_tasks if not t.to_dict().get('assignedTo')]
        
        tasks_cleared = 0
        
        for task_doc in queued_tasks:
            db.collection('tasks').document(task_doc.id).delete()
            tasks_cleared += 1
        
        return jsonify({'message': f'Cleared {tasks_cleared} tasks', 'tasksCleared': tasks_cleared}), 200
        
    except Exception as e:
        print(f"Error clearing queue: {e}")
        return jsonify({'error': str(e)}), 500

# ============================================
# ADMIN TASK REASSIGNMENT FEATURE
# ============================================

@app.route('/admin/reassign_task', methods=['POST'])
def reassign_task_admin():
    """Admin can manually reassign a task to a different staff member"""
    try:
        data = request.json
        task_id = data.get('taskId')
        new_staff_id = data.get('staffId')
        
        if not task_id or not new_staff_id:
            return jsonify({'error': 'taskId and staffId are required'}), 400
        
        db = firestore.client()
        
        # Verify task exists
        task_ref = db.collection('tasks').document(task_id)
        task_doc = task_ref.get()
        
        if not task_doc.exists:
            return jsonify({'error': 'Task not found'}), 404
        
        task_data = task_doc.to_dict()
        old_staff_id = task_data.get('assignedTo', 'unassigned')
        
        # Verify new staff exists
        staff_doc = db.collection('staff').document(new_staff_id).get()
        if not staff_doc.exists:
            return jsonify({'error': f'Staff member {new_staff_id} not found'}), 404
        
        staff_data = staff_doc.to_dict()
        
        # Update task assignment
        task_ref.update({
            'assignedTo': new_staff_id,
            'reassignedAt': firestore.SERVER_TIMESTAMP,
            'reassignedFrom': old_staff_id,
            'reassignedBy': 'admin'
        })
        
        print(f"📋 Task {task_id} reassigned from {old_staff_id} to {new_staff_id} by admin")
        
        # Send notification to new staff member
        caption = task_data.get('aiCaption', task_data.get('studentCaption', 'New task assigned'))
        location = task_data.get('location', 'Unknown location')
        send_notification_to_assigned_staff(new_staff_id, caption, location, task_id)
        
        return jsonify({
            'success': True,
            'message': f'Task reassigned to {staff_data.get("name", new_staff_id)}',
            'taskId': task_id,
            'oldStaffId': old_staff_id,
            'newStaffId': new_staff_id,
            'newStaffName': staff_data.get('name', new_staff_id)
        }), 200
        
    except Exception as e:
        print(f"❌ Error reassigning task: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/admin/bulk_reassign', methods=['POST'])
def bulk_reassign_tasks_admin():
    """Admin can reassign multiple tasks at once"""
    try:
        data = request.json
        task_ids = data.get('taskIds', [])
        new_staff_id = data.get('staffId')
        
        if not task_ids or not new_staff_id:
            return jsonify({'error': 'taskIds array and staffId are required'}), 400
        
        db = firestore.client()
        
        # Verify staff exists
        staff_doc = db.collection('staff').document(new_staff_id).get()
        if not staff_doc.exists:
            return jsonify({'error': f'Staff member {new_staff_id} not found'}), 404
        
        staff_data = staff_doc.to_dict()
        
        success_count = 0
        failed_tasks = []
        
        for task_id in task_ids:
            try:
                task_ref = db.collection('tasks').document(task_id)
                task_doc = task_ref.get()
                
                if task_doc.exists:
                    old_staff = task_doc.to_dict().get('assignedTo', 'unassigned')
                    task_ref.update({
                        'assignedTo': new_staff_id,
                        'reassignedAt': firestore.SERVER_TIMESTAMP,
                        'reassignedFrom': old_staff,
                        'reassignedBy': 'admin'
                    })
                    success_count += 1
                else:
                    failed_tasks.append({'taskId': task_id, 'reason': 'Task not found'})
            except Exception as task_error:
                failed_tasks.append({'taskId': task_id, 'reason': str(task_error)})
        
        print(f"📋 Bulk reassign: {success_count} tasks reassigned to {new_staff_id}")
        
        return jsonify({
            'success': True,
            'message': f'{success_count} tasks reassigned to {staff_data.get("name", new_staff_id)}',
            'successCount': success_count,
            'failedCount': len(failed_tasks),
            'failedTasks': failed_tasks
        }), 200
        
    except Exception as e:
        print(f"❌ Error in bulk reassign: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/admin/unassigned_tasks', methods=['GET'])
def get_unassigned_tasks_admin():
    """Get all tasks that are unassigned or assigned to non-existent staff"""
    try:
        db = firestore.client()
        
        # Get all tasks
        all_tasks = list(db.collection('tasks').stream())
        
        # Get all valid staff IDs
        staff_docs = list(db.collection('staff').stream())
        valid_staff_ids = [doc.id for doc in staff_docs]
        
        unassigned_tasks = []
        
        for task_doc in all_tasks:
            task_data = task_doc.to_dict()
            assigned_to = task_data.get('assignedTo')
            
            # Task is unassigned if:
            # 1. No assignedTo field
            # 2. assignedTo is empty
            # 3. assignedTo is a staff that doesn't exist
            is_unassigned = (
                not assigned_to or 
                assigned_to == '' or 
                assigned_to not in valid_staff_ids
            )
            
            if is_unassigned and task_data.get('status') != 'completed':
                created_at = task_data.get('createdAt')
                unassigned_tasks.append({
                    'taskId': task_doc.id,
                    'studentName': task_data.get('studentName', 'Unknown'),
                    'registerNumber': task_data.get('registerNumber', 'Unknown'),
                    'aiCaption': task_data.get('aiCaption', ''),
                    'studentCaption': task_data.get('studentCaption', ''),
                    'location': task_data.get('location', 'Unknown'),
                    'imageUrl': task_data.get('imageUrl', ''),
                    'status': task_data.get('status', 'pending'),
                    'assignedTo': assigned_to or 'unassigned',
                    'createdAt': created_at.isoformat() if hasattr(created_at, 'isoformat') else str(created_at),
                    'reason': 'No assignment' if not assigned_to else f'Staff {assigned_to} not found'
                })
        
        return jsonify({
            'unassignedTasks': unassigned_tasks,
            'total': len(unassigned_tasks),
            'validStaffIds': valid_staff_ids
        }), 200
        
    except Exception as e:
        print(f"❌ Error getting unassigned tasks: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/admin/send_notification', methods=['POST'])
def send_broadcast_notification_admin():
    """Send notification to users from admin panel"""
    try:
        data = request.json
        target = data.get('target')  # 'all_staff', 'all_students', 'specific'
        user_id = data.get('userId')
        title = data.get('title')
        body = data.get('body')
        
        if not title or not body:
            return jsonify({'error': 'Title and body are required'}), 400
        
        db = firestore.client()
        tokens = []
        
        if target == 'all_staff':
            staff_docs = db.collection('staff').stream()
            tokens = [doc.to_dict().get('fcmToken') for doc in staff_docs if doc.to_dict().get('fcmToken')]
        elif target == 'all_students':
            student_docs = db.collection('students').stream()
            tokens = [doc.to_dict().get('fcmToken') for doc in student_docs if doc.to_dict().get('fcmToken')]
        elif target == 'specific' and user_id:
            # Try both collections
            user_doc = db.collection('students').document(user_id).get()
            if not user_doc.exists:
                user_doc = db.collection('staff').document(user_id).get()
            if user_doc.exists:
                token = user_doc.to_dict().get('fcmToken')
                if token:
                    tokens = [token]
        
        if not tokens:
            return jsonify({'error': 'No valid tokens found'}), 400
        
        # Send notification to each token individually
        success_count = 0
        failure_count = 0
        
        for token in tokens:
            try:
                message = messaging.Message(
                    notification=messaging.Notification(
                        title=title,
                        body=body
                    ),
                    token=token,
                    data={
                        'type': 'admin_broadcast',
                        'timestamp': datetime.now().isoformat()
                    }
                )
                
                messaging.send(message)
                success_count += 1
                print(f"✅ Notification sent to token: {token[:20]}...")
                
            except Exception as send_error:
                failure_count += 1
                print(f"❌ Failed to send to token {token[:20]}...: {send_error}")
        
        return jsonify({
            'success': success_count,
            'failed': failure_count,
            'total': len(tokens),
            'message': f'Sent to {success_count} out of {len(tokens)} users'
        }), 200
        
    except Exception as e:
        print(f"Error sending notification: {e}")
        return jsonify({'error': str(e)}), 500

# ============================================================================
# AUTHENTICATION ENDPOINTS
# ============================================================================

@app.route('/auth/student/login', methods=['POST'])
def student_login():
    """Authenticate student login with cross-login prevention"""
    try:
        data = request.get_json()
        name = data.get('name', '').strip()
        register_number = data.get('registerNumber', '').strip()
        
        if not name or not register_number:
            return jsonify({'error': 'Name and register number are required'}), 400
        
        db = firestore.client()
        
        # Check if this ID is registered as staff
        staff_doc = db.collection('staff').document(register_number).get()
        if staff_doc.exists:
            return jsonify({
                'error': 'This ID is registered as staff. Please login through the Staff Portal.',
                'errorCode': 'CROSS_LOGIN_PREVENTED'
            }), 403
        
        # Check if student exists
        student_ref = db.collection('students').document(register_number)
        student_doc = student_ref.get()
        
        if student_doc.exists:
            # Existing student - update name if changed
            student_data = student_doc.to_dict()
            if student_data.get('name') != name:
                student_ref.update({
                    'name': name,
                    'lastLogin': firestore.SERVER_TIMESTAMP
                })
            else:
                student_ref.update({
                    'lastLogin': firestore.SERVER_TIMESTAMP
                })
            
            return jsonify({
                'success': True,
                'message': 'Login successful',
                'student': {
                    'name': name,
                    'registerNumber': register_number,
                    'isNewUser': False
                }
            }), 200
        else:
            # New student - create account
            student_ref.set({
                'name': name,
                'registerNumber': register_number,
                'createdAt': firestore.SERVER_TIMESTAMP,
                'lastLogin': firestore.SERVER_TIMESTAMP,
                'active': True
            })
            
            return jsonify({
                'success': True,
                'message': 'Account created successfully',
                'student': {
                    'name': name,
                    'registerNumber': register_number,
                    'isNewUser': True
                }
            }), 200
        
    except Exception as e:
        print(f"Error in student login: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/auth/staff/login', methods=['POST'])
def staff_login():
    """Authenticate staff login with restrictions"""
    try:
        data = request.get_json()
        staff_id = data.get('staffId', '').strip()
        password = data.get('password', '').strip()
        
        if not staff_id or not password:
            return jsonify({'error': 'Staff ID and password are required'}), 400
        
        db = firestore.client()
        
        # Check if this ID is registered as student
        student_doc = db.collection('students').document(staff_id).get()
        if student_doc.exists:
            return jsonify({
                'error': 'This ID is registered as a student. Please login through the Student Portal.',
                'errorCode': 'CROSS_LOGIN_PREVENTED'
            }), 403
        
        # Check if staff exists (must be created by admin)
        staff_ref = db.collection('staff').document(staff_id)
        staff_doc = staff_ref.get()
        
        if not staff_doc.exists:
            return jsonify({
                'error': 'Staff account not found. Please contact admin to create your account.',
                'errorCode': 'ACCOUNT_NOT_FOUND'
            }), 404
        
        staff_data = staff_doc.to_dict()
        
        # Check if account is active
        if not staff_data.get('active', True):
            return jsonify({
                'error': 'Your account has been deactivated. Please contact admin.',
                'errorCode': 'ACCOUNT_DEACTIVATED'
            }), 403
        
        # Verify password (simple check for now - in production use proper hashing)
        stored_password = staff_data.get('password', 'admin123')  # Default password
        if password != stored_password:
            return jsonify({
                'error': 'Invalid password',
                'errorCode': 'INVALID_PASSWORD'
            }), 401
        
        # Update last login
        staff_ref.update({
            'lastLogin': firestore.SERVER_TIMESTAMP
        })
        
        return jsonify({
            'success': True,
            'message': 'Login successful',
            'staff': {
                'staffId': staff_id,
                'name': staff_data.get('name', 'Staff User'),
                'active': staff_data.get('active', True)
            }
        }), 200
        
    except Exception as e:
        print(f"Error in staff login: {e}")
        return jsonify({'error': str(e)}), 500

# ============================================================================

@app.route('/update_fcm_token', methods=['POST'])
def update_fcm_token():
    """Update FCM token for a user (student or staff)"""
    try:
        data = request.get_json()
        token = data.get('token')
        user_type = data.get('userType')  # 'student' or 'staff'
        user_id = data.get('userId')
        
        if not all([token, user_type, user_id]):
            return jsonify({'error': 'Missing required fields'}), 400
        
        db = firestore.client()
        
        # Update token in appropriate collection
        if user_type == 'student':
            collection_name = 'students'
        elif user_type == 'staff':
            collection_name = 'staff'
        else:
            return jsonify({'error': 'Invalid user type'}), 400
        
        # Update the user's FCM token
        user_ref = db.collection(collection_name).document(user_id)
        user_ref.set({
            'fcmToken': token,
            'lastTokenUpdate': firestore.SERVER_TIMESTAMP,
            'tokenUpdatedAt': datetime.now().isoformat()
        }, merge=True)
        
        print(f"✅ FCM token updated for {user_type} {user_id}: {token[:20]}...")
        
        return jsonify({
            'message': f'FCM token updated successfully for {user_type}',
            'userId': user_id,
            'timestamp': datetime.now().isoformat()
        }), 200
        
    except Exception as e:
        print(f"❌ Error updating FCM token: {e}")
        return jsonify({
            'error': str(e),
            'message': 'Failed to update FCM token'
        }), 500

@app.route('/fcm_diagnostic', methods=['GET'])
def fcm_diagnostic():
    """Diagnostic endpoint to check FCM configuration"""
    try:
        # Check if Firebase is initialized
        firebase_initialized = len(firebase_admin._apps) > 0
        
        # Check if service account key exists
        service_key_exists = os.path.exists('serviceAccountKey.json')
        
        # Get Firebase project info if available
        project_id = None
        if firebase_initialized:
            try:
                app = firebase_admin.get_app()
                project_id = app.project_id
            except:
                project_id = "Unable to retrieve"
        
        return jsonify({
            'firebase_initialized': firebase_initialized,
            'service_key_exists': service_key_exists,
            'project_id': project_id,
            'timestamp': datetime.now().isoformat(),
            'message': 'FCM diagnostic complete'
        }), 200
        
    except Exception as e:
        return jsonify({
            'error': str(e),
            'message': 'FCM diagnostic failed',
            'timestamp': datetime.now().isoformat()
        }), 500

@app.route('/test_upload', methods=['POST'])
def test_upload():
    """Simple test endpoint to debug upload issues."""
    print("🧪 Test upload endpoint called")
    print(f"Request method: {request.method}")
    print(f"Request files: {list(request.files.keys())}")
    print(f"Request form: {dict(request.form)}")
    
    return jsonify({
        'status': 'test_success',
        'message': 'Test upload endpoint working',
        'received_files': list(request.files.keys()),
        'received_form': dict(request.form),
        'timestamp': datetime.now().isoformat()
    }), 200

@app.route('/history', methods=['GET'])
def get_history():
    """Get task history for a specific student with both original and completion images."""
    try:
        register_number = request.args.get('register_number')
        if not register_number:
            return jsonify({'error': 'register_number parameter is required'}), 400
        
        db = firestore.client()
        
        tasks_query = fs_filter(db.collection('tasks'), 'registerNumber', '==', register_number).order_by('createdAt', direction=firestore.Query.DESCENDING)
        tasks_docs = tasks_query.stream()
        
        history = []
        for doc in tasks_docs:
            task_data = doc.to_dict()
            created_at = task_data.get('createdAt')
            if created_at:
                task_data['timestamp'] = created_at.isoformat() if hasattr(created_at, 'isoformat') else str(created_at)
            
            history_item = {
                'id': doc.id,
                'type': 'image',
                'caption': task_data.get('aiCaption', ''),
                'user_caption': task_data.get('studentCaption', ''),
                'status': task_data.get('status', 'pending').title(),
                'timestamp': task_data.get('timestamp', datetime.now().isoformat()),
                'name': task_data.get('studentName', ''),
                'register_number': task_data.get('registerNumber', ''),
                'location': task_data.get('location', 'Unknown Location'),
                'imageUrl': task_data.get('imageUrl', ''),  # Original student image
                'completionImageUrl': task_data.get('completionImageUrl', ''),  # Staff completion image
                'assignedTo': task_data.get('assignedTo', ''),
                'ai_confidence': 0.85,
                # Add completion details
                'completedAt': task_data.get('completedAt'),
                'hasCompletionImage': bool(task_data.get('completionImageUrl'))
            }
            history.append(history_item)
        
        return jsonify(history), 200
        
    except Exception as e:
        print(f"Error fetching history: {e}")
        return jsonify({'error': f'Failed to fetch history: {str(e)}'}), 500

@app.route('/notifications', methods=['GET'])
def get_notifications():
    """Get notifications for students from staff."""
    try:
        register_number = request.args.get('register_number')
        if not register_number:
            return jsonify({'error': 'register_number parameter is required'}), 400
        
        db = firestore.client()
        notifications = []
        
        try:
            notifications_ref = db.collection('notifications').document(register_number).collection('user_notifications')
            notifications_docs = notifications_ref.order_by('timestamp', direction=firestore.Query.DESCENDING).limit(50).stream()
            
            for doc in notifications_docs:
                notification_data = doc.to_dict()
                
                # Filter out only old "Thank You" notifications, keep all others
                title = notification_data.get('title', '')
                message = notification_data.get('message', '')
                notification_type = notification_data.get('type', '')
                
                # Skip only old "Thank You" notifications
                if ('Thank You' in title and 
                    'Thank you for helping us maintain' in message):
                    continue
                
                # Include all other notifications (task_completed, test notifications, etc.)
                if True:  # Keep all non-filtered notifications
                    if 'timestamp' in notification_data and notification_data['timestamp']:
                        try:
                            timestamp = notification_data['timestamp']
                            if hasattr(timestamp, 'isoformat'):
                                notification_data['timestamp'] = timestamp.isoformat() + 'Z'
                            else:
                                notification_data['timestamp'] = datetime.now().isoformat() + 'Z'
                        except:
                            notification_data['timestamp'] = datetime.now().isoformat() + 'Z'
                    
                    # Debug: Log notification data being returned
                    if notification_data.get('type') == 'task_completed':
                        print(f'📤 DEBUG: Returning task_completed notification:')
                        print(f'   - imageUrl: {notification_data.get("imageUrl")}')
                        print(f'   - type: {notification_data.get("type")}')
                        print(f'   - title: {notification_data.get("title")}')
                    
                    notifications.append(notification_data)
        except Exception as db_error:
            print(f"Database error: {db_error}")
        
        # Don't add sample notifications - let it be empty if no real notifications exist
        # This prevents showing welcome messages that cause errors
        
        return jsonify(notifications), 200
        
    except Exception as e:
        print(f"Error fetching notifications: {e}")
        return jsonify({'error': f'Failed to fetch notifications: {str(e)}'}), 500

@app.route('/complete_task', methods=['POST'])
def complete_task():
    """Handles completion photo/video uploads from staff and updates task status."""
    if 'file' not in request.files: return jsonify({'error': 'No file part'}), 400
    
    task_id = request.form.get('taskId')
    if not task_id: return jsonify({'error': 'Task ID is required'}), 400
        
    file = request.files['file']
    if file.filename == '': return jsonify({'error': 'No selected file'}), 400

    if file and allowed_file(file.filename):
        # Check if file is a video
        is_video = is_video_file(file.filename)
        
        # Use appropriate extension
        if is_video:
            file_ext = file.filename.rsplit('.', 1)[1].lower()
            unique_filename = f"completed_{uuid.uuid4()}.{file_ext}"
        else:
            unique_filename = f"completed_{uuid.uuid4()}.jpg"
            
        filepath = os.path.join(app.config['COMPLETED_FOLDER'], unique_filename)
        file.save(filepath)
        
        completed_image_url = f"{SERVER_BASE_URL}/completed/{unique_filename}"

        db = firestore.client()
        task_ref = db.collection('tasks').document(task_id)
        task_doc = task_ref.get()
        
        if task_doc.exists:
            task_data = task_doc.to_dict()
            
            task_ref.update({
                'status': 'completed',
                'completedAt': firestore.SERVER_TIMESTAMP,
                'completionImageUrl': completed_image_url
            })
            
            register_number = task_data.get('registerNumber')
            ai_caption = task_data.get('aiCaption', 'Task completed')
            
            if register_number:
                staff_id = request.form.get('staffId', 'Garden Staff')
                # Send completion notification with photo
                send_completion_notification(register_number, completed_image_url, ai_caption, staff_id, task_id)
                print(f"✅ Task {task_id} marked as completed and student {register_number} notified")
                
                # Also send thank you notification
                try:
                    send_thank_you_notification_internal(register_number, task_id, staff_id)
                    print(f"✅ Thank you notification sent to student {register_number}")
                except Exception as thank_you_error:
                    print(f"⚠️ Error sending thank you notification: {thank_you_error}")
            else:
                print(f"⚠️ No register number found for task {task_id}")

        return jsonify({
            'message': 'Task completed successfully',
            'completedImageUrl': completed_image_url,
            'image_url': completed_image_url,  # Add for Flutter compatibility
            'imageUrl': completed_image_url,   # Add for Flutter compatibility
            'status': 'completed'
        })
    return jsonify({'error': 'Invalid file'}), 400

@app.route('/mark_completed', methods=['POST'])
def mark_task_completed():
    """Mark a task as completed without uploading a photo (for staff dashboard)."""
    try:
        data = request.get_json()
        task_id = data.get('taskId')
        
        if not task_id:
            return jsonify({'error': 'Task ID is required'}), 400
        
        db = firestore.client()
        task_ref = db.collection('tasks').document(task_id)
        task_doc = task_ref.get()
        
        if not task_doc.exists:
            return jsonify({'error': 'Task not found'}), 404
        
        task_data = task_doc.to_dict()
        
        task_ref.update({
            'status': 'completed',
            'completedAt': firestore.SERVER_TIMESTAMP
        })
        
        register_number = task_data.get('registerNumber')
        ai_caption = task_data.get('aiCaption', 'Your reported issue has been resolved')
        
        if register_number:
            staff_id = data.get('staffId', 'Garden Staff')
            send_completion_notification(register_number, '', ai_caption, staff_id, task_id)
            print(f"✅ Task {task_id} marked as completed and student {register_number} notified")
            
            # Also send thank you notification
            try:
                send_thank_you_notification_internal(register_number, task_id, staff_id)
                print(f"✅ Thank you notification sent to student {register_number}")
            except Exception as thank_you_error:
                print(f"⚠️ Error sending thank you notification: {thank_you_error}")
        
        return jsonify({
            'message': 'Task marked as completed successfully',
            'status': 'completed',
            'taskId': task_id
        }), 200
        
    except Exception as e:
        print(f"❌ Error marking task completed: {e}")
        return jsonify({'error': f'Failed to mark task completed: {str(e)}'}), 500

@app.route('/staff/tasks/<string:staff_id>', methods=['GET'])
def get_staff_tasks(staff_id):
    """Get all tasks assigned to a specific staff member with both original and completion images."""
    try:
        db = firestore.client()
        
        # Get query parameters for filtering
        status_filter = request.args.get('status')  # 'pending', 'completed', or None for all
        limit = request.args.get('limit', 50)
        
        # First, get ALL tasks for accurate statistics calculation
        all_tasks_query = fs_filter(db.collection('tasks'), 'assignedTo', '==', staff_id)
        all_tasks_docs = list(all_tasks_query.stream())
        
        # Calculate accurate statistics from ALL tasks
        total_tasks = len(all_tasks_docs)
        completed_tasks = len([doc for doc in all_tasks_docs if doc.to_dict().get('status') == 'completed'])
        pending_tasks = len([doc for doc in all_tasks_docs if doc.to_dict().get('status') == 'pending'])
        
        print(f"📊 Staff {staff_id} statistics: Total={total_tasks}, Completed={completed_tasks}, Pending={pending_tasks}")
        
        # Build the limited query for task details (avoid composite index requirement)
        # Get all tasks first, then sort and limit in Python to avoid Firestore index issues
        tasks_query = fs_filter(db.collection('tasks'), 'assignedTo', '==', staff_id)
        
        if status_filter:
            tasks_query = fs_filter(tasks_query, 'status', '==', status_filter)
        
        # Get all matching tasks and sort in Python to avoid index requirement
        all_matching_tasks = list(tasks_query.stream())
        
        # Sort by createdAt in Python (most recent first)
        all_matching_tasks.sort(key=lambda doc: doc.to_dict().get('createdAt', datetime.min), reverse=True)
        
        # Apply limit in Python
        tasks_docs = all_matching_tasks[:int(limit)]
        
        tasks = []
        for doc in tasks_docs:
            task_data = doc.to_dict()
            created_at = task_data.get('createdAt')
            completed_at = task_data.get('completedAt')
            
            # Format timestamps
            if created_at:
                task_data['createdAtFormatted'] = created_at.isoformat() if hasattr(created_at, 'isoformat') else str(created_at)
            if completed_at:
                task_data['completedAtFormatted'] = completed_at.isoformat() if hasattr(completed_at, 'isoformat') else str(completed_at)
            
            task_item = {
                'taskId': doc.id,
                'studentName': task_data.get('studentName', 'Unknown'),
                'registerNumber': task_data.get('registerNumber', 'Unknown'),
                'studentCaption': task_data.get('studentCaption', ''),
                'aiCaption': task_data.get('aiCaption', ''),
                'location': task_data.get('location', 'Unknown Location'),
                'status': task_data.get('status', 'pending'),
                'createdAt': task_data.get('createdAtFormatted', ''),
                'completedAt': task_data.get('completedAtFormatted', ''),
                # Both image URLs for complete workflow visibility
                'originalImageUrl': task_data.get('imageUrl', ''),  # Student's reported image
                'completionImageUrl': task_data.get('completionImageUrl', ''),  # Staff's completion image
                'hasOriginalImage': bool(task_data.get('imageUrl')),
                'hasCompletionImage': bool(task_data.get('completionImageUrl')),
                'gpsData': task_data.get('gpsData'),
                'assignedTo': task_data.get('assignedTo', staff_id)
            }
            tasks.append(task_item)
        
        return jsonify({
            'tasks': tasks,
            'staffId': staff_id,
            'totalTasks': total_tasks,  # Now using accurate count from ALL tasks
            'pendingTasks': pending_tasks,  # Now using accurate count from ALL tasks
            'completedTasks': completed_tasks,  # Now using accurate count from ALL tasks
            'lastUpdated': datetime.now().isoformat()
        }), 200
        
    except Exception as e:
        print(f"Error fetching tasks for staff {staff_id}: {e}")
        return jsonify({'error': f'Failed to fetch tasks: {str(e)}'}), 500

@app.route('/task/<string:task_id>', methods=['GET'])
def get_task_details(task_id):
    """Get detailed information about a specific task including all images."""
    try:
        db = firestore.client()
        task_doc = db.collection('tasks').document(task_id).get()
        
        if not task_doc.exists:
            return jsonify({'error': 'Task not found'}), 404
            
        task_data = task_doc.to_dict()
        
        # Format timestamps
        created_at = task_data.get('createdAt')
        completed_at = task_data.get('completedAt')
        
        if created_at:
            task_data['createdAtFormatted'] = created_at.isoformat() if hasattr(created_at, 'isoformat') else str(created_at)
        if completed_at:
            task_data['completedAtFormatted'] = completed_at.isoformat() if hasattr(completed_at, 'isoformat') else str(completed_at)
        
        task_details = {
            'taskId': task_id,
            'studentName': task_data.get('studentName', 'Unknown'),
            'registerNumber': task_data.get('registerNumber', 'Unknown'),
            'studentCaption': task_data.get('studentCaption', ''),
            'aiCaption': task_data.get('aiCaption', ''),
            'location': task_data.get('location', 'Unknown Location'),
            'status': task_data.get('status', 'pending'),
            'assignedTo': task_data.get('assignedTo', ''),
            'createdAt': task_data.get('createdAtFormatted', ''),
            'completedAt': task_data.get('completedAtFormatted', ''),
            # Complete image workflow
            'images': {
                'original': {
                    'url': task_data.get('imageUrl', ''),
                    'type': 'student_report',
                    'caption': task_data.get('aiCaption', 'Student reported issue')
                },
                'completion': {
                    'url': task_data.get('completionImageUrl', ''),
                    'type': 'staff_completion',
                    'caption': 'Task completion photo'
                }
            },
            'hasOriginalImage': bool(task_data.get('imageUrl')),
            'hasCompletionImage': bool(task_data.get('completionImageUrl')),
            'gpsData': task_data.get('gpsData'),
            'workflow': {
                'reported': bool(task_data.get('imageUrl')),
                'assigned': bool(task_data.get('assignedTo')),
                'completed': task_data.get('status') == 'completed',
                'hasCompletionPhoto': bool(task_data.get('completionImageUrl'))
            }
        }
        
        return jsonify(task_details), 200
        
    except Exception as e:
        print(f"Error fetching task details for {task_id}: {e}")
        return jsonify({'error': f'Failed to fetch task details: {str(e)}'}), 500

@app.route('/update_location', methods=['POST'])
def update_location():
    """Updates the location for a user (student or staff)."""
    data = request.get_json()
    user_id = data.get('userId')
    user_type = data.get('userType')
    latitude = data.get('latitude')
    longitude = data.get('longitude')

    if not all([user_id, user_type, latitude, longitude]):
        return jsonify({'error': 'Missing required location data'}), 400

    try:
        db = firestore.client()
        collection = 'students' if user_type == 'student' else 'staff'
        
        address = blip_processor.get_address_from_coords(latitude, longitude)

        location_data = {
            'latitude': latitude,
            'longitude': longitude,
            'address': address,
            'last_updated': firestore.SERVER_TIMESTAMP
        }

        db.collection(collection).document(user_id).set({'location': location_data}, merge=True)
        
        print(f"✅ Location updated for {user_type} {user_id}: {address}")
        return jsonify({'message': 'Location updated successfully', 'address': address}), 200
    except Exception as e:
        print(f"❌ Error updating location: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/test_notification', methods=['POST'])
def test_notification():
    """Test endpoint to send a notification to a student."""
    try:
        data = request.get_json()
        register_number = data.get('register_number')
        message = data.get('message', 'Test notification from server')
        
        if not register_number:
            return jsonify({'error': 'register_number is required'}), 400
        
        # Create test notification
        test_image_url = f"{SERVER_BASE_URL}/completed/test_image.jpg"
        
        # Send notification
        send_completion_notification(
            student_id=register_number,
            completed_image_url=test_image_url,
            caption=message,
            staff_id='Test Staff',
            task_id='test_task_123'
        )
        
        return jsonify({
            'message': 'Test notification sent successfully',
            'register_number': register_number,
            'test_image_url': test_image_url,
            'notification_type': 'task_completed',
            'timestamp': datetime.now().isoformat()
        }), 200
        
    except Exception as e:
        print(f"❌ Error sending test notification: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/test_student_notification', methods=['POST'])
def test_student_notification():
    """Test endpoint to send a notification to a student."""
    try:
        data = request.get_json()
        student_id = data.get('studentId')
        title = data.get('title', 'Test Notification')
        body = data.get('body', 'This is a test notification to verify your notifications are working!')
        
        if not student_id:
            return jsonify({'error': 'studentId is required'}), 400
        
        # For test notifications, don't include an image URL to avoid 404 errors
        # Instead, send a direct FCM notification without completion image
        db = firestore.client()
        try:
            student_ref = db.collection('students').document(student_id)
            student_doc = student_ref.get()
            if not student_doc.exists:
                return jsonify({'error': f'Student document for ID {student_id} not found'}), 404

            token = student_doc.to_dict().get('fcmToken')
            if not token:
                return jsonify({'error': f'FCM token not found for student {student_id}'}), 400

            # Send test notification without image
            message = messaging.Message(
                notification=messaging.Notification(
                    title=title,
                    body=body
                ),
                token=token,
                data={
                    'type': 'test_notification',
                    'studentId': student_id,
                    'timestamp': datetime.now().isoformat(),
                    'click_action': 'FLUTTER_NOTIFICATION_CLICK'
                },
                android=messaging.AndroidConfig(
                    notification=messaging.AndroidNotification(
                        icon='@drawable/notification_icon',
                        color='#2196F3',  # Blue color for test notifications
                        sound='default',
                        channel_id='test_notification_channel'
                    ),
                    priority='high'
                ),
                apns=messaging.APNSConfig(
                    payload=messaging.APNSPayload(
                        aps=messaging.Aps(
                            alert=messaging.ApsAlert(
                                title=title,
                                body=body
                            ),
                            badge=1,
                            sound='default'
                        )
                    )
                )
            )

            response = messaging.send(message)
            print(f'✅ Test notification sent to {student_id}: {response}')
            
            # Also save test notification to database without image
            notification_data = {
                'id': f'test_{student_id}_{datetime.now().microsecond}',
                'title': title,
                'message': body,
                'type': 'test_notification',
                'timestamp': firestore.SERVER_TIMESTAMP,
                'read': False,
                'sender': 'System Test'
            }
            db.collection('notifications').document(student_id).collection('user_notifications').add(notification_data)
            
        except Exception as e:
            print(f'❌ Error sending test notification: {e}')
            return jsonify({'error': str(e)}), 500
        
        return jsonify({
            'message': 'Test notification sent successfully',
            'studentId': student_id,
            'title': title,
            'body': body,
            'timestamp': datetime.now().isoformat()
        }), 200
        
    except Exception as e:
        print(f"❌ Error sending test student notification: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/trigger_token_refresh', methods=['POST'])
def trigger_token_refresh():
    """Endpoint to trigger FCM token refresh for a student"""
    try:
        data = request.get_json()
        student_id = data.get('studentId')
        reason = data.get('reason', 'manual_trigger')
        
        if not student_id:
            return jsonify({'error': 'studentId is required'}), 400
        
        print(f"🔄 Token refresh triggered for student {student_id}, reason: {reason}")
        
        # Store refresh request in database for the app to pick up
        db = firestore.client()
        refresh_request = {
            'studentId': student_id,
            'reason': reason,
            'timestamp': firestore.SERVER_TIMESTAMP,
            'status': 'pending'
        }
        
        db.collection('token_refresh_requests').add(refresh_request)
        print(f"✅ Token refresh request stored for student {student_id}")
        
        return jsonify({
            'message': 'Token refresh triggered successfully',
            'studentId': student_id,
            'reason': reason,
            'timestamp': datetime.now().isoformat()
        }), 200
        
    except Exception as e:
        print(f"❌ Error triggering token refresh: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/check_refresh_requests', methods=['GET'])
def check_refresh_requests():
    """Check if there are pending token refresh requests for a student"""
    try:
        student_id = request.args.get('studentId')
        if not student_id:
            return jsonify({'error': 'studentId parameter is required'}), 400
        
        db = firestore.client()
        
        # Check for pending refresh requests
        refresh_requests = db.collection('token_refresh_requests')\
            .where('studentId', '==', student_id)\
            .where('status', '==', 'pending')\
            .limit(1)\
            .stream()
        
        has_request = any(True for _ in refresh_requests)
        
        return jsonify({
            'hasRefreshRequest': has_request,
            'studentId': student_id,
            'timestamp': datetime.now().isoformat()
        }), 200
        
    except Exception as e:
        print(f"❌ Error checking refresh requests: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/complete_refresh_request', methods=['POST'])
def complete_refresh_request():
    """Mark token refresh request as completed"""
    try:
        data = request.get_json()
        student_id = data.get('studentId')
        
        if not student_id:
            return jsonify({'error': 'studentId is required'}), 400
        
        db = firestore.client()
        
        # Update pending refresh requests to completed
        refresh_requests = db.collection('token_refresh_requests')\
            .where('studentId', '==', student_id)\
            .where('status', '==', 'pending')\
            .stream()
        
        for request_doc in refresh_requests:
            request_doc.reference.update({
                'status': 'completed',
                'completedAt': firestore.SERVER_TIMESTAMP
            })
        
        print(f"✅ Token refresh requests marked as completed for student {student_id}")
        
        return jsonify({
            'message': 'Refresh requests marked as completed',
            'studentId': student_id,
            'timestamp': datetime.now().isoformat()
        }), 200
        
    except Exception as e:
        print(f"❌ Error completing refresh requests: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/test_task_completion', methods=['POST'])
def test_task_completion():
    """Test endpoint to simulate a task completion with image for testing student notifications."""
    try:
        data = request.get_json()
        student_id = data.get('studentId', '24MCA0018')
        staff_id = data.get('staffId', 'Test Staff')
        
        # Create a test completion image URL (using the test image we created)
        test_completion_image_url = f"{SERVER_BASE_URL}/processed/test_image.jpg"
        
        # Send completion notification with image
        send_completion_notification(
            student_id=student_id,
            completed_image_url=test_completion_image_url,
            caption='Test task has been completed successfully!',
            staff_id=staff_id,
            task_id=f'test_completion_{datetime.now().microsecond}'
        )
        
        return jsonify({
            'message': 'Test task completion notification sent successfully',
            'studentId': student_id,
            'staffId': staff_id,
            'completionImageUrl': test_completion_image_url,
            'timestamp': datetime.now().isoformat()
        }), 200
        
    except Exception as e:
        print(f"❌ Error sending test task completion: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/test_staff_notification', methods=['POST'])
def test_staff_notification():
    """Test endpoint to send a notification to staff."""
    try:
        data = request.get_json()
        staff_id = data.get('staff_id', 'staff1')
        caption = data.get('caption', 'Test task assignment')
        location = data.get('location', 'Test Location')
        
        # Send notification to staff
        send_notification_to_assigned_staff(
            staff_id=staff_id,
            caption=caption,
            location=location,
            task_id='test_staff_task_456'
        )
        
        return jsonify({
            'message': 'Test staff notification sent successfully',
            'staff_id': staff_id,
            'caption': caption,
            'location': location,
            'notification_type': 'new_task',
            'timestamp': datetime.now().isoformat()
        }), 200
        
    except Exception as e:
        print(f"❌ Error sending test staff notification: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/debug/staff/<string:staff_id>/stats', methods=['GET'])
def debug_staff_stats(staff_id):
    """Debug endpoint to check staff statistics."""
    try:
        db = firestore.client()
        
        # Get all tasks for this staff member
        tasks_query = fs_filter(db.collection('tasks'), 'assignedTo', '==', staff_id)
        tasks_docs = list(tasks_query.stream())
        
        tasks_data = []
        for doc in tasks_docs:
            task_data = doc.to_dict()
            tasks_data.append({
                'taskId': doc.id,
                'status': task_data.get('status', 'unknown'),
                'studentName': task_data.get('studentName', 'Unknown'),
                'createdAt': str(task_data.get('createdAt', 'Unknown')),
                'assignedTo': task_data.get('assignedTo', 'Unknown')
            })
        
        # Calculate stats
        total_tasks = len(tasks_data)
        completed_tasks = len([t for t in tasks_data if t['status'] == 'completed'])
        pending_tasks = len([t for t in tasks_data if t['status'] == 'pending'])
        
        return jsonify({
            'staff_id': staff_id,
            'total_tasks': total_tasks,
            'completed_tasks': completed_tasks,
            'pending_tasks': pending_tasks,
            'tasks_sample': tasks_data[:5],  # Show first 5 tasks as sample
            'debug_info': {
                'collection_exists': True,
                'query_successful': True,
                'timestamp': datetime.now().isoformat()
            }
        }), 200
        
    except Exception as e:
        print(f"❌ Error in debug staff stats: {e}")
        return jsonify({
            'error': str(e),
            'staff_id': staff_id,
            'debug_info': {
                'collection_exists': False,
                'query_successful': False,
                'timestamp': datetime.now().isoformat()
            }
        }), 500

@app.route('/send_thank_you_notification', methods=['POST'])
def send_thank_you_notification():
    """Sends a thank you notification to a student when staff completes their task."""
    try:
        data = request.get_json()
        student_id = data.get('studentId')
        task_id = data.get('taskId')
        staff_name = data.get('staffName', 'Garden Staff')

        if not student_id or not task_id:
            return jsonify({'error': 'Student ID and Task ID are required'}), 400

        db = firestore.client()
        
        student_doc = db.collection('students').document(student_id).get()
        if not student_doc.exists:
            return jsonify({'error': 'Student not found'}), 404
            
        student_data = student_doc.to_dict()
        fcm_token = student_data.get('fcmToken')
        
        if not fcm_token:
            return jsonify({'error': 'Student FCM token not found'}), 404

        message = messaging.Message(
            notification=messaging.Notification(
                title='Thank You for Your Report!',
                body=f'Thank you for helping us maintain our garden. Your report has been addressed by {staff_name}.'
            ),
            # FIX 2: Converted timestamp to string for the data payload
            data={
                'type': 'thank_you',
                'taskId': task_id,
                'timestamp': datetime.now().isoformat()
            },
            token=fcm_token
        )
        
        response = messaging.send(message)
        
        notification_ref = db.collection('notifications').document(student_id).collection('user_notifications')
        notification_ref.add({
            'title': 'Thank You for Your Report!',
            'message': f'Thank you for helping us maintain our garden. Your report has been addressed by {staff_name}.',
            'type': 'thank_you',
            'taskId': task_id,
            'timestamp': firestore.SERVER_TIMESTAMP,
            'read': False
        })
        
        print(f'✅ Thank you notification sent to student {student_id}: {response}')
        return jsonify({'message': 'Thank you notification sent successfully'}), 200
        
    except Exception as e:
        print(f"❌ Error sending thank you notification: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/staff/completed_tasks_count/<string:staff_id>', methods=['GET'])
def get_completed_tasks_count(staff_id):
    try:
        db = firestore.client()
        # Query Firestore for tasks assigned to the staff_id and marked as completed
        completed_tasks_ref = fs_filter(db.collection('tasks'), 'assignedTo', '==', staff_id).filter(FieldFilter('status', '==', 'completed')).stream()
        completed_tasks_count = len(list(completed_tasks_ref))
        return jsonify({'completed_tasks_count': completed_tasks_count}), 200
    except Exception as e:
        print(f"Error fetching completed tasks count for staff {staff_id}: {e}")
        return jsonify({'error': 'Failed to fetch completed tasks count'}), 500

@app.route('/student/<string:student_id>', methods=['GET'])
def get_student_details(student_id):
    try:
        db = firestore.client()
        student_ref = db.collection('students').document(student_id).get()
        if student_ref.exists:
            return jsonify(student_ref.to_dict()), 200
        else:
            return jsonify({'error': 'Student not found'}), 404
    except Exception as e:
        print(f"Error fetching student details for {student_id}: {e}")
        return jsonify({'error': 'Failed to fetch student details'}), 500

@app.route('/staff/<string:staff_id>', methods=['GET'])
def get_staff_details(staff_id):
    try:
        db = firestore.client()
        staff_ref = db.collection('staff').document(staff_id).get()
        if staff_ref.exists:
            return jsonify(staff_ref.to_dict()), 200
        else:
            return jsonify({'error': 'Staff not found'}), 404
    except Exception as e:
        print(f"Error fetching staff details for {staff_id}: {e}")
        return jsonify({'error': 'Failed to fetch staff details'}), 500

# Note: File serving routes are already defined above with proper headers and error handling
# Removed duplicate route definitions to prevent conflicts

if __name__ == '__main__':
    import subprocess
    import sys
    import time
    
    # Start admin_server.py as a subprocess
    admin_server_process = None
    try:
        print("="*60)
        print("🌱 Garden App - Main Server Starting")
        print("="*60)
        print(f"Main Server URL: {SERVER_BASE_URL}")
        print(f"Main Server Port: 5000")
        print("="*60)
        
        # Check if admin_server.py exists
        admin_server_path = os.path.join(os.path.dirname(__file__), 'admin_server.py')
        if os.path.exists(admin_server_path):
            print("\n🚀 Starting Admin Server on port 5001...")
            
            # Start admin_server.py in a separate process
            admin_server_process = subprocess.Popen(
                [sys.executable, admin_server_path],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )
            
            # Give it a moment to start
            time.sleep(2)
            
            # Check if it's still running
            if admin_server_process.poll() is None:
                print("✅ Admin Server started successfully on port 5001")
                print(f"📊 Admin Panel: {SERVER_BASE_URL}/admin_panel_enhanced.html")
            else:
                print("⚠️  Admin Server failed to start (check admin_server.py)")
        else:
            print("⚠️  admin_server.py not found - running without admin server")
        
        print("="*60)
        print("🌱 Main Server is now running...")
        print("="*60)
        print()
        
        # Start main Flask app
        app.run(host='0.0.0.0', port=5000, debug=True)
        
    except KeyboardInterrupt:
        print("\n\n🛑 Shutting down servers...")
        if admin_server_process and admin_server_process.poll() is None:
            admin_server_process.terminate()
            admin_server_process.wait()
            print("✅ Admin Server stopped")
        print("✅ Main Server stopped")
        print("Goodbye! 👋")
    except Exception as e:
        print(f"❌ Error starting servers: {e}")
        if admin_server_process and admin_server_process.poll() is None:
            admin_server_process.terminate()