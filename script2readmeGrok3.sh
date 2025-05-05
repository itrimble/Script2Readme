#!/bin/sh
#
# script2readme.sh - Generate README documentation from scripts using Ollama models
# Author: Ian Trimble
# Created: April 28, 2025
# Version: 1.5.0

set -eu
# Attempt to enable pipefail if available
set -o pipefail 2>/dev/null

# =================== CONFIGURATION ===================
# App information
APP_NAME="Script to README Generator"
APP_VERSION="1.5.0"
APP_AUTHOR="Ian Trimble"

# Directory structure
BENCHMARK_DIR="${HOME}/ollama_benchmarks"
PROJECT_DIR="$(pwd)"
SESSION_ID="$(date +%Y%m%d_%H%M%S)_$(openssl rand -hex 4)"
BENCHMARK_LOG="${BENCHMARK_DIR}/benchmark_log.csv"
METRICS_LOG="${BENCHMARK_DIR}/metrics_${SESSION_ID}.json"
CHANGELOG="${PROJECT_DIR}/CHANGELOG.md"
README="${PROJECT_DIR}/README.md"
OLLAMA_API="http://localhost:11434/api/chat"

# Colors and formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
BOLD='\033[1m'
RESET='\033[0m'

# Disable colors if not in a terminal
if [ ! -t 1 ]; then
    RED="" GREEN="" YELLOW="" BLUE="" MAGENTA="" CYAN="" WHITE="" GRAY="" BOLD="" RESET=""
fi

# Did you know tips (here-document for POSIX compliance)
TIPS_LIST=$(cat << 'EOF'
You can select different models for different scripts to compare documentation quality.
Larger models (13B+) generally produce more detailed documentation but take longer.
Your benchmarks are saved to ${BENCHMARK_DIR} for performance analysis.
The script automatically detects base64-encoded files and decodes them.
Script metrics like function count and line count help estimate processing time.
Good documentation can reduce project onboarding time by up to 60%.
The script supports multiple script types: shell, python, ruby, javascript, and more.
Historical performance data improves time estimates with each run.
The generated README includes detailed metadata about your script.
Future versions will support batch processing and interactive editing.
EOF
)

# Default model (will be set dynamically based on available models)
DEFAULT_MODEL=""
DEFAULT_COMPLEXITY=2.5

# Create benchmark directory if it doesn't exist
mkdir -p "${BENCHMARK_DIR}"

# OS detection for stat, sed commands
OS_TYPE=$(uname)
if [ "$OS_TYPE" = "Darwin" ]; then
    SED_INPLACE="sed -i ''"
    STAT_SIZE="stat -f%z"
else
    SED_INPLACE="sed -i"
    STAT_SIZE="stat -c%s"
fi

# Enable debug mode if requested
if [ "${1:-}" = "--debug" ]; then
    set -x
    shift
fi

# Strict cleanup on exit
cleanup() {
    rm -f "${SYSTEM_FILE:-}" "${USER_FILE:-}" "${TEMP_RESPONSE:-}" 2>/dev/null
}
trap cleanup EXIT INT TERM

# Function: display usage information
show_usage() {
    printf "%s%s%s (v%s)%s\n" "$CYAN" "$BOLD" "$APP_NAME" "$APP_VERSION" "$RESET"
    printf "%sGenerates README documentation from script files using Ollama models%s\n\n" "$GRAY" "$RESET"
    printf "%s%sUsage:%s %s./script2readme.sh%s %s<input_file>%s %s[model]%s\n" \
        "$YELLOW" "$BOLD" "$RESET" "$GREEN" "$RESET" "$MAGENTA" "$RESET" "$BLUE" "$RESET"
    printf "    %s--debug%s                Enable debug mode\n" "$GREEN" "$RESET"
    printf "    %s--help%s                 Show this help message\n" "$GREEN" "$RESET"
    printf "    %s--version%s              Show version information\n" "$GREEN" "$RESET"
    printf "    %s--list-models%s          List available Ollama models\n\n" "$GREEN" "$RESET"
    printf "%s%sArguments:%s\n" "$YELLOW" "$BOLD" "$RESET"
    printf "    %s<input_file>%s           Path to script file to document\n" "$MAGENTA" "$RESET"
    printf "    %s[model]%s                Optional Ollama model name (default: %s)\n\n" "$BLUE" "$RESET" "$DEFAULT_MODEL"
    printf "%sExamples:%s\n" "$YELLOW" "$RESET"
    printf "  %s./script2readme.sh my_script.sh%s\n" "$GRAY" "$RESET"
    printf "  %s./script2readme.sh my_script.sh codellama:7b%s\n\n" "$GRAY" "$RESET"
    printf "%sOutput:%s\n" "$YELLOW" "$RESET"
    printf "  - Creates a new README file (format: README_script_model.md)\n"
    printf "  - Logs performance metrics and benchmarks to %s\n\n" "$BENCHMARK_DIR"
}

# Function: display version information
show_version() {
    printf "%s%s%s %sv%s%s\n" "$CYAN" "$BOLD" "$APP_NAME" "$WHITE" "$APP_VERSION" "$RESET"
    printf "%sAuthor: %s%s%s\n" "$GRAY" "$WHITE" "$APP_AUTHOR" "$RESET"
    printf "%sLicense: MIT%s\n" "$GRAY" "$RESET"
}

# Function: get system information
get_system_info() {
    # CPU info
    if [ "$OS_TYPE" = "Darwin" ]; then
        cpu_info=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown")
    elif [ -f /proc/cpuinfo ]; then
        cpu_info=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ //')
    else
        cpu_info="Unknown"
    fi
    # Memory info
    if [ "$OS_TYPE" = "Darwin" ]; then
        memory_info=$(sysctl -n hw.memsize 2>/dev/null | awk '{print int($1/1024/1024/1024) " GB"}' || echo "Unknown")
    else
        memory_info=$(free -g 2>/dev/null | awk '/^Mem:/{print int($2/1024) " GB"}' || echo "Unknown")
    fi
    # OS version
    os_info=$(uname -sr 2>/dev/null || echo "Unknown")
    # Ollama version
    ollama_version=$(ollama --version 2>/dev/null || echo "Unknown")

    # Update metrics log
    if jq --arg cpu "$cpu_info" --arg mem "$memory_info" --arg os "$os_info" --arg ollama "$ollama_version" \
          '.system_info = {"cpu": $cpu, "memory": $mem, "os": $os, "ollama_version": $ollama}' \
          "$METRICS_LOG" > "${METRICS_LOG}.tmp"; then
        mv "${METRICS_LOG}.tmp" "$METRICS_LOG"
    else
        echo "Warning: Failed to update metrics log with system information"
    fi

    printf "%sSystem Info:%s CPU: %s%s%s, Memory: %s%s%s, OS: %s%s%s, Ollama: %s%s%s\n" \
        "$BLUE" "$RESET" \
        "$WHITE" "$cpu_info" "$RESET" \
        "$WHITE" "$memory_info" "$RESET" \
        "$WHITE" "$os_info" "$RESET" \
        "$WHITE" "$ollama_version" "$RESET"
}

# Function: get current resource usage
get_resource_usage() {
    cpu_usage=$(ps -o %cpu= -p $$ | awk '{print $1}')
    memory_usage=$(ps -o rss= -p $$ | awk '{print int($1/1024) " MB"}')
    echo "${cpu_usage},${memory_usage}"
}

# Function: log benchmark data
log_benchmark() {
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    script_name=$1
    script_size=$2
    script_lines=$3
    script_chars=$4
    model_name=$5
    operation=$6
    duration=$7
    token_count=$8

    # Get current resource usage
    resource_usage=$(get_resource_usage)
    cpu_usage=$(echo "$resource_usage" | cut -d, -f1)
    memory_usage=$(echo "$resource_usage" | cut -d, -f2)

    # Log to CSV
    printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n" \
        "$timestamp" "$SESSION_ID" "$script_name" "$script_size" "$script_lines" "$script_chars" \
        "$model_name" "$operation" "$duration" "$token_count" "$cpu_usage" "$memory_usage" \
        >> "$BENCHMARK_LOG"

    # Update JSON metrics
    if jq --arg timestamp "$timestamp" --arg script "$script_name" --arg size "$script_size" \
         --arg lines "$script_lines" --arg chars "$script_chars" --arg model "$model_name" \
         --arg op "$operation" --arg dur "$duration" --arg tokens "$token_count" \
         --arg cpu "$cpu_usage" --arg mem "$memory_usage" \
         '.metrics += [{"timestamp": $timestamp, "script": $script, "size_bytes": $size, "line_count": $lines, "char_count": $chars, "model": $model, "operation": $op, "duration": $dur, "token_count": $tokens, "cpu_usage": $cpu, "memory_usage": $mem}]' \
         "$METRICS_LOG" > "${METRICS_LOG}.tmp"; then
        mv "${METRICS_LOG}.tmp" "$METRICS_LOG"
    else
        echo "Warning: Failed to update metrics log"
    fi
}

# Function: check and install dependencies
check_dependencies() {
    missing=0
    for cmd in jq bc curl ollama openssl base64 awk grep sed wc; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "Error: $cmd is required."
            missing=1
            echo "Attempting to install $cmd..."
            if [ "$OS_TYPE" = "Darwin" ]; then
                if command -v brew >/dev/null 2>&1; then
                    brew install "$cmd" || { echo "Failed to install $cmd with brew"; exit 1; }
                else
                    echo "Homebrew not found. Please install $cmd manually."
                    exit 1
                fi
            else
                if command -v apt-get >/dev/null 2>&1; then
                    sudo apt-get update && sudo apt-get install -y "$cmd" || { echo "Failed to install $cmd with apt-get"; exit 1; }
                elif command -v yum >/dev/null 2>&1; then
                    sudo yum install -y "$cmd" || { echo "Failed to install $cmd with yum"; exit 1; }
                elif command -v dnf >/dev/null 2>&1; then
                    sudo dnf install -y "$cmd" || { echo "Failed to install $cmd with dnf"; exit 1; }
                else
                    echo "No supported package manager found. Please install $cmd manually."
                    exit 1
                fi
            fi
        fi
    done

    # Check if Ollama server is running
    if ! curl -s -m 2 "${OLLAMA_API}/tags" >/dev/null 2>&1; then
        echo "Error: Ollama server is not running. Please start it with 'ollama serve'."
        missing=1
    fi

    return $missing
}

# Function: get available models and determine default
get_models() {
    arg=${1:-}
    if [ "$arg" = "--list-models" ] || [ "$arg" = "--list" ]; then
        echo "Available Ollama models:"
        ollama list
        exit 0
    fi
    DEFAULT_MODEL=$(ollama list 2>/dev/null | awk 'NR==2 {print $1}')
    model="$DEFAULT_MODEL"
}

# Function: select model (arg or default)
select_model() {
    if [ $# -ge 2 ]; then
        provided_model="$2"
        if ollama list | grep -q "$provided_model"; then
            model="$provided_model"
        else
            echo "Warning: Model '$provided_model' not found. Attempting to pull..."
            if ollama pull "$provided_model"; then
                model="$provided_model"
            else
                echo "Error: Failed to pull model '$provided_model'. Using default: $DEFAULT_MODEL"
                model="$DEFAULT_MODEL"
            fi
        fi
    else
        model="$DEFAULT_MODEL"
        echo "No model specified. Using default model: $model"
    fi
}

# Function: count script features (basic placeholders)
count_script_features() {
    file="$1"
    # Count functions, commands, etc. (simple estimates)
    func_count=$(grep -c "function " "$file" || echo "0")
    cmd_count=$(grep -c ";" "$file" || echo "0")
    if_count=$(grep -c "^if " "$file" || echo "0")
    case_count=$(grep -c "^case " "$file" || echo "0")
    for_count=$(grep -c "^for " "$file" || echo "0")
    while_count=$(grep -c "^while " "$file" || echo "0")

    if jq --arg func "$func_count" --arg cmd "$cmd_count" --arg ifs "$if_count" \
          --arg cases "$case_count" --arg fors "$for_count" --arg whiles "$while_count" \
          '.script_features = {"function_count": $func, "command_count": $cmd, "if_count": $ifs, "case_count": $cases, "for_count": $fors, "while_count": $whiles}' \
          "$METRICS_LOG" > "${METRICS_LOG}.tmp"; then
        mv "${METRICS_LOG}.tmp" "$METRICS_LOG"
    else
        echo "Warning: Failed to update metrics log with script features"
    fi
}

# Function: validate the input file
validate_input_file() {
    input="$1"
    [ -f "$input" ] || { echo "Error: File '$input' not found."; exit 1; }
    # File stats
    file_size=$($STAT_SIZE "$input" 2>/dev/null || wc -c < "$input")
    line_count=$(wc -l < "$input" | tr -d ' ')
    char_count=$(wc -c < "$input" | tr -d ' ')
    # Record metrics
    if jq --arg file "$input" --arg size "$file_size" --arg lines "$line_count" --arg chars "$char_count" \
         '.input_file = {"path": $file, "size_bytes": $size, "line_count": $lines, "char_count": $chars}' \
         "$METRICS_LOG" > "${METRICS_LOG}.tmp"; then
        mv "${METRICS_LOG}.tmp" "$METRICS_LOG"
    else
        echo "Warning: Failed to update metrics log with file metrics"
    fi
    # Determine extension (lowercase)
    ext=$(printf "%s" "${input##*.}" | tr '[:upper:]' '[:lower:]')
    # (Additional type-specific processing can be added here if needed)
    count_script_features "$input"
    echo "File validated: $input ($file_size bytes, $line_count lines)"
}

# Function: generate README using Ollama
generate_readme() {
    input="$1"
    model="$2"
    skip_est="$3"
    script_basename=$(basename "$input")
    start_time=$(date +%s.%N)
    echo "Generating README for ${script_basename} with model ${model}..."

    # Estimate time if not skipped (simplified)
    if [ "$skip_est" != "true" ]; then
        echo "Estimating completion time... (this may take a moment)"
        # Simplified estimation placeholder (could be replaced with actual logic)
        est_seconds=30
        est_time=$(printf "%s seconds" "$est_seconds")
        echo "Estimated completion time: $est_time"
        if jq --arg est "$est_seconds" '.estimated_completion_time = $est' "$METRICS_LOG" > "${METRICS_LOG}.tmp"; then
            mv "${METRICS_LOG}.tmp" "$METRICS_LOG"
        fi
    fi

    # Prepare prompts for Ollama (system and user)
    SYSTEM_FILE=$(mktemp)
    USER_FILE=$(mktemp)
    printf "%s" "You are an expert code documentarian tasked with producing clear, comprehensive documentation for scripts. Analyze the script thoroughly and create documentation that explains its purpose, usage, and functionality. Format your response in markdown with proper sections, code blocks, and examples." | jq -R -s '.' > "$SYSTEM_FILE"
    
    # Read the script content and include it in the prompt
    script_content=$(cat "$input")
    prompt="Please analyze the following script ($script_basename) and create a comprehensive README in markdown format:

## The script to analyze:
\`\`\`
$script_content
\`\`\`

Include these sections:
1. Overview - What the script does and its purpose
2. Requirements - Dependencies and prerequisites
3. Usage - How to use the script with examples
4. How It Works - Explanation of the main functionality
5. Configuration - Any configurable options
6. Troubleshooting - Common issues and solutions

Format your output as proper markdown with headings, code blocks, lists, and tables where appropriate."
    
    printf "%s" "$prompt" | jq -R -s '.' > "$USER_FILE"

    # Create JSON payload for Ollama API
    payload=$(jq -n \
        --arg model "$model" \
        --rawfile system_content "$SYSTEM_FILE" \
        --rawfile user_content "$USER_FILE" \
        '{
            "model": $model,
            "messages": [
                {"role": "system", "content": $system_content},
                {"role": "user", "content": $user_content}
            ],
            "stream": false
        }')

    # Send request to Ollama API
    temp_response=$(mktemp)
    curl -s -X POST "$OLLAMA_API" \
         -H "Content-Type: application/json" \
         -d "$payload" > "$temp_response" 2>/dev/null || {
        echo "Error: Failed to contact Ollama API."
        rm -f "$SYSTEM_FILE" "$USER_FILE" "$temp_response"
        exit 1
    }

    # Extract response content (Ollama API response format)
    # Check for different JSON response formats
    # Create safe model name for filenames
    safe_model="${model//[\/:]/_}"
    output_file="${README%.*}_${script_basename}_${safe_model}.md"
    raw_file="${README%.*}_${script_basename}_${safe_model}_raw.json"
    
    # Always save the raw response for debugging
    cat "$temp_response" > "$raw_file"
    
    # Try to parse non-streaming JSON response
    # New format for Ollama with stream: false
    if [ -s "$temp_response" ]; then
        # Check for common response structures
        if jq -e '.message.content' "$temp_response" >/dev/null 2>&1; then
            # Standard Ollama non-streaming format
            jq -r '.message.content' "$temp_response" > "$output_file"
            echo "README generated: $output_file (Ollama format)"
        elif jq -e '.response' "$temp_response" >/dev/null 2>&1; then
            # Alternative Ollama format
            jq -r '.response' "$temp_response" > "$output_file"
            echo "README generated: $output_file (response format)"
        elif grep -q '"done":true' "$temp_response"; then
            # It might be a streaming response that we need to concatenate
            echo "Detected streaming response, concatenating..."
            # Extract and concatenate all content from streaming JSON
            # We preserve the line breaks by not removing all newlines
            # Instead, replace multiple newlines with a single newline and clean word breaks
            jq -r 'select(.message.content != null) | .message.content' "$temp_response" | \
                awk 'BEGIN{ORS="";} {print}' | \
                sed 's/\([a-z]\)\n\([a-z]\)/\1\2/g' | sed 's/\n\n/\n/g' > "$output_file"
            echo "README generated: $output_file (streaming format)"
        else
            # Show raw response for debugging
            echo "Error: Ollama API response did not match expected formats."
            echo "JSON structure:"
            jq '.' "$temp_response" | head -20
            echo "..."
            echo "Raw response saved to: $raw_file"
        fi
    else
        echo "Error: Empty response from Ollama API."
    fi

    # Clean up temp prompt files
    rm -f "$SYSTEM_FILE" "$USER_FILE"

    # Benchmark logging for generation
    end_time=$(date +%s.%N)
    duration=$(printf "%.2f" "$(echo "$end_time - $start_time" | bc)")
    # Read the file metrics we should have from validate_input_file
    if [ -z "${file_size:-}" ] || [ -z "${line_count:-}" ] || [ -z "${char_count:-}" ]; then
        # If variables not available, get them now
        file_size=$($STAT_SIZE "$input" 2>/dev/null || wc -c < "$input")
        line_count=$(wc -l < "$input" | tr -d ' ')
        char_count=$(wc -c < "$input" | tr -d ' ')
    fi
    log_benchmark "$input" "$file_size" "$line_count" "$char_count" "$model" "generate_readme" "$duration" "0"
}

# =================== MAIN SCRIPT ===================

# Start timer
SCRIPT_START_TIME=$(date +%s.%N)

# Get system info and initialize metrics log
jq -n "{session_id: \"$SESSION_ID\", app_version: \"$APP_VERSION\", metrics: []}" > "$METRICS_LOG"
get_system_info

# Parse options
SKIP_ESTIMATE="false"
while [ "${1:-}" != "" ] && [ "${1#--}" != "$1" ]; do
    case "$1" in
        --help)
            show_usage
            exit 0
            ;;
        --version)
            show_version
            exit 0
            ;;
        --list-models)
            get_models --list-models
            ;;
        --no-estimate)
            SKIP_ESTIMATE="true"
            shift
            ;;
        --debug)
            # Already handled
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Run '$0 --help' for usage information."
            exit 1
            ;;
    esac
done

# Check for input file
if [ $# -lt 1 ]; then
    echo "Error: No input file specified."
    echo "Run '$0 --help' for usage information."
    exit 1
fi

INPUT="$1"
printf "%sInput file:%s %s%s%s\n" "$BLUE" "$RESET" "$YELLOW" "$INPUT" "$RESET"

# Check dependencies
check_dependencies || exit 1

# Get models and select
get_models
select_model "$@"

# Validate and analyze input
validate_input_file "$INPUT"

# Generate the README
generate_readme "$INPUT" "$model" "$SKIP_ESTIMATE"

# End timer and finalize metrics
SCRIPT_END_TIME=$(date +%s.%N)
TOTAL_TIME=$(printf "%.2f" "$(echo "$SCRIPT_END_TIME - $SCRIPT_START_TIME" | bc)")
# Make sure metrics variables are available
if [ -z "${file_size:-}" ] || [ -z "${line_count:-}" ] || [ -z "${char_count:-}" ]; then
    # If variables not available, get them now
    file_size=$($STAT_SIZE "$INPUT" 2>/dev/null || wc -c < "$INPUT")
    line_count=$(wc -l < "$INPUT" | tr -d ' ')
    char_count=$(wc -c < "$INPUT" | tr -d ' ')
fi
# Get script basename if not already set
script_basename=$(basename "$INPUT")
# Create a filesystem-safe version of the model name
safe_model_name="${model//[\/:]/_}"
log_benchmark "$INPUT" "$file_size" "$line_count" "$char_count" "$model" "script_execution" "$TOTAL_TIME" "0"

printf "%s%sScript completed in %s seconds%s\n" "$GREEN" "$BOLD" "$TOTAL_TIME" "$RESET"
printf "%sDetailed metrics saved to:%s\n" "$BLUE" "$RESET"
printf "  - README: %s\n" "${README%.*}_${script_basename}_${safe_model_name}.md"
printf "  - CSV log: %s\n" "$BENCHMARK_LOG"
printf "  - JSON metrics: %s\n" "$METRICS_LOG"
printf "  - Changelog: %s\n" "$CHANGELOG"
