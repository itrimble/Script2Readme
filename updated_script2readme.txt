#!/bin/zsh
#
# script2readme.sh - Generate high-quality README documentation from scripts using Ollama models
# Author: Ian Trimble
# Created: April 28, 2025
# Version: 1.3.0
#

# Enable debug mode only when explicitly requested
if [[ "$1" == "--debug" ]]; then
  set -x
  shift
fi

# =================== COLORS AND FORMATTING ===================
# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
BOLD='\033[1m'
DIM='\033[2m'
UNDERLINE='\033[4m'
BLINK='\033[5m'
REVERSE='\033[7m'
RESET='\033[0m'

# Color gradients for progress bar
declare -a GRADIENT
GRADIENT=(
  '\033[38;5;27m' '\033[38;5;33m' '\033[38;5;39m' '\033[38;5;45m' '\033[38;5;51m'
  '\033[38;5;50m' '\033[38;5;49m' '\033[38;5;48m' '\033[38;5;47m' '\033[38;5;46m'
)

# Check if terminal supports colors
if [ -t 1 ]; then
  COLORTERM=1
else
  COLORTERM=0
  # Reset all color variables to empty strings
  RED='' GREEN='' YELLOW='' BLUE='' MAGENTA='' CYAN='' WHITE='' GRAY=''
  BOLD='' DIM='' UNDERLINE='' BLINK='' REVERSE='' RESET=''
  for i in {0..9}; do GRADIENT[$i]=''; done
fi

# =================== CONFIGURATION ===================
# App information
APP_NAME="Script to README Generator"
APP_VERSION="1.3.0"
APP_AUTHOR="Ian Trimble"

# Directory structure
BENCHMARK_DIR="${HOME}/ollama_benchmarks"
SESSION_ID=$(date +%Y%m%d_%H%M%S)_$(openssl rand -hex 4)
BENCHMARK_LOG="${BENCHMARK_DIR}/benchmark_log.csv"
METRICS_LOG="${BENCHMARK_DIR}/metrics_${SESSION_ID}.json"
CHANGELOG="${BENCHMARK_DIR}/changelog.md"
DETAILED_COMPARISON="${BENCHMARK_DIR}/model_comparisons.md"
README="$(pwd)/README.md"
OLLAMA_API="http://localhost:11434/api/chat"
TEMPLATE_DIR="${HOME}/.script2readme/templates"
CONFIG_FILE="${HOME}/.script2readme/config.json"

# Default model (can be overridden)
DEFAULT_MODEL="qwen2.5-coder:7b"

# Sound effects (if enabled)
SOUND_ENABLED=0
SOUND_COMPLETE="afplay /System/Library/Sounds/Glass.aiff"
SOUND_ERROR="afplay /System/Library/Sounds/Sosumi.aiff"

# Model complexity factors (for time estimation)
declare -A MODEL_COMPLEXITY
MODEL_COMPLEXITY["qwen2.5:1.5b"]=1.0
MODEL_COMPLEXITY["qwen2.5-coder:7b"]=3.5
MODEL_COMPLEXITY["deepseek-coder:6.7b"]=3.0
MODEL_COMPLEXITY["codellama:7b"]=3.0
MODEL_COMPLEXITY["codellama:13b"]=5.5
MODEL_COMPLEXITY["deepseek-coder:latest"]=0.8
MODEL_COMPLEXITY["llama3:8b"]=3.2
MODEL_COMPLEXITY["mistral:7b"]=2.8
MODEL_COMPLEXITY["phi3:mini"]=0.5
# Default for unknown models
MODEL_COMPLEXITY["default"]=2.5

# Model descriptions and strengths
declare -A MODEL_DESCRIPTIONS
MODEL_DESCRIPTIONS["qwen2.5:1.5b"]="Fastest option for simple scripts. Less detailed but great for quick documentation of straightforward code. Uses minimal resources."
MODEL_DESCRIPTIONS["qwen2.5-coder:7b"]="Excellent for code documentation with balanced performance and accuracy. Specializes in understanding programming patterns and explaining them clearly. Good middle ground between speed and quality."
MODEL_DESCRIPTIONS["deepseek-coder:6.7b"]="Specializes in deep code analysis with strong understanding of programming paradigms. Excellent for explaining complex functionality in readable terms."
MODEL_DESCRIPTIONS["codellama:7b"]="Good balance of speed and quality. Strong at API and function documentation. More efficient than 13b while maintaining good quality."
MODEL_DESCRIPTIONS["codellama:13b"]="Most comprehensive documentation but slowest option. Best for complex scripts where detail matters more than speed. Excellent pattern recognition."
MODEL_DESCRIPTIONS["deepseek-coder:latest"]="Optimized for modern coding practices and patterns. Best for documenting complex functions and design patterns. Good balance of speed and thoroughness."
MODEL_DESCRIPTIONS["llama3:8b"]="General-purpose model with decent coding knowledge. Good for scripts with both code and natural language explanations."
MODEL_DESCRIPTIONS["mistral:7b"]="Fast with good reasoning. Handles multi-language scripts well. Excellent for documentation requiring explanations of logic."
MODEL_DESCRIPTIONS["phi3:mini"]="Ultra-fast option for simple scripts. Minimalist documentation but works well for straightforward code."
# Default description for unknown models
MODEL_DESCRIPTIONS["default"]="General-purpose model for code documentation. Performance characteristics unknown."

# Script complexity factors (for time estimation)
LINE_FACTOR=0.3
FUNCTION_FACTOR=2.0
CONDITIONAL_FACTOR=1.5
LOOP_FACTOR=1.2

# Did you know tips
declare -a TIPS
TIPS=(
  "You can create custom templates in ${TEMPLATE_DIR}."
  "Use the --watch flag to automatically process scripts as they're added to a directory."
  "Different models have different strengths - smaller models are faster, larger ones more detailed."
  "The --batch flag lets you process multiple scripts at once."
  "Your benchmarks are saved to ${BENCHMARK_DIR} for performance analysis."
  "You can use --export to generate HTML or PDF documentation from your README."
  "The --interactive mode lets you edit the AI-generated content before it's saved."
  "Set your preferred default model in ${CONFIG_FILE}."
  "Good documentation can reduce project onboarding time by up to 60%."
  "Use --update to refresh documentation while preserving your custom edits."
  "The qwen2.5-coder:7b model generally produces the most balanced documentation."
  "Check model comparison data at ${DETAILED_COMPARISON}."
  "For very small scripts, deepseek-coder:latest offers the best speed-to-quality ratio."
  "Add a TOC to your README with the --toc flag."
  "Run with --stats to see performance metrics for all your previous runs."
)

# Create required directories
mkdir -p "${BENCHMARK_DIR}"
mkdir -p "${TEMPLATE_DIR}"
mkdir -p "$(dirname "${CONFIG_FILE}")"

# Create default config if it doesn't exist
if [ ! -f "${CONFIG_FILE}" ]; then
  echo "{\"default_model\": \"${DEFAULT_MODEL}\", \"sound_enabled\": false, \"template\": \"default\", \"preferred_format\": \"enhanced\"}" > "${CONFIG_FILE}"
fi

# Load config if it exists
if [ -f "${CONFIG_FILE}" ]; then
  if command -v jq &> /dev/null; then
    DEFAULT_MODEL=$(jq -r '.default_model // "qwen2.5-coder:7b"' "${CONFIG_FILE}")
    SOUND_ENABLED=$(jq -r '.sound_enabled // false' "${CONFIG_FILE}")
    README_FORMAT=$(jq -r '.preferred_format // "enhanced"' "${CONFIG_FILE}")
    if [[ "${SOUND_ENABLED}" == "true" ]]; then
      SOUND_ENABLED=1
    else
      SOUND_ENABLED=0
    fi
  fi
fi

# Initialize benchmark file if it doesn't exist
if [ ! -f "${BENCHMARK_LOG}" ]; then
  echo "timestamp,session_id,script_name,script_size_bytes,script_lines,script_chars,model,operation,duration,tokens,cpu_usage,memory_usage,script_complexity,accuracy" > "${BENCHMARK_LOG}"
fi

# Initialize model comparison file if it doesn't exist
if [ ! -f "${DETAILED_COMPARISON}" ]; then
  {
    echo "# Model Performance Comparison"
    echo ""
    echo "| Model | Avg Speed | Accuracy | Best For | Notes |"
    echo "|-------|-----------|----------|----------|-------|"
    echo "| qwen2.5-coder:7b | Medium | High | General documentation | Most balanced results |"
    echo "| deepseek-coder:latest | Very Fast | Medium | Quick documentation | Best speed-to-quality ratio |"
    echo "| deepseek-coder:6.7b | Medium | High | Detailed analysis | Good technical details |"
    echo "| codellama:7b | Medium | Medium | Simple scripts | Occasional inaccuracies |"
    echo "| codellama:13b | Slow | Medium-High | Complex scripts | Not worth the extra time |"
  } > "${DETAILED_COMPARISON}"
fi

# Initialize changelog if it doesn't exist
if [ ! -f "${CHANGELOG}" ]; then
  {
    echo "# Script to README Generator Changelog"
    echo ""
    echo "## Version 1.3.0 - $(date '+%Y-%m-%d')"
    echo "- Enhanced README format with better styling"
    echo "- Improved model descriptions and selection"
    echo "- Fixed time estimation accuracy"
    echo "- Added script complexity analysis"
    echo "- Added duplicate script versioning"
    echo "- Enhanced benchmark metrics and reporting"
    echo "- Added model comparison data"
  } > "${CHANGELOG}"
else
  # Check if version entry exists, add if not
  if ! grep -q "## Version ${APP_VERSION}" "${CHANGELOG}"; then
    sed -i '' "1a\\
\\
## Version ${APP_VERSION} - $(date '+%Y-%m-%d')\\
- Enhanced README format with better styling\\
- Improved model descriptions and selection\\
- Fixed time estimation accuracy\\
- Added script complexity analysis\\
- Added duplicate script versioning\\
- Enhanced benchmark metrics and reporting\\
- Added model comparison data
" "${CHANGELOG}"
  fi
fi

# Initialize metrics JSON log
echo "{\"session_id\": \"${SESSION_ID}\", \"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\", \"app_version\": \"${APP_VERSION}\", \"metrics\": []}" > "${METRICS_LOG}"

# =================== HELPER FUNCTIONS ===================
# Function to show the app logo
show_logo() {
  clear
  echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BLUE}║                                                      ║${RESET}"
  echo -e "${BLUE}║  ${MAGENTA}███████╗${GREEN}██████╗${CYAN} ██████╗${YELLOW}███████╗${RED}██████╗ ${MAGENTA}███████╗${BLUE}  ║${RESET}"
  echo -e "${BLUE}║  ${MAGENTA}██╔════╝${GREEN}██╔══██╗${CYAN}██╔════╝${YELLOW}██╔════╝${RED}██╔══██╗${MAGENTA}██╔════╝${BLUE}  ║${RESET}"
  echo -e "${BLUE}║  ${MAGENTA}███████╗${GREEN}██████╔╝${CYAN}██║     ${YELLOW}█████╗  ${RED}██████╔╝${MAGENTA}█████╗  ${BLUE}  ║${RESET}"
  echo -e "${BLUE}║  ${MAGENTA}╚════██║${GREEN}██╔══██╗${CYAN}██║     ${YELLOW}██╔══╝  ${RED}██╔══██╗${MAGENTA}██╔══╝  ${BLUE}  ║${RESET}"
  echo -e "${BLUE}║  ${MAGENTA}███████║${GREEN}██║  ██║${CYAN}╚██████╗${YELLOW}███████╗${RED}██║  ██║${MAGENTA}███████╗${BLUE}  ║${RESET}"
  echo -e "${BLUE}║  ${MAGENTA}╚══════╝${GREEN}╚═╝  ╚═╝${CYAN} ╚═════╝${YELLOW}╚══════╝${RED}╚═╝  ╚═╝${MAGENTA}╚══════╝${BLUE}  ║${RESET}"
  echo -e "${BLUE}║                                                      ║${RESET}"
  echo -e "${BLUE}║  ${CYAN}Script to README Generator ${WHITE}v${APP_VERSION}              ${BLUE}  ║${RESET}"
  echo -e "${BLUE}║  ${GRAY}By ${APP_AUTHOR}                                    ${BLUE}  ║${RESET}"
  echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${RESET}"
  echo ""
}

# Function to show a random tip
show_tip() {
  local tip_index=$((RANDOM % ${#TIPS[@]}))
  local tip="${TIPS[$tip_index]}"
  echo -e "\n${YELLOW}💡 ${BOLD}Did you know?${RESET} ${tip}${RESET}\n"
}

# Function to log messages with different levels
log_message() {
  local level=$1
  local message=$2
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  
  case ${level} in
    "INFO")
      echo -e "${BLUE}[${timestamp}] ℹ️  ${RESET}${message}"
      ;;
    "SUCCESS")
      echo -e "${GREEN}[${timestamp}] ✅ ${BOLD}${message}${RESET}"
      ;;
    "WARNING")
      echo -e "${YELLOW}[${timestamp}] ⚠️  ${BOLD}${message}${RESET}"
      ;;
    "ERROR")
      echo -e "${RED}[${timestamp}] ❌ ${BOLD}${message}${RESET}"
      ;;
    "DEBUG")
      if [[ "$1" == "--debug" ]]; then
        echo -e "${GRAY}[${timestamp}] 🔍 ${message}${RESET}"
      fi
      ;;
    *)
      echo -e "[${timestamp}] ${message}"
      ;;
  esac
}

# Function to play sounds if enabled
play_sound() {
  local sound_type=$1
  
  if [ ${SOUND_ENABLED} -eq 1 ]; then
    case ${sound_type} in
      "complete")
        eval ${SOUND_COMPLETE} &> /dev/null &
        ;;
      "error")
        eval ${SOUND_ERROR} &> /dev/null &
        ;;
    esac
  fi
}

# Function to display an animated spinner
spinner() {
  local pid=$1
  local delay=0.1
  local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  
  while kill -0 $pid 2>/dev/null; do
    local temp=${spinstr#?}
    printf " %c  " "$spinstr"
    local spinstr=$temp${spinstr%"$temp"}
    sleep $delay
    printf "\b\b\b\b"
  done
  printf "    \b\b\b\b"
}

# Function to display progress
display_progress() {
  local progress=$1
  local duration=$2
  local width=40
  local filled=$((width * progress / 100))
  local empty=$((width - filled))
  local bar=""
  
  # Create gradient filled part
  for ((i = 0; i < filled; i++)); do
    local color_index=$((i * 10 / width))
    bar="${bar}${GRADIENT[$color_index]}█"
  done
  
  # Create empty part
  for ((i = 0; i < empty; i++)); do
    bar="${bar}${GRAY}░"
  done
  
  # Print the bar
  printf "\r${WHITE}[${RESET}${bar}${RESET}${WHITE}]${RESET} ${BOLD}%3d%%${RESET} ${WHITE}(${CYAN}%s${WHITE})${RESET}" $progress "$duration"
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

# Function to calculate script complexity score
calculate_complexity() {
  local content="$1"
  local line_count="$2"
  
  # Count script features
  local function_count=$(echo "${content}" | grep -c "function " || echo "0")
  local if_count=$(echo "${content}" | grep -c "if " || echo "0")
  local case_count=$(echo "${content}" | grep -c "case " || echo "0")
  local for_count=$(echo "${content}" | grep -c "for " || echo "0")
  local while_count=$(echo "${content}" | grep -c "while " || echo "0")
  
  # Calculate complexity score based on features
  local complexity=$(echo "scale=2; ${line_count} * ${LINE_FACTOR} + 
                     ${function_count} * ${FUNCTION_FACTOR} + 
                     (${if_count} + ${case_count}) * ${CONDITIONAL_FACTOR} + 
                     (${for_count} + ${while_count}) * ${LOOP_FACTOR}" | bc)
  
  # Ensure minimum complexity of 1.0
  if (( $(echo "$complexity < 1.0" | bc -l) )); then
    complexity=1.0
  fi
  
  # Return the complexity score
  echo $complexity
}

# Function to estimate completion time
estimate_completion_time() {
  local script_size=$1
  local script_complexity=$2
  local model=$3
  
  # Get model complexity factor
  local model_factor=${MODEL_COMPLEXITY[$model]}
  if [ -z "$model_factor" ]; then
    model_factor=${MODEL_COMPLEXITY["default"]}
  fi
  
  # Base time in seconds per KB with adjustment for complexity
  local base_time=2
  
  # Adjust based on script size (larger scripts may take disproportionately longer)
  local size_factor=$(printf "%.2f" $(echo "scale=2; ($script_size / 1024) ^ 0.6" | bc))
  
  # Calculate estimated seconds with complexity factored in
  local complexity_adjustment=$(printf "%.2f" $(echo "scale=2; $script_complexity * 0.8" | bc))
  local estimate=$(printf "%.0f" $(echo "scale=0; $base_time * $size_factor * $model_factor * $complexity_adjustment" | bc))
  
  # Ensure minimum reasonable time
  if [ $estimate -lt 10 ]; then
    estimate=10
  fi
  
  echo $estimate
}

# Function to display model description
show_model_description() {
  local model=$1
  local description=""
  
  # Get description
  if [ -n "${MODEL_DESCRIPTIONS[$model]}" ]; then
    description="${MODEL_DESCRIPTIONS[$model]}"
  else
    description="${MODEL_DESCRIPTIONS["default"]}"
  fi
  
  # Get complexity factor
  local complexity=${MODEL_COMPLEXITY[$model]}
  if [ -z "$complexity" ]; then
    complexity=${MODEL_COMPLEXITY["default"]}
  fi
  
  # Calculate speed category
  local speed=""
  local speed_color=""
  if (( $(echo "$complexity < 1.5" | bc -l) )); then
    speed="Very Fast"
    speed_color="${GREEN}"
  elif (( $(echo "$complexity < 2.5" | bc -l) )); then
    speed="Fast"
    speed_color="${CYAN}"
  elif (( $(echo "$complexity < 4.0" | bc -l) )); then
    speed="Medium"
    speed_color="${YELLOW}"
  else
    speed="Slow"
    speed_color="${RED}"
  fi
  
  echo -e "${MAGENTA}${BOLD}${model}${RESET}"
  echo -e "${GRAY}${description}${RESET}"
  echo -e "${GRAY}• Speed: ${speed_color}${speed}${RESET}"
  echo -e "${GRAY}• Performance factor: ${WHITE}${complexity}x${RESET}"
  
  # If we have benchmark data, display it
  if [ -f "${BENCHMARK_LOG}" ]; then
    local avg_time=$(grep "${model}" "${BENCHMARK_LOG}" | grep "total_analysis" | awk -F',' '{sum+=$9; count++} END {if(count>0) print sum/count; else print "N/A"}')
    local runs=$(grep "${model}" "${BENCHMARK_LOG}" | grep "total_analysis" | wc -l | tr -d ' ')
    
    if [[ "$avg_time" != "N/A" && $runs -gt 0 ]]; then
      echo -e "${GRAY}• Average run time: ${WHITE}$(printf "%.2f" ${avg_time})s${RESET} (${runs} previous runs)"
    fi
  fi
  
  echo ""
}

# Function to display usage information
show_usage() {
  echo -e "${CYAN}${BOLD}${APP_NAME}${RESET} ${WHITE}(v${APP_VERSION})${RESET}"
  echo -e "${GRAY}Generates README documentation from script files using Ollama models${RESET}"
  echo ""
  echo -e "${YELLOW}${BOLD}Usage:${RESET} $0 ${GREEN}[OPTIONS]${RESET} ${MAGENTA}<input_file>${RESET} ${BLUE}[model]${RESET}"
  echo ""
  echo -e "${YELLOW}${BOLD}Options:${RESET}"
  echo -e "  ${GREEN}--debug${RESET}                Enable debug mode"
  echo -e "  ${GREEN}--help${RESET}                 Show this help message"
  echo -e "  ${GREEN}--list-models${RESET}          List available Ollama models"
  echo -e "  ${GREEN}--version${RESET}              Show version information"
  echo -e "  ${GREEN}--no-estimate${RESET}          Skip time estimation"
  echo -e "  ${GREEN}--no-color${RESET}             Disable colored output"
  echo -e "  ${GREEN}--sound${RESET}                Enable sound notifications"
  echo -e "  ${GREEN}--batch${RESET} ${BLUE}<pattern>${RESET}      Process multiple files matching pattern"
  echo -e "  ${GREEN}--watch${RESET} ${BLUE}<directory>${RESET}    Watch directory for new scripts and process them"
  echo -e "  ${GREEN}--template${RESET} ${BLUE}<name>${RESET}      Use specified template (default: standard)"
  echo -e "  ${GREEN}--interactive${RESET}          Edit AI-generated documentation before saving"
  echo -e "  ${GREEN}--update${RESET}               Update existing documentation preserving manual edits"
  echo -e "  ${GREEN}--export${RESET} ${BLUE}<format>${RESET}      Export documentation to specified format (html, pdf)"
  echo -e "  ${GREEN}--format${RESET} ${BLUE}<style>${RESET}       README format style (basic, enhanced, fancy)"
  echo -e "  ${GREEN}--toc${RESET}                  Add table of contents to README"
  echo -e "  ${GREEN}--config${RESET}               Create or update configuration"
  echo -e "  ${GREEN}--stats${RESET}                Show benchmark statistics for all runs"
  echo -e "  ${GREEN}--compare${RESET}              Compare multiple models on the same script"
  echo ""
  echo -e "${YELLOW}${BOLD}Arguments:${RESET}"
  echo -e "  ${MAGENTA}<input_file>${RESET}           Path to script file to document"
  echo -e "  ${BLUE}[model]${RESET}                Optional Ollama model name (default: ${WHITE}${DEFAULT_MODEL}${RESET})"
  echo ""
  echo -e "${YELLOW}${BOLD}Examples:${RESET}"
  echo -e "  ${GRAY}$0 my_script.sh${RESET}"
  echo -e "  ${GRAY}$0 my_script.sh codellama:7b${RESET}"
  echo -e "  ${GRAY}$0 --batch \"*.sh\" --template code${RESET}"
  echo -e "  ${GRAY}$0 --watch ~/scripts --template minimal${RESET}"
  echo -e "  ${GRAY}$0 my_script.sh --format fancy --toc${RESET}"
  echo -e "  ${GRAY}$0 --compare my_script.sh${RESET}"
  echo ""
  echo -e "${YELLOW}${BOLD}Output:${RESET}"
  echo -e "  - Updates README.md in the current directory with script documentation"
  echo -e "  - Logs performance metrics and benchmarks to ${BENCHMARK_DIR}"
  echo ""
  show_tip
  exit 0
}

# Function to display version information
show_version() {
  echo -e "${CYAN}${BOLD}${APP_NAME}${RESET} ${WHITE}v${APP_VERSION}${RESET}"
  echo -e "${GRAY}Author: ${WHITE}${APP_AUTHOR}${RESET}"
  echo -e "${GRAY}Created: April 28, 2025${RESET}"
  echo -e "${GRAY}License: MIT${RESET}"
  exit 0
}

# Function to display benchmark statistics
show_benchmark_stats() {
  if [ ! -f "${BENCHMARK_LOG}" ]; then
    log_message "ERROR" "No benchmark data found."
    exit 1
  fi
  
  echo -e "${CYAN}${BOLD}Benchmark Statistics${RESET}"
  echo ""
  
  # Get model statistics
  echo -e "${YELLOW}${BOLD}Model Performance${RESET}"
  echo -e "${WHITE}|--------------------|-----------|------------|----------|${RESET}"
  echo -e "${WHITE}| Model              | Avg Time  | Success %  | Runs     |${RESET}"
  echo -e "${WHITE}|--------------------|-----------|------------|----------|${RESET}"
  
  # Extract unique models
  local models=$(tail -n +2 "${BENCHMARK_LOG}" | awk -F',' '{print $7}' | sort | uniq)
  
  for model in $models; do
    # Skip system entries
    if [[ "$model" == "system" ]]; then
      continue
    fi
    
    local runs=$(grep "${model}" "${BENCHMARK_LOG}" | grep "total_analysis" | wc -l | tr -d ' ')
    local avg_time=$(grep "${model}" "${BENCHMARK_LOG}" | grep "total_analysis" | awk -F',' '{sum+=$9; count++} END {if(count>0) print sum/count; else print "N/A"}')
    
    # Calculate accuracy if available
    local accuracy="N/A"
    local accuracy_data=$(grep "${model}" "${BENCHMARK_LOG}" | grep "total_analysis" | awk -F',' '{if($12!="") print $12}')
    if [ -n "$accuracy_data" ]; then
      accuracy=$(echo "$accuracy_data" | awk '{sum+=$1; count++} END {if(count>0) print (sum/count)*100; else print "N/A"}')
      if [[ "$accuracy" != "N/A" ]]; then
        accuracy="$(printf "%.1f" ${accuracy})%"
      fi
    fi
    
    # Format the model name and values for display
    local model_display=$(printf "%-18s" "${model}")
    local time_display="N/A"
    if [[ "$avg_time" != "N/A" ]]; then
      time_display="$(printf "%.2f" ${avg_time})s"
    fi
    local time_display=$(printf "%-9s" "${time_display}")
    local accuracy_display=$(printf "%-10s" "${accuracy}")
    local runs_display=$(printf "%-8s" "${runs}")
    
    echo -e "| ${MAGENTA}${model_display}${RESET} | ${CYAN}${time_display}${RESET} | ${GREEN}${accuracy_display}${RESET} | ${YELLOW}${runs_display}${RESET} |"
  done
  
  echo -e "${WHITE}|--------------------|-----------|------------|----------|${RESET}"
  echo ""
  
  # Script type statistics
  echo -e "${YELLOW}${BOLD}Script Types${RESET}"
  echo -e "${WHITE}|------------|---------|------------|${RESET}"
  echo -e "${WHITE}| Type       | Count   | Avg Time   |${RESET}"
  echo -e "${WHITE}|------------|---------|------------|${RESET}"
  
  # Extract script extensions and count them
  local exts=$(for file in $(tail -n +2 "${BENCHMARK_LOG}" | awk -F',' '{print $3}' | grep -v "system"); do 
    echo "${file##*.}"; 
  done | sort | uniq)
  
  for ext in $exts; do
    if [[ -z "$ext" || "$ext" == "system" ]]; then
      continue
    fi
    
    local count=$(grep "\.${ext}" "${BENCHMARK_LOG}" | grep "total_analysis" | wc -l | tr -d ' ')
    local avg_time=$(grep "\.${ext}" "${BENCHMARK_LOG}" | grep "total_analysis" | awk -F',' '{sum+=$9; count++} END {if(count>0) print sum/count; else print "N/A"}')
    
    # Format for display
    local ext_display=$(printf "%-10s" "${ext}")
    local count_display=$(printf "%-7s" "${count}")
    local time_display="N/A"
    if [[ "$avg_time" != "N/A" ]]; then
      time_display="$(printf "%.2f" ${avg_time})s"
    fi
    local time_display=$(printf "%-10s" "${time_display}")
    
    echo -e "| ${CYAN}${ext_display}${RESET} | ${YELLOW}${count_display}${RESET} | ${GREEN}${time_display}${RESET} |"
  done
  
  echo -e "${WHITE}|------------|---------|------------|${RESET}"
  echo ""
  
  # Overall statistics
  local total_runs=$(grep "total_analysis" "${BENCHMARK_LOG}" | wc -l | tr -d ' ')
  local avg_total_time=$(grep "total_analysis" "${BENCHMARK_LOG}" | awk -F',' '{sum+=$9; count++} END {if(count>0) print sum/count; else print "N/A"}')
  local avg_script_size=$(grep "total_analysis" "${BENCHMARK_LOG}" | awk -F',' '{sum+=$4; count++} END {if(count>0) print sum/count; else print "N/A"}')
  local avg_script_lines=$(grep "total_analysis" "${BENCHMARK_LOG}" | awk -F',' '{sum+=$5; count++} END {if(count>0) print sum/count; else print "N/A"}')
  
  # Format times
  local avg_time_display="N/A"
  if [[ "$avg_total_time" != "N/A" ]]; then
    avg_time_display="$(printf "%.2f" ${avg_total_time})s"
  fi
  
  echo -e "${YELLOW}${BOLD}Overall Statistics${RESET}"
  echo -e "${GRAY}Total runs: ${WHITE}${total_runs}${RESET}"
  echo -e "${GRAY}Average runtime: ${WHITE}${avg_time_display}${RESET}"
  if [[ "$avg_script_size" != "N/A" ]]; then
    echo -e "${GRAY}Average script size: ${WHITE}$(printf "%.2f" ${avg_script_size}) bytes${RESET}"
  fi
  if [[ "$avg_script_lines" != "N/A" ]]; then
    echo -e "${GRAY}Average script lines: ${WHITE}$(printf "%.1f" ${avg_script_lines}) lines${RESET}"
  fi
  echo ""
  
  # Location of benchmark files
  echo -e "${YELLOW}${BOLD}Benchmark Files${RESET}"
  echo -e "${GRAY}CSV log: ${WHITE}${BENCHMARK_LOG}${RESET}"
  echo -e "${GRAY}Model comparison: ${WHITE}${DETAILED_COMPARISON}${RESET}"
  echo -e "${GRAY}Session logs: ${WHITE}${BENCHMARK_DIR}/metrics_*.json${RESET}"
  echo -e "${GRAY}Responses: ${WHITE}${BENCHMARK_DIR}/response_*.md${RESET}"
  echo ""
  
  exit 0
}

# Function to compare model outputs
compare_models() {
  local input_file=$1
  
  log_message "INFO" "Comparing models for ${input_file}..."
  
  # Validate the input file
  if [ ! -f "${input_file}" ]; then
    log_message "ERROR" "Input file '${input_file}' does not exist."
    exit 1
  fi
  
  # Get available models
  get_models
  
  # Ask which models to compare if in interactive mode
  local models_to_compare=()
  
  if is_terminal; then
    echo -e "${YELLOW}${BOLD}Select models to compare (space-separated numbers, e.g. '1 3 5'):${RESET}"
    
    # Display models with numbers
    for ((i=1; i<=${#models[@]}; i++)); do
      local model="${models[$i]}"
      echo -e "${WHITE}${i})${RESET} ${MAGENTA}${model}${RESET}"
    done
    
    # Read user selection
    read -p "Models to compare: " model_selection
    
    # Convert selection to models
    for num in $model_selection; do
      if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le ${#models[@]} ]; then
        models_to_compare+=("${models[$num]}")
      fi
    done
  else
    # Non-interactive: use predefined good models
    models_to_compare=("qwen2.5-coder:7b" "deepseek-coder:latest" "codellama:7b")
  fi
  
  # If no models selected, use default
  if [ ${#models_to_compare[@]} -eq 0 ]; then
    log_message "WARNING" "No models selected. Using default comparison set."
    models_to_compare=("qwen2.5-coder:7b" "deepseek-coder:latest" "codellama:7b")
  fi
  
  # Create a comparison directory
  local comparison_dir="${BENCHMARK_DIR}/comparison_${SESSION_ID}"
  mkdir -p "${comparison_dir}"
  
  # Create comparison markdown file
  local comparison_file="${comparison_dir}/model_comparison.md"
  
  # Initialize comparison file
  {
    echo "# Model Comparison for $(basename "${input_file}")"
    echo ""
    echo "Generated on $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    echo "## Script Information"
    echo ""
    echo "| Property | Value |"
    echo "|----------|-------|"
    echo "| Filename | $(basename "${input_file}") |"
    echo "| Size | $(stat -f%z "${input_file}") bytes |"
    echo "| Lines | $(wc -l < "${input_file}" | tr -d ' ') |"
    echo ""
    echo "## Performance Comparison"
    echo ""
    echo "| Model | Time | Word Count | Accuracy | Notes |"
    echo "|-------|------|------------|----------|-------|"
  } > "${comparison_file}"
  
  # Validate and process with each model
  for model in "${models_to_compare[@]}"; do
    log_message "INFO" "Testing with model: ${model}"
    
    # Skip if model doesn't exist
    if ! ollama list | grep -q "${model}"; then
      log_message "WARNING" "Model '${model}' not found. Skipping."
      continue
    fi
    
    # Run with current model
    local model_start_time=$(date +%s.%N)
    
    # Validate input file
    CONTENT=$(cat "${input_file}")
    FILE_SIZE=$(stat -f%z "${input_file}")
    LINE_COUNT=$(echo "${CONTENT}" | wc -l | tr -d ' ')
    CHAR_COUNT=$(echo "${CONTENT}" | wc -c | tr -d ' ')
    SCRIPT_TYPE="${input_file##*.}"
    
    # Calculate script complexity
    SCRIPT_COMPLEXITY=$(calculate_complexity "${CONTENT}" "${LINE_COUNT}")
    
    # Create request payload
    local payload=$(jq -n \
      --arg model "${model}" \
      --arg content "${CONTENT}" \
      --arg filename "$(basename "${input_file}")" \
      --arg script_type "${SCRIPT_TYPE}" \
      '{
        "model": $model,
        "messages": [
          {
            "role": "system",
            "content": "You are an expert code documentarian tasked with producing professional, accurate, and comprehensive documentation. Analyze the provided script with precision, describing only the functionality explicitly present in the code. Generate a detailed Markdown README section that is clear, thorough, and professionally structured, suitable for developers and end-users."
          },
          {
            "role": "user",
            "content": "Analyze the following script provided as plain text. Pay close attention to specific elements such as references to applications, system paths, and command-line tools. Consider the script'\''s potential impact on the system.\n\nGenerate a Markdown README section with these sections:\n\n- **Overview**: Summarize the script'\''s purpose and primary actions.\n- **Requirements**: List prerequisites inferred from the script.\n- **Usage**: Provide precise instructions for running the script.\n- **What the Script Does**: Describe the script'\''s operations step-by-step.\n- **Important Notes**: Highlight critical details derived from the script.\n- **Disclaimer**: Warn about risks of running the script.\n\nFile: \($filename)\n\nScript Content:\n\($content)"
          }
        ],
        "stream": false
      }')
    
    # Temporary file for response
    local temp_response=$(mktemp)
    
    # Send the request
    log_message "INFO" "Sending request to Ollama API for ${model}..."
    curl -s -X POST "${OLLAMA_API}" \
      -H "Content-Type: application/json" \
      -d "${payload}" > "${temp_response}"
    
    # Check for errors
    if grep -q "error" "${temp_response}"; then
      log_message "ERROR" "Error in Ollama response for ${model}:"
      cat "${temp_response}"
      continue
    fi
    
    # Extract response content
    local RESPONSE=""
    if jq -e '.message.content' "${temp_response}" > /dev/null 2>&1; then
      RESPONSE=$(jq -r '.message.content' "${temp_response}")
    else
      # Fallback methods
      RESPONSE=$(grep -o '"content":"[^"]*"' "${temp_response}" | sed 's/"content":"//;s/"//')
      
      if [ -z "${RESPONSE}" ]; then
        RESPONSE=$(perl -0777 -ne 'print $1 if /"content":"(.*?)"/s' "${temp_response}")
      fi
      
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
    fi
    
    # Save model response
    local model_response_file="${comparison_dir}/${model//[:\/]/_}.md"
    echo "${RESPONSE}" > "${model_response_file}"
    
    # Calculate timing
    local model_end_time=$(date +%s.%N)
    local model_duration=$(printf "%.2f" $(echo "${model_end_time} - ${model_start_time}" | bc))
    
    # Calculate statistics
    local word_count=$(echo "${RESPONSE}" | wc -w | tr -d ' ')
    
    # Add to comparison file
    echo "| ${model} | ${model_duration}s | ${word_count} | - | [View]($(basename "${model_response_file}")) |" >> "${comparison_file}"
  done
  
  # Complete comparison file
  {
    echo ""
    echo "## Summary"
    echo ""
    echo "This comparison shows how different models analyze the same script. The quality of documentation can vary significantly between models, with some providing more detailed explanations while others may be more concise or faster."
    echo ""
    echo "Generally, qwen2.5-coder:7b provides the most balanced results, deepseek-coder:latest is fastest, and codellama:13b is most comprehensive but slowest."
    echo ""
    echo "## How to View Full Outputs"
    echo ""
    echo "The individual model outputs are saved in the same directory as this file:"
    echo ""
    echo "```"
    echo "${comparison_dir}"
    echo "```"
  } >> "${comparison_file}"
  
  # Output results
  log_message "SUCCESS" "Comparison complete!"
  log_message "INFO" "Results saved to: ${comparison_file}"
  
  # Open the comparison file if on macOS
  if [[ "$OSTYPE" == "darwin"* ]]; then
    open "${comparison_file}"
  fi
  
  exit 0
}

# Function to update config
update_config() {
  echo -e "${CYAN}${BOLD}Configuration Setup${RESET}"
  echo ""
  
  # Ask for default model
  echo -e "${YELLOW}Default model:${RESET} (current: ${WHITE}${DEFAULT_MODEL}${RESET})"
  read -r new_model
  if [ -z "$new_model" ]; then
    new_model="${DEFAULT_MODEL}"
  fi
  
  # Ask for sound preference
  echo -e "${YELLOW}Enable sound effects?${RESET} (y/N)"
  read -r sound_pref
  if [[ "${sound_pref}" =~ ^[Yy]$ ]]; then
    sound_enabled="true"
  else
    sound_enabled="false"
  fi
  
  # Ask for preferred README format
  echo -e "${YELLOW}Preferred README format:${RESET} (basic, enhanced, fancy) [current: ${README_FORMAT}]"
  read -r format_pref
  if [ -z "$format_pref" ]; then
    format_pref="${README_FORMAT}"
  fi
  if [[ ! "${format_pref}" =~ ^(basic|enhanced|fancy)$ ]]; then
    format_pref="enhanced"
  fi
  
  # Write to config file
  echo "{\"default_model\": \"${new_model}\", \"sound_enabled\": ${sound_enabled}, \"template\": \"default\", \"preferred_format\": \"${format_pref}\"}" > "${CONFIG_FILE}"
  
  echo -e "${GREEN}${BOLD}Configuration updated!${RESET}"
  exit 0
}

# Function to get system information
get_system_info() {
  local cpu_info=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown")
  local memory_info=$(sysctl -n hw.memsize 2>/dev/null | awk '{print int($1/1024/1024/1024) " GB"}' || echo "Unknown")
  local os_info=$(sw_vers -productVersion 2>/dev/null || echo "Unknown")
  local ollama_version=$(ollama version 2>/dev/null || echo "Unknown")
  
  # Add system info to metrics log
  jq --arg cpu "${cpu_info}" \
     --arg mem "${memory_info}" \
     --arg os "${os_info}" \
     --arg ollama "${ollama_version}" \
     '.system_info = {"cpu": $cpu, "memory": $mem, "os": $os, "ollama_version": $ollama}' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
  
  log_message "INFO" "System Info: CPU: ${cpu_info}, Memory: ${memory_info}, OS: ${os_info}, Ollama: ${ollama_version}"
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
  local complexity=$9
  local accuracy=${10}
  
  # Get resource usage
  local resource_usage=$(get_resource_usage)
  local cpu_usage=$(echo ${resource_usage} | cut -d, -f1)
  local memory_usage=$(echo ${resource_usage} | cut -d, -f2)
  
  # Log to CSV for detailed data
  echo "${timestamp},${SESSION_ID},${script_name},${script_size},${script_lines},${script_chars},${model},${operation},${duration},${token_count},${cpu_usage},${memory_usage},${complexity},${accuracy}" >> "${BENCHMARK_LOG}"
  
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
     --arg complexity "${complexity}" \
     --arg accuracy "${accuracy}" \
     '.metrics += [{"timestamp": $timestamp, "script": $script, "size_bytes": $size, "line_count": $lines, "char_count": $chars, "model": $model, "operation": $op, "duration": $dur, "token_count": $tokens, "cpu_usage": $cpu, "memory_usage": $mem, "complexity": $complexity, "accuracy": $accuracy}]' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
  
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
  local complexity=${11}
  
  echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BLUE}║ ${CYAN}${BOLD}README GENERATION COMPLETE                         ${RESET}${BLUE}║${RESET}"
  echo -e "${BLUE}╠══════════════════════════════════════════════════════╣${RESET}"
  echo -e "${BLUE}║ ${WHITE}📄 Script:${RESET} ${YELLOW}${script_name}${RESET}$(printf "%$((40-${#script_name}))s" "")${BLUE}║${RESET}"
  echo -e "${BLUE}║ ${WHITE}🤖 Model:${RESET} ${MAGENTA}${model}${RESET}$(printf "%$((41-${#model}))s" "")${BLUE}║${RESET}"
  echo -e "${BLUE}║ ${WHITE}⏱️  Total time:${RESET} ${GREEN}${total_time}s${RESET}$(printf "%$((37-${#total_time}))s" "")${BLUE}║${RESET}"
  
  if [ -n "$estimated_time" ]; then
    local accuracy=0
    if [ "$total_time" -gt 0 ]; then
      accuracy=$(printf "%.1f" $(echo "scale=1; (${estimated_time} / ${total_time}) * 100" | bc 2>/dev/null || echo "0"))
      if [ -z "$accuracy" ] || [ "$accuracy" = "0" ]; then
        accuracy="N/A"
      fi
    else
      accuracy="N/A"
    fi
    
    echo -e "${BLUE}║ ${WHITE}🔮 Est. vs Actual:${RESET} ${estimated_time}s vs ${total_time}s (${accuracy}%)$(printf "%$((21-${#estimated_time}-${#total_time}-${#accuracy}))s" "")${BLUE}║${RESET}"
  fi
  
  echo -e "${BLUE}║ ${WHITE}🔄 API request time:${RESET} ${CYAN}${api_time}s${RESET}$(printf "%$((31-${#api_time}))s" "")${BLUE}║${RESET}"
  echo -e "${BLUE}║ ${WHITE}🔍 Response parse time:${RESET} ${CYAN}${parse_time}s${RESET}$(printf "%$((29-${#parse_time}))s" "")${BLUE}║${RESET}"
  echo -e "${BLUE}║ ${WHITE}📝 Response size:${RESET} ~${token_count} words$(printf "%$((33-${#token_count}))s" "")${BLUE}║${RESET}"
  echo -e "${BLUE}║ ${WHITE}🧮 Script complexity:${RESET} ${complexity}$(printf "%$((31-${#complexity}))s" "")${BLUE}║${RESET}"
  echo -e "${BLUE}║ ${WHITE}📂 Script metrics:${RESET}$(printf "%$((35))s" "")${BLUE}║${RESET}"
  
  local kb_size=$(printf "%.2f" $(echo "scale=2; ${script_size}/1024" | bc))
  echo -e "${BLUE}║   ${GRAY}- Size: ${script_size} bytes (${kb_size} KB)${RESET}$(printf "%$((38-${#script_size}-${#kb_size}))s" "")${BLUE}║${RESET}"
  echo -e "${BLUE}║   ${GRAY}- Lines: ${script_lines}${RESET}$(printf "%$((43-${#script_lines}))s" "")${BLUE}║${RESET}"
  echo -e "${BLUE}║   ${GRAY}- Characters: ${script_chars}${RESET}$(printf "%$((37-${#script_chars}))s" "")${BLUE}║${RESET}"
  echo -e "${BLUE}╠══════════════════════════════════════════════════════╣${RESET}"
  echo -e "${BLUE}║ ${GRAY}📋 Session ID: ${DIM}${SESSION_ID}${RESET}$(printf "%$((38-${#SESSION_ID}))s" "")${BLUE}║${RESET}"
  echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${RESET}"
}

# Function to show benchmark location
show_benchmark_location() {
  echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BLUE}║ ${CYAN}${BOLD}BENCHMARK FILES LOCATION                           ${RESET}${BLUE}║${RESET}"
  echo -e "${BLUE}╠══════════════════════════════════════════════════════╣${RESET}"
  echo -e "${BLUE}║ ${WHITE}Metrics Log:${RESET} ${YELLOW}${METRICS_LOG}${RESET}$(printf "%$((40-${#METRICS_LOG}))s" "")${BLUE}║${RESET}"
  echo -e "${BLUE}║ ${WHITE}CSV History:${RESET} ${YELLOW}${BENCHMARK_LOG}${RESET}$(printf "%$((40-${#BENCHMARK_LOG}))s" "")${BLUE}║${RESET}"
  echo -e "${BLUE}║ ${WHITE}Response:${RESET} ${YELLOW}${BENCHMARK_DIR}/response_${SESSION_ID}.md${RESET}$(printf "%$((40-${#BENCHMARK_DIR}-${#SESSION_ID}-15))s" "")${BLUE}║${RESET}"
  echo -e "${BLUE}║ ${WHITE}Changelog:${RESET} ${YELLOW}${CHANGELOG}${RESET}$(printf "%$((40-${#CHANGELOG}))s" "")${BLUE}║${RESET}"
  echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${RESET}"
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

# Function to edit text interactively
edit_text() {
  local text="$1"
  local temp_file=$(mktemp)
  
  # Write text to temp file
  echo "${text}" > "${temp_file}"
  
  # Determine editor
  local editor="${EDITOR:-nano}"
  
  # Prompt user
  echo -e "${YELLOW}${BOLD}Interactive Edit Mode${RESET}"
  echo -e "${GRAY}Opening text in ${editor}. Make your changes and save the file.${RESET}"
  echo -e "${GRAY}Press Enter to continue...${RESET}"
  read -r
  
  # Open editor
  ${editor} "${temp_file}"
  
  # Read back edited text
  local edited_text=$(cat "${temp_file}")
  
  # Clean up
  rm "${temp_file}"
  
  echo "${edited_text}"
}

# Function to check if running in a terminal
is_terminal() {
  [ -t 0 ]
}

# Function to check for dependencies
check_dependencies() {
  local missing_deps=0
  
  # Start timer
  local start_time=$(date +%s.%N)
  
  # Check for jq
  if ! command -v jq &> /dev/null; then
    log_message "ERROR" "jq is required. Please install jq (e.g., 'brew install jq')."
    missing_deps=1
  fi
  
  # Check for bc
  if ! command -v bc &> /dev/null; then
    log_message "ERROR" "bc is required. Please install bc."
    missing_deps=1
  fi
  
  # Check for fswatch if in watch mode
  if [ "${WATCH_MODE}" = "true" ] && ! command -v fswatch &> /dev/null; then
    log_message "ERROR" "fswatch is required for watch mode. Please install fswatch."
    missing_deps=1
  fi
  
  # Check for pandoc if export mode
  if [ "${EXPORT_MODE}" = "true" ] && ! command -v pandoc &> /dev/null; then
    log_message "ERROR" "pandoc is required for export mode. Please install pandoc."
    missing_deps=1
  fi
  
  # Check for ollama
  if ! command -v ollama &> /dev/null; then
    log_message "ERROR" "ollama is required. Please install Ollama."
    missing_deps=1
  else
    # Check if Ollama server is running
    log_message "INFO" "Checking Ollama server..."
    if ! curl -s -m 2 "http://localhost:11434/api/tags" &> /dev/null; then
      log_message "ERROR" "Ollama server is not running. Please start it with 'ollama serve'."
      missing_deps=1
    else
      log_message "SUCCESS" "Ollama server is running."
    fi
  fi
  
  # End timer
  local end_time=$(date +%s.%N)
  local duration=$(printf "%.2f" $(echo "${end_time} - ${start_time}" | bc))
  
  log_benchmark "system" "0" "0" "0" "system" "dependency_check" "${duration}" "0" "1.0" ""
  
  return ${missing_deps}
}

# Function to get available models
get_models() {
  local start_time=$(date +%s.%N)
  
  log_message "INFO" "Fetching available models..."
  local ollama_output=$(ollama list 2>/dev/null)
  
  if [ $? -ne 0 ]; then
    log_message "ERROR" "Failed to run 'ollama list'. Ensure Ollama is running."
    exit 1
  fi
  
  # Parse models
  models=($(echo "$ollama_output" | tail -n +2 | awk '{print $1}'))
  model_ids=($(echo "$ollama_output" | tail -n +2 | awk '{print $2}'))
  model_sizes=($(echo "$ollama_output" | tail -n +2 | awk '{print $3, $4}'))
  
  if [ ${#models[@]} -eq 0 ]; then
    log_message "ERROR" "No models found. Please download a model using 'ollama pull <model>'."
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
  
  log_benchmark "system" "0" "0" "0" "system" "fetch_models" "${duration}" "${#models[@]}" "1.0" ""
  
  # Just list models if that's what was requested
  if [[ "$1" == "--list" ]]; then
    echo -e "${CYAN}${BOLD}Available Ollama models for README generation:${RESET}"
    echo ""
    printf "${WHITE}%-30s %-15s %-15s${RESET}\n" "MODEL" "SIZE" "EST. SPEED"
    printf "${GRAY}%-30s %-15s %-15s${RESET}\n" "-----" "----" "---------"
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
      local speed_color=""
      if (( $(echo "$complexity < 1.5" | bc -l) )); then
        speed="Very Fast"
        speed_color="${GREEN}"
      elif (( $(echo "$complexity < 2.5" | bc -l) )); then
        speed="Fast"
        speed_color="${CYAN}"
      elif (( $(echo "$complexity < 4.0" | bc -l) )); then
        speed="Medium"
        speed_color="${YELLOW}"
      else
        speed="Slow"
        speed_color="${RED}"
      fi
      
      printf "${MAGENTA}%-30s ${BLUE}%-15s ${speed_color}%-15s${RESET}\n" "$model_name" "$model_size" "$speed"
      
      # Show model description if available
      if [ -n "${MODEL_DESCRIPTIONS[$model_name]}" ]; then
        printf "${GRAY}%s${RESET}\n\n" "${MODEL_DESCRIPTIONS[$model_name]}"
      else
        echo ""
      fi
    done
    exit 0
  fi
  
  log_message "INFO" "Found ${#models[@]} available models"
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
      log_message "SUCCESS" "Using specified model: ${model}"
      show_model_description "${model}"
    else
      log_message "WARNING" "Model '${provided_model}' not found in available models."
      log_message "INFO" "Trying to pull the model..."
      ollama pull "${provided_model}"
      if [ $? -ne 0 ]; then
        log_message "ERROR" "Failed to pull model '${provided_model}'. Using default model: ${DEFAULT_MODEL}"
        model="${DEFAULT_MODEL}"
      else
        model="${provided_model}"
        log_message "SUCCESS" "Model '${provided_model}' pulled successfully."
        show_model_description "${model}"
      fi
    fi
  elif is_terminal; then
    # Interactive selection if terminal is available
    echo -e "${YELLOW}${BOLD}Select a model for README generation:${RESET}"
    echo ""
    printf "${WHITE}%-5s %-30s %-15s %-15s${RESET}\n" "NUM" "MODEL" "SIZE" "EST. SPEED"
    printf "${GRAY}%-5s %-30s %-15s %-15s${RESET}\n" "---" "-----" "----" "---------"
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
      local speed_color=""
      if (( $(echo "$complexity < 1.5" | bc -l) )); then
        speed="Very Fast"
        speed_color="${GREEN}"
      elif (( $(echo "$complexity < 2.5" | bc -l) )); then
        speed="Fast"
        speed_color="${CYAN}"
      elif (( $(echo "$complexity < 4.0" | bc -l) )); then
        speed="Medium"
        speed_color="${YELLOW}"
      else
        speed="Slow"
        speed_color="${RED}"
      fi
      
      printf "${WHITE}%-5s ${MAGENTA}%-30s ${BLUE}%-15s ${speed_color}%-15s${RESET}\n" "$i" "$model_name" "$model_size" "$speed"
    done
    echo ""
    echo -e "${CYAN}Enter the number of the model to use:${RESET}"
    read -r model_num
    
    if [[ "$model_num" =~ ^[0-9]+$ ]] && [ "$model_num" -ge 1 ] && [ "$model_num" -le ${#models[@]} ]; then
      model="${models[$model_num]}"
      log_message "SUCCESS" "Selected model: ${model}"
      show_model_description "${model}"
    else
      log_message "WARNING" "Invalid selection. Using default model: ${DEFAULT_MODEL}"
      model="${DEFAULT_MODEL}"
      show_model_description "${model}"
    fi
  else
    # Non-interactive: use the default model
    model="${DEFAULT_MODEL}"
    log_message "INFO" "No terminal available for interactive selection. Using default model: ${model}"
  fi
  
  local end_time=$(date +%s.%N)
  local duration=$(printf "%.2f" $(echo "${end_time} - ${start_time}" | bc))
  
  log_benchmark "${INPUT}" "0" "0" "0" "${model}" "model_selection" "${duration}" "0" "1.0" ""
  
  # Record the selected model
  jq --arg model "${model}" '.selected_model = $model' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
}

# Function to validate input file
validate_input_file() {
  local input="$1"
  local start_time=$(date +%s.%N)
  
  if [ ! -f "${input}" ]; then
    log_message "ERROR" "Input file '${input}' does not exist."
    exit 1
  fi
  
  # Get file stats
  local file_size=$(stat -f%z "${input}")
  CONTENT=$(cat "${input}")
  local line_count=$(echo "${CONTENT}" | wc -l | tr -d ' ')
  local char_count=$(echo "${CONTENT}" | wc -c | tr -d ' ')
  
  # Calculate script complexity
  SCRIPT_COMPLEXITY=$(calculate_complexity "${CONTENT}" "${line_count}")
  
  # Record file metrics
  jq --arg file "${input}" \
     --arg size "${file_size}" \
     --arg lines "${line_count}" \
     --arg chars "${char_count}" \
     --arg complexity "${SCRIPT_COMPLEXITY}" \
     '.input_file = {"path": $file, "size_bytes": $size, "line_count": $lines, "char_count": $chars, "complexity": $complexity}' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
  
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
          log_message "INFO" "Input detected as base64-encoded shell script. Decoded successfully."
        else
          log_message "WARNING" "Input appears to be base64 but failed to decode as a valid shell script. Treating as plain text."
        fi
      fi
      
      # Validate as shell script
      if echo "${CONTENT}" | grep -qE "^#!/bin/(bash|zsh|sh)"; then
        SCRIPT_TYPE="shell"
        log_message "SUCCESS" "Validated shell script with ${line_count} lines."
      else
        SCRIPT_TYPE="shell"
        log_message "WARNING" "Input does not appear to be a valid shell script (missing shebang)."
      fi
      ;;
    scpt|applescript)
      # AppleScript
      SCRIPT_TYPE="applescript"
      log_message "SUCCESS" "Validated AppleScript with ${line_count} lines."
      ;;
    py|python)
      # Python script
      SCRIPT_TYPE="python"
      log_message "SUCCESS" "Validated Python script with ${line_count} lines."
      ;;
    rb|ruby)
      # Ruby script
      SCRIPT_TYPE="ruby"
      log_message "SUCCESS" "Validated Ruby script with ${line_count} lines."
      ;;
    js|javascript|jsx|ts|tsx)
      # JavaScript/TypeScript
      SCRIPT_TYPE="javascript"
      log_message "SUCCESS" "Validated JavaScript/TypeScript with ${line_count} lines."
      ;;
    php)
      # PHP script
      SCRIPT_TYPE="php"
      log_message "SUCCESS" "Validated PHP script with ${line_count} lines."
      ;;
    pl|pm|perl)
      # Perl script
      SCRIPT_TYPE="perl"
      log_message "SUCCESS" "Validated Perl script with ${line_count} lines."
      ;;
    lua)
      # Lua script
      SCRIPT_TYPE="lua"
      log_message "SUCCESS" "Validated Lua script with ${line_count} lines."
      ;;
    r|R)
      # R script
      SCRIPT_TYPE="r"
      log_message "SUCCESS" "Validated R script with ${line_count} lines."
      ;;
    *)
      SCRIPT_TYPE="generic"
      log_message "WARNING" "Unsupported file type: ${ext}. Will attempt to analyze as generic script."
      ;;
  esac
  
  # Count script features for metrics
  local function_count=$(echo "${CONTENT}" | grep -c "function " || echo "0")
  local if_count=$(echo "${CONTENT}" | grep -c "if " || echo "0")
  local case_count=$(echo "${CONTENT}" | grep -c "case " || echo "0")
  local for_count=$(echo "${CONTENT}" | grep -c "for " || echo "0")
  local while_count=$(echo "${CONTENT}" | grep -c "while " || echo "0")
  
  # Add features to metrics log
  jq --arg functions "${function_count}" \
     --arg commands "${if_count}" \
     --arg ifs "${if_count}" \
     --arg cases "${case_count}" \
     --arg fors "${for_count}" \
     --arg whiles "${while_count}" \
     '.script_features = {"function_count": $functions, "if_count": $ifs, "case_count": $cases, "for_count": $fors, "while_count": $whiles}' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
  
  local end_time=$(date +%s.%N)
  local duration=$(printf "%.2f" $(echo "${end_time} - ${start_time}" | bc))
  
  log_benchmark "${input}" "${file_size}" "${line_count}" "${char_count}" "${model}" "file_validation" "${duration}" "0" "${SCRIPT_COMPLEXITY}" ""
  
  # Store file metrics for later use
  FILE_SIZE="${file_size}"
  LINE_COUNT="${line_count}"
  CHAR_COUNT="${char_count}"
  
  log_message "INFO" "File validated: ${input} (${file_size} bytes, ${line_count} lines, complexity: ${SCRIPT_COMPLEXITY})"
}

# Function to handle duplicate files
handle_duplicate_files() {
  local input_file=$1
  local base_name=$(basename "${input_file}")
  local output_file="${README}"
  local count=1
  
  # Check if this script has already been documented in the README
  if grep -q "^## ${base_name}" "${output_file}" 2>/dev/null; then
    # Script already exists in README, create a timestamped section
    local timestamp=$(date +%Y%m%d_%H%M%S)
    log_message "INFO" "Script ${base_name} already documented. Adding new version with timestamp."
    
    # Add a timestamp to the section header in README
    SECTION_HEADER="${base_name} (${timestamp})"
    VERSION_SUFFIX="v$(grep -c "^## ${base_name}" "${output_file}")"
    
    # Add an entry to metrics log about duplicate
    jq --arg name "${base_name}" --arg timestamp "${timestamp}" \
       --arg version "${VERSION_SUFFIX}" \
       '.duplicate_handling = {"script_name": $name, "timestamp": $timestamp, "version": $version}' \
       "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
    
    return 1
  else
    # First time seeing this script
    SECTION_HEADER="${base_name}"
    VERSION_SUFFIX=""
    return 0
  fi
}

# Function to generate enhanced README format
generate_enhanced_readme() {
  local script_name=$1
  local model=$2
  local response=$3
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local version_suffix=$4
  
  # Determine script type for appropriate icon
  local script_icon="📜"
  case "${SCRIPT_TYPE}" in
    shell) script_icon="🐚" ;;
    python) script_icon="🐍" ;;
    ruby) script_icon="💎" ;;
    javascript) script_icon="🟨" ;;
    applescript) script_icon="🍎" ;;
    php) script_icon="🐘" ;;
    perl) script_icon="🐪" ;;
    lua) script_icon="🌙" ;;
    r) script_icon="📊" ;;
    *) script_icon="📜" ;;
  esac
  
  # Create README with better formatting
  {
    echo -e "<div align=\"center\">"
    echo -e "\n# ${script_icon} ${script_name} ${version_suffix}\n"
    echo -e "**Generated with script2readme using ${model}**"
    echo -e "\n*Documentation generated on ${timestamp}*"
    echo -e "</div>\n\n---\n"
    
    # Table of contents if needed
    if [ "${ADD_TOC}" = "true" ]; then
      echo -e "## Table of Contents\n"
      # Extract headings from response
      local headings=$(echo "${RESPONSE}" | grep -E "^#+\s+" | sed 's/^#\+\s\+//' | awk '{print "- [" $0 "](#" tolower($0) ")"}' | sed 's/ /-/g')
      echo -e "${headings}\n"
      echo -e "---\n"
    fi
    
    echo -e "${RESPONSE}\n"
    echo -e "## Metadata\n"
    echo -e "| Property | Value |"
    echo -e "|----------|-------|"
    echo -e "| File Size | $(du -h "${INPUT}" | cut -f1) (${FILE_SIZE} bytes) |"
    echo -e "| Line Count | ${LINE_COUNT} lines |"
    echo -e "| Script Type | ${SCRIPT_TYPE^} |"
    echo -e "| Complexity | ${SCRIPT_COMPLEXITY} |"
    echo -e "| Generated With | ${model} |"
    echo -e "| Generation Time | ${TOTAL_EXECUTION_TIME}s |"
    echo -e "\n---\n"
    echo -e "### License\n"
    echo -e "This script is provided under the MIT License.\n"
    echo -e "MIT License\n"
    echo -e "Copyright (c) $(date +%Y) ${APP_AUTHOR}\n"
    echo -e "Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the \"Software\"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:\n"
    echo -e "The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.\n"
    echo -e "THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE."
  } >> "${README}"
}

# Function to generate fancy README format
generate_fancy_readme() {
  local script_name=$1
  local model=$2
  local response=$3
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local version_suffix=$4
  local model_name_clean=${model//[:\/]/_}
  
  # Determine script type for appropriate icon
  local script_icon="📜"
  case "${SCRIPT_TYPE}" in
    shell) script_icon="🐚" ;;
    python) script_icon="🐍" ;;
    ruby) script_icon="💎" ;;
    javascript) script_icon="🟨" ;;
    applescript) script_icon="🍎" ;;
    php) script_icon="🐘" ;;
    perl) script_icon="🐪" ;;
    lua) script_icon="🌙" ;;
    r) script_icon="📊" ;;
    *) script_icon="📜" ;;
  esac
  
  # Create README with better formatting
  {
    echo -e "<a name=\"readme-top\"></a>"
    echo -e "<div align=\"center\">"
    echo -e "\n<img src=\"https://raw.githubusercontent.com/lobehub/sd-webui-lobe-theme/main/public/logo.webp\" width=\"100\">"
    echo -e "\n# ${script_icon} ${script_name} ${version_suffix}\n"
    echo -e "A fully documented guide for the **${script_name}** script, generated with script2readme"
    echo -e "\n[![Model Used][model-shield]][model-link]"
    echo -e "[![Generated][generated-shield]][generated-link]"
    echo -e "[![Language][language-shield]][language-link]"
    echo -e "[![MIT License][license-shield]][license-link]"
    echo -e "</div>\n\n---\n"
    
    # Table of contents if needed
    echo -e "<details>"
    echo -e "<summary><kbd>Table of contents</kbd></summary>\n"
    # Extract headings from response
    local headings=$(echo "${RESPONSE}" | grep -E "^#+\s+" | sed 's/^#\+\s\+//' | awk '{print "- [" $0 "](#" tolower($0) ")"}' | sed 's/ /-/g')
    echo -e "${headings}\n"
    echo -e "- [Metadata](#metadata)"
    echo -e "- [License](#license)"
    echo -e "</details>\n"
    
    echo -e "${RESPONSE}\n"
    echo -e "<div align=\"right\">"
    echo -e "\n[![Back to top][back-to-top]](#readme-top)\n"
    echo -e "</div>"
    
    echo -e "## Metadata\n"
    echo -e "| Property | Value |"
    echo -e "|----------|-------|"
    echo -e "| File Size | $(du -h "${INPUT}" | cut -f1) (${FILE_SIZE} bytes) |"
    echo -e "| Line Count | ${LINE_COUNT} lines |"
    echo -e "| Script Type | ${SCRIPT_TYPE^} |"
    echo -e "| Complexity | ${SCRIPT_COMPLEXITY} |"
    echo -e "| Generated With | ${model} |"
    echo -e "| Generation Time | ${TOTAL_EXECUTION_TIME}s |"
    echo -e "| Session ID | ${SESSION_ID} |"
    echo -e "\n<div align=\"right\">"
    echo -e "\n[![Back to top][back-to-top]](#readme-top)\n"
    echo -e "</div>"
    
    echo -e "## License\n"
    echo -e "This script is provided under the MIT License.\n"
    echo -e "MIT License\n"
    echo -e "Copyright (c) $(date +%Y) ${APP_AUTHOR}\n"
    echo -e "Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the \"Software\"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:\n"
    echo -e "The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.\n"
    echo -e "THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE."
    
    # Add badges definitions at the end
    echo -e "\n\n<!-- MARKDOWN LINKS & IMAGES -->"
    echo -e "[back-to-top]: https://img.shields.io/badge/-BACK_TO_TOP-151515?style=flat-square"
    echo -e "[model-shield]: https://img.shields.io/badge/${model_name_clean}-Model-6425FE?style=for-the-badge&labelColor=black"
    echo -e "[model-link]: https://ollama.com/library/${model%%:*}"
    echo -e "[generated-shield]: https://img.shields.io/badge/Generated_on-${timestamp//[: ]/-}-FF791A?style=for-the-badge&labelColor=black"
    echo -e "[generated-link]: #"
    echo -e "[language-shield]: https://img.shields.io/badge/${SCRIPT_TYPE}-Script-FF6484?style=for-the-badge&labelColor=black"
    echo -e "[language-link]: #"
    echo -e "[license-shield]: https://img.shields.io/badge/License-MIT-31C48D?style=for-the-badge&labelColor=black"
    echo -e "[license-link]: #license"
  } >> "${README}"
}

# Function to generate basic README format (simpler)
generate_basic_readme() {
  local script_name=$1
  local model=$2
  local response=$3
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local version_suffix=$4
  
  # Create README with simple formatting
  {
    echo -e "## ${script_name} (Analyzed with ${model}) ${version_suffix}"
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
}

# Function to generate README from script
generate_readme() {
  local input="$1"
  local model="$2"
  local skip_estimate="$3"
  local interactive_mode="$4"
  local readme_format="$5"
  local script_basename=$(basename "${input}")
  local start_time=$(date +%s.%N)
  
  # Check for duplicate script handling
  local is_first_version=true
  local version_suffix=""
  
  handle_duplicate_files "${input}"
  local duplicate_status=$?
  
  if [ $duplicate_status -eq 1 ]; then
    is_first_version=false
    version_suffix=" ${VERSION_SUFFIX}"
    script_basename="${SECTION_HEADER}"
  fi
  
  log_message "INFO" "Generating README documentation for ${script_basename} with ${model}..."
  
  # Estimate completion time if not skipped
  local estimated_seconds=""
  if [ "$skip_estimate" != "true" ]; then
    estimated_seconds=$(estimate_completion_time "${FILE_SIZE}" "${SCRIPT_COMPLEXITY}" "${model}")
    local estimated_time=$(format_time "${estimated_seconds}")
    log_message "INFO" "Estimated completion time: ${YELLOW}${estimated_time}${RESET}"
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
          "content": "You are an expert code documentarian tasked with producing professional, accurate, and comprehensive documentation. Analyze the provided script with precision, describing only the functionality explicitly present in the code. Generate a detailed Markdown README section that is clear, thorough, and professionally structured, suitable for developers and end-users."
        },
        {
          "role": "user",
          "content": "Analyze the following script provided as plain text. Pay close attention to specific elements such as references to applications, system paths, and command-line tools. Consider the script'\''s potential impact on the system.\n\nGenerate a Markdown README section with these sections:\n\n- **Overview**: Summarize the script'\''s purpose and primary actions.\n- **Requirements**: List prerequisites inferred from the script.\n- **Usage**: Provide precise instructions for running the script.\n- **What the Script Does**: Describe the script'\''s operations step-by-step.\n- **Important Notes**: Highlight critical details derived from the script.\n- **Disclaimer**: Warn about risks of running the script.\n\nFile: \($filename)\n\nScript Content:\n\($content)"
        }
      ],
      "stream": false
    }')
  
  # Log the prompt size (in characters)
  local prompt_size=$(echo "${payload}" | jq -r '.messages[1].content' | wc -c | tr -d ' ')
  jq --arg size "${prompt_size}" '.prompt_size_chars = $size' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
  
  # Send request to Ollama API
  log_message "INFO" "Sending request to Ollama API..."
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
      log_message "ERROR" "Failed to connect to Ollama API. Ensure the server is running."
      play_sound "error"
      exit 1
    fi
    
    # Show 100% completion
    display_progress 100 "$(format_time $((SECONDS - start_secs)))"
    echo ""
  else
    # Regular request without progress bar
    log_message "INFO" "Processing request..."
    curl -s -X POST "${OLLAMA_API}" \
      -H "Content-Type: application/json" \
      -d "${payload}" > "${temp_response}" &
    
    local pid=$!
    spinner $pid
    
    wait $pid
    if [ $? -ne 0 ]; then
      log_message "ERROR" "Failed to connect to Ollama API. Ensure the server is running."
      play_sound "error"
      exit 1
    fi
  fi
  
  local request_end_time=$(date +%s.%N)
  local request_duration=$(printf "%.2f" $(echo "${request_end_time} - ${request_start_time}" | bc))
  
  log_benchmark "${script_basename}" "${FILE_SIZE}" "${LINE_COUNT}" "${CHAR_COUNT}" "${model}" "api_request" "${request_duration}" "${prompt_size}" "${SCRIPT_COMPLEXITY}" ""
  
  # Parse response
  log_message "INFO" "Processing response..."
  local parse_start_time=$(date +%s.%N)
  
  if grep -q "error" "${temp_response}"; then
    log_message "ERROR" "Ollama response error:"
    cat "${temp_response}"
    jq --arg error "$(cat ${temp_response})" '.error = $error' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
    rm "${temp_response}"
    play_sound "error"
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
     '.ollama_metrics = {"total_duration": $total, "eval_count":