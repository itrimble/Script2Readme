#!/bin/zsh
#
# ollama_troubleshoot.sh - Diagnostic tool for troubleshooting Ollama API issues
# Author: Ian Trimble
# Created: April 29, 2025
#

# Enable verbose logging
set -x

# Configuration
OLLAMA_API="http://localhost:11434/api/chat"
TEMP_DIR="$(mktemp -d)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${TEMP_DIR}/ollama_debug_${TIMESTAMP}.log"
REQUEST_FILE="${TEMP_DIR}/request_payload.json"
RESPONSE_FILE="${TEMP_DIR}/response_payload.json"
CURL_LOG="${TEMP_DIR}/curl_trace.log"
SYSTEM_INFO_FILE="${TEMP_DIR}/system_info.txt"
DEBUG_ARCHIVE="${HOME}/ollama_debug_${TIMESTAMP}.tar.gz"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

# Functions
log() {
  echo -e "${BLUE}[$(date +%H:%M:%S)]${RESET} $1" | tee -a "$LOG_FILE"
}

error() {
  echo -e "${RED}[ERROR]${RESET} $1" | tee -a "$LOG_FILE"
}

success() {
  echo -e "${GREEN}[SUCCESS]${RESET} $1" | tee -a "$LOG_FILE"
}

warning() {
  echo -e "${YELLOW}[WARNING]${RESET} $1" | tee -a "$LOG_FILE"
}

cleanup() {
  log "Creating debug archive at $DEBUG_ARCHIVE"
  tar -czf "$DEBUG_ARCHIVE" -C "$(dirname "$TEMP_DIR")" "$(basename "$TEMP_DIR")"
  log "Debug information saved to $DEBUG_ARCHIVE"
  echo ""
  echo -e "${GREEN}===============================================${RESET}"
  echo -e "${GREEN}Troubleshooting complete!${RESET}"
  echo -e "${YELLOW}Please upload $DEBUG_ARCHIVE to Claude for analysis${RESET}"
  echo -e "${GREEN}===============================================${RESET}"
}

collect_system_info() {
  log "Collecting system information..."
  
  {
    echo "TIMESTAMP: $(date)"
    echo "HOSTNAME: $(hostname)"
    echo "OS: $(uname -a)"
    echo "PROCESSOR: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown")"
    echo "MEMORY: $(sysctl -n hw.memsize 2>/dev/null | awk '{print int($1/1024/1024/1024) " GB"}' || echo "Unknown")"
    echo "OLLAMA VERSION: $(ollama --version 2>/dev/null || echo "Unknown")"
    echo ""
    echo "ENVIRONMENT VARIABLES:"
    env | grep -v -i "key\|secret\|password\|token" | sort
    echo ""
    echo "NETWORK STATUS:"
    ping -c 3 localhost
    echo ""
    echo "PROCESS STATUS:"
    ps aux | grep ollama
    echo ""
    echo "DISK SPACE:"
    df -h
    echo ""
    echo "AVAILABLE MODELS:"
    ollama list
  } > "$SYSTEM_INFO_FILE" 2>&1
  
  success "System information collected"
}

check_ollama_status() {
  log "Checking if Ollama server is running..."
  
  if curl -s -m 2 "http://localhost:11434/api/tags" &> /dev/null; then
    success "Ollama server is running"
    return 0
  else
    error "Ollama server is not running. Please start it with 'ollama serve'"
    return 1
  fi
}

create_test_payload() {
  local model=$1
  local content_type=$2
  
  log "Creating test payload for model: $model"
  
  # Create a simple test prompt
  cat > "$REQUEST_FILE" <<EOF
{
  "model": "$model",
  "messages": [
    {
      "role": "system",
      "content": "You are a helpful assistant that responds in Markdown format. Keep your responses concise."
    },
    {
      "role": "user",
      "content": "Write a very short README for a Hello World program in Python."
    }
  ],
  "stream": false
}
EOF

  log "Test payload created at $REQUEST_FILE"
}

test_ollama_api() {
  local model=$1
  local content_type="${2:-application/json}"
  
  log "Testing Ollama API with model: $model (Content-Type: $content_type)"
  
  # Create test payload
  create_test_payload "$model" "$content_type"
  
  # Send request with detailed logging
  log "Sending request to Ollama API..."
  
  curl -v \
    --trace-ascii "$CURL_LOG" \
    -H "Content-Type: $content_type" \
    -H "Accept: application/json" \
    -X POST \
    --data @"$REQUEST_FILE" \
    "$OLLAMA_API" > "$RESPONSE_FILE" 2>> "$LOG_FILE"
  
  local curl_status=$?
  
  if [ $curl_status -ne 0 ]; then
    error "Curl command failed with status $curl_status"
    return 1
  fi
  
  # Check if response contains error
  if grep -q "error" "$RESPONSE_FILE"; then
    error "API returned an error"
    cat "$RESPONSE_FILE" | tee -a "$LOG_FILE"
    return 1
  fi
  
  # Check if we got content
  if grep -q "content" "$RESPONSE_FILE"; then
    success "API returned content successfully"
    # Extract just the first part of content to avoid large logs
    jq -r '.message.content | if length > 200 then (.[0:200] + "...") else . end' "$RESPONSE_FILE" | tee -a "$LOG_FILE"
    return 0
  else
    warning "API response doesn't contain expected content field"
    cat "$RESPONSE_FILE" | tee -a "$LOG_FILE"
    return 1
  fi
}

try_alternative_formats() {
  local model=$1
  
  log "Trying alternative content types for model: $model"
  
  # Try with different content types
  test_ollama_api "$model" "application/json"
  local status1=$?
  
  # Copy original response for comparison
  cp "$RESPONSE_FILE" "${RESPONSE_FILE}.json"
  
  # Try with text/plain
  test_ollama_api "$model" "text/plain"
  local status2=$?
  
  # Compare results
  if [ $status1 -eq 0 ] || [ $status2 -eq 0 ]; then
    success "At least one content type worked for model: $model"
  else
    error "All content types failed for model: $model"
  fi
}

# Main execution
main() {
  log "Starting Ollama API troubleshooting"
  log "Debug information will be saved to $DEBUG_ARCHIVE"
  
  # Make sure Ollama is running
  check_ollama_status || exit 1
  
  # Collect system information
  collect_system_info
  
  # Get available models
  readarray -t models < <(ollama list | tail -n +2 | awk '{print $1}')
  
  if [ ${#models[@]} -eq 0 ]; then
    error "No models found. Please download a model using 'ollama pull <model>'"
    exit 1
  fi
  
  log "Found ${#models[@]} models: ${models[*]}"
  
  # Select model to test
  if [ -n "$1" ]; then
    # Use provided model
    for model in "${models[@]}"; do
      if [ "$model" = "$1" ]; then
        selected_model="$1"
        break
      fi
    done
    
    if [ -z "$selected_model" ]; then
      warning "Model '$1' not found in available models. Using default."
      selected_model="${models[0]}"
    fi
  else
    # Interactive selection if no model provided
    echo "Select a model to test:"
    for ((i=0; i<${#models[@]}; i++)); do
      echo "$((i+1)). ${models[i]}"
    done
    
    echo -n "Enter number (1-${#models[@]}): "
    read selection
    
    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le ${#models[@]} ]; then
      selected_model="${models[$((selection-1))]}"
    else
      warning "Invalid selection. Using first model."
      selected_model="${models[0]}"
    fi
  fi
  
  log "Selected model for testing: $selected_model"
  
  # Test with the selected model
  try_alternative_formats "$selected_model"
  
  # Create debug archive
  cleanup
}

# Run main function with arguments
main "$@"