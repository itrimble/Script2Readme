#!/bin/zsh

# Enable debug mode only when explicitly requested
if [[ "$1" == "--debug" ]]; then
  set -x
  shift
fi

# =================== CONFIGURATION ===================
BENCHMARK_DIR="${HOME}/ollama_benchmarks"
SESSION_ID=$(date +%Y%m%d_%H%M%S)_$(openssl rand -hex 4)
BENCHMARK_LOG="${BENCHMARK_DIR}/benchmark_log.csv"
METRICS_LOG="${BENCHMARK_DIR}/metrics_${SESSION_ID}.json"
README="$(pwd)/README.md"
OLLAMA_API="http://localhost:11434/api/chat"

# Create benchmark directory if it doesn't exist
mkdir -p "${BENCHMARK_DIR}"

# Initialize benchmark file if it doesn't exist
if [ ! -f "${BENCHMARK_LOG}" ]; then
  echo "timestamp,session_id,script_name,script_size_bytes,script_lines,script_chars,model,operation,duration,tokens,cpu_usage,memory_usage" > "${BENCHMARK_LOG}"
fi

# Initialize metrics JSON log
echo "{\"session_id\": \"${SESSION_ID}\", \"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\", \"metrics\": []}" > "${METRICS_LOG}"

# =================== HELPER FUNCTIONS ===================
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
  
  echo "═════════════════════════════════════════════════"
  echo "📊 BENCHMARK SUMMARY FOR ${script_name}"
  echo "═════════════════════════════════════════════════"
  echo "🤖 Model: ${model}"
  echo "⏱️  Total analysis time: ${total_time}s"
  echo "🔄 API request time: ${api_time}s"
  echo "🔍 Response parsing time: ${parse_time}s"
  echo "📝 Response size: ~${token_count} words"
  echo "📂 Script metrics:"
  echo "   - Size: ${script_size} bytes ($(printf "%.2f" $(echo "scale=2; ${script_size}/1024" | bc)) KB)"
  echo "   - Lines: ${script_lines}"
  echo "   - Characters: ${script_chars}"
  echo "═════════════════════════════════════════════════"
  echo "📋 Session ID: ${SESSION_ID}"
  echo "📊 Detailed metrics saved to: ${METRICS_LOG}"
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
  
  echo "Available models: ${models[@]}"
}

# Function to select a model
select_model() {
  local start_time=$(date +%s.%N)
  
  # If a model is provided as an argument, use it
  if [ $# -ge 2 ]; then
    local provided_model="$2"
    if [[ " ${models[@]} " =~ " ${provided_model} " ]]; then
      model="$provided_model"
    else
      echo "Model '$provided_model' not found in available models: ${models[@]}"
      exit 1
    fi
  elif is_terminal; then
    # Interactive selection if terminal is available
    echo "Select a model:"
    select model in "${models[@]}"; do
      if [ -n "$model" ]; then
        break
      fi
    done
  else
    # Non-interactive: default to the first model
    model="${models[1]}"
    echo "No terminal available for interactive selection. Defaulting to first model: ${model}"
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
    sh)
      # Validate as shell script
      if ! echo "${CONTENT}" | grep -qE "^#!/bin/(bash|zsh|sh)"; then
        echo "Warning: Input does not appear to be a valid shell script (missing shebang)."
      fi
      SCRIPT_TYPE="shell"
      ;;
    scpt)
      # Read content for AppleScript
      SCRIPT_TYPE="applescript"
      ;;
    *)
      echo "Unsupported file type: ${ext}"
      exit 1
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

# Function to analyze script with Ollama
analyze_script() {
  local input="$1"
  local model="$2"
  local script_basename=$(basename "${input}")
  local start_time=$(date +%s.%N)
  
  echo "Analyzing script with ${model}..."
  
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
          "content": "You are an expert code analyst tasked with producing professional, accurate, and comprehensive documentation. Analyze the provided macOS \($script_type) script with precision, describing only the functionality explicitly present in the code. Generate a detailed Markdown README section that is clear, thorough, and professionally structured, suitable for developers and end-users."
        },
        {
          "role": "user",
          "content": "Analyze the following macOS \($script_type) script provided as plain text. Pay close attention to macOS-specific elements such as references to applications, system paths, and command-line tools. Consider the script'\''s potential impact on the system.\n\nGenerate a Markdown README section with these sections:\n\n- **Overview**: Summarize the script'\''s purpose and primary actions.\n- **Requirements**: List prerequisites inferred from the script.\n- **Usage**: Provide precise instructions for running the script.\n- **What the Script Does**: Describe the script'\''s operations step-by-step.\n- **Important Notes**: Highlight critical details derived from the script.\n- **Disclaimer**: Warn about risks of running the script.\n\nFile: \($filename)\n\nScript Content:\n\($content)"
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
  
  # Send the request
  curl -s -X POST "${OLLAMA_API}" \
    -H "Content-Type: application/json" \
    -d "${payload}" > "${temp_response}"
  
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
  
  # Update README.md (without benchmarking info)
  echo "Updating README.md..."
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  
  {
    echo -e "\n## ${script_basename} (Model: ${model}, Time: ${timestamp})\n${RESPONSE}\n"
    echo -e "### License\nThis script is provided under the MIT License.\n"
  } >> "${README}"
  
  echo "README.md updated for ${script_basename}"
  
  local end_time=$(date +%s.%N)
  local total_duration=$(printf "%.2f" $(echo "${end_time} - ${start_time}" | bc))
  
  # Log total analysis time
  log_benchmark "${script_basename}" "${FILE_SIZE}" "${LINE_COUNT}" "${CHAR_COUNT}" "${model}" "total_analysis" "${total_duration}" "${response_word_count}"
  
  # Generate benchmark summary
  generate_benchmark_summary "${model}" "${script_basename}" "${total_duration}" "${request_duration}" "${parse_duration}" "${FILE_SIZE}" "${LINE_COUNT}" "${CHAR_COUNT}" "${response_word_count}"
  
  # Add final timestamp to metrics log
  jq --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" '.completion_timestamp = $ts' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
  
  return 0
}

# =================== MAIN SCRIPT ===================

# Start timer for overall execution
SCRIPT_START_TIME=$(date +%s.%N)

# Get system information
get_system_info

# Input handling
if [ $# -lt 1 ]; then
  echo "Usage: $0 [--debug] <input_file> [model]"
  exit 1
fi

INPUT="$1"
echo "Input file: ${INPUT}"

# Check dependencies
check_dependencies || exit 1

# Get available models
get_models

# Select model and analyze
select_model "$@"
validate_input_file "${INPUT}"
analyze_script "${INPUT}" "${model}"

# End timer for overall execution
SCRIPT_END_TIME=$(date +%s.%N)
TOTAL_EXECUTION_TIME=$(printf "%.2f" $(echo "${SCRIPT_END_TIME} - ${SCRIPT_START_TIME}" | bc))

log_benchmark "${INPUT}" "${FILE_SIZE}" "${LINE_COUNT}" "${CHAR_COUNT}" "${model}" "script_execution" "${TOTAL_EXECUTION_TIME}" "0"

echo "Script completed in ${TOTAL_EXECUTION_TIME} seconds"
echo "Detailed metrics saved to:"
echo "- CSV log: ${BENCHMARK_LOG}"
echo "- JSON metrics: ${METRICS_LOG}"
echo "- Response: ${BENCHMARK_DIR}/response_${SESSION_ID}.md"