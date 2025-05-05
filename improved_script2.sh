#!/bin/zsh
#
# script2readme.sh - Generate README documentation from scripts using Ollama models
# Author: Ian Trimble
# Created: April 28, 2025
# Version: 1.1.0
#

# Enable debug mode only when explicitly requested
if [[ "$1" == "--debug" ]]; then
  set -x
  shift
fi

# =================== CONFIGURATION ===================
# App information
APP_NAME="Script to README Generator"
APP_VERSION="1.1.0"
APP_AUTHOR="Ian Trimble"

# Directory structure
BENCHMARK_DIR="${HOME}/ollama_benchmarks"
SESSION_ID=$(date +%Y%m%d_%H%M%S)_$(openssl rand -hex 4)
BENCHMARK_LOG="${BENCHMARK_DIR}/benchmark_log.csv"
METRICS_LOG="${BENCHMARK_DIR}/metrics_${SESSION_ID}.json"
CHANGELOG="${BENCHMARK_DIR}/changelog.md"
README="$(pwd)/README.md"
OLLAMA_API="http://localhost:11434/api/chat"

# Default model (can be overridden)
DEFAULT_MODEL="qwen2.5:1.5b"

# Model complexity factors (for time estimation)
declare -A MODEL_COMPLEXITY
MODEL_COMPLEXITY["qwen2.5:1.5b"]=1.0
MODEL_COMPLEXITY["qwen2.5-coder:7b"]=3.5
MODEL_COMPLEXITY["deepseek-coder:6.7b"]=3.0
MODEL_COMPLEXITY["codellama:7b"]=3.0
MODEL_COMPLEXITY["codellama:13b"]=5.5
# Default for unknown models
MODEL_COMPLEXITY["default"]=2.5

# Create benchmark directory if it doesn't exist
mkdir -p "${BENCHMARK_DIR}"

# Initialize benchmark file if it doesn't exist
if [ ! -f "${BENCHMARK_LOG}" ]; then
  echo "timestamp,session_id,script_name,script_size_bytes,script_lines,script_chars,model,operation,duration,tokens,cpu_usage,memory_usage" > "${BENCHMARK_LOG}"
fi

# Initialize changelog if it doesn't exist
if [ ! -f "${CHANGELOG}" ]; then
  {
    echo "# Script to README Generator Changelog"
    echo ""
    echo "## Version 1.1.0 - $(date '+%Y-%m-%d')"
    echo "- Initial release"
    echo "- Added benchmarking capabilities"
    echo "- Added time estimation feature"
    echo "- Added model selection"
    echo "- Added detailed metrics tracking"
  } > "${CHANGELOG}"
else
  # Check if version entry exists, add if not
  if ! grep -q "## Version ${APP_VERSION}" "${CHANGELOG}"; then
    sed -i '' "1a\\
\\
## Version ${APP_VERSION} - $(date '+%Y-%m-%d')\\
- Added completion time estimation\\
- Renamed script to better reflect purpose\\
- Enhanced error handling\\
- Added compatibility with more script types
" "${CHANGELOG}"
  fi
fi

# Initialize metrics JSON log
echo "{\"session_id\": \"${SESSION_ID}\", \"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\", \"app_version\": \"${APP_VERSION}\", \"metrics\": []}" > "${METRICS_LOG}"

# =================== HELPER FUNCTIONS ===================
# Function to display progress
display_progress() {
  local progress=$1
  local duration=$2
  local width=50
  local filled=$((width * progress / 100))
  local empty=$((width - filled))
  
  # Create the progress bar
  printf "\r["
  printf "%${filled}s" '' | tr ' ' '='
  printf ">"
  printf "%${empty}s" '' | tr ' ' ' '
  printf "] %3d%% (%s)" $progress "$duration"
}

# Function to estimate completion time
estimate_completion_time() {
  local script_size=$1
  local model=$2
  
  # Get model complexity factor
  local complexity=${MODEL_COMPLEXITY[$model]}
  if [ -z "$complexity" ]; then
    complexity=${MODEL_COMPLEXITY["default"]}
  fi
  
  # Base time in seconds per KB for a standard model
  local base_time=3
  
  # Adjust based on script size (larger scripts may take disproportionately longer)
  local size_factor=$(printf "%.2f" $(echo "scale=2; ($script_size / 1024) ^ 0.7" | bc))
  
  # Calculate estimated seconds
  local estimate=$(printf "%.0f" $(echo "scale=0; $base_time * $size_factor * $complexity" | bc))
  
  # Ensure minimum reasonable time
  if [ $estimate -lt 10 ]; then
    estimate=10
  fi
  
  echo $estimate
}

# Function to format time in human-readable format
format_time() {
  local seconds=$1
  local minutes=$((seconds / 60))
  local remaining_seconds=$((seconds % 60))
  
  if [ $minutes -gt 0 ]; then
    echo "${minutes}m ${remaining_seconds}s"
  else
    echo "${seconds}s"
  fi
}

# Function to display usage information
show_usage() {
  echo "${APP_NAME} (v${APP_VERSION})"
  echo "Generates README documentation from script files using Ollama models"
  echo ""
  echo "Usage: $0 [OPTIONS] <input_file> [model]"
  echo ""
  echo "Options:"
  echo "  --debug                Enable debug mode"
  echo "  --help                 Show this help message"
  echo "  --list-models          List available Ollama models"
  echo "  --version              Show version information"
  echo "  --no-estimate          Skip time estimation"
  echo ""
  echo "Arguments:"
  echo "  <input_file>           Path to script file to document"
  echo "  [model]                Optional Ollama model name (default: ${DEFAULT_MODEL})"
  echo ""
  echo "Example:"
  echo "  $0 my_script.sh"
  echo "  $0 my_script.sh codellama:7b"
  echo ""
  echo "Output:"
  echo "  - Updates README.md in the current directory with script documentation"
  echo "  - Logs performance metrics and benchmarks"
  echo ""
  exit 0
}

# Function to display version information
show_version() {
  echo "${APP_NAME} v${APP_VERSION}"
  echo "Author: ${APP_AUTHOR}"
  echo "Created: April 28, 2025"
  exit 0
}

# Function to get system information
get_system_info() {
  local cpu_info=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown")
  local memory_info=$(sysctl -n hw.memsize 2>/dev/null | awk '{print int($1/1024/1024/1024) " GB"}' || echo "Unknown")
  local os_info=$(sw_vers -productVersion 2>/dev/null || echo "Unknown")
  local ollama_version=$(ollama --version 2>/dev/null || echo "Unknown")
  
  # Add system info to metrics log
  jq --arg cpu "${cpu_info}" \
     --arg mem "${memory_info}" \
     --arg os "${os_info}" \
     --arg ollama "${ollama_version}" \
     '.system_info = {"cpu": $cpu, "memory": $mem, "os": $os, "ollama_version": $ollama}' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
  
  echo "System Info: CPU: ${cpu_info}, Memory: ${memory_info}, OS: ${os_info}, Ollama: ${ollama_version}"
}

# Function to get current resource usage
get_resource_usage() {
  local cpu_usage=$(ps -o %cpu= -p $$ | awk '{print $1}')
  local memory_usage=$(ps -o rss= -p $$ | awk '{print int($1/1024) " MB"}')
  
  echo "${cpu_usage},${memory_usage}"
}

# Function to log benchmark data
log_benchmark() {
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local script_name=$1
  local script_size=$2
  local script_lines=$3
  local script_chars=$4
  local model=$5
  local operation=$6
  local duration=$7
  local token_count=$8
  
  # Get resource usage
  local resource_usage=$(get_resource_usage)
  local cpu_usage=$(echo ${resource_usage} | cut -d, -f1)
  local memory_usage=$(echo ${resource_usage} | cut -d, -f2)
  
  # Log to CSV for detailed data
  echo "${timestamp},${SESSION_ID},${script_name},${script_size},${script_lines},${script_chars},${model},${operation},${duration},${token_count},${cpu_usage},${memory_usage}" >> "${BENCHMARK_LOG}"
  
  # Add metric to JSON log
  jq --arg timestamp "${timestamp}" \
     --arg script "${script_name}" \
     --arg size "${script_size}" \
     --arg lines "${script_lines}" \
     --arg chars "${script_chars}" \
     --arg model "${model}" \
     --arg op "${operation}" \
     --arg dur "${duration}" \
     --arg tokens "${token_count}" \
     --arg cpu "${cpu_usage}" \
     --arg mem "${memory_usage}" \
     '.metrics += [{"timestamp": $timestamp, "script": $script, "size_bytes": $size, "line_count": $lines, "char_count": $chars, "model": $model, "operation": $op, "duration": $dur, "token_count": $tokens, "cpu_usage": $cpu, "memory_usage": $mem}]' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
  
  # Return for chaining
  echo "${operation}:${duration}"
}

# Function to generate a benchmark summary
generate_benchmark_summary() {
  local model=$1
  local script_name=$2
  local total_time=$3
  local api_time=$4
  local parse_time=$5
  local script_size=$6
  local script_lines=$7
  local script_chars=$8
  local token_count=$9
  local estimated_time=${10}
  
  echo "═════════════════════════════════════════════════"
  echo "📊 README GENERATION COMPLETE"
  echo "═════════════════════════════════════════════════"
  echo "📄 Script: ${script_name}"
  echo "🤖 Model: ${model}"
  echo "⏱️  Total time: ${total_time}s"
  if [ -n "$estimated_time" ]; then
    local accuracy=$(printf "%.1f" $(echo "scale=1; $estimated_time / $total_time * 100" | bc))
    echo "🔮 Estimated vs Actual: ${estimated_time}s vs ${total_time}s (${accuracy}% accuracy)"
  fi
  echo "🔄 API request time: ${api_time}s"
  echo "🔍 Response parse time: ${parse_time}s"
  echo "📝 Response size: ~${token_count} words"
  echo "📂 Script metrics:"
  echo "   - Size: ${script_size} bytes ($(printf "%.2f" $(echo "scale=2; ${script_size}/1024" | bc)) KB)"
  echo "   - Lines: ${script_lines}"
  echo "   - Characters: ${script_chars}"
  echo "═════════════════════════════════════════════════"
  echo "📋 Session ID: ${SESSION_ID}"
  echo "📊 Detailed metrics saved to: ${METRICS_LOG}"
}

# Function to update the changelog
update_changelog() {
  local script_name=$1
  local model=$2
  local duration=$3
  
  # Get the current date
  local today=$(date '+%Y-%m-%d')
  
  # Check if there's already an entry for today
  if grep -q "### ${today}" "${CHANGELOG}"; then
    # Append to today's entry
    sed -i '' "/### ${today}/a\\
- Generated README for ${script_name} with ${model} (${duration}s)
" "${CHANGELOG}"
  else
    # Create a new entry for today
    sed -i '' "/^## Version/a\\
\\
### ${today}\\
- Generated README for ${script_name} with ${model} (${duration}s)
" "${CHANGELOG}"
  fi
}

# Function to check if running in a terminal
is_terminal() {
  [ -t 0 ]
}

# Function to count script features
count_script_features() {
  local content="$1"
  
  # Count functions (very basic, may need refinement)
  local function_count=$(echo "${content}" | grep -c "function " || echo "0")
  
  # Count commands (very rough estimate)
  local command_count=$(echo "${content}" | grep -v "^#" | grep -v "^$" | grep -c ";" || echo "0")
  
  # Count conditionals
  local if_count=$(echo "${content}" | grep -c "if " || echo "0")
  local case_count=$(echo "${content}" | grep -c "case " || echo "0")
  
  # Count loops
  local for_count=$(echo "${content}" | grep -c "for " || echo "0")
  local while_count=$(echo "${content}" | grep -c "while " || echo "0")
  
  # Add features to metrics log
  jq --arg functions "${function_count}" \
     --arg commands "${command_count}" \
     --arg ifs "${if_count}" \
     --arg cases "${case_count}" \
     --arg fors "${for_count}" \
     --arg whiles "${while_count}" \
     '.script_features = {"function_count": $functions, "command_count": $commands, "if_count": $ifs, "case_count": $cases, "for_count": $fors, "while_count": $whiles}' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
}

# Function to check for dependencies
check_dependencies() {
  local missing_deps=0
  
  # Start timer
  local start_time=$(date +%s.%N)
  
  # Check for jq
  if ! command -v jq &> /dev/null; then
    echo "Error: jq is required. Please install jq (e.g., 'brew install jq')."
    missing_deps=1
  fi
  
  # Check for bc
  if ! command -v bc &> /dev/null; then
    echo "Error: bc is required. Please install bc."
    missing_deps=1
  fi
  
  # Check for ollama
  if ! command -v ollama &> /dev/null; then
    echo "Error: ollama is required. Please install Ollama."
    missing_deps=1
  else
    # Check if Ollama server is running
    if ! curl -s -m 2 "http://localhost:11434/api/tags" &> /dev/null; then
      echo "Error: Ollama server is not running. Please start it with 'ollama serve'."
      missing_deps=1
    fi
  fi
  
  # End timer
  local end_time=$(date +%s.%N)
  local duration=$(printf "%.2f" $(echo "${end_time} - ${start_time}" | bc))
  
  log_benchmark "system" "0" "0" "0" "system" "dependency_check" "${duration}" "0"
  
  return ${missing_deps}
}

# Function to get available models
get_models() {
  local start_time=$(date +%s.%N)
  
  echo "Fetching available models..."
  local ollama_output=$(ollama list 2>/dev/null)
  
  if [ $? -ne 0 ]; then
    echo "Error: Failed to run 'ollama list'. Ensure Ollama is running."
    exit 1
  fi
  
  # Parse models
  models=($(echo "$ollama_output" | tail -n +2 | awk '{print $1}'))
  model_ids=($(echo "$ollama_output" | tail -n +2 | awk '{print $2}'))
  model_sizes=($(echo "$ollama_output" | tail -n +2 | awk '{print $3, $4}'))
  
  if [ ${#models[@]} -eq 0 ]; then
    echo "No models found. Please download a model using 'ollama pull <model>'."
    exit 1
  fi
  
  # Add models to metrics log
  local models_json="["
  for ((i=1; i<=${#models[@]}; i++)); do
    models_json+="\"${models[$i]}\""
    if [ $i -lt ${#models[@]} ]; then
      models_json+=","
    fi
  done
  models_json+="]"
  
  jq --argjson models "${models_json}" '.available_models = $models' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
  
  local end_time=$(date +%s.%N)
  local duration=$(printf "%.2f" $(echo "${end_time} - ${start_time}" | bc))
  
  log_benchmark "system" "0" "0" "0" "system" "fetch_models" "${duration}" "${#models[@]}"
  
  # Just list models if that's what was requested
  if [[ "$1" == "--list" ]]; then
    echo "Available Ollama models for README generation:"
    printf "%-30s %-15s %-15s\n" "MODEL" "SIZE" "EST. SPEED"
    printf "%-30s %-15s %-15s\n" "-----" "----" "---------"
    for ((i=1; i<=${#models[@]}; i++)); do
      local model_name="${models[$i]}"
      local model_size="${model_sizes[$i]}"
      
      # Get complexity factor for speed estimation
      local complexity=${MODEL_COMPLEXITY[$model_name]}
      if [ -z "$complexity" ]; then
        complexity=${MODEL_COMPLEXITY["default"]}
      fi
      
      # Calculate relative speed
      local speed=""
      if (( $(echo "$complexity < 1.5" | bc -l) )); then
        speed="Very Fast"
      elif (( $(echo "$complexity < 2.5" | bc -l) )); then
        speed="Fast"
      elif (( $(echo "$complexity < 4.0" | bc -l) )); then
        speed="Medium"
      else
        speed="Slow"
      fi
      
      printf "%-30s %-15s %-15s\n" "$model_name" "$model_size" "$speed"
    done
    exit 0
  fi
  
  echo "Available models: ${models[@]}"
}

# Function to select a model
select_model() {
  local start_time=$(date +%s.%N)
  
  # If a model is provided as an argument, use it
  if [ $# -ge 2 ]; then
    local provided_model="$2"
    # Check if the model is available
    if ollama list | grep -q "${provided_model}"; then
      model="${provided_model}"
    else
      echo "Warning: Model '$provided_model' not found in available models."
      echo "Pulling the model..."
      ollama pull "${provided_model}"
      if [ $? -ne 0 ]; then
        echo "Error: Failed to pull model '${provided_model}'. Using default model: ${DEFAULT_MODEL}"
        model="${DEFAULT_MODEL}"
      else
        model="${provided_model}"
      fi
    fi
  elif is_terminal; then
    # Interactive selection if terminal is available
    echo "Select a model for README generation:"
    printf "%-5s %-30s %-15s %-15s\n" "NUM" "MODEL" "SIZE" "EST. SPEED"
    printf "%-5s %-30s %-15s %-15s\n" "---" "-----" "----" "---------"
    for ((i=1; i<=${#models[@]}; i++)); do
      local model_name="${models[$i]}"
      local model_size="${model_sizes[$i]}"
      
      # Get complexity factor for speed estimation
      local complexity=${MODEL_COMPLEXITY[$model_name]}
      if [ -z "$complexity" ]; then
        complexity=${MODEL_COMPLEXITY["default"]}
      fi
      
      # Calculate relative speed
      local speed=""
      if (( $(echo "$complexity < 1.5" | bc -l) )); then
        speed="Very Fast"
      elif (( $(echo "$complexity < 2.5" | bc -l) )); then
        speed="Fast"
      elif (( $(echo "$complexity < 4.0" | bc -l) )); then
        speed="Medium"
      else
        speed="Slow"
      fi
      
      printf "%-5s %-30s %-15s %-15s\n" "$i" "$model_name" "$model_size" "$speed"
    done
    echo ""
    echo "Enter the number of the model to use:"
    read model_num
    
    if [[ "$model_num" =~ ^[0-9]+$ ]] && [ "$model_num" -ge 1 ] && [ "$model_num" -le ${#models[@]} ]; then
      model="${models[$model_num]}"
    else
      echo "Invalid selection. Using default model: ${DEFAULT_MODEL}"
      model="${DEFAULT_MODEL}"
    fi
  else
    # Non-interactive: use the default model
    model="${DEFAULT_MODEL}"
    echo "No terminal available for interactive selection. Using default model: ${model}"
  fi
  
  local end_time=$(date +%s.%N)
  local duration=$(printf "%.2f" $(echo "${end_time} - ${start_time}" | bc))
  
  log_benchmark "${INPUT}" "0" "0" "0" "${model}" "model_selection" "${duration}" "0"
  
  # Record the selected model
  jq --arg model "${model}" '.selected_model = $model' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
  
  echo "Selected model: ${model}"
}

# Function to validate input file
validate_input_file() {
  local input="$1"
  local start_time=$(date +%s.%N)
  
  if [ ! -f "${input}" ]; then
    echo "Error: Input file '${input}' does not exist."
    exit 1
  fi
  
  # Get file stats
  local file_size=$(stat -f%z "${input}")
  CONTENT=$(cat "${input}")
  local line_count=$(echo "${CONTENT}" | wc -l | tr -d ' ')
  local char_count=$(echo "${CONTENT}" | wc -c | tr -d ' ')
  
  # Record file metrics
  jq --arg file "${input}" \
     --arg size "${file_size}" \
     --arg lines "${line_count}" \
     --arg chars "${char_count}" \
     '.input_file = {"path": $file, "size_bytes": $size, "line_count": $lines, "char_count": $chars}' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
  
  # Determine file extension
  ext="${input##*.}"
  
  # Check supported file types
  case "${ext}" in
    sh|bash|zsh)
      # Check if it's base64 encoded (from legacy code)
      if echo "$CONTENT" | grep -qE '^[A-Za-z0-9+/=]+$'; then
        # Attempt to decode as base64
        local DECODED_CONTENT=$(echo "$CONTENT" | base64 -d 2>/dev/null)
        if [ $? -eq 0 ] && echo "$DECODED_CONTENT" | grep -qE "^#!/bin/(bash|zsh|sh)"; then
          CONTENT="$DECODED_CONTENT"
          echo "Input detected as base64-encoded shell script. Decoded successfully."
        else
          echo "Input appears to be base64 but failed to decode as a valid shell script. Treating as plain text."
        fi
      fi
      
      # Validate as shell script
      if ! echo "${CONTENT}" | grep -qE "^#!/bin/(bash|zsh|sh)"; then
        echo "Warning: Input does not appear to be a valid shell script (missing shebang)."
      fi
      SCRIPT_TYPE="shell"
      ;;
    scpt|applescript)
      # AppleScript
      SCRIPT_TYPE="applescript"
      ;;
    py|python)
      # Python script
      SCRIPT_TYPE="python"
      ;;
    rb|ruby)
      # Ruby script
      SCRIPT_TYPE="ruby"
      ;;
    js|javascript)
      # JavaScript
      SCRIPT_TYPE="javascript"
      ;;
    *)
      echo "Warning: Unsupported file type: ${ext}. Will attempt to analyze as generic script."
      SCRIPT_TYPE="generic"
      ;;
  esac
  
  # Count script features
  count_script_features "${CONTENT}"
  
  local end_time=$(date +%s.%N)
  local duration=$(printf "%.2f" $(echo "${end_time} - ${start_time}" | bc))
  
  log_benchmark "${input}" "${file_size}" "${line_count}" "${char_count}" "${model}" "file_validation" "${duration}" "0"
  
  # Store file metrics for later use
  FILE_SIZE="${file_size}"
  LINE_COUNT="${line_count}"
  CHAR_COUNT="${char_count}"
  
  echo "File validated: ${input} (${file_size} bytes, ${line_count} lines)"
}

# Function to generate README from script
generate_readme() {
  local input="$1"
  local model="$2"
  local skip_estimate="$3"
  local script_basename=$(basename "${input}")
  local start_time=$(date +%s.%N)
  
  echo "Generating README documentation for ${script_basename} with ${model}..."
  
  # Estimate completion time if not skipped
  local estimated_seconds=""
  if [ "$skip_estimate" != "true" ]; then
    estimated_seconds=$(estimate_completion_time "${FILE_SIZE}" "${model}")
    local estimated_time=$(format_time "${estimated_seconds}")
    echo "Estimated completion time: ${estimated_time}"
    jq --arg est "${estimated_seconds}" '.estimated_completion_time = $est' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
  fi
  
  # Create request payload
  local payload=$(jq -n \
    --arg model "${model}" \
    --arg content "${CONTENT}" \
    --arg filename "${script_basename}" \
    --arg script_type "${SCRIPT_TYPE}" \
    '{
      "model": $model,
      "messages": [
        {
          "role": "system",
          "content": "You are an expert code documentarian tasked with producing professional, accurate, and comprehensive documentation. Analyze the provided \($script_type) script with precision, describing only the functionality explicitly present in the code. Generate a detailed Markdown README section that is clear, thorough, and professionally structured, suitable for developers and end-users."
        },
        {
          "role": "user",
          "content": "Analyze the following \($script_type) script provided as plain text. Pay close attention to specific elements such as references to applications, system paths, and command-line tools. Consider the script'\''s potential impact on the system.\n\nGenerate a Markdown README section with these sections:\n\n- **Overview**: Summarize the script'\''s purpose and primary actions.\n- **Requirements**: List prerequisites inferred from the script.\n- **Usage**: Provide precise instructions for running the script.\n- **What the Script Does**: Describe the script'\''s operations step-by-step.\n- **Important Notes**: Highlight critical details derived from the script.\n- **Disclaimer**: Warn about risks of running the script.\n\nFile: \($filename)\n\nScript Content:\n\($content)"
        }
      ],
      "stream": false
    }')
  
  # Log the prompt size (in characters)
  local prompt_size=$(echo "${payload}" | jq -r '.messages[1].content' | wc -c | tr -d ' ')
  jq --arg size "${prompt_size}" '.prompt_size_chars = $size' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
  
  # Send request to Ollama API
  echo "Sending request to Ollama API..."
  local request_start_time=$(date +%s.%N)
  
  # Temporary file for response
  local temp_response=$(mktemp)
  
  # Show progress bar if estimate is available
  if [ -n "$estimated_seconds" ]; then
    # Send the request in background
    curl -s -X POST "${OLLAMA_API}" \
      -H "Content-Type: application/json" \
      -d "${payload}" > "${temp_response}" &
    
    local pid=$!
    local start_secs=$SECONDS
    local progress=0
    
    # Show progress while curl is running
    while kill -0 $pid 2>/dev/null; do
      local elapsed=$((SECONDS - start_secs))
      if [ $estimated_seconds -gt 0 ]; then
        progress=$((elapsed * 100 / estimated_seconds))
        # Cap at 99% until complete
        if [ $progress -gt 99 ]; then
          progress=99
        fi
      else
        progress=50  # Default to 50% if no estimate
      fi
      
      display_progress $progress "$(format_time $elapsed)"
      sleep 0.5
    done
    
    # Make sure curl completed successfully
    wait $pid
    if [ $? -ne 0 ]; then
      echo ""
      echo "Error: Failed to connect to Ollama API. Ensure the server is running."
      exit 1
    fi
    
    # Show 100% completion
    display_progress 100 "$(format_time $((SECONDS - start_secs)))"
    echo ""
  else
    # Regular request without progress bar
    curl -s -X POST "${OLLAMA_API}" \
      -H "Content-Type: application/json" \
      -d "${payload}" > "${temp_response}"
  fi
  
  local request_end_time=$(date +%s.%N)
  local request_duration=$(printf "%.2f" $(echo "${request_end_time} - ${request_start_time}" | bc))
  
  log_benchmark "${script_basename}" "${FILE_SIZE}" "${LINE_COUNT}" "${CHAR_COUNT}" "${model}" "api_request" "${request_duration}" "${prompt_size}"
  
  # Parse response
  echo "Processing response..."
  local parse_start_time=$(date +%s.%N)
  
  if grep -q "error" "${temp_response}"; then
    echo "Error in Ollama response:"
    cat "${temp_response}"
    jq --arg error "$(cat ${temp_response})" '.error = $error' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
    rm "${temp_response}"
    exit 1
  fi
  
  # Extract metrics from response if available
  local total_duration=$(jq -r '.total_duration // 0' "${temp_response}")
  local eval_count=$(jq -r '.eval_count // 0' "${temp_response}")
  local prompt_eval_count=$(jq -r '.prompt_eval_count // 0' "${temp_response}")
  local eval_duration=$(jq -r '.eval_duration // 0' "${temp_response}")
  local prompt_eval_duration=$(jq -r '.prompt_eval_duration // 0' "${temp_response}")
  
  # Convert to seconds if in nanoseconds
  if [ "${total_duration}" -gt 1000000000 ]; then
    total_duration=$(printf "%.2f" $(echo "scale=2; ${total_duration}/1000000000" | bc))
  fi
  
  # Add Ollama-reported metrics to log
  jq --arg total "${total_duration}" \
     --arg eval "${eval_count}" \
     --arg prompt_eval "${prompt_eval_count}" \
     --arg eval_dur "${eval_duration}" \
     --arg prompt_dur "${prompt_eval_duration}" \
     '.ollama_metrics = {"total_duration": $total, "eval_count": $eval, "prompt_eval_count": $prompt_eval, "eval_duration": $eval_dur, "prompt_eval_duration": $prompt_dur}' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
  
  # Extract response content - try different methods for compatibility
  if jq -e '.message.content' "${temp_response}" > /dev/null 2>&1; then
    RESPONSE=$(jq -r '.message.content' "${temp_response}")
  else
    # Fallback method using grep and sed
    RESPONSE=$(grep -o '"content":"[^"]*"' "${temp_response}" | sed 's/"content":"//;s/"//')
    
    # If that fails, try perl
    if [ -z "${RESPONSE}" ]; then
      RESPONSE=$(perl -0777 -ne 'print $1 if /"content":"(.*?)"/s' "${temp_response}")
    fi
  fi
  
  # If still empty, try one more approach
  if [ -z "${RESPONSE}" ]; then
    RESPONSE=$(cat "${temp_response}" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data['message']['content'])
except Exception as e:
    print(f'Error parsing JSON: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null)
  fi
  
  # Check if response is empty
  if [ -z "${RESPONSE}" ]; then
    echo "Error: Empty response from Ollama."
    echo "Raw response:"
    cat "${temp_response}"
    jq --arg error "Empty response" '.error = $error' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
    rm "${temp_response}"
    exit 1
  fi
  
  # Calculate response metrics
  local response_char_count=$(echo "${RESPONSE}" | wc -c | tr -d ' ')
  local response_line_count=$(echo "${RESPONSE}" | wc -l | tr -d ' ')
  local response_word_count=$(echo "${RESPONSE}" | wc -w | tr -d ' ')
  
  # Add response metrics to log
  jq --arg chars "${response_char_count}" \
     --arg lines "${response_line_count}" \
     --arg words "${response_word_count}" \
     '.response_metrics = {"char_count": $chars, "line_count": $lines, "word_count": $words}' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
  
  # Save the full response for analysis
  echo "${RESPONSE}" > "${BENCHMARK_DIR}/response_${SESSION_ID}.md"
  
  # Clean up
  rm "${temp_response}"
  
  local parse_end_time=$(date +%s.%N)
  local parse_duration=$(printf "%.2f" $(echo "${parse_end_time} - ${parse_start_time}" | bc))
  
  log_benchmark "${script_basename}" "${FILE_SIZE}" "${LINE_COUNT}" "${CHAR_COUNT}" "${model}" "response_parsing" "${parse_duration}" "${response_word_count}"
  
  # Update README.md (with model information)
  echo "Updating README.md..."
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  
  {
    echo -e "\n## ${script_basename} (Analyzed with ${model})"
    echo -e "#### Analysis Date: ${timestamp}"
    echo -e "${RESPONSE}\n"
    echo -e "### License"
    echo -e "This script is provided under the MIT License.\n"
    echo -e "MIT License\n"
    echo -e "Copyright (c) $(date +%Y) ${APP_AUTHOR}\n"
    echo -e "Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the \"Software\"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:\n"
    echo -e "The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.\n"
    echo -e "THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE."
  } >> "${README}"
  
  echo "README.md updated for ${script_basename}"
  
  local end_time=$(date +%s.%N)
  local total_duration=$(printf "%.2f" $(echo "${end_time} - ${start_time}" | bc))
  
  # Log total analysis time
  log_benchmark "${script_basename}" "${FILE_SIZE}" "${LINE_COUNT}" "${CHAR_COUNT}" "${model}" "total_analysis" "${total_duration}" "${response_word_count}"
  
  # Update changelog
  update_changelog "${script_basename}" "${model}" "${total_duration}"
  
  # Generate benchmark summary
  generate_benchmark_summary "${model}" "${script_basename}" "${total_duration}" "${request_duration}" "${parse_duration}" "${FILE_SIZE}" "${LINE_COUNT}" "${CHAR_COUNT}" "${response_word_count}" "${estimated_seconds}"
  
  # Add final timestamp to metrics log
  jq --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" '.completion_timestamp = $ts' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
  
  return 0
}

# =================== MAIN SCRIPT ===================

# Start timer for overall execution
SCRIPT_START_TIME=$(date +%s.%N)

# Get system information
get_system_info

# Check for options
SKIP_ESTIMATE=false

# Process command-line arguments
while [[ "$1" == --* ]]; do
  case "$1" in
    --help)
      show_usage
      ;;
    --version)
      show_version
      ;;
    --list-models)
      get_models --list
      ;;
    --no-estimate)
      SKIP_ESTIMATE=true
      shift
      ;;
    --debug)
      # Already handled at the top
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Run '$0 --help' for usage information."
      exit 1
      ;;
  esac
done

# Input handling
if [ $# -lt 1 ]; then
  echo "Error: No input file specified."
  echo "Run '$0 --help' for usage information."
  exit 1
fi

INPUT="$1"
echo "Input file: ${INPUT}"

# Check dependencies
check_dependencies || exit 1

# Get available models
get_models

# Select model and generate README
select_model "$@"
validate_input_file "${INPUT}"
generate_readme "${INPUT}" "${model}" "${SKIP_ESTIMATE}"

# End timer for overall execution
SCRIPT_END_TIME=$(date +%s.%N)
TOTAL_EXECUTION_TIME=$(printf "%.2f" $(echo "${SCRIPT_END_TIME} - ${SCRIPT_START_TIME}" | bc))

log_benchmark "${INPUT}" "${FILE_SIZE}" "${LINE_COUNT}" "${CHAR_COUNT}" "${model}" "script_execution" "${TOTAL_EXECUTION_TIME}" "0"

echo "Script completed in ${TOTAL_EXECUTION_TIME} seconds"
echo "Detailed metrics saved to:"
echo "- CSV log: ${BENCHMARK_LOG}"
echo "- JSON metrics: ${METRICS_LOG}"
echo "- Response: ${BENCHMARK_DIR}/response_${SESSION_ID}.md" 
echo "- Changelog: ${CHANGELOG}"