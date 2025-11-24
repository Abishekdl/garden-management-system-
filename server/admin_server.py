#!/usr/bin/env python3
"""
Admin Server - Separate server for admin panel operations
Integrates with main app.py server via API calls and direct database access
"""

from flask import Flask, request, jsonify, send_file
from flask_cors import CORS
import firebase_admin
from firebase_admin import credentials, firestore
from datetime import datetime, timedelta
import os
import json
from collections import defaultdict
import io
from reportlab.lib.pagesizes import letter
from reportlab.pdfgen import canvas

app = Flask(__name__)
CORS(app)

# Initialize Firebase (reuse existing credentials)
try:
    # Check if Firebase is already initialized
    try:
        firebase_admin.get_app('admin_app')
        print("✅ Admin Server: Using existing Firebase app")
    except ValueError:
        # Not initialized yet, create new app
        cred = credentials.Certificate("serviceAccountKey.json")
        firebase_admin.initialize_app(cred, name='admin_app')
        print("✅ Admin Server: Firebase initialized")
except Exception as e:
    print(f"❌ Admin Server: Firebase initialization failed: {e}")
    print(f"   Will try to use default Firebase app")

# Get Firestore client (will use default app if admin_app fails)
try:
    db = firestore.client(app=firebase_admin.get_app('admin_app'))
except:
    db = firestore.client()  # Use default app

# Configuration
MAIN_SERVER_URL = os.environ.get('MAIN_SERVER_URL', 'http://localhost:5000')
UPLOAD_FOLDER = 'uploads'
PROCESSED_FOLDER = 'processed'
COMPLETED_FOLDER = 'completed'

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'service': 'Admin Server',
        'timestamp': datetime.now().isoformat()
    }), 200

# ============================================================================
# TASK MANAGEMENT ENDPOINTS
# ============================================================================

@app.route('/admin/all_tasks', methods=['GET'])
def get_all_tasks():
    """Get all tasks from database"""
    try:
        tasks_ref = db.collection('tasks')
        tasks_docs = tasks_ref.stream()
        
        tasks = []
        for doc in tasks_docs:
            task_data = doc.to_dict()
            task_data['taskId'] = doc.id
            
            # Format timestamps
            if 'createdAt' in task_data and task_data['createdAt']:
                task_data['createdAt'] = task_data['createdAt'].isoformat()
            if 'completedAt' in task_data and task_data['completedAt']:
                task_data['completedAt'] = task_data['completedAt'].isoformat()
            
            tasks.append(task_data)
        
        # Sort by creation date (newest first)
        tasks.sort(key=lambda x: x.get('createdAt', ''), reverse=True)
        
        return jsonify({
            'tasks': tasks,
            'total': len(tasks),
            'timestamp': datetime.now().isoformat()
        }), 200
        
    except Exception as e:
        print(f"Error fetching all tasks: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/admin/task/<task_id>', methods=['GET'])
def get_task_detail(task_id):
    """Get detailed task information"""
    try:
        task_doc = db.collection('tasks').document(task_id).get()
        
        if not task_doc.exists:
            return jsonify({'error': 'Task not found'}), 404
        
        task_data = task_doc.to_dict()
        task_data['taskId'] = task_id
        
        # Format timestamps
        if 'createdAt' in task_data and task_data['createdAt']:
            task_data['createdAt'] = task_data['createdAt'].isoformat()
        if 'completedAt' in task_data and task_data['completedAt']:
            task_data['completedAt'] = task_data['completedAt'].isoformat()
        
        return jsonify(task_data), 200
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500

# ============================================================================
# STUDENT MANAGEMENT ENDPOINTS
# ============================================================================

@app.route('/admin/all_students', methods=['GET'])
def get_all_students():
    """Get all students with their activity statistics"""
    try:
        students_ref = db.collection('students')
        students_docs = students_ref.stream()
        
        students = []
        for doc in students_docs:
            student_data = doc.to_dict()
            student_id = doc.id
            
            # Get task count for this student
            tasks_query = db.collection('tasks').where('registerNumber', '==', student_id)
            tasks_count = len(list(tasks_query.stream()))
            
            students.append({
                'registerNumber': student_id,
                'name': student_data.get('name', 'Unknown'),
                'totalReports': tasks_count,
                'lastActive': student_data.get('lastActive', None),
                'fcmToken': 'Yes' if student_data.get('fcmToken') else 'No'
            })
        
        return jsonify({
            'students': students,
            'total': len(students),
            'timestamp': datetime.now().isoformat()
        }), 200
        
    except Exception as e:
        print(f"Error fetching students: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/admin/student/<student_id>', methods=['GET'])
def get_student_detail(student_id):
    """Get detailed student information"""
    try:
        student_doc = db.collection('students').document(student_id).get()
        
        if not student_doc.exists:
            return jsonify({'error': 'Student not found'}), 404
        
        student_data = student_doc.to_dict()
        
        # Get student's tasks
        tasks_query = db.collection('tasks').where('registerNumber', '==', student_id)
        tasks = [doc.to_dict() for doc in tasks_query.stream()]
        
        return jsonify({
            'student': student_data,
            'tasks': tasks,
            'totalTasks': len(tasks)
        }), 200
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500

# ============================================================================
# MEDIA MANAGEMENT ENDPOINTS
# ============================================================================

@app.route('/admin/media_gallery', methods=['GET'])
def get_media_gallery():
    """Get all media files from upload folders"""
    try:
        media_files = []
        
        # Scan all media folders
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
                            'url': f"{MAIN_SERVER_URL}/{folder_name}/{filename}",
                            'size': file_size,
                            'type': media_type,
                            'extension': file_ext,
                            'modified': datetime.fromtimestamp(os.path.getmtime(file_path)).isoformat()
                        })
        
        # Sort by modification date (newest first)
        media_files.sort(key=lambda x: x['modified'], reverse=True)
        
        return jsonify({
            'media': media_files,
            'total': len(media_files),
            'totalSize': sum(m['size'] for m in media_files)
        }), 200
        
    except Exception as e:
        print(f"Error fetching media gallery: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/admin/cleanup_media', methods=['POST'])
def cleanup_old_media():
    """Delete media files older than specified days"""
    try:
        days = request.json.get('days', 30)
        cutoff_date = datetime.now() - timedelta(days=days)
        
        files_deleted = 0
        space_freed = 0
        
        folders = [UPLOAD_FOLDER, PROCESSED_FOLDER, COMPLETED_FOLDER]
        
        for folder_path in folders:
            if os.path.exists(folder_path):
                for filename in os.listdir(folder_path):
                    file_path = os.path.join(folder_path, filename)
                    if os.path.isfile(file_path):
                        file_mtime = datetime.fromtimestamp(os.path.getmtime(file_path))
                        
                        if file_mtime < cutoff_date:
                            file_size = os.path.getsize(file_path)
                            os.remove(file_path)
                            files_deleted += 1
                            space_freed += file_size
        
        return jsonify({
            'filesDeleted': files_deleted,
            'spaceFreed': space_freed,
            'message': f'Deleted {files_deleted} files, freed {space_freed} bytes'
        }), 200
        
    except Exception as e:
        print(f"Error cleaning up media: {e}")
        return jsonify({'error': str(e)}), 500

# ============================================================================
# ANALYTICS ENDPOINTS
# ============================================================================

@app.route('/admin/analytics', methods=['GET'])
def get_analytics():
    """Get analytics data for specified time range"""
    try:
        range_param = request.args.get('range', 'all')
        
        # Calculate date range
        now = datetime.now()
        if range_param == 'today':
            start_date = now.replace(hour=0, minute=0, second=0, microsecond=0)
        elif range_param == 'week':
            start_date = now - timedelta(days=7)
        elif range_param == 'month':
            start_date = now - timedelta(days=30)
        else:
            start_date = datetime.min
        
        # Get tasks in range
        tasks_ref = db.collection('tasks')
        all_tasks = list(tasks_ref.stream())
        
        filtered_tasks = []
        for doc in all_tasks:
            task_data = doc.to_dict()
            created_at = task_data.get('createdAt')
            if created_at and created_at >= start_date:
                filtered_tasks.append(task_data)
        
        # Calculate metrics
        total_tasks = len(filtered_tasks)
        completed_tasks = len([t for t in filtered_tasks if t.get('status') == 'completed'])
        pending_tasks = len([t for t in filtered_tasks if t.get('status') == 'pending'])
        
        completion_rate = (completed_tasks / total_tasks * 100) if total_tasks > 0 else 0
        
        # Calculate average response time
        response_times = []
        for task in filtered_tasks:
            if task.get('status') == 'completed' and task.get('createdAt') and task.get('completedAt'):
                created = task['createdAt']
                completed = task['completedAt']
                if hasattr(created, 'timestamp') and hasattr(completed, 'timestamp'):
                    response_time = (completed.timestamp() - created.timestamp()) / 60  # minutes
                    response_times.append(response_time)
        
        avg_response_time = sum(response_times) / len(response_times) if response_times else 0
        
        # Get unique active users
        unique_students = set(t.get('registerNumber') for t in filtered_tasks if t.get('registerNumber'))
        unique_staff = set(t.get('assignedTo') for t in filtered_tasks if t.get('assignedTo'))
        
        return jsonify({
            'totalTasks': total_tasks,
            'completedTasks': completed_tasks,
            'pendingTasks': pending_tasks,
            'completionRate': round(completion_rate, 2),
            'avgResponseTime': round(avg_response_time, 2),
            'activeUsers': len(unique_students) + len(unique_staff),
            'activeStudents': len(unique_students),
            'activeStaff': len(unique_staff),
            'range': range_param,
            'startDate': start_date.isoformat(),
            'endDate': now.isoformat()
        }), 200
        
    except Exception as e:
        print(f"Error generating analytics: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/admin/recent_activity', methods=['GET'])
def get_recent_activity():
    """Get recent system activity"""
    try:
        limit = int(request.args.get('limit', 20))
        
        # Get recent tasks
        tasks_ref = db.collection('tasks').order_by('createdAt', direction=firestore.Query.DESCENDING).limit(limit)
        tasks = list(tasks_ref.stream())
        
        activities = []
        for doc in tasks:
            task_data = doc.to_dict()
            
            # Task created activity
            if task_data.get('createdAt'):
                activities.append({
                    'type': 'Task Created',
                    'description': f"{task_data.get('studentName')} reported: {task_data.get('aiCaption', 'Issue')}",
                    'timestamp': task_data['createdAt'].isoformat() if hasattr(task_data['createdAt'], 'isoformat') else str(task_data['createdAt']),
                    'icon': '📋'
                })
            
            # Task completed activity
            if task_data.get('status') == 'completed' and task_data.get('completedAt'):
                activities.append({
                    'type': 'Task Completed',
                    'description': f"{task_data.get('assignedTo')} completed task for {task_data.get('studentName')}",
                    'timestamp': task_data['completedAt'].isoformat() if hasattr(task_data['completedAt'], 'isoformat') else str(task_data['completedAt']),
                    'icon': '✅'
                })
        
        # Sort by timestamp (newest first)
        activities.sort(key=lambda x: x['timestamp'], reverse=True)
        
        return jsonify({
            'activities': activities[:limit],
            'total': len(activities)
        }), 200
        
    except Exception as e:
        print(f"Error fetching recent activity: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/admin/generate_report', methods=['GET'])
def generate_report():
    """Generate PDF report"""
    try:
        range_param = request.args.get('range', 'all')
        
        # Get analytics data
        analytics_response = get_analytics()
        analytics_data = json.loads(analytics_response[0].data)
        
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
            f"Total Tasks: {analytics_data['totalTasks']}",
            f"Completed Tasks: {analytics_data['completedTasks']}",
            f"Pending Tasks: {analytics_data['pendingTasks']}",
            f"Completion Rate: {analytics_data['completionRate']}%",
            f"Average Response Time: {analytics_data['avgResponseTime']} minutes",
            f"Active Users: {analytics_data['activeUsers']}"
        ]
        
        for metric in metrics:
            p.drawString(120, y_position, metric)
            y_position -= 25
        
        p.showPage()
        p.save()
        
        buffer.seek(0)
        return send_file(buffer, mimetype='application/pdf', as_attachment=True, 
                        download_name=f'report_{range_param}_{datetime.now().strftime("%Y%m%d")}.pdf')
        
    except Exception as e:
        print(f"Error generating report: {e}")
        return jsonify({'error': str(e)}), 500

# ============================================================================
# NOTIFICATION ENDPOINTS
# ============================================================================

@app.route('/admin/send_notification', methods=['POST'])
def send_broadcast_notification():
    """Send notification to users"""
    try:
        data = request.json
        target = data.get('target')  # 'all_staff', 'all_students', 'specific'
        user_id = data.get('userId')
        title = data.get('title')
        body = data.get('body')
        
        if not title or not body:
            return jsonify({'error': 'Title and body are required'}), 400
        
        from firebase_admin import messaging
        
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
# SYSTEM MANAGEMENT ENDPOINTS
# ============================================================================

@app.route('/admin/system_stats', methods=['GET'])
def get_system_stats():
    """Get system statistics"""
    try:
        # Database stats
        total_tasks = len(list(db.collection('tasks').stream()))
        total_students = len(list(db.collection('students').stream()))
        total_staff = len(list(db.collection('staff').stream()))
        
        # Storage stats
        total_storage = 0
        file_count = 0
        
        folders = [UPLOAD_FOLDER, PROCESSED_FOLDER, COMPLETED_FOLDER]
        for folder in folders:
            if os.path.exists(folder):
                for filename in os.listdir(folder):
                    file_path = os.path.join(folder, filename)
                    if os.path.isfile(file_path):
                        total_storage += os.path.getsize(file_path)
                        file_count += 1
        
        return jsonify({
            'database': {
                'totalTasks': total_tasks,
                'totalStudents': total_students,
                'totalStaff': total_staff
            },
            'storage': {
                'totalFiles': file_count,
                'totalSize': total_storage,
                'totalSizeMB': round(total_storage / 1024 / 1024, 2)
            },
            'timestamp': datetime.now().isoformat()
        }), 200
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/admin/backup_database', methods=['POST'])
def backup_database():
    """Create database backup"""
    try:
        backup_data = {
            'timestamp': datetime.now().isoformat(),
            'tasks': [],
            'students': [],
            'staff': []
        }
        
        # Backup tasks
        for doc in db.collection('tasks').stream():
            task_data = doc.to_dict()
            task_data['id'] = doc.id
            backup_data['tasks'].append(task_data)
        
        # Backup students
        for doc in db.collection('students').stream():
            student_data = doc.to_dict()
            student_data['id'] = doc.id
            backup_data['students'].append(student_data)
        
        # Backup staff
        for doc in db.collection('staff').stream():
            staff_data = doc.to_dict()
            staff_data['id'] = doc.id
            backup_data['staff'].append(staff_data)
        
        # Save to file
        backup_filename = f"backup_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        backup_path = os.path.join('backups', backup_filename)
        
        os.makedirs('backups', exist_ok=True)
        
        with open(backup_path, 'w') as f:
            json.dump(backup_data, f, indent=2, default=str)
        
        return jsonify({
            'message': 'Backup created successfully',
            'filename': backup_filename,
            'path': backup_path,
            'size': os.path.getsize(backup_path)
        }), 200
        
    except Exception as e:
        print(f"Error creating backup: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/admin/export_data', methods=['GET'])
def export_data():
    """Export data as CSV"""
    try:
        data_type = request.args.get('type', 'tasks')
        
        if data_type == 'tasks':
            tasks = list(db.collection('tasks').stream())
            csv_data = "Task ID,Student Name,Register Number,Caption,Location,Status,Assigned To,Created At\n"
            
            for doc in tasks:
                task = doc.to_dict()
                csv_data += f"{doc.id},{task.get('studentName','')},{task.get('registerNumber','')},{task.get('aiCaption','')},{task.get('location','')},{task.get('status','')},{task.get('assignedTo','')},{task.get('createdAt','')}\n"
        
        elif data_type == 'students':
            students = list(db.collection('students').stream())
            csv_data = "Register Number,Name,Total Reports\n"
            
            for doc in students:
                student = doc.to_dict()
                tasks_count = len(list(db.collection('tasks').where('registerNumber', '==', doc.id).stream()))
                csv_data += f"{doc.id},{student.get('name','')},{tasks_count}\n"
        
        else:
            return jsonify({'error': 'Invalid data type'}), 400
        
        # Create response
        output = io.BytesIO()
        output.write(csv_data.encode('utf-8'))
        output.seek(0)
        
        return send_file(output, mimetype='text/csv', as_attachment=True,
                        download_name=f'{data_type}_export_{datetime.now().strftime("%Y%m%d")}.csv')
        
    except Exception as e:
        print(f"Error exporting data: {e}")
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    print("="*60)
    print("🌱 Garden App - Admin Server")
    print("="*60)
    print(f"Main Server URL: {MAIN_SERVER_URL}")
    print(f"Admin Server starting on port 5001...")
    print("="*60)
    app.run(host='0.0.0.0', port=5001, debug=True)
