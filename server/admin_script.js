// Admin Panel Enhanced JavaScript
const SERVER_URL = window.location.origin;
const ADMIN_SERVER_URL = window.location.origin.replace(':5000', ':5001'); // Admin server on port 5001
let autoRefreshInterval = null;
let autoRefreshEnabled = false;
let allTasks = [];
let allStudents = [];
let allMedia = [];

// Check which server to use for admin endpoints
let useAdminServer = true;

// Test if admin server is available
async function checkAdminServer() {
    try {
        const response = await fetch(`${ADMIN_SERVER_URL}/health`, { timeout: 2000 });
        if (response.ok) {
            console.log('✅ Admin Server detected on port 5001');
            useAdminServer = true;
        }
    } catch (error) {
        console.log('⚠️ Admin Server not available, using main server only');
        useAdminServer = false;
    }
}

// Get the appropriate server URL for admin endpoints
function getAdminURL() {
    return useAdminServer ? ADMIN_SERVER_URL : SERVER_URL;
}

// Initialize on page load
document.addEventListener('DOMContentLoaded', async function() {
    await checkAdminServer();
    initializeApp();
});

function initializeApp() {
    loadDashboard();
    setupEventListeners();
    updateLastUpdateTime();
}

function setupEventListeners() {
    // Notification target change
    const notifTarget = document.getElementById('notifTarget');
    if (notifTarget) {
        notifTarget.addEventListener('change', function() {
            const userIdInput = document.getElementById('notifUserId');
            if (userIdInput) {
                userIdInput.style.display = this.value === 'specific' ? 'block' : 'none';
            }
        });
    }
}

// Navigation
function showSection(sectionId) {
    // Hide all sections
    document.querySelectorAll('.section').forEach(section => {
        section.classList.remove('active');
    });
    
    // Remove active from all nav items
    document.querySelectorAll('.nav-item').forEach(item => {
        item.classList.remove('active');
    });
    
    // Show selected section
    document.getElementById(sectionId).classList.add('active');
    
    // Add active to clicked nav item
    event.target.closest('.nav-item').classList.add('active');
    
    // Update page title
    const titles = {
        'dashboard': 'Dashboard',
        'tasks': 'All Tasks',
        'staff': 'Staff Management',
        'students': 'Student Management',
        'media': 'Media Gallery',
        'analytics': 'Analytics & Reports',
        'notifications': 'Notifications',
        'settings': 'Settings'
    };
    document.getElementById('pageTitle').textContent = titles[sectionId] || 'Dashboard';
    
    // Load section data
    loadSectionData(sectionId);
}

function loadSectionData(sectionId) {
    switch(sectionId) {
        case 'dashboard':
            loadDashboard();
            break;
        case 'tasks':
            loadAllTasks();
            break;
        case 'staff':
            loadStaffManagement();
            break;
        case 'students':
            loadStudents();
            break;
        case 'media':
            loadMediaGallery();
            break;
        case 'analytics':
            loadAnalytics();
            break;
    }
}

// Dashboard Functions
async function loadDashboard() {
    try {
        await Promise.all([
            loadStats(),
            loadRecentActivity(),
            loadCharts()
        ]);
    } catch (error) {
        console.error('Error loading dashboard:', error);
    }
}

async function loadStats() {
    try {
        console.log('🔄 Loading stats...');
        const [workloadRes, queueRes, studentsRes] = await Promise.all([
            fetch(`${SERVER_URL}/staff/workload`),
            fetch(`${SERVER_URL}/queue/status`),
            fetch(`${SERVER_URL}/admin/all_students`)
        ]);
        
        if (workloadRes.ok) {
            const workloadData = await workloadRes.json();
            console.log('📊 Workload data received:', workloadData);
            console.log('   totalStaff:', workloadData.totalStaff);
            console.log('   totalTasksInSystem:', workloadData.totalTasksInSystem);
            console.log('   totalPendingInSystem:', workloadData.totalPendingInSystem);
            console.log('   totalCompletedInSystem:', workloadData.totalCompletedInSystem);
            
            // Update DOM elements with explicit logging
            const totalStaffEl = document.getElementById('totalStaff');
            const totalTasksEl = document.getElementById('totalTasks');
            const pendingTasksEl = document.getElementById('pendingTasks');
            const completedTasksEl = document.getElementById('completedTasks');
            
            console.log('🎯 DOM Elements found:', {
                totalStaff: !!totalStaffEl,
                totalTasks: !!totalTasksEl,
                pendingTasks: !!pendingTasksEl,
                completedTasks: !!completedTasksEl
            });
            
            if (totalStaffEl) totalStaffEl.textContent = workloadData.totalStaff || 0;
            if (totalTasksEl) totalTasksEl.textContent = workloadData.totalTasksInSystem || 0;
            if (pendingTasksEl) pendingTasksEl.textContent = workloadData.totalPendingInSystem || 0;
            if (completedTasksEl) completedTasksEl.textContent = workloadData.totalCompletedInSystem || 0;
            
            console.log('✅ Stats updated in DOM:', {
                totalStaff: totalStaffEl?.textContent,
                totalTasks: totalTasksEl?.textContent,
                pending: pendingTasksEl?.textContent,
                completed: completedTasksEl?.textContent
            });
        }
        
        if (queueRes.ok) {
            const queueData = await queueRes.json();
            const queuedEl = document.getElementById('queuedTasks');
            if (queuedEl) queuedEl.textContent = queueData.queueLength || 0;
        }
        
        if (studentsRes.ok) {
            const studentsData = await studentsRes.json();
            console.log('👥 Students data:', studentsData.total);
            const studentsEl = document.getElementById('totalStudents');
            if (studentsEl) studentsEl.textContent = studentsData.total || 0;
        }
        
        updateLastUpdateTime();
    } catch (error) {
        console.error('❌ Error loading stats:', error);
    }
}

async function loadRecentActivity() {
    try {
        const response = await fetch(`${SERVER_URL}/admin/recent_activity`);
        if (response.ok) {
            const data = await response.json();
            displayRecentActivity(data.activities);
        }
    } catch (error) {
        console.error('Error loading recent activity:', error);
        document.getElementById('recentActivityList').innerHTML = '<div class="loading">No recent activity</div>';
    }
}

function displayRecentActivity(activities) {
    const container = document.getElementById('recentActivityList');
    if (!activities || activities.length === 0) {
        container.innerHTML = '<div class="loading">No recent activity</div>';
        return;
    }
    
    container.innerHTML = activities.map(activity => `
        <div class="activity-item">
            <div>
                <strong>${activity.type}</strong>: ${activity.description}
                <br><small>${new Date(activity.timestamp).toLocaleString()}</small>
            </div>
            <span>${activity.icon}</span>
        </div>
    `).join('');
}

async function loadCharts() {
    // Placeholder for chart loading - would use Chart.js in production
    console.log('Charts would be loaded here with Chart.js library');
}

// Tasks Management
async function loadAllTasks() {
    try {
        const adminURL = getAdminURL();
        const response = await fetch(`${adminURL}/admin/all_tasks`);
        if (response.ok) {
            const data = await response.json();
            allTasks = data.tasks;
            displayTasks(allTasks);
        }
    } catch (error) {
        console.error('Error loading tasks:', error);
        document.getElementById('tasksList').innerHTML = '<div class="error">Failed to load tasks</div>';
    }
}

function displayTasks(tasks) {
    const container = document.getElementById('tasksList');
    if (!tasks || tasks.length === 0) {
        container.innerHTML = '<div class="loading">No tasks found</div>';
        return;
    }
    
    container.innerHTML = tasks.map(task => `
        <div class="task-card" onclick="showTaskDetail('${task.taskId}')">
            <div style="display: flex; justify-content: space-between; align-items: start;">
                <div>
                    <h3>${task.aiCaption || 'No caption'}</h3>
                    <p><strong>Student:</strong> ${task.studentName} (${task.registerNumber})</p>
                    <p><strong>Location:</strong> ${task.location}</p>
                    <p><strong>Assigned to:</strong> ${task.assignedTo}</p>
                    <p><small>${new Date(task.createdAt).toLocaleString()}</small></p>
                </div>
                <span class="status-badge status-${task.status}">${task.status}</span>
            </div>
        </div>
    `).join('');
}

function filterTasks() {
    const status = document.getElementById('taskStatusFilter').value;
    const filtered = status === 'all' ? allTasks : allTasks.filter(t => t.status === status);
    displayTasks(filtered);
}

function searchTasks() {
    const query = document.getElementById('taskSearch').value.toLowerCase();
    const filtered = allTasks.filter(t => 
        t.aiCaption.toLowerCase().includes(query) ||
        t.studentName.toLowerCase().includes(query) ||
        t.location.toLowerCase().includes(query)
    );
    displayTasks(filtered);
}

async function showTaskDetail(taskId) {
    try {
        const response = await fetch(`${SERVER_URL}/task/${taskId}`);
        if (response.ok) {
            const task = await response.json();
            displayTaskDetailModal(task);
        }
    } catch (error) {
        console.error('Error loading task detail:', error);
    }
}

function displayTaskDetailModal(task) {
    const modal = document.getElementById('taskDetailModal');
    const content = document.getElementById('taskDetailContent');
    
    content.innerHTML = `
        <h2>Task Details</h2>
        <p><strong>Task ID:</strong> ${task.taskId}</p>
        <p><strong>Student:</strong> ${task.studentName} (${task.registerNumber})</p>
        <p><strong>AI Caption:</strong> ${task.aiCaption}</p>
        <p><strong>User Caption:</strong> ${task.studentCaption || 'None'}</p>
        <p><strong>Location:</strong> ${task.location}</p>
        <p><strong>Status:</strong> ${task.status}</p>
        <p><strong>Assigned to:</strong> ${task.assignedTo}</p>
        <p><strong>Created:</strong> ${new Date(task.createdAt).toLocaleString()}</p>
        ${task.completedAt ? `<p><strong>Completed:</strong> ${new Date(task.completedAt).toLocaleString()}</p>` : ''}
        ${task.hasOriginalImage ? `<img src="${task.images.original.url}" style="max-width: 100%; margin-top: 10px;">` : ''}
        ${task.hasCompletionImage ? `<img src="${task.images.completion.url}" style="max-width: 100%; margin-top: 10px;">` : ''}
    `;
    
    modal.classList.add('active');
}

function exportTasks() {
    const csv = convertTasksToCSV(allTasks);
    downloadCSV(csv, 'tasks_export.csv');
}

function convertTasksToCSV(tasks) {
    const headers = ['Task ID', 'Student Name', 'Register Number', 'Caption', 'Location', 'Status', 'Assigned To', 'Created At'];
    const rows = tasks.map(t => [
        t.taskId,
        t.studentName,
        t.registerNumber,
        t.aiCaption,
        t.location,
        t.status,
        t.assignedTo,
        new Date(t.createdAt).toLocaleString()
    ]);
    
    return [headers, ...rows].map(row => row.join(',')).join('\n');
}

function downloadCSV(csv, filename) {
    const blob = new Blob([csv], { type: 'text/csv' });
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    a.click();
}

// Staff Management
async function loadStaffManagement() {
    try {
        const response = await fetch(`${SERVER_URL}/admin/all_staff`);
        if (response.ok) {
            const data = await response.json();
            displayStaffList(data.staff);
        } else {
            // Fallback to old endpoint
            const fallbackResponse = await fetch(`${SERVER_URL}/staff/workload`);
            if (fallbackResponse.ok) {
                const fallbackData = await fallbackResponse.json();
                displayStaffList(fallbackData.workload);
            }
        }
    } catch (error) {
        console.error('Error loading staff:', error);
        document.getElementById('staffList').innerHTML = '<div class="error">Failed to load staff members</div>';
    }
}

function displayStaffList(staffList) {
    const container = document.getElementById('staffList');
    if (!staffList || staffList.length === 0) {
        container.innerHTML = '<div class="loading">No staff members found</div>';
        return;
    }
    
    container.innerHTML = staffList.map(staff => `
        <div class="staff-card">
            <div style="display: flex; justify-content: space-between; align-items: center;">
                <div style="flex: 1;">
                    <h3>${staff.name}</h3>
                    <p>ID: ${staff.staffId}</p>
                    <p>📋 Total: ${staff.taskCounts?.total || 0} | ⏳ Pending: ${staff.taskCounts?.pending || 0} | ✅ Completed: ${staff.taskCounts?.completed || 0}</p>
                    <p style="font-size: 0.9em; color: #666;">
                        ${staff.lastLogin ? '🕐 Last login: ' + new Date(staff.lastLogin).toLocaleString() : '🕐 Never logged in'}
                    </p>
                </div>
                <div style="display: flex; gap: 10px; align-items: center;">
                    <button class="btn btn-primary" onclick="viewStaffTasks('${staff.staffId}', '${staff.name}')">
                        👁️ View Tasks
                    </button>
                    <span class="status-badge ${staff.active ? 'status-active' : 'status-inactive'}">
                        ${staff.active ? 'Active' : 'Inactive'}
                    </span>
                    <button class="btn ${staff.active ? 'btn-danger' : ''}" 
                            onclick="toggleStaffStatus('${staff.staffId}', ${!staff.active})">
                        ${staff.active ? 'Deactivate' : 'Activate'}
                    </button>
                </div>
            </div>
        </div>
    `).join('');
}

async function viewStaffTasks(staffId, staffName) {
    try {
        // Show loading
        const modal = document.getElementById('staffTasksModal') || createStaffTasksModal();
        modal.classList.add('active');
        document.getElementById('staffTasksContent').innerHTML = '<div class="loading">Loading tasks...</div>';
        document.getElementById('staffTasksTitle').textContent = `Tasks for ${staffName}`;
        
        // Fetch tasks
        const response = await fetch(`${SERVER_URL}/admin/staff/${staffId}/tasks?status=pending`);
        if (!response.ok) {
            throw new Error('Failed to load tasks');
        }
        
        const data = await response.json();
        displayStaffTasks(data.tasks, staffId, staffName);
    } catch (error) {
        console.error('Error loading staff tasks:', error);
        document.getElementById('staffTasksContent').innerHTML = '<div class="error">Failed to load tasks</div>';
    }
}

function createStaffTasksModal() {
    const modal = document.createElement('div');
    modal.id = 'staffTasksModal';
    modal.className = 'modal';
    modal.innerHTML = `
        <div class="modal-content" style="max-width: 1200px; max-height: 90vh; overflow-y: auto;">
            <div class="modal-header">
                <h2 id="staffTasksTitle">Staff Tasks</h2>
                <button class="close-btn" onclick="closeModal('staffTasksModal')">×</button>
            </div>
            <div class="modal-body">
                <div style="margin-bottom: 20px;">
                    <select id="staffTasksFilter" onchange="filterStaffTasks()" style="padding: 8px; border-radius: 4px; border: 1px solid #ddd;">
                        <option value="pending">Pending Tasks</option>
                        <option value="completed">Completed Tasks</option>
                        <option value="all">All Tasks</option>
                    </select>
                </div>
                <div id="staffTasksContent"></div>
            </div>
        </div>
    `;
    document.body.appendChild(modal);
    return modal;
}

let currentStaffId = null;
let currentStaffName = null;

async function filterStaffTasks() {
    const filter = document.getElementById('staffTasksFilter').value;
    if (!currentStaffId) return;
    
    try {
        document.getElementById('staffTasksContent').innerHTML = '<div class="loading">Loading tasks...</div>';
        
        const response = await fetch(`${SERVER_URL}/admin/staff/${currentStaffId}/tasks?status=${filter}`);
        if (!response.ok) {
            throw new Error('Failed to load tasks');
        }
        
        const data = await response.json();
        displayStaffTasks(data.tasks, currentStaffId, currentStaffName);
    } catch (error) {
        console.error('Error filtering staff tasks:', error);
        document.getElementById('staffTasksContent').innerHTML = '<div class="error">Failed to load tasks</div>';
    }
}

function displayStaffTasks(tasks, staffId, staffName) {
    currentStaffId = staffId;
    currentStaffName = staffName;
    
    const container = document.getElementById('staffTasksContent');
    
    if (!tasks || tasks.length === 0) {
        container.innerHTML = '<div class="loading">No tasks found</div>';
        return;
    }
    
    container.innerHTML = tasks.map(task => `
        <div class="task-card" style="margin-bottom: 20px; padding: 15px; border: 1px solid #ddd; border-radius: 8px; background: white;">
            <div style="display: flex; gap: 20px;">
                <div style="flex-shrink: 0;">
                    ${task.imageUrl ? `
                        <img src="${task.imageUrl}" 
                             alt="Task image" 
                             style="width: 200px; height: 150px; object-fit: cover; border-radius: 8px; cursor: pointer;"
                             onclick="openImageModal('${task.imageUrl}')">
                    ` : '<div style="width: 200px; height: 150px; background: #f0f0f0; border-radius: 8px; display: flex; align-items: center; justify-content: center;">No Image</div>'}
                </div>
                <div style="flex: 1;">
                    <div style="display: flex; justify-content: space-between; align-items: start; margin-bottom: 10px;">
                        <div>
                            <h3 style="margin: 0 0 5px 0;">${task.studentName}</h3>
                            <p style="margin: 0; color: #666; font-size: 0.9em;">Register: ${task.registerNumber}</p>
                        </div>
                        <span class="status-badge status-${task.status.toLowerCase().replace(' ', '-')}">
                            ${task.status}
                        </span>
                    </div>
                    
                    <div style="margin: 10px 0;">
                        <p style="margin: 5px 0;"><strong>Student Caption:</strong> ${task.studentCaption || 'N/A'}</p>
                        <p style="margin: 5px 0;"><strong>AI Caption:</strong> ${task.aiCaption || 'N/A'}</p>
                        <p style="margin: 5px 0;"><strong>📍 Location:</strong> ${task.location || 'Unknown'}</p>
                        <p style="margin: 5px 0; color: #666; font-size: 0.9em;">
                            <strong>🕐 Created:</strong> ${task.createdAt ? new Date(task.createdAt).toLocaleString() : 'Unknown'}
                        </p>
                        ${task.completedAt ? `
                            <p style="margin: 5px 0; color: #666; font-size: 0.9em;">
                                <strong>✅ Completed:</strong> ${new Date(task.completedAt).toLocaleString()}
                            </p>
                        ` : ''}
                    </div>
                    
                    ${task.completionImageUrl ? `
                        <div style="margin-top: 10px;">
                            <p style="margin: 5px 0;"><strong>Completion Photo:</strong></p>
                            <img src="${task.completionImageUrl}" 
                                 alt="Completion image" 
                                 style="width: 150px; height: 100px; object-fit: cover; border-radius: 4px; cursor: pointer;"
                                 onclick="openImageModal('${task.completionImageUrl}')">
                        </div>
                    ` : ''}
                    
                    <div style="margin-top: 15px; display: flex; gap: 10px;">
                        <button class="btn btn-primary" onclick="viewTaskDetails('${task.taskId}')">
                            📋 View Details
                        </button>
                        ${task.status === 'pending' ? `
                            <button class="btn btn-success" onclick="markTaskComplete('${task.taskId}')">
                                ✅ Mark Complete
                            </button>
                        ` : ''}
                    </div>
                </div>
            </div>
        </div>
    `).join('');
}

function openImageModal(imageUrl) {
    const modal = document.getElementById('imageModal') || createImageModal();
    document.getElementById('modalImage').src = imageUrl;
    modal.classList.add('active');
}

function createImageModal() {
    const modal = document.createElement('div');
    modal.id = 'imageModal';
    modal.className = 'modal';
    modal.innerHTML = `
        <div class="modal-content" style="max-width: 90vw; max-height: 90vh;">
            <div class="modal-header">
                <h2>Image Preview</h2>
                <button class="close-btn" onclick="closeModal('imageModal')">×</button>
            </div>
            <div class="modal-body" style="text-align: center;">
                <img id="modalImage" src="" style="max-width: 100%; max-height: 70vh; object-fit: contain;">
            </div>
        </div>
    `;
    document.body.appendChild(modal);
    return modal;
}

function showCreateStaffModal() {
    document.getElementById('createStaffModal').classList.add('active');
}

async function createStaff() {
    const staffId = document.getElementById('newStaffId').value.trim();
    const staffName = document.getElementById('newStaffName').value.trim();
    
    if (!staffId || !staffName) {
        alert('Please fill in all fields');
        return;
    }
    
    try {
        const response = await fetch(`${SERVER_URL}/staff/create`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ staffId, name: staffName })
        });
        
        if (response.ok) {
            alert('Staff member created successfully');
            closeModal('createStaffModal');
            loadStaffManagement();
            loadStats();
        } else {
            const data = await response.json();
            alert('Error: ' + (data.error || 'Failed to create staff'));
        }
    } catch (error) {
        alert('Network error: ' + error.message);
    }
}

async function toggleStaffStatus(staffId, activate) {
    try {
        const response = await fetch(`${SERVER_URL}/staff/activate/${staffId}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ active: activate })
        });
        
        if (response.ok) {
            loadStaffManagement();
            loadStats();
        } else {
            alert('Failed to update staff status');
        }
    } catch (error) {
        alert('Network error: ' + error.message);
    }
}

// Student Management
async function loadStudents() {
    try {
        const response = await fetch(`${SERVER_URL}/admin/all_students`);
        if (response.ok) {
            const data = await response.json();
            allStudents = data.students;
            displayStudents(allStudents);
        }
    } catch (error) {
        console.error('Error loading students:', error);
        document.getElementById('studentsList').innerHTML = '<div class="error">Failed to load students</div>';
    }
}

function displayStudents(students) {
    const container = document.getElementById('studentsList');
    if (!students || students.length === 0) {
        container.innerHTML = '<div class="loading">No students found</div>';
        return;
    }
    
    container.innerHTML = students.map(student => `
        <div class="student-card">
            <h3>${student.name}</h3>
            <p>Register Number: ${student.registerNumber}</p>
            <p>Total Reports: ${student.totalReports || 0}</p>
            <p>Last Active: ${student.lastActive ? new Date(student.lastActive).toLocaleString() : 'Never'}</p>
        </div>
    `).join('');
}

function searchStudents() {
    const query = document.getElementById('studentSearch').value.toLowerCase();
    const filtered = allStudents.filter(s => 
        s.name.toLowerCase().includes(query) ||
        s.registerNumber.toLowerCase().includes(query)
    );
    displayStudents(filtered);
}

// Media Gallery
async function loadMediaGallery() {
    try {
        const response = await fetch(`${SERVER_URL}/admin/media_gallery`);
        if (response.ok) {
            const data = await response.json();
            allMedia = data.media;
            displayMediaGallery(allMedia);
        }
    } catch (error) {
        console.error('Error loading media:', error);
        document.getElementById('mediaGallery').innerHTML = '<div class="error">Failed to load media</div>';
    }
}

function displayMediaGallery(media) {
    const container = document.getElementById('mediaGallery');
    if (!media || media.length === 0) {
        container.innerHTML = '<div class="loading">No media found</div>';
        return;
    }
    
    container.innerHTML = media.map(item => `
        <div class="media-item" onclick="viewMedia('${item.url}', '${item.type}')">
            ${item.type === 'video' ? 
                `<video src="${item.url}" muted></video>` :
                `<img src="${item.url}" alt="Media">`
            }
            <div class="media-overlay">
                <div>${item.type === 'video' ? '🎥' : '📷'} ${item.filename}</div>
                <div>${(item.size / 1024).toFixed(2)} KB</div>
            </div>
        </div>
    `).join('');
}

function filterMedia() {
    const type = document.getElementById('mediaTypeFilter').value;
    const filtered = type === 'all' ? allMedia : allMedia.filter(m => m.type === type);
    displayMediaGallery(filtered);
}

function viewMedia(url, type) {
    window.open(url, '_blank');
}

async function cleanupOldMedia() {
    if (!confirm('This will delete media files older than 30 days. Continue?')) {
        return;
    }
    
    try {
        const response = await fetch(`${SERVER_URL}/admin/cleanup_media`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' }
        });
        
        if (response.ok) {
            const data = await response.json();
            alert(`Cleaned up ${data.filesDeleted} files, freed ${(data.spaceFreed / 1024 / 1024).toFixed(2)} MB`);
            loadMediaGallery();
        }
    } catch (error) {
        alert('Error cleaning up media: ' + error.message);
    }
}

// Analytics
async function loadAnalytics() {
    try {
        const range = document.getElementById('analyticsRange').value;
        const response = await fetch(`${SERVER_URL}/admin/analytics?range=${range}`);
        if (response.ok) {
            const data = await response.json();
            displayAnalytics(data);
        }
    } catch (error) {
        console.error('Error loading analytics:', error);
    }
}

function displayAnalytics(data) {
    const container = document.getElementById('analyticsContent');
    container.innerHTML = `
        <div class="stats-grid">
            <div class="stat-card">
                <div class="stat-value">${data.totalTasks || 0}</div>
                <div class="stat-label">Total Tasks</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">${data.completionRate || 0}%</div>
                <div class="stat-label">Completion Rate</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">${data.avgResponseTime || 0} min</div>
                <div class="stat-label">Avg Response Time</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">${data.activeUsers || 0}</div>
                <div class="stat-label">Active Users</div>
            </div>
        </div>
        <div class="chart-card">
            <h3>Task Trends</h3>
            <p>Chart visualization would go here</p>
        </div>
    `;
}

async function generateReport() {
    const range = document.getElementById('analyticsRange').value;
    try {
        const response = await fetch(`${SERVER_URL}/admin/generate_report?range=${range}`);
        if (response.ok) {
            const blob = await response.blob();
            const url = window.URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = `report_${range}_${Date.now()}.pdf`;
            a.click();
        }
    } catch (error) {
        alert('Error generating report: ' + error.message);
    }
}

// Notifications
async function sendBroadcastNotification() {
    const target = document.getElementById('notifTarget').value;
    const userId = document.getElementById('notifUserId').value;
    const title = document.getElementById('notifTitle').value;
    const body = document.getElementById('notifBody').value;
    
    if (!title || !body) {
        alert('Please fill in title and message');
        return;
    }
    
    try {
        const response = await fetch(`${SERVER_URL}/admin/send_notification`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ target, userId, title, body })
        });
        
        if (response.ok) {
            alert('Notification sent successfully');
            document.getElementById('notifTitle').value = '';
            document.getElementById('notifBody').value = '';
        } else {
            alert('Failed to send notification');
        }
    } catch (error) {
        alert('Error: ' + error.message);
    }
}

// Settings
function saveSettings() {
    const refreshInterval = document.getElementById('refreshInterval').value;
    const maxImageSize = document.getElementById('maxImageSize').value;
    const maxVideoSize = document.getElementById('maxVideoSize').value;
    
    localStorage.setItem('adminSettings', JSON.stringify({
        refreshInterval,
        maxImageSize,
        maxVideoSize
    }));
    
    alert('Settings saved successfully');
}

// Utility Functions
function toggleAutoRefresh() {
    autoRefreshEnabled = !autoRefreshEnabled;
    const icon = document.getElementById('autoRefreshIcon');
    
    if (autoRefreshEnabled) {
        icon.textContent = '▶️';
        const interval = parseInt(document.getElementById('refreshInterval').value) * 1000;
        autoRefreshInterval = setInterval(refreshAll, interval);
    } else {
        icon.textContent = '⏸️';
        if (autoRefreshInterval) {
            clearInterval(autoRefreshInterval);
        }
    }
}

async function refreshAll() {
    const activeSection = document.querySelector('.section.active').id;
    await loadSectionData(activeSection);
    await loadStats();
    updateLastUpdateTime();
}

function updateLastUpdateTime() {
    document.getElementById('lastUpdate').textContent = new Date().toLocaleTimeString();
}

function closeModal(modalId) {
    document.getElementById(modalId).classList.remove('active');
}

// Close modal when clicking outside
window.onclick = function(event) {
    if (event.target.classList.contains('modal')) {
        event.target.classList.remove('active');
    }
}


// Utility Functions
async function refreshAll() {
    console.log('🔄 Refreshing all data...');
    try {
        const activeSection = document.querySelector('.section.active');
        if (activeSection) {
            await loadSectionData(activeSection.id);
        }
        await loadStats();
        updateLastUpdateTime();
        console.log('✅ Refresh complete');
    } catch (error) {
        console.error('❌ Error refreshing:', error);
    }
}

function updateLastUpdateTime() {
    const now = new Date();
    document.getElementById('lastUpdate').textContent = now.toLocaleTimeString();
}

function closeModal(modalId) {
    const modal = document.getElementById(modalId);
    if (modal) {
        modal.classList.remove('active');
    }
}

// Close modal when clicking outside
window.onclick = function(event) {
    if (event.target.classList.contains('modal')) {
        event.target.classList.remove('active');
    }
}

// Initialize charts (placeholder)
async function loadCharts() {
    console.log('📊 Charts would be loaded here with Chart.js library');
}
