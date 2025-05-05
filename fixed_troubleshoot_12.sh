#!/bin/zsh

# Define log file
LOG_FILE="$HOME/ollama_troubleshoot_$(date +%Y%m%d_%H%M%S).log"

# Function to log messages with timestamps
log_message() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Start logging
log_message "Starting troubleshooting script..."

# System and environment information
log_message "=== System Information ==="
log_message "User: $(whoami)"
log_message "Shell: $SHELL"
log_message "Zsh version: $(zsh --version)"
log_message "System memory: $(sysctl -n hw.memsize | awk '{print $1/1024/1024/1024 " GiB"}')"
log_message "Available memory: $(vm_stat | grep 'Pages free' | awk '{print $3*4096/1024/1024/1024 " GiB"}')"

# Check dependencies
log_message "=== Dependency Checks ==="
log_message "Checking for jq..."
command -v jq &> /dev/null && log_message "jq found: $(command -v jq)" || log_message "jq not found"
log_message "Checking for ollama..."
command -v ollama &> /dev/null && log_message "ollama found: $(command -v ollama)" || log_message "ollama not found"
log_message "Ollama version: $(ollama --version 2>&1)"

# Ollama server status
log_message "=== Ollama Server Status ==="
log_message "Running Ollama processes:"
ps aux | grep '[o]llama' | tee -a "$LOG_FILE"
log_message "Checking if Ollama server is running on 127.0.0.1:11434..."
curl -s http://127.0.0.1:11434/api/tags > /dev/null
if [ $? -eq 0 ]; then
  log_message "Ollama server is responding"
else
  log_message "Ollama server is not responding. Attempting to start..."
  pkill ollama
  ollama serve &
  sleep 5  # Wait for server to start
  curl -s http://127.0.0.1:11434/api/tags > /dev/null
  [ $? -eq 0 ] && log_message "Ollama server started successfully" || log_message "Failed to start Ollama server"
fi

# Ollama model information
log_message "=== Ollama Model Information ==="
log_message "Model directory contents:"
ls -lh /Users/ian/.ollama/models 2>&1 | tee -a "$LOG_FILE"
ls -lh /Users/ian/.ollama/models/blobs 2>&1 | tee -a "$LOG_FILE"
log_message "Available models (ollama list):"
ollama list 2>&1 | tee -a "$LOG_FILE"
log_message "Loaded models (ollama ps):"
ollama ps 2>&1 | tee -a "$LOG_FILE"
log_message "Models via API (/api/tags):"
curl -s http://127.0.0.1:11434/api/tags | tee -a "$LOG_FILE"

# Validate sync-Brew.sh
log_message "=== Input File Validation ==="
log_message "Checking sync-Brew.sh shebang..."
head -n 1 /Users/ian/Library/Mobile\ Documents/com~apple~ScriptEditor2/Documents/sync-Brew.sh 2>&1 | tee -a "$LOG_FILE"
log_message "File permissions:"
ls -l /Users/ian/Library/Mobile\ Documents/com~apple~ScriptEditor2/Documents/sync-Brew.sh 2>&1 | tee -a "$LOG_FILE"

# Run the script
log_message "=== Running analyze_with_ollama_picker.sh ==="
cd /Users/ian/Library/Mobile\ Documents/com~apple~ScriptEditor2/Documents/
log_message "Running interactively..."
./analyze_with_ollama_picker.sh sync-Brew.sh 2>&1 | tee -a "$LOG_FILE"
log_message "Running non-interactively with deepseek-coder:6.7b..."
./analyze_with_ollama_picker.sh sync-Brew.sh deepseek-coder:6.7b 2>&1 | tee -a "$LOG_FILE"

# Check README.md
log_message "=== Checking README.md ==="
if [ -f README.md ]; then
  log_message "README.md contents (last 50 lines):"
  tail -n 50 README.md 2>&1 | tee -a "$LOG_FILE"
else
  log_message "README.md does not exist"
fi

# Final Ollama status
log_message "=== Final Ollama Status ==="
log_message "Loaded models (ollama ps):"
ollama ps 2>&1 | tee -a "$LOG_FILE"

log_message "Troubleshooting complete. Log file: $LOG_FILE"