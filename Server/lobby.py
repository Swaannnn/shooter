import os
from flask import Flask, request, jsonify
import random
import string
import time

app = Flask(__name__)

# Store lobbies in memory: { "CODE": { "ip": "1.2.3.4", "port": 7777, "last_seen": timestamp } }
lobbies = {}

def generate_code():
    # Generate 4-char uppercase code
    return ''.join(random.choices(string.ascii_uppercase + string.digits, k=4))

def cleanup_lobbies():
    # Remove lobbies older than 10 mins
    now = time.time()
    expired = [code for code, data in lobbies.items() if now - data['last_seen'] > 600]
    for code in expired:
        del lobbies[code]

@app.route('/host', methods=['POST'])
def host_game():
    cleanup_lobbies()

    data = request.json
    if not data or 'port' not in data:
        return jsonify({"error": "Missing port"}), 400

    code = generate_code()
    while code in lobbies:
        code = generate_code()

    ip = request.headers.get("X-Forwarded-For", request.remote_addr)
    ip = ip.split(",")[0].strip()

    lobbies[code] = {
        "ip": ip,
        "port": data['port'],
        "last_seen": time.time()
    }

    print(f"New Lobby: {code} -> {ip}:{data['port']}")
    return jsonify({"code": code})


@app.route('/join/<code>', methods=['GET'])
def join_game(code):
    cleanup_lobbies()
    code = code.upper()
    
    if code in lobbies:
        lobby = lobbies[code]
        return jsonify({
            "ip": lobby['ip'],
            "port": lobby['port']
        })
    else:
        return jsonify({"error": "Lobby not found"}), 404

@app.route('/', methods=['GET'])
def status():
    return jsonify({"status": "running", "lobbies": len(lobbies)})

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    print(f"Lobby Server Running on Port {port}...")
    app.run(host='0.0.0.0', port=port)
