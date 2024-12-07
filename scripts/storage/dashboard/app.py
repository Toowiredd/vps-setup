#!/usr/bin/env python3
from flask import Flask, jsonify, request, send_from_directory
from flask_cors import CORS
import json
import os
import subprocess
import psutil
import time
from datetime import datetime
import threading
import queue
import socket

app = Flask(__name__, static_folder='frontend/build')

# Get server IP
def get_server_ip():
    try:
        # Get the primary IP address
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(('8.8.8.8', 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except:
        return '0.0.0.0'  # Fallback to all interfaces if can't determine IP

SERVER_IP = get_server_ip()
SERVER_PORT = 5000

# Configure CORS for security
CORS(app, resources={
    r"/api/*": {
        "origins": [
            f"http://{SERVER_IP}:3000",  # Development
            f"http://{SERVER_IP}:5000",  # Production
            "http://localhost:3000",      # Local development
        ],
        "methods": ["GET", "POST", "OPTIONS"],
        "allow_headers": ["Content-Type"]
    }
})

# Configuration
WORKSPACE_DIR = os.getenv('WORKSPACE_DIR', '/opt/storage-migration')
METRICS_FILE = os.path.join(WORKSPACE_DIR, 'transfer_metrics/historical.json')
PREDICTIONS_FILE = os.path.join(WORKSPACE_DIR, 'predictions/resources/prediction.json')
STATUS_FILE = os.path.join(WORKSPACE_DIR, 'status/current.json')

# Queue for real-time updates
update_queue = queue.Queue()

def load_json_file(filepath, default=None):
    try:
        with open(filepath, 'r') as f:
            return json.load(f)
    except:
        return default or {}

def save_json_file(filepath, data):
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    with open(filepath, 'w') as f:
        json.dump(data, f, indent=2)

def get_system_metrics():
    return {
        'cpu_usage': psutil.cpu_percent(),
        'memory_usage': psutil.virtual_memory().percent,
        'disk_usage': psutil.disk_usage('/').percent,
        'network': {
            interface: stats._asdict()
            for interface, stats in psutil.net_io_counters(pernic=True).items()
        }
    }

# Routes for serving the React frontend
@app.route('/', defaults={'path': ''})
@app.route('/<path:path>')
def serve(path):
    if path and os.path.exists(app.static_folder + '/' + path):
        return send_from_directory(app.static_folder, path)
    return send_from_directory(app.static_folder, 'index.html')

# API Routes
@app.route('/api/status')
def get_status():
    status = load_json_file(STATUS_FILE)
    metrics = get_system_metrics()
    return jsonify({
        'status': status,
        'system_metrics': metrics,
        'timestamp': datetime.now().isoformat()
    })

@app.route('/api/metrics')
def get_metrics():
    metrics = load_json_file(METRICS_FILE)
    predictions = load_json_file(PREDICTIONS_FILE)
    return jsonify({
        'historical': metrics,
        'predictions': predictions,
        'current': get_system_metrics()
    })

@app.route('/api/transfers')
def get_transfers():
    metrics = load_json_file(METRICS_FILE)
    return jsonify({
        'transfers': metrics.get('transfers', []),
        'total_count': len(metrics.get('transfers', [])),
        'success_rate': sum(1 for t in metrics.get('transfers', []) if t.get('success')) /
                       max(len(metrics.get('transfers', [])), 1) * 100
    })

@app.route('/api/config', methods=['GET', 'POST'])
def handle_config():
    config_file = os.path.join(WORKSPACE_DIR, 'config/preflight.json')
    if request.method == 'POST':
        new_config = request.json
        save_json_file(config_file, new_config)
        return jsonify({'status': 'success', 'message': 'Configuration updated'})
    return jsonify(load_json_file(config_file))

@app.route('/api/start', methods=['POST'])
def start_migration():
    params = request.json
    source = params.get('source')
    target = params.get('target')

    if not source or not target:
        return jsonify({'error': 'Source and target are required'}), 400

    # Start migration in background
    thread = threading.Thread(target=run_migration, args=(source, target))
    thread.start()

    return jsonify({'status': 'started', 'message': 'Migration started'})

@app.route('/api/stop', methods=['POST'])
def stop_migration():
    # Implement migration stopping logic
    status = load_json_file(STATUS_FILE)
    status['state'] = 'stopping'
    save_json_file(STATUS_FILE, status)
    return jsonify({'status': 'stopping', 'message': 'Migration is being stopped'})

@app.route('/api/events')
def get_events():
    def generate():
        while True:
            try:
                update = update_queue.get(timeout=30)
                yield f"data: {json.dumps(update)}\n\n"
            except queue.Empty:
                yield f"data: {json.dumps({'type': 'heartbeat'})}\n\n"

    return app.response_class(
        generate(),
        mimetype='text/event-stream'
    )

def run_migration(source, target):
    try:
        # Update status
        status = {'state': 'running', 'source': source, 'target': target, 'start_time': time.time()}
        save_json_file(STATUS_FILE, status)

        # Run migration script
        cmd = ['/bin/bash', 'migrate_storage.sh', source, target]
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True
        )

        # Monitor progress
        while True:
            output = process.stdout.readline()
            if output == '' and process.poll() is not None:
                break
            if output:
                update_queue.put({
                    'type': 'progress',
                    'message': output.strip(),
                    'timestamp': time.time()
                })

        # Update final status
        status['state'] = 'completed' if process.returncode == 0 else 'failed'
        status['end_time'] = time.time()
        save_json_file(STATUS_FILE, status)

    except Exception as e:
        status = load_json_file(STATUS_FILE)
        status['state'] = 'failed'
        status['error'] = str(e)
        save_json_file(STATUS_FILE, status)
        update_queue.put({
            'type': 'error',
            'message': str(e),
            'timestamp': time.time()
        })

if __name__ == '__main__':
    # Ensure required directories exist
    os.makedirs(os.path.join(WORKSPACE_DIR, 'transfer_metrics'), exist_ok=True)
    os.makedirs(os.path.join(WORKSPACE_DIR, 'predictions/resources'), exist_ok=True)
    os.makedirs(os.path.join(WORKSPACE_DIR, 'status'), exist_ok=True)

    # Initialize status file if it doesn't exist
    if not os.path.exists(STATUS_FILE):
        save_json_file(STATUS_FILE, {'state': 'idle'})

    print(f"Starting server on {SERVER_IP}:{SERVER_PORT}")
    app.run(host=SERVER_IP, port=SERVER_PORT, threaded=True)