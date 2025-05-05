#!/bin/zsh

# Enable debug mode only when explicitly requested
if [[ "$1" == "--debug" ]]; then
  set -x
  shift
fi

# =================== CONFIGURATION ===================
BENCHMARK_DIR="${HOME}/ollama_benchmarks"
RESULTS_FILE="${BENCHMARK_DIR}/ollama_model_results.md"
BENCHMARK_LOG="${BENCHMARK_DIR}/benchmark_log.csv"
README="$(pwd)/README.md"
OLLAMA_API="http://localhost:11434/api/chat"

# Create benchmark directory if it doesn't exist
mkdir -p "${BENCHMARK_DIR}"

# Initialize benchmark files if they don't exist
if [ ! -f "${BENCHMARK_LOG}" ]; then
  echo "Timestamp,Script,Model,Operation,Duration,TokenCount" > "${BENCHMARK_LOG}"
fi

if [ ! -f "${RESULTS_FILE}" ]; then
  {
    echo "# Ollama Model Analysis Results"
    echo ""
    echo "| Timestamp | Script | Model | Total Time | API Time | Parse Time |"
    echo "|-----------|--------|-------|------------|----------|------------|"
  } > "${RESULTS_FILE}"
fi

# =================== HELPER FUNCTIONS ===================
# Function to log benchmark data
log_benchmark() {
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local script_name=$1
  local model=$2
  local operation=$3
  local duration=$4
  local token_count=$5
  
  # Log to CSV for detailed data
  echo "${timestamp},${script_name},${model},${operation},${duration},${token_count}" >> "${BENCHMARK_LOG}"
  
  # Return for chaining
  echo "${operation}:${duration}"
}

# Function to add benchmark result to markdown summary
add_benchmark_result() {
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local script_name=$1
  local model=$2
  local total_time=$3
  local api_time=$4
  local parse_time=$5
  
  # Add to summary table
  echo "| ${timestamp} | ${script_name} | ${model} | ${total_time}s | ${api_time}s | ${parse_time}s |" >> "${RESULTS_FILE}"
}

# Function to check if running in a terminal
is_terminal() {
  [ -t 0 ]
}

# Function to check for dependencies
check_dependencies() {
  local missing_deps=0
  
  # Check for jq
  if ! command -v jq &> /dev/null; then
    echo "Error: jq is required. Please install jq (e.g., 'brew install jq')."
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
  
  return ${missing_deps}
}

# Function to get available models
get_models() {
  echo "Fetching available models..."
  local start_time=$(date +%s.%N)
  
  local ollama_output=$(ollama list 2>/dev/null)
  
  if [ $? -ne 0 ]; then
    echo "Error: Failed to run 'ollama list'. Ensure Ollama is running."
    exit 1
  fi
  
  # Parse models
  models=($(echo "$ollama_output" | tail -n +2 | awk '{print $1}'))
  
  if [ ${#models[@]} -eq 0 ]; then
    echo "No models found. Please download a model using 'ollama pull <model>'."
    exit 1
  fi
  
  local end_time=$(date +%s.%N)
  local duration=$(printf "%.2f" $(echo "${end_time} - ${start_time}" | bc))
  
  log_benchmark "system" "system" "fetch_models" "${duration}" "${#models[@]}"
  
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
  
  log_benchmark "${INPUT}" "${model}" "model_selection" "${duration}" "0"
  
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
  
  # Determine file extension
  ext="${input##*.}"
  
  # Check supported file types
  case "${ext}" in
    sh)
      # Read content and validate as shell script
      CONTENT=$(cat "${input}")
      if ! echo "${CONTENT}" | grep -qE "^#!/bin/(bash|zsh|sh)"; then
        echo "Error: Input does not appear to be a valid shell script (missing shebang)."
        exit 1
      fi
      SCRIPT_TYPE="shell"
      ;;
    scpt)
      # Read content for AppleScript
      CONTENT=$(cat "${input}")
      SCRIPT_TYPE="applescript"
      ;;
    *)
      echo "Unsupported file type: ${ext}"
      exit 1
      ;;
  esac
  
  local end_time=$(date +%s.%N)
  local duration=$(printf "%.2f" $(echo "${end_time} - ${start_time}" | bc))
  
  log_benchmark "${input}" "${model}" "file_validation" "${duration}" "${#CONTENT}"
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
  
  log_benchmark "${script_basename}" "${model}" "api_request" "${request_duration}" "0"
  
  # Parse response
  echo "Processing response..."
  local parse_start_time=$(date +%s.%N)
  
  if grep -q "error" "${temp_response}"; then
    echo "Error in Ollama response:"
    cat "${temp_response}"
    rm "${temp_response}"
    exit 1
  fi
  
  # Extract token counts and timing data if available
  local prompt_tokens=0
  local completion_tokens=0
  local eval_count=$(jq -r '.eval_count // 0' "${temp_response}")
  local prompt_eval_count=$(jq -r '.prompt_eval_count // 0' "${temp_response}")
  
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
    rm "${temp_response}"
    exit 1
  fi
  
  # Calculate token count estimate (very rough)
  local response_token_count=$(echo "${RESPONSE}" | wc -w)
  
  # Clean up
  rm "${temp_response}"
  
  local parse_end_time=$(date +%s.%N)
  local parse_duration=$(printf "%.2f" $(echo "${parse_end_time} - ${parse_start_time}" | bc))
  
  log_benchmark "${script_basename}" "${model}" "response_parsing" "${parse_duration}" "${response_token_count}"
  
  # Update README.md
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
  log_benchmark "${script_basename}" "${model}" "total_analysis" "${total_duration}" "${response_token_count}"
  
  # Add benchmark summary
  add_benchmark_result "${script_basename}" "${model}" "${total_duration}" "${request_duration}" "${parse_duration}"
  
  # Show benchmark summary
  echo "═════════════════════════════════════════════════"
  echo "📊 BENCHMARK SUMMARY FOR ${script_basename}"
  echo "═════════════════════════════════════════════════"
  echo "🤖 Model: ${model}"
  echo "⏱️  Total analysis time: ${total_duration}s"
  echo "🔄 API request time: ${request_duration}s"
  echo "🔍 Response parsing time: ${parse_duration}s"
  echo "📝 Response size: ${response_token_count} words"
  echo "═════════════════════════════════════════════════"
  echo "📋 Full results logged to: ${RESULTS_FILE}"
  
  return 0
}

# =================== MAIN SCRIPT ===================

# Start timer for overall execution
SCRIPT_START_TIME=$(date +%s.%N)

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

log_benchmark "${INPUT}" "${model}" "script_execution" "${TOTAL_EXECUTION_TIME}" "0"

echo "Script completed in ${TOTAL_EXECUTION_TIME} seconds"
echo "Benchmark data saved to ${RESULTS_FILE}"