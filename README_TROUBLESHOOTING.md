# Troubleshooting Ollama API Issues

This guide will help you troubleshoot issues with the Ollama API in the script2readme tool.

## Using the Troubleshooting Script

I've created a dedicated troubleshooting script that collects detailed debug information about Ollama API requests and responses.

```bash
# Make the script executable if needed
chmod +x ./ollama_troubleshoot.sh

# Run the script and follow the interactive prompts
./ollama_troubleshoot.sh

# Or specify a model directly
./ollama_troubleshoot.sh codellama:7b
```

The script will:
1. Check if Ollama is running
2. Collect system information
3. Create a simple test request to the API
4. Log the request and response with detailed tracing
5. Package all debug info into a tarball for analysis

## Debugging Tips

### Known Issues and Workarounds

1. **Issue**: Some models like deepseek-coder:latest don't respond correctly to the API request.
   **Workaround**: Use qwen2.5-coder:7b which has better reliability.

2. **Issue**: JSON content may not be properly parsed from the Ollama API response.
   **Workaround**: The script includes multiple fallback methods for extracting content.

### Manual Troubleshooting

If you want to manually test the Ollama API, you can use curl:

```bash
# Create a simple test file
cat > test_request.json << EOF
{
  "model": "MODEL_NAME",
  "messages": [
    {
      "role": "system",
      "content": "You are a helpful assistant."
    },
    {
      "role": "user",
      "content": "Write a hello world program."
    }
  ],
  "stream": false
}
EOF

# Replace MODEL_NAME with your desired model
sed -i '' 's/MODEL_NAME/qwen2.5-coder:7b/g' test_request.json

# Send the request
curl -v -X POST http://localhost:11434/api/chat \
  -H "Content-Type: application/json" \
  -d @test_request.json > response.json

# Check the response
cat response.json
```

## Interpreting Results

When looking at the debug tarball, check:

1. `curl_trace.log` - Shows the full HTTP request and response, including headers.
2. `request_payload.json` - The exact JSON sent to the API.
3. `response_payload.json` - The raw response from the API.
4. `ollama_debug_*.log` - Comprehensive log of all operations performed.

## Common Problems

1. **Empty or malformed responses**: Some models may return unexpected response formats.
2. **Timeout issues**: Large models may take too long to respond and trigger timeouts.
3. **JSON escaping problems**: Special characters in the script content may cause JSON parsing issues.
4. **Model-specific quirks**: Each model has different behavior and limitations.

## Reporting Issues

If you've collected debug information using the script, you can:

1. Share the tarball with Claude for analysis
2. File an issue in the Ollama GitHub repository
3. Contact the model provider for model-specific issues

## Compatible Models

Based on testing, the following models show good compatibility:
- qwen2.5-coder:7b ✅ (most reliable)
- deepseek-coder:6.7b ⚠️ (sometimes works)
- codellama:7b ⚠️ (sometimes works)