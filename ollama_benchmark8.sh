#!/bin/zsh

# Enable debug mode only when explicitly requested
if [[ "$1" == "--debug" ]]; then
  set -x
  shift
fi

# =================== CONFIGURATION ===================
BENCHMARK_DIR="${HOME}/ollama_benchmarks"
BENCHMARK_FILE="${BENCHMARK_DIR}/benchmark_$(date +%Y%m%d_%H%M%S).md"
README="$(pwd)/README.md"
OLLAMA_API="http://localhost:11434/api/chat"

# Create benchmark directory if it doesn't exist
mkdir -p "${BENCHMARK_DIR}"

# =================== HELPER FUNCTIONS ===================
# Function to log messages with timestamps
log_benchmark() {
  local model=$1
  local operation=$2
  local duration=$3
  local details=$4
  
  echo "| $(date '+%Y-%m-%d %H:%M:%S') | ${model} | ${operation} | ${duration}s | ${details} |" >> "${BENCHMARK_FILE}"
}

# Function to initialize benchmark file
init_benchmark_file() {
  {
    echo "# Ollama Model Benchmark Results - $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    echo "## System Information"
    echo "* CPU: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown")"
    echo "* Memory: $(sysctl -n hw.memsize 2>/dev/null | awk '{print $1/1024/1024/1024 " GB"}' || echo "Unknown")"
    echo "* macOS Version: $(sw_vers -productVersion 2>/dev/null || echo "Unknown")"
    echo "* Ollama Version: $(ollama -v 2>/dev/null || echo "Unknown")"
    echo ""
    echo "## Benchmark Results"
    echo "| Timestamp | Model | Operation | Duration (s) | Details |"
    echo "|-----------|-------|-----------|--------------|---------|"
  } > "${BENCHMARK_FILE}"
  
  echo "Benchmark file initialized at ${BENCHMARK_FILE}"
}

# Function to check if running in a terminal
is_terminal() {
  [ -t 0 ]
}

# Function to check for dependencies
check_dependencies() {
  local missing_deps=0
  
  # Start timer
  local start_time=$(date +%s)
  
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
  
  # End timer
  local end_time=$(date +%s)
  local duration=$((end_time - start_time))
  
  log_benchmark "system" "dependency_check" "${duration}" "Status: $([[ ${missing_deps} -eq 0 ]] && echo 'OK' || echo 'Failed')"
  
  return ${missing_deps}
}

# Function to get available models
get_models() {
  local start_time=$(date +%s)
  
  echo "Fetching available models..."
  local ollama_output=$(ollama list 2>/dev/null)
  
  if [ $? -ne 0 ]; then
    echo "Error: Failed to run 'ollama list'. Ensure Ollama is running."
    exit 1
  fi
  
  # Parse models more efficiently
  models=($(echo "$ollama_output" | tail -n +2 | awk '{print $1}'))
  
  if [ ${#models[@]} -eq 0 ]; then
    echo "No models found. Please download a model using 'ollama pull <model>'."
    exit 1
  fi
  
  local end_time=$(date +%s)
  local duration=$((end_time - start_time))
  
  log_benchmark "system" "fetch_models" "${duration}" "Found ${#models[@]} models"
  
  echo "Available models: ${models[@]}"
}

# Function to select a model
select_model() {
  local start_time=$(date +%s)
  
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
  
  local end_time=$(date +%s)
  local duration=$((end_time - start_time))
  
  log_benchmark "${model}" "model_selection" "${duration}" "Selected model"
  
  echo "Selected model: ${model}"
}

# Function to validate input file
validate_input_file() {
  local input="$1"
  local start_time=$(date +%s)
  
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
  
  local end_time=$(date +%s)
  local duration=$((end_time - start_time))
  
  log_benchmark "${model}" "file_validation" "${duration}" "File type: ${SCRIPT_TYPE}"
}

# Function to analyze script with Ollama
analyze_script() {
  local input="$1"
  local model="$2"
  local start_time=$(date +%s)
  
  echo "Analyzing script with ${model}..."
  
  # Create request payload
  local payload=$(jq -n \
    --arg model "${model}" \
    --arg content "${CONTENT}" \
    --arg filename "$(basename "${input}")" \
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
  local request_start_time=$(date +%s)
  
  # Temporary file for response
  local temp_response=$(mktemp)
  
  # Send the request
  curl -s -X POST "${OLLAMA_API}" \
    -H "Content-Type: application/json" \
    -d "${payload}" > "${temp_response}"
  
  local request_end_time=$(date +%s)
  local request_duration=$((request_end_time - request_start_time))
  
  log_benchmark "${model}" "api_request" "${request_duration}" "API request completed"
  
  # Parse response
  echo "Processing response..."
  local parse_start_time=$(date +%s)
  
  if grep -q "error" "${temp_response}"; then
    echo "Error in Ollama response:"
    cat "${temp_response}"
    rm "${temp_response}"
    exit 1
  fi
  
  # Extract response content safely (avoiding jq issues with newlines)
  # Use perl instead of jq for more robust JSON parsing
  RESPONSE=$(perl -MJSON -e '
    local $/;
    my $json = <STDIN>;
    my $data = decode_json($json);
    print $data->{message}{content};
  ' < "${temp_response}")
  
  # Check if response is empty
  if [ -z "${RESPONSE}" ]; then
    echo "Error: Empty response from Ollama."
    echo "Raw response:"
    cat "${temp_response}"
    rm "${temp_response}"
    exit 1
  fi
  
  # Clean up
  rm "${temp_response}"
  
  local parse_end_time=$(date +%s)
  local parse_duration=$((parse_end_time - parse_start_time))
  
  log_benchmark "${model}" "response_parsing" "${parse_duration}" "Response size: $(echo "${RESPONSE}" | wc -c) bytes"
  
  # Update README.md
  echo "Updating README.md..."
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local filename=$(basename "${input}")
  
  {
    echo -e "\n## ${filename} (Model: ${model}, Time: ${timestamp})\n${RESPONSE}\n"
    echo -e "### License\nThis script is provided under the MIT License.\n"
  } >> "${README}"
  
  echo "README.md updated for ${filename}"
  
  local end_time=$(date +%s)
  local total_duration=$((end_time - start_time))
  
  log_benchmark "${model}" "total_analysis" "${total_duration}" "Complete analysis of ${filename}"
  
  # Return the total duration for benchmarking
  echo "${total_duration}"
}

# Function to run benchmark on multiple models
run_benchmark() {
  local input="$1"
  shift
  local model_list=("$@")
  
  if [ ${#model_list[@]} -eq 0 ]; then
    # If no models specified, use all available models
    model_list=("${models[@]}")
  fi
  
  echo "Running benchmark on ${#model_list[@]} models for ${input}..."
  
  local results=()
  
  for m in "${model_list[@]}"; do
    echo "========================================="
    echo "Benchmarking model: ${m}"
    echo "========================================="
    
    validate_input_file "${input}"
    local duration=$(analyze_script "${input}" "${m}")
    
    results+=("${m}: ${duration}s")
  done
  
  echo "========================================="
  echo "Benchmark Results Summary:"
  echo "========================================="
  
  for result in "${results[@]}"; do
    echo "${result}"
  done
  
  echo "Full benchmark details available in: ${BENCHMARK_FILE}"
}

# =================== MAIN SCRIPT ===================

# Start timer for overall execution
SCRIPT_START_TIME=$(date +%s)

# Initialize benchmark file
init_benchmark_file

# Input handling
if [ $# -lt 1 ]; then
  echo "Usage: $0 [--debug] <input_file> [model]"
  echo "       $0 --benchmark <input_file> [model1 model2 ...]"
  exit 1
fi

INPUT="$1"
echo "Input file: ${INPUT}"

# Check dependencies
check_dependencies || exit 1

# Get available models
get_models

# Handle benchmark mode
if [[ "${INPUT}" == "--benchmark" ]]; then
  if [ $# -lt 2 ]; then
    echo "Error: Benchmark mode requires at least one input file."
    echo "Usage: $0 --benchmark <input_file> [model1 model2 ...]"
    exit 1
  fi
  
  actual_input="$2"
  shift 2
  run_benchmark "${actual_input}" "$@"
else
  # Regular mode: select model and analyze
  select_model "$@"
  validate_input_file "${INPUT}"
  analyze_script "${INPUT}" "${model}"
fi

# End timer for overall execution
SCRIPT_END_TIME=$(date +%s)
TOTAL_EXECUTION_TIME=$((SCRIPT_END_TIME - SCRIPT_START_TIME))

log_benchmark "system" "script_execution" "${TOTAL_EXECUTION_TIME}" "Total script runtime"

echo "Script completed in ${TOTAL_EXECUTION_TIME} seconds"
echo "Benchmark data saved to ${BENCHMARK_FILE}"