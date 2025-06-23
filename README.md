# Minecraft Addon Manager - Deployment Guide

## 📁 Project Structure
```
mcaddon-manager/
├── Dockerfile
├── requirements.txt
├── app.py
├── install-mcaddon.sh
├── remove-mcaddon.sh
└── docker-compose.yml
```

## 🚀 Quick Start

### 1. Create Project Directory
```bash
mkdir mcaddon-manager && cd mcaddon-manager
# Add all the provided files (Dockerfile, app.py, requirements.txt, etc.)
```

### 2. Build the Docker Image
```bash
docker build -t mcaddon-manager .
```

### 3. Deploy with Docker Compose
The provided `docker-compose.yml` is already configured for your setup:

```bash
docker-compose up -d
```

### 4. Add to NPM (Nginx Proxy Manager)
In your NPM dashboard:
- **Domain**: `mcaddon.yourdomain.com` (or whatever you prefer)
- **Forward Hostname/IP**: `mcaddon-manager`
- **Forward Port**: `8000`
- **Block Common Exploits**: ✅
- **Websockets Support**: ✅ (optional)

### 5. Alternative: Run with Docker directly
```bash
docker run -d \
  --name mcaddon-manager \
  --network prod-network \
  -p 8000:8000 \
  -v /root/tools/minecraft:/root/tools/minecraft \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /etc/localtime:/etc/localtime:ro \
  mcaddon-manager
```

## 🔧 Configuration

### Volume Mounting
The configuration is already set up to match your existing Minecraft setup:
- **Host**: `/root/tools/minecraft` → **Container**: `/root/tools/minecraft`
- This directory should contain your `behavior_packs/`, `resource_packs/`, `worlds/`, and `server.properties`

### Network Configuration
The mcaddon-manager will join your existing `prod-network`, allowing it to communicate with your Minecraft server and be accessible through NPM.

### Docker Socket Access
The container needs access to the Docker socket to restart the `minecraft` container after addon installations.

## 🌐 Usage

### Web Interface
1. Access through NPM: `https://mcaddon.yourdomain.com`
2. Or directly: `http://localhost:8000`
3. Upload `.mcaddon` files using the web form
4. Monitor installation progress and results

### API Endpoints

#### Install Addon
```bash
curl -X POST -F "file=@your-addon.mcaddon" https://mcaddon.yourdomain.com/api/install
```

#### List Installed Addons
```bash
curl https://mcaddon.yourdomain.com/api/list
```

#### Remove Addons
```bash
curl -X POST -H "Content-Type: application/json" \
  -d '{"packs": ["addon_name"], "confirm": true}' \
  https://mcaddon.yourdomain.com/api/remove
```

#### Remove All Addons
```bash
curl -X POST -H "Content-Type: application/json" \
  -d '{"remove_all": true, "confirm": true}' \
  https://mcaddon.yourdomain.com/api/remove
```

#### Health Check
```bash
curl https://mcaddon.yourdomain.com/health
```

## 🔍 Monitoring

Check container logs:
```bash
docker logs mcaddon-manager
```

Check if the service is running:
```bash
docker ps | grep mcaddon-manager
```

## 🛠️ Troubleshooting

### Common Issues

1. **Permission Denied**: Make sure the container has access to the Docker socket
2. **Mount Issues**: Verify your volume paths are correct
3. **Minecraft Container Not Found**: Ensure your Minecraft container is named `minecraft`

### Debug Mode
To run in debug mode, add environment variable:
```bash
docker run -e FLASK_DEBUG=1 ...
```

## 🔒 Security Considerations

- The container requires Docker socket access (privileged operation)
- File uploads are limited to 50MB
- Only `.mcaddon` files are accepted
- Consider running behind a reverse proxy with authentication for production use

## 📝 Notes

- The service automatically restarts the Minecraft server after addon installation
- Uploaded files are cleaned up after processing
- The web interface provides real-time feedback on installation progress
- Both behavior and resource packs are handled automatically
  root@zuptalo:~/mcaddon-manager#