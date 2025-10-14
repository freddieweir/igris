# MCP Integration Guide - Cross-Platform Setup

This guide covers how to use the ElevenLabs MCP server across different tools and platforms.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                   Application Layer                          │
│  (Claude Code, Open-WebUI, Fifth Symphony, etc.)            │
└────────────────────┬────────────────────────────────────────┘
                     │
                     │ MCP Protocol (stdio or HTTP)
                     ▼
        ┌────────────────────────────────────────┐
        │  ElevenLabs MCP Server                 │
        │  - Text-to-Speech                      │
        │  - Speech-to-Text                      │
        │  - Voice Cloning                       │
        │  - Sound Effects                       │
        │  - Conversational AI                   │
        └────────────┬───────────────────────────┘
                     │
                     │ HTTPS REST API
                     ▼
           ┌─────────────────┐
           │  ElevenLabs API │
           │  (Cloud Service)│
           └─────────────────┘
```

## Integration Methods

### Method 1: stdio (Direct Process Communication)
**Best for**: Claude Code, Cursor, Windsurf, CLI tools
**Pros**: Low latency, simple setup
**Cons**: Process per client, not network-accessible

### Method 2: HTTP via mcpo (OpenAPI Proxy)
**Best for**: Open-WebUI, web applications, remote access
**Pros**: Network accessible, multiple clients, REST API
**Cons**: Additional proxy process, slight latency

---

## 🖥️ Claude Code / VSCodium Setup

**Status**: ✅ Already configured

### Configuration
File: `.mcp.json` in project root

```json
{
  "mcpServers": {
    "elevenlabs": {
      "type": "stdio",
      "command": "uv",
      "args": [
        "--directory",
        "/Users/fweir/git/external/mcp/elevenlabs-mcp",
        "run",
        "elevenlabs-mcp"
      ],
      "env": {
        "ELEVENLABS_API_KEY": "${env:ELEVENLABS_API_KEY}",
        "ELEVENLABS_DEFAULT_VOICE_ID": "Sr4DTtH3Kmyd0sUrsL97"
      }
    }
  }
}
```

### Usage
Ask Claude directly:
```
Use text_to_speech to say "Hello from Claude Code"
```

### Repositories with MCP Configured
- ✅ `/Users/fweir/git/internal/repos/igris/.mcp.json`
- ✅ `/Users/fweir/git/claude/.mcp.json`

---

## 🌐 Open-WebUI Integration

### Step 1: Start mcpo Proxy Server

Create a startup script:

```bash
# /Users/fweir/git/internal/repos/carian-observatory/services/elevenlabs-mcp/start-mcpo.sh

#!/bin/bash
export ELEVENLABS_API_KEY=$(op item get "Eleven Labs - API" --fields credential --vault API --reveal)
export ELEVENLABS_DEFAULT_VOICE_ID="Sr4DTtH3Kmyd0sUrsL97"

uvx mcpo --port 8000 -- uv --directory /Users/fweir/git/external/mcp/elevenlabs-mcp run elevenlabs-mcp
```

Make it executable:
```bash
chmod +x start-mcpo.sh
```

### Step 2: Run in Background
```bash
# Start mcpo proxy
./start-mcpo.sh > /tmp/mcpo-elevenlabs.log 2>&1 &

# Check it's running
curl http://localhost:8000/docs
```

### Step 3: Configure Open-WebUI

1. Open Open-WebUI admin panel
2. Navigate to **Settings** → **Functions** → **OpenAPI**
3. Click **Add OpenAPI Server**
4. Configure:
   - **Name**: `ElevenLabs TTS`
   - **URL**: `http://localhost:8000`
   - **Headers**: (none needed)
5. Save and enable

### Step 4: Use in Open-WebUI

In chat, you can now call:
```
/openapi ElevenLabs text_to_speech "Hello from Open-WebUI"
```

Or use Tools interface in Open-WebUI.

### Docker Compose Example

```yaml
# services/elevenlabs-mcp/docker-compose.yml
version: "3.8"

services:
  elevenlabs-mcp-proxy:
    build:
      context: /Users/fweir/git/external/mcp/elevenlabs-mcp
      dockerfile: Dockerfile
    container_name: co-elevenlabs-mcp-proxy
    ports:
      - "8000:8000"
    environment:
      - ELEVENLABS_API_KEY=${ELEVENLABS_API_KEY}
      - ELEVENLABS_DEFAULT_VOICE_ID=Sr4DTtH3Kmyd0sUrsL97
    command: uvx mcpo --port 8000 --host 0.0.0.0 -- elevenlabs-mcp
    restart: unless-stopped
    networks:
      - carian-observatory_app-network

networks:
  carian-observatory_app-network:
    external: true
```

---

## 🎼 Fifth Symphony Integration

Fifth Symphony can orchestrate MCP tools via Python.

### Option A: Direct Python Integration

```python
# fifth_symphony/modules/mcp_client.py

import subprocess
import json

class MCPClient:
    def __init__(self, mcp_config_path: str):
        self.config = self._load_config(mcp_config_path)

    def _load_config(self, path: str) -> dict:
        with open(path) as f:
            return json.load(f)

    def call_tool(self, server_name: str, tool_name: str, params: dict) -> dict:
        """Call an MCP tool via stdio."""
        server_config = self.config["mcpServers"][server_name]

        # Build command
        cmd = [server_config["command"]] + server_config["args"]
        env = {**os.environ, **server_config.get("env", {})}

        # MCP request
        request = {
            "jsonrpc": "2.0",
            "method": f"tools/{tool_name}",
            "params": params,
            "id": 1
        }

        # Execute
        proc = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env
        )

        stdout, stderr = proc.communicate(json.dumps(request).encode())
        return json.loads(stdout)

# Usage example
mcp = MCPClient("/Users/fweir/git/claude/.mcp.json")
result = mcp.call_tool("elevenlabs", "text_to_speech", {
    "text": "Automation task completed successfully",
    "voice_id": "Sr4DTtH3Kmyd0sUrsL97"
})
```

### Option B: HTTP Proxy Integration

```python
# fifth_symphony/modules/elevenlabs_tts.py

import httpx

class ElevenLabsTTS:
    def __init__(self, mcpo_url: str = "http://localhost:8000"):
        self.base_url = mcpo_url
        self.client = httpx.Client()

    def speak(self, text: str, voice_id: str = "Sr4DTtH3Kmyd0sUrsL97"):
        """Generate and play speech."""
        response = self.client.post(
            f"{self.base_url}/tools/text_to_speech",
            json={
                "text": text,
                "voice_id": voice_id
            }
        )

        if response.status_code == 200:
            audio_data = response.json()
            # Save and play audio
            return audio_data
        else:
            raise Exception(f"TTS failed: {response.text}")

# Usage
tts = ElevenLabsTTS()
tts.speak("Fifth Symphony automation complete")
```

### Integration into Automation Workflows

```python
# Example: Voice feedback in automation scripts
from fifth_symphony.modules.elevenlabs_tts import ElevenLabsTTS

def deploy_service(service_name: str):
    tts = ElevenLabsTTS()

    tts.speak(f"Starting deployment of {service_name}")

    try:
        # ... deployment logic ...
        tts.speak(f"Deployment of {service_name} completed successfully")
    except Exception as e:
        tts.speak(f"Deployment failed: {str(e)}")
```

---

## 🎯 MCP Tool Reference

### Quick Tool Usage Examples

#### Text-to-Speech
```python
{
  "tool": "text_to_speech",
  "params": {
    "text": "Your text here",
    "voice_id": "Sr4DTtH3Kmyd0sUrsL97",  # Optional, uses default
    "output_path": "/path/to/output.mp3"  # Optional
  }
}
```

#### Speech-to-Text
```python
{
  "tool": "speech_to_text",
  "params": {
    "audio_path": "/path/to/audio.mp3",
    "language": "en",  # Optional
    "diarize": true    # Speaker identification
  }
}
```

#### Voice Clone
```python
{
  "tool": "voice_clone",
  "params": {
    "name": "My Voice Clone",
    "audio_paths": ["/path/to/sample1.mp3", "/path/to/sample2.mp3"],
    "description": "Professional voice clone"
  }
}
```

#### Text-to-Sound Effects
```python
{
  "tool": "text_to_sound_effects",
  "params": {
    "text": "A thunderstorm in a dense jungle with animal sounds",
    "duration_seconds": 10
  }
}
```

---

## 🔧 Troubleshooting

### MCP Server Won't Start
```bash
# Test manually
cd /Users/fweir/git/external/mcp/elevenlabs-mcp
ELEVENLABS_API_KEY=$ELEVENLABS_API_KEY uv run elevenlabs-mcp

# Check logs
tail -f ~/Library/Logs/Claude/mcp-server-elevenlabs.log  # Claude Desktop
# or check VSCodium console
```

### API Key Issues
```bash
# Verify key is loaded
echo ${ELEVENLABS_API_KEY:0:20}...

# Reload shell
source ~/.zshrc

# Test 1Password access
op item get "Eleven Labs - API" --fields credential --vault API --reveal
```

### mcpo Proxy Issues
```bash
# Check if running
lsof -i :8000

# Test endpoint
curl http://localhost:8000/docs

# View logs
tail -f /tmp/mcpo-elevenlabs.log
```

### Open-WebUI Integration Issues
1. Verify mcpo is running on port 8000
2. Check Open-WebUI can reach localhost:8000
3. Review Open-WebUI function logs
4. Test with curl first before configuring Open-WebUI

---

## 📚 Additional Resources

- [ElevenLabs MCP Server Documentation](https://github.com/elevenlabs/elevenlabs-mcp)
- [Model Context Protocol Specification](https://github.com/modelcontextprotocol)
- [mcpo (MCP-to-OpenAPI Proxy)](https://github.com/modelcontextprotocol/mcpo)
- [Open-WebUI Functions Documentation](https://docs.openwebui.com)

---

## 🚀 Next Steps

1. **Test Claude Code integration** - Ask Claude to use text_to_speech
2. **Set up mcpo proxy** - For Open-WebUI integration
3. **Create Fifth Symphony module** - For automation workflows
4. **Docker Compose setup** - For production deployment

---

**Created**: 2025-10-10
**Last Updated**: 2025-10-10
**Maintainer**: See [CLAUDE.md](CLAUDE.md) for repository guidance
