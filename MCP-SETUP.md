# MCP Setup Guide - ElevenLabs Text-to-Speech

This repository is configured to use the ElevenLabs MCP server for text-to-speech functionality within Claude Code.

## Quick Start

1. **Reload your shell** to load the API key:
   ```bash
   source ~/.zshrc
   ```

2. **Restart VSCodium** to load the MCP configuration

3. **Test the MCP tool** by asking Claude:
   ```
   Use the text_to_speech tool to say "Hello, this is Albedo v2 speaking"
   ```

## Configuration

### API Key Management
The ElevenLabs API key is retrieved from 1Password CLI:
- **Item**: "Eleven Labs - API"
- **Vault**: "API"
- **Auto-loaded**: Via `~/.zshrc` on shell startup

### Voice Configuration
- **Voice**: Albedo v2 (set via `ELEVENLABS_DEFAULT_VOICE_ID` env var)
- **Model**: Eleven Multilingual v2
- **Settings**:
  - Stability: 50%
  - Similarity: 75%
  - Style Exaggeration: 30%
  - Speaker Boost: Enabled

### MCP Server Configuration
Location: [`.mcp.json`](.mcp.json)

```json
{
  "mcpServers": {
    "elevenlabs": {
      "type": "stdio",
      "command": "uv",
      "args": [
        "--directory",
        "${env:GIT_ROOT}/external/mcp/elevenlabs-mcp",
        "run",
        "elevenlabs-mcp"
      ],
      "env": {
        "ELEVENLABS_API_KEY": "${env:ELEVENLABS_API_KEY}",
        "ELEVENLABS_DEFAULT_VOICE_ID": "${env:ELEVENLABS_DEFAULT_VOICE_ID}"
      }
    }
  }
}
```

## Available MCP Tools

The ElevenLabs MCP server provides these tools:

### 🔊 Core TTS Tools
- **`text_to_speech`** - Convert text to speech (Albedo v2 voice)
- **`speech_to_text`** - Transcribe audio to text
- **`text_to_sound_effects`** - Generate sound effects from descriptions
- **`speech_to_speech`** - Convert speech with different voice characteristics

### 🎤 Voice Management
- **`search_voices`** - Find available voices
- **`get_voice`** - Get details of a specific voice
- **`voice_clone`** - Clone a voice from audio samples
- **`text_to_voice`** - Design a new voice from text description
- **`create_voice_from_preview`** - Create voice from preview

### 🎭 Conversational AI
- **`create_agent`** - Create conversational AI agent
- **`list_agents`** - List all agents
- **`get_agent`** - Get agent details
- **`add_knowledge_base_to_agent`** - Add knowledge base to agent
- **`get_conversation`** - Get conversation details
- **`list_conversations`** - List all conversations
- **`make_outbound_call`** - Make phone call with AI agent

### 🔧 Utility Tools
- **`list_models`** - List available TTS models
- **`isolate_audio`** - Remove background noise from audio
- **`check_subscription`** - Check API subscription status

## Usage Examples

### Basic Text-to-Speech
```
Use text_to_speech to say: "The deployment is complete and all tests are passing"
```

### With Audio Summary Pattern
```
Generate audio for this summary:

Audio Summary: Successfully implemented YubiKey enforcement across all git operations.
The system now requires physical hardware tap before any network operations can proceed.
```

### Search for Voices
```
Search for voices that sound like "wise old wizard"
```

### Check Subscription
```
Check my ElevenLabs subscription status
```

## Troubleshooting

### MCP Server Not Loading
1. Verify API key is loaded:
   ```bash
   echo ${ELEVENLABS_API_KEY:0:20}...
   ```
   Should show: `sk_xxxxxxxxxxxx...`

2. Test MCP server manually:
   ```bash
   cd $GIT_ROOT/external/mcp/elevenlabs-mcp
   ELEVENLABS_API_KEY=$ELEVENLABS_API_KEY uv run elevenlabs-mcp
   ```

3. Check VSCodium MCP logs:
   - Open Command Palette (Cmd+Shift+P)
   - Search for "MCP: Show Logs"

### API Key Not Found
```bash
# Reload shell configuration
source ~/.zshrc

# Test 1Password CLI access
op item get "Eleven Labs - API" --fields credential --vault API --reveal
```

### Wrong Voice Being Used
The default voice is set in `.mcp.json` as `ELEVENLABS_DEFAULT_VOICE_ID`.
You can override it per-call by specifying voice_id in the tool parameters.

## Manual Fallback

If MCP is not working, use the manual `speak` command:
```bash
speak "Your text here"
pbpaste | speak
```

## Integration with Other Tools

### Claude Orchestrator
Copy `.mcp.json` to `$GIT_ROOT/claude/.mcp.json`

### Fifth Symphony
MCP can be integrated into automation workflows via Python:
```python
# Future integration example
from fifth_symphony import mcp_client
mcp_client.call_tool("elevenlabs", "text_to_speech", {"text": "Task complete"})
```

### Open-WebUI
MCP servers can be exposed via HTTP using `mcpo` proxy:
```bash
uvx mcpo --port 8000 -- uv --directory /path/to/elevenlabs-mcp run elevenlabs-mcp
# Then add http://localhost:8000 as OpenAPI server in Open-WebUI
```

## Related Files

- [.mcp.json](.mcp.json) - MCP server configuration
- [~/.zshrc](~/.zshrc) - Environment variables and API key loading
- [MCP Server Source]($GIT_ROOT/external/mcp/elevenlabs-mcp) - ElevenLabs MCP implementation

## Security Notes

- ✅ API key retrieved from 1Password (secure, auditable)
- ✅ No hardcoded credentials in repository
- ✅ Environment variable expansion in MCP config
- ⚠️ `.mcp.json` contains paths but no secrets (safe to commit)
- 🔒 Ensure `~/.zshrc` is not committed (contains service account token)

---

**Next Steps:**
1. Restart VSCodium to load MCP server
2. Test with: "Use text_to_speech to introduce yourself as Albedo"
3. Experiment with other MCP tools for voice cloning and sound effects
