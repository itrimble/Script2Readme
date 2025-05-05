#!/bin/zsh
#
# script2readme.sh - Generate high-quality README documentation from scripts using Ollama models
# Author: Ian Trimble
# Created: April 28, 2025
# Version: 1.3.0 (Fixed)
#

# Enable debug mode only when explicitly requested
if [[ "$1" == "--debug" ]]; then
  set -x # Print commands and their arguments as they are executed.
  DEBUG_MODE=true # Set debug flag for log_message
  shift # Remove --debug from the arguments list
else
  DEBUG_MODE=false
fi

# =================== COLORS AND FORMATTING ===================
# Define terminal colors for enhanced output
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
RESET='\033[0m' # Reset all formatting

# Define a color gradient for the progress bar
declare -a GRADIENT
GRADIENT=(
  '\033[38;5;27m' '\033[38;5;33m' '\033[38;5;39m' '\033[38;5;45m' '\033[38;5;51m'
  '\033[38;5;50m' '\033[38;5;49m' '\033[38;5;48m' '\033[38;5;47m' '\033[38;5;46m'
)

# Check if the terminal supports colors; disable if not
if [ -t 1 ]; then
  COLORTERM=1 # Colors enabled
else
  COLORTERM=0 # Colors disabled
  # Reset all color variables to empty strings if colors are not supported
  RED='' GREEN='' YELLOW='' BLUE='' MAGENTA='' CYAN='' WHITE='' GRAY=''
  BOLD='' DIM='' UNDERLINE='' BLINK='' REVERSE='' RESET=''
  for i in {0..9}; do GRADIENT[$i]=''; done # Reset gradient colors
fi

# =================== HELPER FUNCTIONS ===================
# NOTE: All function definitions are placed here, before they are called.

# Function to log messages with different levels (INFO, SUCCESS, WARNING, ERROR, DEBUG)
log_message() {
  local level=$1 # Message level (e.g., INFO)
  local message=$2 # The message text
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S') # Current timestamp

  # Print message with appropriate color and icon based on level
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
      # Only print debug messages if debug mode is enabled
      if [[ "${DEBUG_MODE}" == "true" ]]; then
        echo -e "${GRAY}[${timestamp}] 🔍 ${message}${RESET}"
      fi
      ;;
    *) # Default case for unknown levels
      echo -e "[${timestamp}] ${message}"
      ;;
  esac
}

# Function to display the application logo (ASCII art)
show_logo() {
  # Only show logo if in an interactive terminal
  if ! is_terminal; then return 0; fi
  clear # Clear the terminal screen
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

# Function to display a random "Did you know?" tip
show_tip() {
  # Ensure TIPS array is populated before accessing (defined later in CONFIGURATION)
  if [ ${#TIPS[@]} -gt 0 ]; then
      local tip_index=$((RANDOM % ${#TIPS[@]})) # Select a random index
      local tip="${TIPS[$tip_index]}" # Get the tip
      # Only show tip if in an interactive terminal
      if is_terminal; then
          echo -e "\n${YELLOW}💡 ${BOLD}Did you know?${RESET} ${tip}${RESET}\n"
      fi
  fi
}

# Function to play sounds if sound is enabled in config
play_sound() {
  local sound_type=$1 # Type of sound ('complete' or 'error')

  # Check if sound is enabled (use default 0 if SOUND_ENABLED is not set)
  if [ ${SOUND_ENABLED:-0} -eq 1 ]; then
    # Check if afplay exists (macOS specific)
    if command -v afplay &> /dev/null; then
        # Use default sound paths if variables are empty
        local complete_sound="${SOUND_COMPLETE:-/System/Library/Sounds/Glass.aiff}"
        local error_sound="${SOUND_ERROR:-/System/Library/Sounds/Sosumi.aiff}"
        case ${sound_type} in
          "complete")
            # Play completion sound in the background, suppressing output
            afplay "${complete_sound}" &> /dev/null &
            ;;
          "error")
            # Play error sound in the background, suppressing output
            afplay "${error_sound}" &> /dev/null &
            ;;
        esac
    else
        log_message "DEBUG" "afplay command not found, cannot play sound."
    fi
  fi
}

# Function to display an animated spinner while a background process runs
spinner() {
  local pid=$1 # Process ID of the background task
  # Check if we are in an interactive terminal before showing spinner
  if ! is_terminal; then return 0; fi

  local delay=0.1 # Delay between frames
  local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' # Spinner characters

  # Loop while the process is still running
  while kill -0 $pid 2>/dev/null; do
    local temp=${spinstr#?} # Rotate the spinner string
    printf " %c  " "$spinstr" # Print the current spinner character
    local spinstr=$temp${spinstr%"$temp"}
    sleep $delay # Wait for the next frame
    printf "\b\b\b\b" # Move cursor back to overwrite
  done
  printf "    \b\b\b\b" # Clear the spinner area
}

# Function to display a progress bar with gradient colors
display_progress() {
  # Check if we are in an interactive terminal before showing progress
  if ! is_terminal; then return 0; fi

  local progress=$1 # Current progress percentage (0-100)
  local duration=$2 # Elapsed time string
  local width=40 # Width of the progress bar in characters

  # Ensure progress is within 0-100
  if [ $progress -lt 0 ]; then progress=0; fi
  if [ $progress -gt 100 ]; then progress=100; fi

  local filled=$((width * progress / 100)) # Number of filled characters
  local empty=$((width - filled)) # Number of empty characters
  local bar="" # Initialize the bar string

  # Create the filled part of the bar with gradient colors
  for ((i = 0; i < filled; i++)); do
    local color_index=$((i * ${#GRADIENT[@]} / width)) # Calculate color index based on position
    # Handle potential index out of bounds
    if [ $color_index -ge ${#GRADIENT[@]} ]; then color_index=$((${#GRADIENT[@]} - 1)); fi
    bar="${bar}${GRADIENT[$color_index]}█" # Append colored block
  done

  # Create the empty part of the bar
  for ((i = 0; i < empty; i++)); do
    bar="${bar}${GRAY}░" # Append gray block
  done

  # Print the complete progress bar with percentage and duration
  # \r moves the cursor to the beginning of the line for overwriting
  printf "\r${WHITE}[${RESET}${bar}${RESET}${WHITE}]${RESET} ${BOLD}%3d%%${RESET} ${WHITE}(${CYAN}%s${WHITE})${RESET}" $progress "$duration"
}

# Function to format time in seconds into a human-readable string (e.g., "1m 30s")
format_time() {
  local seconds_float=$1 # Total seconds (can be float)
  # Ensure input is numeric, default to 0
  if ! [[ "$seconds_float" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then seconds_float=0; fi
  local seconds_int=$(printf "%.0f" "$seconds_float") # Round to nearest integer

  # Use integer arithmetic for calculation
  local minutes=$((seconds_int / 60))
  local remaining_seconds=$((seconds_int % 60))

  # Format output based on whether minutes are present
  if [ $minutes -gt 0 ]; then
    echo "${minutes}m ${remaining_seconds}s"
  else
    echo "${seconds_int}s"
  fi
}

# Function to calculate a complexity score for a script based on features
calculate_complexity() {
  local content="$1" # Script content
  local line_count="$2" # Number of lines in the script

  # Ensure line_count is a number, default to 0 if not
  if ! [[ "$line_count" =~ ^[0-9]+$ ]]; then line_count=0; fi

  # Count various script features using grep
  # Use || echo "0" to handle cases where grep finds nothing
  local function_count=$(echo "${content}" | grep -c "function " || echo "0")
  local if_count=$(echo "${content}" | grep -E '(^|[^a-zA-Z0-9_])if\s+' || echo "0") # Avoid matching words like 'diff'
  local case_count=$(echo "${content}" | grep -c "case " || echo "0")
  local for_count=$(echo "${content}" | grep -E '(^|[^a-zA-Z0-9_])for\s+' || echo "0")
  local while_count=$(echo "${content}" | grep -E '(^|[^a-zA-Z0-9_])while\s+' || echo "0")

  # Calculate complexity score using weighted factors and bc for floating point math
  # Ensure factors are defined, use defaults if not
  local lc_factor=${LINE_FACTOR:-0.3}
  local fn_factor=${FUNCTION_FACTOR:-2.0}
  local cond_factor=${CONDITIONAL_FACTOR:-1.5}
  local loop_factor=${LOOP_FACTOR:-1.2}

  # Use bc for calculation, handle potential errors
  local complexity=$(echo "scale=2; (${line_count} * ${lc_factor}) + (${function_count} * ${fn_factor}) + ((${if_count} + ${case_count}) * ${cond_factor}) + ((${for_count} + ${while_count}) * ${loop_factor})" | bc 2>/dev/null || echo "1.0")

  # Ensure a minimum complexity score of 1.0
  if (( $(echo "$complexity < 1.0" | bc -l) )); then
    complexity=1.0
  fi

  # Return the calculated complexity score
  echo $complexity
}

# Function to estimate the completion time for generating documentation
estimate_completion_time() {
  local script_size=$1 # Size of the script in bytes
  local script_complexity=$2 # Calculated complexity score
  local model=$3 # Ollama model being used

  # Ensure inputs are numeric, provide defaults
  if ! [[ "$script_size" =~ ^[0-9]+$ ]]; then script_size=1000; fi
  if ! [[ "$script_complexity" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then script_complexity=1.0; fi

  # Get the complexity factor for the selected model
  local model_factor=${MODEL_COMPLEXITY[$model]}
  if [ -z "$model_factor" ]; then
    model_factor=${MODEL_COMPLEXITY["default"]:-2.5} # Use default if model not found
  fi

  # Base time in seconds per KB, adjusted for complexity
  local base_time=2

  # Adjust based on script size (larger scripts may take disproportionately longer)
  # Use bc for floating point exponentiation (approximated with ^0.6)
  local size_kb=$(echo "scale=4; $script_size / 1024" | bc)
  if (( $(echo "$size_kb <= 0" | bc -l) )); then size_kb=0.1; fi # Avoid log(0)
  # Check if bc supports 'l' (natural log) function
  local size_factor="1" # Default size factor
  if echo "l(1)" | bc -l >/dev/null 2>&1; then
      size_factor=$(echo "scale=4; e(0.6 * l($size_kb))" | bc -l 2>/dev/null || echo "1") # Use natural log and exp for power
  else
      log_message "DEBUG" "bc does not support 'l'. Using simplified size factor."
      # Simplified factor if log not available
      size_factor=$(echo "scale=2; 1 + $size_kb / 10" | bc)
  fi
  if (( $(echo "$size_factor < 1" | bc -l) )); then size_factor=1; fi # Ensure factor is at least 1

  # Calculate estimated seconds, factoring in script size, model, and script complexity
  local complexity_adjustment=$(printf "%.2f" $(echo "scale=2; $script_complexity * 0.8" | bc))
  local estimate=$(printf "%.0f" $(echo "scale=0; $base_time * $size_factor * $model_factor * $complexity_adjustment" | bc))

  # Ensure a minimum reasonable estimate (e.g., 10 seconds)
  if [ $estimate -lt 10 ]; then
    estimate=10
  fi

  echo $estimate # Return estimated time in seconds
}

# Function to display detailed description and stats for a specific model
show_model_description() {
  local model=$1 # Model name
  local description=""

  # Get the model's description from the associative array
  if [ -n "${MODEL_DESCRIPTIONS[$model]}" ]; then
    description="${MODEL_DESCRIPTIONS[$model]}"
  else
    description="${MODEL_DESCRIPTIONS["default"]:-'No description available.'}" # Use default if not found
  fi

  # Get the model's complexity factor
  local complexity=${MODEL_COMPLEXITY[$model]}
  if [ -z "$complexity" ]; then
    complexity=${MODEL_COMPLEXITY["default"]:-2.5}
  fi

  # Determine speed category based on complexity factor
  local speed=""
  local speed_color=""
  if (( $(echo "$complexity < 1.5" | bc -l) )); then speed="Very Fast"; speed_color="${GREEN}";
  elif (( $(echo "$complexity < 2.5" | bc -l) )); then speed="Fast"; speed_color="${CYAN}";
  elif (( $(echo "$complexity < 4.0" | bc -l) )); then speed="Medium"; speed_color="${YELLOW}";
  else speed="Slow"; speed_color="${RED}"; fi

  # Print model details
  echo -e "${MAGENTA}${BOLD}${model}${RESET}"
  echo -e "${GRAY}${description}${RESET}"
  echo -e "${GRAY}• Speed: ${speed_color}${speed}${RESET}"
  echo -e "${GRAY}• Performance factor: ${WHITE}${complexity}x${RESET}"

  # Display average run time from benchmark log if available
  if [ -f "${BENCHMARK_LOG}" ]; then
    # Use awk to calculate average time for 'total_analysis' operations for this model
    local avg_time=$(awk -F',' -v model="$model" '$7 == model && $8 == "total_analysis" {sum+=$9; count++} END {if(count>0) print sum/count; else print "N/A"}' "${BENCHMARK_LOG}")
    local runs=$(awk -F',' -v model="$model" '$7 == model && $8 == "total_analysis" {count++} END {print count+0}' "${BENCHMARK_LOG}") # Count runs

    if [[ "$avg_time" != "N/A" && $runs -gt 0 ]]; then
      echo -e "${GRAY}• Average run time: ${WHITE}$(printf "%.2f" ${avg_time})s${RESET} (${runs} previous runs)"
    fi
  fi
  echo "" # Add a blank line for spacing
}

# Function to display usage information (help message)
show_usage() {
  # Print application header
  echo -e "${CYAN}${BOLD}${APP_NAME}${RESET} ${WHITE}(v${APP_VERSION})${RESET}"
  echo -e "${GRAY}Generates README documentation from script files using Ollama models${RESET}"
  echo ""
  # Print usage syntax
  echo -e "${YELLOW}${BOLD}Usage:${RESET} $0 ${GREEN}[OPTIONS]${RESET} ${MAGENTA}<input_file>${RESET} ${BLUE}[model]${RESET}"
  echo ""
  # List available options
  echo -e "${YELLOW}${BOLD}Options:${RESET}"
  echo -e "  ${GREEN}--debug${RESET}                Enable debug mode (print commands)"
  echo -e "  ${GREEN}--help${RESET}                 Show this help message"
  echo -e "  ${GREEN}--list-models${RESET}          List available Ollama models with descriptions"
  echo -e "  ${GREEN}--version${RESET}              Show version information"
  echo -e "  ${GREEN}--no-estimate${RESET}          Skip time estimation calculation"
  echo -e "  ${GREEN}--no-color${RESET}             Disable colored output"
  echo -e "  ${GREEN}--sound${RESET}                Enable sound notifications (macOS only)"
  echo -e "  ${GREEN}--batch${RESET} ${BLUE}<pattern>${RESET}      Process multiple files matching pattern (e.g., \"*.sh\")"
  echo -e "  ${GREEN}--watch${RESET} ${BLUE}<directory>${RESET}    Watch directory for new/modified scripts and process them"
  echo -e "  ${GREEN}--process-existing${RESET}     Process existing files when starting watch mode"
  echo -e "  ${GREEN}--template${RESET} ${BLUE}<name>${RESET}      Use specified template (basic implementation)"
  echo -e "  ${GREEN}--interactive${RESET}          Edit AI-generated documentation before saving"
  echo -e "  ${GREEN}--update${RESET}               Update existing documentation preserving manual edits (Not Implemented)"
  echo -e "  ${GREEN}--export${RESET} ${BLUE}<format>${RESET}      Export documentation to specified format (html, pdf)"
  echo -e "  ${GREEN}--format${RESET} ${BLUE}<style>${RESET}       README format style (basic, enhanced, fancy)"
  echo -e "  ${GREEN}--toc${RESET}                  Add table of contents to README (enhanced/fancy formats)"
  echo -e "  ${GREEN}--config${RESET}               Create or update configuration file interactively"
  echo -e "  ${GREEN}--stats${RESET}                Show benchmark statistics for all runs"
  echo -e "  ${GREEN}--compare${RESET} ${MAGENTA}<input_file>${RESET} Compare multiple models on the same script"
  echo ""
  # List arguments
  echo -e "${YELLOW}${BOLD}Arguments:${RESET}"
  echo -e "  ${MAGENTA}<input_file>${RESET}           Path to script file to document (required unless using --watch, --batch, --stats, --compare)"
  echo -e "  ${BLUE}[model]${RESET}                Optional Ollama model name (default: ${WHITE}${DEFAULT_MODEL:-default}${RESET})" # Show default
  echo ""
  # Provide examples
  echo -e "${YELLOW}${BOLD}Examples:${RESET}"
  echo -e "  ${GRAY}$0 my_script.sh${RESET}"
  echo -e "  ${GRAY}$0 my_script.sh codellama:7b${RESET}"
  echo -e "  ${GRAY}$0 --batch \"*.py\" --template code${RESET}"
  echo -e "  ${GRAY}$0 --watch ~/scripts --process-existing${RESET}"
  echo -e "  ${GRAY}$0 my_script.sh --format fancy --toc${RESET}"
  echo -e "  ${GRAY}$0 --compare my_script.sh${RESET}"
  echo -e "  ${GRAY}$0 --stats${RESET}"
  echo ""
  # Describe output
  echo -e "${YELLOW}${BOLD}Output:${RESET}"
  echo -e "  - Updates README.md in the current directory with script documentation"
  echo -e "  - Logs performance metrics and benchmarks to ${BENCHMARK_DIR:-$HOME/ollama_benchmarks}" # Show default
  echo ""
  # Show a random tip
  show_tip
  exit 0 # Exit after showing help
}

# Function to display version information
show_version() {
  echo -e "${CYAN}${BOLD}${APP_NAME}${RESET} ${WHITE}v${APP_VERSION}${RESET}"
  echo -e "${GRAY}Author: ${WHITE}${APP_AUTHOR}${RESET}"
  echo -e "${GRAY}Created: April 28, 2025${RESET}"
  echo -e "${GRAY}License: MIT${RESET}"
  exit 0 # Exit after showing version
}

# Function to display benchmark statistics from the log file
show_benchmark_stats() {
  # Check if the benchmark log file exists
  if [ ! -f "${BENCHMARK_LOG}" ]; then
    log_message "ERROR" "No benchmark data found at ${BENCHMARK_LOG}."
    exit 1
  fi

  echo -e "${CYAN}${BOLD}Benchmark Statistics${RESET}"
  echo ""

  # --- Model Performance ---
  echo -e "${YELLOW}${BOLD}Model Performance${RESET}"
  echo -e "${WHITE}|--------------------|-----------|------------|----------|${RESET}"
  echo -e "${WHITE}| Model              | Avg Time  | Accuracy % | Runs     |${RESET}"
  echo -e "${WHITE}|--------------------|-----------|------------|----------|${RESET}"

  # Extract unique models from the log (column 7), skipping header and system entries
  local models=$(tail -n +2 "${BENCHMARK_LOG}" | awk -F',' '$7 != "system" {print $7}' | sort | uniq)

  for model in $models; do
    # Calculate stats for each model using awk
    local stats=$(awk -F',' -v model="$model" '
      $7 == model && $8 == "total_analysis" {
        runs++;
        sum_time += $9;
        if ($14 != "" && $14 != "N/A") { sum_accuracy += $14; accuracy_runs++ } # Ensure accuracy is numeric
      }
      END {
        avg_time = (runs > 0) ? sum_time / runs : "N/A";
        avg_accuracy = (accuracy_runs > 0) ? (sum_accuracy / accuracy_runs) * 100 : "N/A";
        print avg_time, avg_accuracy, runs+0;
      }' "${BENCHMARK_LOG}")

    local avg_time=$(echo $stats | cut -d' ' -f1)
    local accuracy=$(echo $stats | cut -d' ' -f2)
    local runs=$(echo $stats | cut -d' ' -f3)

    # Format the output strings for table alignment
    local model_display=$(printf "%-18s" "${model}")
    local time_display="N/A"
    if [[ "$avg_time" != "N/A" ]]; then time_display=$(printf "%.2fs" ${avg_time}); fi
    time_display=$(printf "%-9s" "${time_display}")

    local accuracy_display="N/A"
    if [[ "$accuracy" != "N/A" ]]; then accuracy_display=$(printf "%.1f%%" ${accuracy}); fi
    accuracy_display=$(printf "%-10s" "${accuracy_display}")

    local runs_display=$(printf "%-8s" "${runs}")

    # Print the table row for the model
    echo -e "| ${MAGENTA}${model_display}${RESET} | ${CYAN}${time_display}${RESET} | ${GREEN}${accuracy_display}${RESET} | ${YELLOW}${runs_display}${RESET} |"
  done
  echo -e "${WHITE}|--------------------|-----------|------------|----------|${RESET}"
  echo ""

  # --- Script Type Statistics ---
  echo -e "${YELLOW}${BOLD}Script Types${RESET}"
  echo -e "${WHITE}|------------|---------|------------|${RESET}"
  echo -e "${WHITE}| Type       | Count   | Avg Time   |${RESET}"
  echo -e "${WHITE}|------------|---------|------------|${RESET}"

  # Extract script extensions (type) and calculate stats
  # Use awk to extract extension from filename (column 3)
  local exts=$(tail -n +2 "${BENCHMARK_LOG}" | awk -F',' '
    $8 == "total_analysis" {
      # Extract extension robustly, handle names with multiple dots
      n = split($3, parts, ".");
      if (n > 1 && parts[n] ~ /^[a-zA-Z0-9]+$/) {
          ext = parts[n];
      } else {
          ext = "other"; # Handle files with no extension or complex names
      }
      if (ext != "" && ext != "system" && $3 !~ /^(unknown|system)$/ ) print ext; # Filter out non-file entries
    }' | sort | uniq)


  for ext in $exts; do
    # Calculate stats for each script type using awk
    # Match filenames ending with .ext explicitly
    local type_stats=$(awk -F',' -v ext="${ext}" '
      BEGIN { count=0; sum_time=0; }
      $8 == "total_analysis" {
          n = split($3, parts, ".");
          current_ext = (n > 1 && parts[n] ~ /^[a-zA-Z0-9]+$/) ? parts[n] : "other";
          if (current_ext == ext) {
              count++;
              sum_time += $9;
          }
      }
      END {
        avg_time = (count > 0) ? sum_time / count : "N/A";
        print count+0, avg_time;
      }' "${BENCHMARK_LOG}")


    local count=$(echo $type_stats | cut -d' ' -f1)
    local avg_time=$(echo $type_stats | cut -d' ' -f2)

    # Format for display
    local ext_display=$(printf "%-10s" "${ext}")
    local count_display=$(printf "%-7s" "${count}")
    local time_display="N/A"
    if [[ "$avg_time" != "N/A" ]]; then time_display=$(printf "%.2fs" ${avg_time}); fi
    time_display=$(printf "%-10s" "${time_display}")

    # Print the table row for the script type
    echo -e "| ${CYAN}${ext_display}${RESET} | ${YELLOW}${count_display}${RESET} | ${GREEN}${time_display}${RESET} |"
  done
  echo -e "${WHITE}|------------|---------|------------|${RESET}"
  echo ""

  # --- Overall Statistics ---
  # Calculate overall stats using awk
  local overall_stats=$(awk -F',' '
    $8 == "total_analysis" {
      total_runs++;
      sum_total_time += $9;
      sum_script_size += $4;
      sum_script_lines += $5;
    }
    END {
      avg_total_time = (total_runs > 0) ? sum_total_time / total_runs : "N/A";
      avg_script_size = (total_runs > 0) ? sum_script_size / total_runs : "N/A";
      avg_script_lines = (total_runs > 0) ? sum_script_lines / total_runs : "N/A";
      print total_runs+0, avg_total_time, avg_script_size, avg_script_lines;
    }' "${BENCHMARK_LOG}")

  local total_runs=$(echo $overall_stats | cut -d' ' -f1)
  local avg_total_time=$(echo $overall_stats | cut -d' ' -f2)
  local avg_script_size=$(echo $overall_stats | cut -d' ' -f3)
  local avg_script_lines=$(echo $overall_stats | cut -d' ' -f4)

  # Format times and sizes
  local avg_time_display="N/A"
  if [[ "$avg_total_time" != "N/A" ]]; then avg_time_display=$(printf "%.2fs" ${avg_total_time}); fi
  local avg_size_display="N/A"
  if [[ "$avg_script_size" != "N/A" ]]; then avg_size_display=$(printf "%.2f bytes" ${avg_script_size}); fi
  local avg_lines_display="N/A"
  if [[ "$avg_script_lines" != "N/A" ]]; then avg_lines_display=$(printf "%.1f lines" ${avg_script_lines}); fi

  # Print overall statistics
  echo -e "${YELLOW}${BOLD}Overall Statistics${RESET}"
  echo -e "${GRAY}Total runs: ${WHITE}${total_runs}${RESET}"
  echo -e "${GRAY}Average runtime: ${WHITE}${avg_time_display}${RESET}"
  echo -e "${GRAY}Average script size: ${WHITE}${avg_size_display}${RESET}"
  echo -e "${GRAY}Average script lines: ${WHITE}${avg_lines_display}${RESET}"
  echo ""

  # --- Benchmark File Locations ---
  show_benchmark_location # Call function to display file paths
  echo ""

  exit 0 # Exit after showing stats
}

# Function to compare outputs of multiple models for a single script
compare_models() {
  local input_file=$1 # The script file to compare models on

  log_message "INFO" "Comparing models for ${input_file}..."

  # Validate the input file existence
  if [ ! -f "${input_file}" ]; then
    log_message "ERROR" "Input file '${input_file}' does not exist."
    exit 1
  fi

  # Get the list of available Ollama models
  get_models

  # Ask user which models to compare if running interactively
  local models_to_compare=()
  if is_terminal; then
    echo -e "${YELLOW}${BOLD}Select models to compare (space-separated numbers, e.g., '1 3 5'):${RESET}"
    # Display numbered list of available models
    for ((i=1; i<=${#models[@]}; i++)); do
      echo -e "${WHITE}${i})${RESET} ${MAGENTA}${models[$((i-1))]}${RESET}" # Use 0-based index
    done
    echo ""
    # Read user's selection
    read -p "Models to compare: " model_selection

    # Convert selected numbers to model names
    for num in $model_selection; do
      if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le ${#models[@]} ]; then
        # Use 0-based index for array access
        models_to_compare+=("${models[$((num-1))]}")
      fi
    done
  else
    # Non-interactive: use a predefined set of good models for comparison
    models_to_compare=("qwen2.5-coder:7b" "deepseek-coder:latest" "codellama:7b")
    log_message "INFO" "Non-interactive mode. Comparing default set: ${models_to_compare[*]}"
  fi

  # If no valid models were selected interactively, use the default set
  if [ ${#models_to_compare[@]} -eq 0 ]; then
    log_message "WARNING" "No valid models selected. Using default comparison set: qwen2.5-coder:7b, deepseek-coder:latest, codellama:7b"
    models_to_compare=("qwen2.5-coder:7b" "deepseek-coder:latest" "codellama:7b")
  fi

  # Create a dedicated directory for this comparison session
  local comparison_dir="${BENCHMARK_DIR}/comparison_${SESSION_ID}_$(basename ${input_file} .${input_file##*.})"
  mkdir -p "${comparison_dir}"
  log_message "INFO" "Saving comparison results to: ${comparison_dir}"

  # Create the main comparison markdown file
  local comparison_file="${comparison_dir}/model_comparison_summary.md"

  # Initialize the comparison summary file with headers
  {
    echo "# Model Comparison for $(basename "${input_file}")"
    echo ""
    echo "Generated on $(date '+%Y-%m-%d %H:%M:%S') by script2readme v${APP_VERSION}"
    echo ""
    echo "## Script Information"
    echo ""
    echo "| Property | Value |"
    echo "|----------|-------|"
    echo "| Filename | $(basename "${input_file}") |"
    echo "| Size | $(stat -f%z "${input_file}" 2>/dev/null || stat -c%s "${input_file}" 2>/dev/null || echo "0") bytes |"
    echo "| Lines | $(wc -l < "${input_file}" | tr -d ' ') |"
    echo ""
    echo "## Performance Comparison"
    echo ""
    echo "| Model | Time (s) | Word Count | Notes | Full Output |"
    echo "|-------|----------|------------|-------|-------------|"
  } > "${comparison_file}"

  # Validate the input file once before looping through models
  validate_input_file "${input_file}"
  if [ $? -ne 0 ]; then
      log_message "ERROR" "Failed to validate input file ${input_file}. Aborting comparison."
      exit 1
  fi

  # Process the script with each selected model
  for model_to_test in "${models_to_compare[@]}"; do # Use different variable name
    log_message "INFO" "Testing with model: ${model_to_test}"

    # Skip if the model doesn't actually exist locally (e.g., typo in selection)
    # Use exact match grep
    if ! ollama list | grep -q -w "^${model_to_test}"; then
      log_message "WARNING" "Model '${model_to_test}' not found locally. Skipping."
      # Add a note to the comparison file
      echo "| ${model_to_test} | N/A | N/A | Model not found | N/A |" >> "${comparison_file}"
      continue
    fi

    # --- Run the generation process (similar to generate_readme but without writing to main README) ---
    local model_start_time=$(date +%s.%N)

    # Create request payload (using validated global CONTENT, SCRIPT_TYPE etc.)
    # Ensure CONTENT is escaped for JSON
    local escaped_content_compare=$(echo "$CONTENT" | jq -Rsa .)
    local payload=$(jq -n \
      --arg model "${model_to_test}" \
      --argjson content "${escaped_content_compare}" \
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
            "content": "Analyze the following \($script_type) script provided as plain text. Pay close attention to specific elements such as references to applications, system paths, and command-line tools. Consider the script'\''s potential impact on the system.\n\nGenerate a Markdown README section with these sections:\n\n- **Overview**: Summarize the script'\''s purpose and primary actions.\n- **Requirements**: List prerequisites inferred from the script.\n- **Usage**: Provide precise instructions for running the script.\n- **What the Script Does**: Describe the script'\''s operations step-by-step.\n- **Important Notes**: Highlight critical details derived from the script.\n- **Disclaimer**: Warn about risks of running the script.\n\nFile: \($filename)\n\nScript Content:\n\( $content )"
          }
        ],
        "stream": false
      }')

    # Temporary file for the API response
    local temp_response=$(mktemp)

    # Send the request to Ollama API
    log_message "INFO" "Sending request to Ollama API for ${model_to_test}..."
    curl -s -X POST "${OLLAMA_API}" \
      -H "Content-Type: application/json" \
      -d "${payload}" > "${temp_response}"

    local curl_exit_code=$?
    if [ $curl_exit_code -ne 0 ]; then
        log_message "ERROR" "curl command failed for model ${model_to_test} with exit code ${curl_exit_code}."
        echo "| ${model_to_test} | Error | N/A | curl failed | N/A |" >> "${comparison_file}"
        rm "${temp_response}"
        continue
    fi

    # Check for errors in the Ollama response
    if jq -e '.error' "${temp_response}" > /dev/null 2>&1; then
      log_message "ERROR" "Error in Ollama response for ${model_to_test}:"
      jq '.' "${temp_response}" # Print error details
      echo "| ${model_to_test} | Error | N/A | API Error | N/A |" >> "${comparison_file}"
      rm "${temp_response}"
      continue
    fi

    # Extract response content using robust methods
    local RESPONSE_COMPARE="" # Use different variable name
    if jq -e '.message.content' "${temp_response}" > /dev/null 2>&1; then
      RESPONSE_COMPARE=$(jq -r '.message.content' "${temp_response}")
    else
      # Fallback methods if jq path fails
      RESPONSE_COMPARE=$(grep -o '"content":"[^"]*"' "${temp_response}" | sed 's/"content":"//;s/"$//')
      if [ -z "${RESPONSE_COMPARE}" ]; then RESPONSE_COMPARE=$(perl -0777 -ne 'print $1 if /"content":\s*"(.*?)(?<!\\)"/s' "${temp_response}"); fi
      if [ -z "${RESPONSE_COMPARE}" ]; then RESPONSE_COMPARE=$(cat "${temp_response}" | python3 -c "import json, sys; d=json.load(sys.stdin); print(d.get('message', {}).get('content', ''))" 2>/dev/null); fi
    fi

    # Check if response content is empty
     if [ -z "${RESPONSE_COMPARE}" ]; then
        log_message "ERROR" "Empty response content from Ollama for model ${model_to_test}."
        echo "Raw response:"
        cat "${temp_response}"
        echo "| ${model_to_test} | Error | N/A | Empty Response | N/A |" >> "${comparison_file}"
        rm "${temp_response}"
        continue
    fi

    # Save the individual model's response to a file
    local model_response_file="${comparison_dir}/${model_to_test//[:\/]/_}.md" # Sanitize model name for filename
    echo "${RESPONSE_COMPARE}" > "${model_response_file}"
    log_message "DEBUG" "Saved response for ${model_to_test} to ${model_response_file}"

    # Calculate timing and statistics
    local model_end_time=$(date +%s.%N)
    local model_duration=$(printf "%.2f" $(echo "${model_end_time} - ${model_start_time}" | bc))
    local word_count=$(echo "${RESPONSE_COMPARE}" | wc -w | tr -d ' ')

    # Add the results to the comparison summary table
    echo "| ${model_to_test} | ${model_duration} | ${word_count} | - | [View Output](./$(basename "${model_response_file}")) |" >> "${comparison_file}"

    # Clean up temporary response file
    rm "${temp_response}"
  done

  # --- Finalize the comparison summary file ---
  {
    echo ""
    echo "## Summary"
    echo ""
    echo "This comparison shows how different models analyze the same script. The quality of documentation can vary significantly between models, with some providing more detailed explanations while others may be more concise or faster."
    echo ""
    echo "Consider factors like speed, detail level, and accuracy when choosing a model for your needs."
    echo ""
    echo "## How to View Full Outputs"
    echo ""
    echo "The individual model outputs are saved in the same directory as this file:"
    echo "\`\`\`"
    echo "${comparison_dir}"
    echo "\`\`\`"
  } >> "${comparison_file}"

  # --- Output results ---
  log_message "SUCCESS" "Model comparison complete!"
  log_message "INFO" "Comparison summary saved to: ${comparison_file}"

  # Open the comparison summary file automatically if on macOS
  if [[ "$OSTYPE" == "darwin"* ]]; then
    open "${comparison_file}"
  fi

  exit 0 # Exit after comparison
}

# Function to interactively update the configuration file
update_config() {
  echo -e "${CYAN}${BOLD}Configuration Setup${RESET}"
  echo ""

  # Ask for the default model
  echo -e "${YELLOW}Default model:${RESET} (current: ${WHITE}${DEFAULT_MODEL:-none}${RESET})"
  read -r new_model
  # Keep current value if user enters nothing
  if [ -z "$new_model" ]; then new_model="${DEFAULT_MODEL}"; fi

  # Ask for sound preference
  local current_sound_pref="N"
  if [ ${SOUND_ENABLED:-0} -eq 1 ]; then current_sound_pref="y"; fi
  echo -e "${YELLOW}Enable sound effects?${RESET} (y/N) [current: ${current_sound_pref}]"
  read -r sound_pref
  local sound_enabled_str="false"
  if [[ "${sound_pref}" =~ ^[Yy]$ ]]; then sound_enabled_str="true"; fi

  # Ask for preferred README format
  local current_format="${README_FORMAT:-enhanced}" # Use current or default
  echo -e "${YELLOW}Preferred README format:${RESET} (basic, enhanced, fancy) [current: ${current_format}]"
  read -r format_pref
  if [ -z "$format_pref" ]; then format_pref="${current_format}"; fi
  # Validate format choice, default to 'enhanced' if invalid
  if [[ ! "${format_pref}" =~ ^(basic|enhanced|fancy)$ ]]; then
    log_message "WARNING" "Invalid format '${format_pref}'. Defaulting to 'enhanced'."
    format_pref="enhanced"
  fi

  # Write the updated configuration to the file using jq for proper JSON formatting
  jq -n \
    --arg model "${new_model}" \
    --argjson sound "${sound_enabled_str}" \
    --arg format "${format_pref}" \
    '{ "default_model": $model, "sound_enabled": $sound, "template": "default", "preferred_format": $format }' > "${CONFIG_FILE}"

  log_message "SUCCESS" "Configuration updated in ${CONFIG_FILE}!"
  exit 0 # Exit after updating config
}

# Function to get system information (CPU, Memory, OS, Ollama version)
get_system_info() {
  # Use sysctl and sw_vers for macOS, provide fallbacks for other systems
  local cpu_info=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || uname -p 2>/dev/null || echo "Unknown")
  # Get memory size in bytes, then format
  local mem_bytes=$(sysctl -n hw.memsize 2>/dev/null || grep MemTotal /proc/meminfo | awk '{print $2 * 1024}' 2>/dev/null || echo 0)
  local memory_info="Unknown"
  if [ "$mem_bytes" -gt 0 ]; then
      memory_info=$(echo "scale=1; $mem_bytes / (1024*1024*1024)" | bc | awk '{printf "%.1f GB", $1}')
  fi

  local os_info=$(sw_vers -productName 2>/dev/null && sw_vers -productVersion 2>/dev/null || uname -s -r 2>/dev/null || echo "Unknown")
  # Use ollama --version for consistency
  local ollama_version=$(ollama --version 2>/dev/null || echo "Not Found")

  # Add system info to the metrics log for this session
  # Ensure METRICS_LOG is defined and writable
  if [ -n "${METRICS_LOG}" ] && [ -w "$(dirname "${METRICS_LOG}")" ]; then
      jq --arg cpu "${cpu_info}" \
         --arg mem "${memory_info}" \
         --arg os "${os_info}" \
         --arg ollama "${ollama_version}" \
         '.system_info = {"cpu": $cpu, "memory": $mem, "os": $os, "ollama_version": $ollama}' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}" \
         || log_message "WARNING" "Failed to write system info to metrics log."
  fi

  log_message "INFO" "System Info: CPU: ${cpu_info}, Memory: ${memory_info}, OS: ${os_info}, Ollama: ${ollama_version}"
}

# Function to get current resource usage (CPU %, Memory RSS) of the script itself
get_resource_usage() {
  # Use ps command to get CPU and Resident Set Size (memory) for the current process ($$)
  # Handle potential errors if ps fails
  local cpu_usage=$(ps -o %cpu= -p $$ | awk '{print $1}' 2>/dev/null || echo "N/A")
  local memory_rss_kb=$(ps -o rss= -p $$ 2>/dev/null || echo "0")
  local memory_usage="N/A"
  if [[ "$memory_rss_kb" =~ ^[0-9]+$ ]] && [ "$memory_rss_kb" -gt 0 ]; then
      memory_usage=$(printf "%.0f MB" $(echo "scale=0; $memory_rss_kb / 1024" | bc)) # Convert KB to MB
  fi

  echo "${cpu_usage},${memory_usage}" # Return comma-separated values
}

# Function to log benchmark data to CSV and JSON files
log_benchmark() {
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ") # ISO 8601 timestamp
  local script_name=$1
  local script_size=$2
  local script_lines=$3
  local script_chars=$4
  local model=$5
  local operation=$6 # e.g., 'api_request', 'total_analysis'
  local duration=$7 # Duration in seconds
  local token_count=$8 # Estimated token count (or word count)
  local complexity=$9 # Script complexity score
  local accuracy=${10} # Estimation accuracy (if applicable)

  # Ensure numeric fields have defaults if empty
  script_size=${script_size:-0}
  script_lines=${script_lines:-0}
  script_chars=${script_chars:-0}
  duration=${duration:-0}
  token_count=${token_count:-0}
  complexity=${complexity:-1.0}
  accuracy=${accuracy:-""} # Accuracy can be empty

  # Get current resource usage
  local resource_usage=$(get_resource_usage)
  local cpu_usage=$(echo ${resource_usage} | cut -d, -f1)
  local memory_usage=$(echo ${resource_usage} | cut -d, -f2)

  # Ensure log files/dirs are writable
  if [ -w "${BENCHMARK_LOG}" ] && [ -w "${METRICS_LOG}" ]; then
      # Log to CSV file for historical data
      echo "${timestamp},${SESSION_ID},${script_name},${script_size},${script_lines},${script_chars},${model},${operation},${duration},${token_count},${cpu_usage},${memory_usage},${complexity},${accuracy}" >> "${BENCHMARK_LOG}"

      # Add metric entry to the session's JSON log file
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
         '.metrics += [{"timestamp": $timestamp, "script": $script, "size_bytes": $size, "line_count": $lines, "char_count": $chars, "model": $model, "operation": $op, "duration": $dur, "token_count": $tokens, "cpu_usage": $cpu, "memory_usage": $mem, "complexity": $complexity, "accuracy": $accuracy}]' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}" \
         || log_message "WARNING" "Failed to write to metrics log ${METRICS_LOG}"
  else
      log_message "WARNING" "Cannot write to benchmark logs (${BENCHMARK_LOG} or ${METRICS_LOG}). Check permissions."
  fi

  log_message "DEBUG" "Logged benchmark: ${operation} for ${script_name} took ${duration}s"
  # Return operation:duration for potential chaining or further use
  echo "${operation}:${duration}"
}

# Function to generate a formatted summary box after README generation
generate_benchmark_summary() {
  local model=$1
  local script_name=$2
  local total_time=$3
  local api_time=$4
  local parse_time=$5
  local script_size=$6
  local script_lines=$7
  local script_chars=$8
  local token_count=$9 # Word count from response
  local estimated_time=${10}
  local complexity=${11}

  # Ensure numeric fields have defaults
  total_time=${total_time:-0}
  api_time=${api_time:-0}
  parse_time=${parse_time:-0}
  script_size=${script_size:-0}
  script_lines=${script_lines:-0}
  script_chars=${script_chars:-0}
  token_count=${token_count:-0}
  estimated_time=${estimated_time:-""}
  complexity=${complexity:-1.0}


  # Calculate estimation accuracy percentage
  local accuracy="N/A"
  if [ -n "$estimated_time" ] && [ "$estimated_time" -gt 0 ] && [ "$(echo "$total_time > 0.01" | bc -l)" -eq 1 ]; then # Avoid division by zero/tiny
      accuracy=$(printf "%.1f" $(echo "scale=1; (${estimated_time} / ${total_time}) * 100" | bc 2>/dev/null || echo "0"))
      # Handle potential bc errors or invalid results
      if [[ -z "$accuracy" || "$accuracy" == ".0" || "$accuracy" == "0.0" || ! "$accuracy" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
          accuracy="N/A"
      else
          accuracy="${accuracy}%"
      fi
  fi

  # Print the formatted summary box
  echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BLUE}║ ${CYAN}${BOLD}README GENERATION COMPLETE                         ${RESET}${BLUE}║${RESET}"
  echo -e "${BLUE}╠══════════════════════════════════════════════════════╣${RESET}"
  echo -e "${BLUE}║ ${WHITE}📄 Script:${RESET} ${YELLOW}${script_name}${RESET}$(printf "%$((40-${#script_name}))s" "")${BLUE}║${RESET}" # Use printf for padding
  echo -e "${BLUE}║ ${WHITE}🤖 Model:${RESET} ${MAGENTA}${model}${RESET}$(printf "%$((41-${#model}))s" "")${BLUE}║${RESET}"
  echo -e "${BLUE}║ ${WHITE}⏱️  Total time:${RESET} ${GREEN}${total_time}s${RESET}$(printf "%$((37-${#total_time}))s" "")${BLUE}║${RESET}"

  # Display estimated vs actual time if estimation was performed
  if [ -n "$estimated_time" ]; then
    local est_vs_actual="${estimated_time}s vs ${total_time}s (${accuracy})"
    # Adjust padding dynamically based on the length of the string
    local padding=$((30 - ${#est_vs_actual}))
    if [ $padding -lt 0 ]; then padding=0; fi
    echo -e "${BLUE}║ ${WHITE}🔮 Est. vs Actual:${RESET} ${est_vs_actual}$(printf "%${padding}s" "")${BLUE}║${RESET}"
  fi

  echo -e "${BLUE}║ ${WHITE}🔄 API request time:${RESET} ${CYAN}${api_time}s${RESET}$(printf "%$((31-${#api_time}))s" "")${BLUE}║${RESET}"
  echo -e "${BLUE}║ ${WHITE}🔍 Response parse time:${RESET} ${CYAN}${parse_time}s${RESET}$(printf "%$((29-${#parse_time}))s" "")${BLUE}║${RESET}"
  echo -e "${BLUE}║ ${WHITE}📝 Response size:${RESET} ~${token_count} words$(printf "%$((33-${#token_count}))s" "")${BLUE}║${RESET}"
  echo -e "${BLUE}║ ${WHITE}🧮 Script complexity:${RESET} ${complexity}$(printf "%$((31-${#complexity}))s" "")${BLUE}║${RESET}"
  echo -e "${BLUE}║ ${WHITE}📂 Script metrics:${RESET}$(printf "%$((35))s" "")${BLUE}║${RESET}"

  # Calculate script size in KB
  local kb_size=$(printf "%.2f" $(echo "scale=2; ${script_size}/1024" | bc))
  echo -e "${BLUE}║   ${GRAY}- Size: ${script_size} bytes (${kb_size} KB)${RESET}$(printf "%$((38-${#script_size}-${#kb_size}))s" "")${BLUE}║${RESET}"
  echo -e "${BLUE}║   ${GRAY}- Lines: ${script_lines}${RESET}$(printf "%$((43-${#script_lines}))s" "")${BLUE}║${RESET}"
  echo -e "${BLUE}║   ${GRAY}- Characters: ${script_chars}${RESET}$(printf "%$((37-${#script_chars}))s" "")${BLUE}║${RESET}"
  echo -e "${BLUE}╠══════════════════════════════════════════════════════╣${RESET}"
  echo -e "${BLUE}║ ${GRAY}📋 Session ID: ${DIM}${SESSION_ID}${RESET}$(printf "%$((38-${#SESSION_ID}))s" "")${BLUE}║${RESET}"
  echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${RESET}"
}

# Function to display the locations of benchmark files
show_benchmark_location() {
  echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BLUE}║ ${CYAN}${BOLD}BENCHMARK FILES LOCATION                           ${RESET}${BLUE}║${RESET}"
  echo -e "${BLUE}╠══════════════════════════════════════════════════════╣${RESET}"
  # Use printf for padding to align paths
  local metrics_log_len=${#METRICS_LOG}
  local benchmark_log_len=${#BENCHMARK_LOG}
  local response_path="${BENCHMARK_DIR}/response_${SESSION_ID}_*.md" # Use wildcard for model name
  local response_path_display="${BENCHMARK_DIR}/response_${SESSION_ID}_<model>.md"
  local response_path_len=${#response_path_display}
  local changelog_len=${#CHANGELOG}

  echo -e "${BLUE}║ ${WHITE}Metrics Log:${RESET} ${YELLOW}${METRICS_LOG}${RESET}$(printf "%$((40-metrics_log_len))s" "")${BLUE}║${RESET}"
  echo -e "${BLUE}║ ${WHITE}CSV History:${RESET} ${YELLOW}${BENCHMARK_LOG}${RESET}$(printf "%$((40-benchmark_log_len))s" "")${BLUE}║${RESET}"
  echo -e "${BLUE}║ ${WHITE}Response(s):${RESET} ${YELLOW}${response_path_display}${RESET}$(printf "%$((38-response_path_len))s" "")${BLUE}║${RESET}"
  echo -e "${BLUE}║ ${WHITE}Changelog:${RESET} ${YELLOW}${CHANGELOG}${RESET}$(printf "%$((40-changelog_len))s" "")${BLUE}║${RESET}"
  echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${RESET}"
}

# Function to update the changelog file with a new entry
update_changelog() {
  local script_name=$1 # Name of the script processed
  local model=$2 # Model used
  local duration=$3 # Time taken

  # Check if changelog file is writable
  if [ ! -w "${CHANGELOG}" ]; then
      log_message "WARNING" "Cannot write to changelog file: ${CHANGELOG}"
      return 1
  fi

  # Get the current date in YYYY-MM-DD format
  local today=$(date '+%Y-%m-%d')

  # Check if an entry for today already exists
  if grep -q "### ${today}" "${CHANGELOG}"; then
    # Append to today's entry using sed
    # Note: sed -i '' works on macOS, Linux might need sed -i without the space
    sed -i '' "/### ${today}/a\\
- Generated README for ${script_name} with ${model} (${duration}s)
" "${CHANGELOG}" || log_message "WARNING" "Failed to update changelog (sed command failed)."
  else
    # Create a new entry for today under the latest version heading
    # Use specific anchor like '# Script to README Generator Changelog' if needed
    sed -i '' "/^## Version /a\\
\\
### ${today}\\
- Generated README for ${script_name} with ${model} (${duration}s)
" "${CHANGELOG}" || log_message "WARNING" "Failed to update changelog (sed command failed)."
  fi
  log_message "DEBUG" "Updated changelog for ${script_name}"
}

# Function to allow interactive editing of text using the default editor
edit_text() {
  local text="$1" # Text content to edit
  local temp_file=$(mktemp) # Create a temporary file

  # Write the initial text to the temporary file
  echo "${text}" > "${temp_file}"

  # Determine the editor to use (environment variable EDITOR, fallback to nano)
  local editor="${EDITOR:-nano}"

  # Prompt the user before opening the editor
  echo -e "${YELLOW}${BOLD}Interactive Edit Mode${RESET}"
  echo -e "${GRAY}Opening text in ${editor}. Make your changes, save the file, and exit the editor.${RESET}"
  echo -e "${GRAY}Press Enter to continue...${RESET}"
  read -r # Wait for user confirmation

  # Open the temporary file in the chosen editor
  # Check if editor command exists
  if command -v ${editor} &> /dev/null; then
      # Run editor in the foreground so script waits
      # Redirect stdin and stdout to the terminal for interactive editors
      ${editor} "${temp_file}" < /dev/tty > /dev/tty
  else
      log_message "ERROR" "Editor '${editor}' not found. Cannot open for interactive editing."
      log_message "INFO" "You can set the EDITOR environment variable (e.g., export EDITOR=vim)."
      # Return original text if editor fails
      echo "${text}"
      rm "${temp_file}"
      return 1
  fi

  # Read the edited text back from the temporary file
  local edited_text=$(cat "${temp_file}")

  # Clean up the temporary file
  rm "${temp_file}"

  # Return the edited text
  echo "${edited_text}"
  return 0
}

# Function to check if the script is running in an interactive terminal
is_terminal() {
  [ -t 0 ] && [ -t 1 ] # Check if both stdin and stdout are terminals
}

# Function to check for required command-line dependencies
check_dependencies() {
  local missing_deps=0 # Counter for missing dependencies
  local start_time=$(date +%s.%N) # Start timer for dependency check

  log_message "INFO" "Checking required dependencies..."

  # List of core dependencies (removed 'free')
  local core_deps=("jq" "bc" "curl" "openssl" "stat" "wc" "grep" "sed" "awk" "ps" "date" "mktemp" "basename" "dirname" "uname" "read")

  # Check core dependencies
  for cmd in "${core_deps[@]}"; do
      if ! command -v "$cmd" &> /dev/null; then
          log_message "ERROR" "${cmd} is required but not installed."
          missing_deps=1
      fi
  done

  # Check for fswatch only if watch mode is requested
  if [ "${WATCH_MODE}" = "true" ] && ! command -v fswatch &> /dev/null; then
    log_message "ERROR" "fswatch is required for watch mode (--watch). Please install fswatch (e.g., 'brew install fswatch')."
    missing_deps=1
  fi

  # Check for pandoc only if export mode is requested
  if [ "${EXPORT_MODE}" = "true" ] && ! command -v pandoc &> /dev/null; then
    log_message "ERROR" "pandoc is required for export mode (--export). Please install pandoc (e.g., 'brew install pandoc')."
    missing_deps=1
  fi

  # Check for afplay only if sound is enabled (macOS specific)
  if [ ${SOUND_ENABLED:-0} -eq 1 ] && [[ "$OSTYPE" == "darwin"* ]] && ! command -v afplay &> /dev/null; then
    log_message "WARNING" "afplay not found. Sound notifications will be disabled."
    SOUND_ENABLED=0 # Disable sound if afplay is missing
  fi

  # Check for Ollama CLI and server status
  if ! command -v ollama &> /dev/null; then
    log_message "ERROR" "ollama command is required. Please install Ollama from https://ollama.com"
    missing_deps=1
  else
    # Check if Ollama server is running by pinging the API
    log_message "INFO" "Checking Ollama server status at ${OLLAMA_API}..."
    # Use curl with timeout (-m), silent (-s), and fail (-f) options
    if ! curl -sf -m 3 "${OLLAMA_API%/api/chat}/api/tags" &> /dev/null; then # Check a known endpoint
      log_message "ERROR" "Ollama server is not responding at ${OLLAMA_API}. Please start it (e.g., 'ollama serve')."
      missing_deps=1
    else
      log_message "SUCCESS" "Ollama server is running."
    fi
  fi

  # End timer for dependency check
  local end_time=$(date +%s.%N)
  local duration=$(printf "%.2f" $(echo "${end_time} - ${start_time}" | bc))

  # Log the dependency check operation
  log_benchmark "system" "0" "0" "0" "system" "dependency_check" "${duration}" "0" "1.0" ""

  # Return the status (0 if all deps met, 1 if any are missing)
  return ${missing_deps}
}

# Function to get the list of available Ollama models
get_models() {
  local start_time=$(date +%s.%N) # Start timer

  log_message "INFO" "Fetching available Ollama models..."
  # Run 'ollama list' and capture output, redirect stderr to /dev/null
  local ollama_output=$(ollama list 2>/dev/null)

  # Check if the 'ollama list' command failed
  if [ $? -ne 0 ]; then
    log_message "ERROR" "Failed to run 'ollama list'. Ensure Ollama is installed and the server is running."
    exit 1
  fi

  # Parse the output to extract model names, IDs, and sizes using awk
  # tail -n +2 skips the header line
  # Use explicit field separators for robustness
  # Correct parsing assuming standard 'ollama list' output format
  models=($(echo "$ollama_output" | tail -n +2 | awk '{print $1}'))
  model_ids=($(echo "$ollama_output" | tail -n +2 | awk '{print $2}'))
  # Capture size potentially spanning two fields (e.g., "7.0 GB")
  model_sizes=()
  while IFS= read -r line; do
      # Extract size (e.g., "7B", "13B", "7.0 GB") - adapt awk logic if needed
      size_part=$(echo "$line" | awk '{ for(i=3; i<=NF-2; i++) printf "%s ", $i; print $(NF-1) }' | sed 's/ *$//')
      model_sizes+=("$size_part")
  done < <(echo "$ollama_output" | tail -n +2)


  # Check if any models were found
  if [ ${#models[@]} -eq 0 ]; then
    log_message "ERROR" "No Ollama models found. Please download a model (e.g., 'ollama pull ${DEFAULT_MODEL}')."
    exit 1
  fi

  # Add the list of available models to the session's metrics log
  local models_json=$(printf '%s\n' "${models[@]}" | jq -R . | jq -s .)
  jq --argjson models "${models_json}" '.available_models = $models' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"

  local end_time=$(date +%s.%N) # End timer
  local duration=$(printf "%.2f" $(echo "${end_time} - ${start_time}" | bc))

  # Log the operation
  log_benchmark "system" "0" "0" "0" "system" "fetch_models" "${duration}" "${#models[@]}" "1.0" ""

  # If the function was called with '--list', display the formatted list and exit
  if [[ "$1" == "--list" ]]; then
    echo -e "${CYAN}${BOLD}Available Ollama models for README generation:${RESET}"
    echo ""
    # Print table header
    printf "${WHITE}%-5s %-30s %-15s %-15s${RESET}\n" "NUM" "MODEL" "SIZE" "EST. SPEED"
    printf "${GRAY}%-5s %-30s %-15s %-15s${RESET}\n" "---" "-----" "----" "---------"
    # Loop through models and display details
    for ((i=0; i<${#models[@]}; i++)); do
      local model_name="${models[$i]}"
      # Show model description and stats using the dedicated function
      show_model_description "${model_name}"
    done
    exit 0 # Exit after listing models
  fi

  log_message "INFO" "Found ${#models[@]} available models."
}

# Function to select the Ollama model to use (interactively or via argument/default)
select_model() {
  # Arguments passed to this function are potential model names from command line
  local start_time=$(date +%s.%N) # Start timer
  local provided_model=""

  # Check if any non-flag arguments were passed
  if [ $# -gt 0 ]; then
      provided_model="$1" # Assume first positional arg is the model
  fi

  # If a model was provided as an argument, use it
  if [ -n "$provided_model" ]; then
    # Check if the provided model exists locally using exact match grep (-w)
    if ollama list | grep -q -w "^${provided_model}"; then
      model="${provided_model}"
      log_message "SUCCESS" "Using specified model: ${model}"
      show_model_description "${model}" # Show details for the selected model
    else
      # If model not found locally, offer to pull it
      log_message "WARNING" "Model '${provided_model}' not found locally."
      if is_terminal; then
          read -p "Do you want to pull this model? (y/N): " pull_confirm
          if [[ "$pull_confirm" =~ ^[Yy]$ ]]; then
              log_message "INFO" "Pulling model '${provided_model}'..."
              ollama pull "${provided_model}"
              if [ $? -ne 0 ]; then
                log_message "ERROR" "Failed to pull model '${provided_model}'. Using default: ${DEFAULT_MODEL}"
                model="${DEFAULT_MODEL}"
              else
                model="${provided_model}"
                log_message "SUCCESS" "Model '${provided_model}' pulled successfully."
                show_model_description "${model}"
              fi
          else
              log_message "INFO" "Using default model: ${DEFAULT_MODEL}"
              model="${DEFAULT_MODEL}"
              show_model_description "${model}"
          fi
      else
          log_message "INFO" "Cannot pull model in non-interactive mode. Using default: ${DEFAULT_MODEL}"
          model="${DEFAULT_MODEL}"
          show_model_description "${model}"
      fi
    fi
  elif is_terminal; then
    # Interactive selection if running in a terminal and no model provided
    echo -e "${YELLOW}${BOLD}Select a model for README generation:${RESET}"
    echo ""
    # Print numbered list of models with details
    printf "${WHITE}%-5s %-30s %-15s %-15s${RESET}\n" "NUM" "MODEL" "SIZE" "EST. SPEED"
    printf "${GRAY}%-5s %-30s %-15s %-15s${RESET}\n" "---" "-----" "----" "---------"
    for ((i=0; i<${#models[@]}; i++)); do
      local model_name="${models[$i]}"
      local model_size="${model_sizes[$i]}"
      local complexity=${MODEL_COMPLEXITY[$model_name]:-${MODEL_COMPLEXITY["default"]}}
      local speed=""
      local speed_color=""
      # Determine speed category
      if (( $(echo "$complexity < 1.5" | bc -l) )); then speed="Very Fast"; speed_color="${GREEN}";
      elif (( $(echo "$complexity < 2.5" | bc -l) )); then speed="Fast"; speed_color="${CYAN}";
      elif (( $(echo "$complexity < 4.0" | bc -l) )); then speed="Medium"; speed_color="${YELLOW}";
      else speed="Slow"; speed_color="${RED}"; fi
      # Print model option
      printf "${WHITE}%-5s ${MAGENTA}%-30s ${BLUE}%-15s ${speed_color}%-15s${RESET}\n" "$((i+1))" "$model_name" "$model_size" "$speed"
    done
    echo ""
    echo -e "${CYAN}Enter the number of the model to use (default: ${DEFAULT_MODEL}):${RESET}"
    read -r model_num # Read user input

    # Validate input and select model
    if [[ "$model_num" =~ ^[0-9]+$ ]] && [ "$model_num" -ge 1 ] && [ "$model_num" -le ${#models[@]} ]; then
      model="${models[$((model_num-1))]}" # Array is 0-indexed
      log_message "SUCCESS" "Selected model: ${model}"
      show_model_description "${model}"
    else
      # Handle invalid input or empty input (use default)
      if [ -z "$model_num" ]; then
          log_message "INFO" "No selection made. Using default model: ${DEFAULT_MODEL}"
      else
          log_message "WARNING" "Invalid selection '${model_num}'. Using default model: ${DEFAULT_MODEL}"
      fi
      model="${DEFAULT_MODEL}"
      show_model_description "${model}"
    fi
  else
    # Non-interactive and no model provided: use the default model
    model="${DEFAULT_MODEL}"
    log_message "INFO" "Non-interactive mode. Using default model: ${model}"
    show_model_description "${model}"
  fi

  # Ensure 'model' variable is set (fallback to default if somehow still empty)
  if [ -z "$model" ]; then
      log_message "WARNING" "Model variable was empty, setting to default: ${DEFAULT_MODEL}"
      model="${DEFAULT_MODEL}"
  fi

  local end_time=$(date +%s.%N) # End timer
  local duration=$(printf "%.2f" $(echo "${end_time} - ${start_time}" | bc))

  # Log the model selection operation
  # Use INPUT variable if set, otherwise use "unknown"
  local log_input_name="${INPUT:-unknown}"
  log_benchmark "${log_input_name}" "0" "0" "0" "${model}" "model_selection" "${duration}" "0" "1.0" ""

  # Record the finally selected model in the session's metrics log
  jq --arg model "${model}" '.selected_model = $model' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
}

# Function to validate the input script file
validate_input_file() {
  local input="$1" # Path to the input script file
  local start_time=$(date +%s.%N) # Start timer

  # Check if the file exists and is a regular file
  if [ ! -f "${input}" ]; then
    log_message "ERROR" "Input file '${input}' does not exist or is not a regular file."
    play_sound "error"
    return 1 # Indicate failure
  fi

  # Check if the file is readable
  if [ ! -r "${input}" ]; then
      log_message "ERROR" "Input file '${input}' is not readable."
      play_sound "error"
      return 1
  fi

  # Get file statistics using 'stat' (handle potential errors)
  local file_size=$(stat -f%z "${input}" 2>/dev/null || stat -c%s "${input}" 2>/dev/null || echo "0") # macOS/Linux stat
  # Read file content into a variable (handle potential errors)
  CONTENT=$(cat "${input}")
  if [ $? -ne 0 ]; then
      log_message "ERROR" "Failed to read content from '${input}'."
      play_sound "error"
      return 1
  fi

  # Count lines and characters using 'wc'
  local line_count=$(echo "${CONTENT}" | wc -l | tr -d ' ')
  local char_count=$(echo "${CONTENT}" | wc -c | tr -d ' ')

  # Calculate script complexity using the dedicated function
  SCRIPT_COMPLEXITY=$(calculate_complexity "${CONTENT}" "${line_count}")

  # Record file metrics in the session's JSON log
  jq --arg file "${input}" \
     --arg size "${file_size}" \
     --arg lines "${line_count}" \
     --arg chars "${char_count}" \
     --arg complexity "${SCRIPT_COMPLEXITY}" \
     '.input_file = {"path": $file, "size_bytes": $size, "line_count": $lines, "char_count": $chars, "complexity": $complexity}' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"

  # Determine script type based on file extension
  ext="${input##*.}"
  SCRIPT_TYPE="generic" # Default type

  # Map extension to script type
  case "${ext}" in
    sh|bash|zsh) SCRIPT_TYPE="shell" ;;
    scpt|applescript) SCRIPT_TYPE="applescript" ;;
    py|python) SCRIPT_TYPE="python" ;;
    rb|ruby) SCRIPT_TYPE="ruby" ;;
    js|javascript|jsx|ts|tsx) SCRIPT_TYPE="javascript" ;;
    php) SCRIPT_TYPE="php" ;;
    pl|pm|perl) SCRIPT_TYPE="perl" ;;
    lua) SCRIPT_TYPE="lua" ;;
    r|R) SCRIPT_TYPE="r" ;;
    *) log_message "WARNING" "Unsupported file extension: '${ext}'. Analyzing as generic script." ;;
  esac

  # Specific validation for shell scripts (check shebang, decode base64)
  if [[ "${SCRIPT_TYPE}" == "shell" ]]; then
      # Check if it looks like base64 encoded (simple check on first line)
      if echo "$CONTENT" | head -n 1 | grep -qE '^[A-Za-z0-9+/=]{40,}$'; then # Check for long base64 string
        # Attempt to decode as base64
        local DECODED_CONTENT=$(echo "$CONTENT" | base64 -d 2>/dev/null)
        # Check if decoded content looks like a shell script
        if [ $? -eq 0 ] && echo "$DECODED_CONTENT" | head -n 1 | grep -qE "^#!/"; then
          CONTENT="$DECODED_CONTENT" # Use decoded content
          log_message "INFO" "Input detected as base64-encoded shell script. Decoded successfully."
          # Recalculate stats for decoded content
          line_count=$(echo "${CONTENT}" | wc -l | tr -d ' ')
          char_count=$(echo "${CONTENT}" | wc -c | tr -d ' ')
          SCRIPT_COMPLEXITY=$(calculate_complexity "${CONTENT}" "${line_count}")
          # Update metrics log
          jq --arg lines "${line_count}" --arg chars "${char_count}" --arg complexity "${SCRIPT_COMPLEXITY}" \
             '.input_file.line_count = $lines | .input_file.char_count = $chars | .input_file.complexity = $complexity' \
             "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
        else
          log_message "WARNING" "Input appears base64-encoded but failed to decode as a valid shell script. Treating as plain text."
        fi
      fi
      # Check for standard shebang line
      if ! echo "${CONTENT}" | head -n 1 | grep -qE "^#!/"; then
        log_message "WARNING" "Shell script '${input}' is missing a shebang (e.g., #!/bin/bash)."
      fi
  fi

  # Count script features (functions, conditionals, loops) for metrics
  local function_count=$(echo "${CONTENT}" | grep -c "function " || echo "0") # Basic function count
  local if_count=$(echo "${CONTENT}" | grep -E '(^|[^a-zA-Z0-9_])if\s+' || echo "0")
  local case_count=$(echo "${CONTENT}" | grep -c "case " || echo "0")
  local for_count=$(echo "${CONTENT}" | grep -E '(^|[^a-zA-Z0-9_])for\s+' || echo "0")
  local while_count=$(echo "${CONTENT}" | grep -E '(^|[^a-zA-Z0-9_])while\s+' || echo "0")


  # Add feature counts to the session's metrics log
  jq --arg functions "${function_count}" \
     --arg ifs "${if_count}" \
     --arg cases "${case_count}" \
     --arg fors "${for_count}" \
     --arg whiles "${while_count}" \
     '.script_features = {"function_count": $functions, "if_count": $ifs, "case_count": $cases, "for_count": $fors, "while_count": $whiles}' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"

  local end_time=$(date +%s.%N) # End timer
  local duration=$(printf "%.2f" $(echo "${end_time} - ${start_time}" | bc))

  # Log the file validation operation
  # Use global 'model' variable if set, otherwise 'unknown'
  local current_model=${model:-unknown}
  log_benchmark "${input}" "${file_size}" "${line_count}" "${char_count}" "${current_model}" "file_validation" "${duration}" "0" "${SCRIPT_COMPLEXITY}" ""

  # Store key file metrics globally for later use in generate_readme
  FILE_SIZE="${file_size}"
  LINE_COUNT="${line_count}"
  CHAR_COUNT="${char_count}"

  log_message "SUCCESS" "Validated: ${input} (${file_size} bytes, ${line_count} lines, type: ${SCRIPT_TYPE}, complexity: ${SCRIPT_COMPLEXITY})"
  return 0 # Indicate success
}

# Function to handle cases where a script is documented multiple times
handle_duplicate_files() {
  local input_file=$1 # Path to the input script
  local base_name=$(basename "${input_file}") # Get filename without path
  local output_file="${README}" # Path to the main README file

  # Ensure README file exists before trying to grep
  if [ ! -f "$output_file" ]; then
      touch "$output_file" # Create if it doesn't exist
  fi

  # Check if a section for this script already exists in the README
  # Use grep -c for count, adjust regex for different formats
  # Define script icon here or pass it as an argument if needed for regex
  local script_icon_placeholder="[📜🐚🐍💎🟨🍎🐘🐪🌙📊]" # Placeholder for icons in regex
  local version_count=$(grep -c -E "(^## ${base_name}|^# ${script_icon_placeholder} ${base_name})" "${output_file}" 2>/dev/null || echo 0)

  if [ "$version_count" -gt 0 ]; then
    # Script section found, handle as a new version
    local timestamp=$(date +%Y%m%d_%H%M%S) # Timestamp for uniqueness
    VERSION_SUFFIX="(v$((version_count + 1)))" # Simple version suffix (e.g., v2)
    SECTION_HEADER="${base_name} ${VERSION_SUFFIX}" # Header for the new section

    log_message "INFO" "Script ${base_name} already documented. Adding new entry: ${SECTION_HEADER}"

    # Add details about handling the duplicate to the metrics log
    jq --arg name "${base_name}" --arg timestamp "${timestamp}" \
       --arg version "${VERSION_SUFFIX}" \
       '.duplicate_handling = {"script_name": $name, "timestamp": $timestamp, "version": $version}' \
       "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"

    return 1 # Indicate that this is not the first version
  else
    # First time documenting this script
    SECTION_HEADER="${base_name}" # Use the base name as the header
    VERSION_SUFFIX="" # No version suffix needed
    return 0 # Indicate this is the first version
  fi
}

# Function to generate README using the "enhanced" format
generate_enhanced_readme() {
  local script_name=$1 # Script name (potentially with version suffix)
  local model=$2 # Model used
  local response=$3 # Generated Markdown content from Ollama
  local timestamp=$4 # Current timestamp string

  # Determine script type icon
  local script_icon="📜" # Default icon
  case "${SCRIPT_TYPE}" in
    shell) script_icon="🐚" ;; python) script_icon="🐍" ;; ruby) script_icon="💎" ;;
    javascript) script_icon="🟨" ;; applescript) script_icon="🍎" ;; php) script_icon="🐘" ;;
    perl) script_icon="🐪" ;; lua) script_icon="🌙" ;; r) script_icon="📊" ;;
  esac

  # Append the generated content to the main README file
  {
    # Header section
    echo -e "\n---\n" # Add separator before new entry
    echo -e "<div align=\"center\">"
    echo -e "\n# ${script_icon} ${script_name}\n" # Use script name from SECTION_HEADER
    echo -e "**Generated with script2readme using ${model}**"
    echo -e "\n*Documentation generated on ${timestamp}*"
    echo -e "</div>\n\n---\n"

    # Table of Contents (if requested)
    if [ "${ADD_TOC}" = "true" ]; then
      echo -e "## Table of Contents\n"
      # Extract H2/H3 headings from the response and format as TOC links
      echo "${response}" | grep -E "^##(#)?\s+" | sed -E 's/^##(#)?\s+//' | awk '{
          link = tolower($0);
          gsub(/[^a-z0-9 -]/, "", link); # Remove special chars
          gsub(/[[:space:]]+/, "-", link); # Replace spaces with hyphens
          gsub(/-+/, "-", link); # Collapse multiple hyphens
          print "- [" $0 "](#" link ")"
        }'
      echo -e "\n- [Metadata](#metadata)"
      echo -e "- [License](#license)"
      echo -e "\n---\n"
    fi

    # Main generated content
    echo -e "${response}\n"

    # Metadata section
    echo -e "## Metadata\n"
    echo -e "| Property | Value |"
    echo -e "|----------|-------|"
    echo -e "| File Size | $(du -sh "${INPUT}" | cut -f1) (${FILE_SIZE} bytes) |" # Use du -sh for human readable size
    echo -e "| Line Count | ${LINE_COUNT} lines |"
    echo -e "| Script Type | ${SCRIPT_TYPE^} |" # Capitalize first letter
    echo -e "| Complexity Score | ${SCRIPT_COMPLEXITY} |"
    echo -e "| Generated With | ${model} |"
    # Use global TOTAL_EXECUTION_TIME calculated in generate_readme
    echo -e "| Generation Time | ${TOTAL_EXECUTION_TIME}s |"
    echo -e "| Session ID | ${SESSION_ID} |"
    echo -e "\n---\n"

    # License section (MIT License)
    echo -e "### License\n"
    echo -e "This script is provided under the MIT License.\n"
    echo -e "MIT License\n"
    echo -e "Copyright (c) $(date +%Y) ${APP_AUTHOR}\n"
    echo -e "Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the \"Software\"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:\n"
    echo -e "The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.\n"
    echo -e "THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE."
  } >> "${README}" # Append to the README file
}

# Function to generate README using the "fancy" format with badges
generate_fancy_readme() {
  local script_name=$1 # Script name (potentially with version suffix)
  local model=$2 # Model used
  local response=$3 # Generated Markdown content
  local timestamp=$4 # Current timestamp string
  local model_name_clean=${model//[:\/]/_} # Sanitize model name for badge URL

  # Determine script type icon
  local script_icon="📜"
  case "${SCRIPT_TYPE}" in
    shell) script_icon="🐚" ;; python) script_icon="🐍" ;; ruby) script_icon="💎" ;;
    javascript) script_icon="🟨" ;; applescript) script_icon="🍎" ;; php) script_icon="🐘" ;;
    perl) script_icon="🐪" ;; lua) script_icon="🌙" ;; r) script_icon="📊" ;;
  esac

  # Append the generated content to the main README file
  {
    # Top anchor and header with logo and badges
    echo -e "\n---\n" # Add separator before new entry
    local anchor_name=$(echo "${script_name}" | tr ' ' '_' | tr -dc '[:alnum:]_') # Create valid anchor name
    echo -e "<a name=\"${anchor_name}-top\"></a>" # Anchor based on script name
    echo -e "<div align=\"center\">"
    # Placeholder logo - replace with a real one if desired
    echo -e "\n<img src=\"https://raw.githubusercontent.com/PKief/vscode-material-icon-theme/main/icons/folder-script.svg\" width=\"100\">"
    echo -e "\n# ${script_icon} ${script_name}\n"
    echo -e "A fully documented guide for the **${script_name}** script, generated with script2readme"
    # Badges linking to model info, generation time, language, and license (unique IDs per entry)
    local unique_id="${SESSION_ID}_${anchor_name}" # Unique ID for badges
    echo -e "\n[![Model Used][model-shield-${unique_id}]][model-link-${unique_id}]"
    echo -e "[![Generated][generated-shield-${unique_id}]][generated-link-${unique_id}]"
    echo -e "[![Language][language-shield-${unique_id}]][language-link-${unique_id}]"
    echo -e "[![MIT License][license-shield-${unique_id}]][license-link-${unique_id}]"
    echo -e "</div>\n\n---\n"

    # Collapsible Table of Contents (if requested)
    if [ "${ADD_TOC}" = "true" ]; then
        echo -e "<details>"
        echo -e "<summary><kbd>Table of contents</kbd></summary>\n"
        # Extract H2/H3 headings and format as TOC links
        echo "${response}" | grep -E "^##(#)?\s+" | sed -E 's/^##(#)?\s+//' | awk '{
            link = tolower($0);
            gsub(/[^a-z0-9 -]/, "", link);
            gsub(/[[:space:]]+/, "-", link);
            gsub(/-+/, "-", link);
            print "- [" $0 "](#" link ")"
          }'
        echo -e "\n- [Metadata](#metadata)"
        echo -e "- [License](#license)"
        echo -e "\n</details>\n\n---\n"
    fi

    # Main generated content
    echo -e "${response}\n"
    # Back to top link
    echo -e "<div align=\"right\">"
    echo -e "\n[![Back to top][back-to-top-${unique_id}]](#${anchor_name}-top)\n" # Link to top anchor
    echo -e "</div>\n---\n"

    # Metadata section
    echo -e "## Metadata\n"
    echo -e "| Property | Value |"
    echo -e "|----------|-------|"
    echo -e "| File Size | $(du -sh "${INPUT}" | cut -f1) (${FILE_SIZE} bytes) |"
    echo -e "| Line Count | ${LINE_COUNT} lines |"
    echo -e "| Script Type | ${SCRIPT_TYPE^} |"
    echo -e "| Complexity Score | ${SCRIPT_COMPLEXITY} |"
    echo -e "| Generated With | ${model} |"
    echo -e "| Generation Time | ${TOTAL_EXECUTION_TIME}s |"
    echo -e "| Session ID | ${SESSION_ID} |"
    # Back to top link
    echo -e "\n<div align=\"right\">"
    echo -e "\n[![Back to top][back-to-top-${unique_id}]](#${anchor_name}-top)\n"
    echo -e "</div>\n---\n"

    # License section
    echo -e "## License\n"
    echo -e "This script is provided under the MIT License.\n"
    echo -e "MIT License\n"
    echo -e "Copyright (c) $(date +%Y) ${APP_AUTHOR}\n"
    echo -e "Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the \"Software\"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:\n"
    echo -e "The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.\n"
    echo -e "THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE."

    # Badge definitions section at the end of the file (use unique IDs)
    echo -e "\n\n"
    echo -e "[back-to-top-${unique_id}]: https://img.shields.io/badge/-BACK_TO_TOP-151515?style=flat-square"
    # Use shields.io for badges, customize colors and style
    echo -e "[model-shield-${unique_id}]: https://img.shields.io/badge/${model_name_clean}-Model-blueviolet?style=for-the-badge&labelColor=black"
    echo -e "[model-link-${unique_id}]: https://ollama.com/library/${model%%:*}" # Link to Ollama library page for the base model
    local timestamp_badge=$(date '+%Y-%m-%d_%H-%M-%S') # Timestamp for badge
    echo -e "[generated-shield-${unique_id}]: https://img.shields.io/badge/Generated-${timestamp_badge}-orange?style=for-the-badge&labelColor=black"
    echo -e "[generated-link-${unique_id}]: #" # Link for generated badge (can be commit hash etc.)
    echo -e "[language-shield-${unique_id}]: https://img.shields.io/badge/Script-${SCRIPT_TYPE}-red?style=for-the-badge&labelColor=black"
    echo -e "[language-link-${unique_id}]: #" # Link for language badge
    echo -e "[license-shield-${unique_id}]: https://img.shields.io/badge/License-MIT-green?style=for-the-badge&labelColor=black"
    echo -e "[license-link-${unique_id}]: #license" # Link to license section
  } >> "${README}"
}

# Function to generate README using the "basic" format (simple headings)
generate_basic_readme() {
  local script_name=$1 # Script name (potentially with version suffix)
  local model=$2 # Model used
  local response=$3 # Generated Markdown content
  local timestamp=$4 # Current timestamp string

  # Append the generated content to the main README file
  {
    # Simple header with script name, model, and timestamp
    echo -e "\n---\n" # Add separator before new entry
    echo -e "\n## ${script_name} (Analyzed with ${model})"
    echo -e "#### Analysis Date: ${timestamp}"
    # Main generated content
    echo -e "${response}\n"
    # License section
    echo -e "### License"
    echo -e "This script is provided under the MIT License.\n"
    echo -e "MIT License\n"
    echo -e "Copyright (c) $(date +%Y) ${APP_AUTHOR}\n"
    echo -e "Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the \"Software\"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:\n"
    echo -e "The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.\n"
    echo -e "THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE."
  } >> "${README}"
}

# Main function to generate README documentation for a script
generate_readme() {
  local input="$1" # Path to the input script
  local model="$2" # Ollama model to use
  local skip_estimate="$3" # Boolean: true to skip time estimation
  local interactive_mode="$4" # Boolean: true to enable interactive editing
  local readme_format="$5" # String: 'basic', 'enhanced', or 'fancy'
  local script_basename=$(basename "${input}") # Get filename
  local start_time=$(date +%s.%N) # Start timer for the whole process

  # Handle potential duplicate documentation entries
  handle_duplicate_files "${input}"
  local duplicate_status=$? # 0 = first version, 1 = duplicate
  # Use SECTION_HEADER which is set by handle_duplicate_files
  local current_script_header="${SECTION_HEADER}"

  log_message "INFO" "Generating README documentation for ${current_script_header} with ${model}..."

  # Estimate completion time if not skipped
  local estimated_seconds=""
  if [ "$skip_estimate" != "true" ]; then
    # Use globally set FILE_SIZE, SCRIPT_COMPLEXITY
    estimated_seconds=$(estimate_completion_time "${FILE_SIZE}" "${SCRIPT_COMPLEXITY}" "${model}")
    local estimated_time_str=$(format_time "${estimated_seconds}")
    log_message "INFO" "Estimated completion time: ${YELLOW}${estimated_time_str}${RESET}"
    # Log the estimation
    jq --arg est "${estimated_seconds}" '.estimated_completion_time = $est' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
  fi

  # --- Prepare Ollama API Request ---
  # Create JSON payload using jq
  # Ensure CONTENT variable is properly escaped for JSON
  local escaped_content=$(echo "$CONTENT" | jq -Rsa .)

  local payload=$(jq -n \
    --arg model "${model}" \
    --argjson content "${escaped_content}" \
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
          "content": "Analyze the following \($script_type) script provided as plain text. Pay close attention to specific elements such as references to applications, system paths, and command-line tools. Consider the script'\''s potential impact on the system.\n\nGenerate a Markdown README section with these sections:\n\n- **Overview**: Summarize the script'\''s purpose and primary actions.\n- **Requirements**: List prerequisites inferred from the script.\n- **Usage**: Provide precise instructions for running the script.\n- **What the Script Does**: Describe the script'\''s operations step-by-step.\n- **Important Notes**: Highlight critical details derived from the script.\n- **Disclaimer**: Warn about risks of running the script.\n\nFile: \($filename)\n\nScript Content:\n\( $content )"
        }
      ],
      "stream": false
    }')

  # Log the size of the prompt being sent
  local prompt_size=$(echo "${payload}" | jq -r '.messages[1].content' | wc -c | tr -d ' ')
  jq --arg size "${prompt_size}" '.prompt_size_chars = $size' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
  log_message "DEBUG" "Prompt size: ${prompt_size} characters"

  # --- Send Request to Ollama API ---
  log_message "INFO" "Sending request to Ollama API..."
  local request_start_time=$(date +%s.%N) # Start timer for API request
  local temp_response=$(mktemp) # Temporary file for API response

  # Execute API call with progress bar or spinner
  if [ -n "$estimated_seconds" ] && is_terminal; then
    # Use progress bar if estimation is available and in terminal
    curl -s -X POST "${OLLAMA_API}" \
      -H "Content-Type: application/json" \
      -d "${payload}" > "${temp_response}" &
    local pid=$! # Get background process ID
    local start_secs=$SECONDS # Use shell's SECONDS variable
    local progress=0
    # Update progress bar while curl runs
    while kill -0 $pid 2>/dev/null; do
      local elapsed=$((SECONDS - start_secs))
      if [ $estimated_seconds -gt 0 ]; then
        progress=$((elapsed * 100 / estimated_seconds))
        if [ $progress -gt 99 ]; then progress=99; fi # Cap at 99% until done
      else
        progress=50 # Default progress if estimate is 0
      fi
      display_progress $progress "$(format_time $elapsed)"
      sleep 0.5 # Update interval
    done
    wait $pid # Wait for curl to finish
    local curl_exit_code=$?
    # Show 100% on completion
    display_progress 100 "$(format_time $((SECONDS - start_secs)))"
    echo "" # Newline after progress bar
    # Check curl exit code
    if [ $curl_exit_code -ne 0 ]; then
      log_message "ERROR" "curl command failed with exit code ${curl_exit_code}. Check network or Ollama server."
      play_sound "error"
      rm "${temp_response}"
      return 1 # Return error code
    fi
  else
    # Use spinner if no estimate or not in terminal
    log_message "INFO" "Processing request (no progress bar)..."
    curl -s -X POST "${OLLAMA_API}" \
      -H "Content-Type: application/json" \
      -d "${payload}" > "${temp_response}" &
    local pid=$!
    spinner $pid # Show spinner
    wait $pid # Wait for curl
    local curl_exit_code=$?
    # Check curl exit code
    if [ $curl_exit_code -ne 0 ]; then
      log_message "ERROR" "curl command failed with exit code ${curl_exit_code}."
      play_sound "error"
      rm "${temp_response}"
      return 1 # Return error code
    fi
  fi

  local request_end_time=$(date +%s.%N) # End timer for API request
  local request_duration=$(printf "%.2f" $(echo "${request_end_time} - ${request_start_time}" | bc))
  # Log API request operation
  log_benchmark "${current_script_header}" "${FILE_SIZE}" "${LINE_COUNT}" "${CHAR_COUNT}" "${model}" "api_request" "${request_duration}" "${prompt_size}" "${SCRIPT_COMPLEXITY}" ""

  # --- Process Ollama API Response ---
  log_message "INFO" "Processing response..."
  local parse_start_time=$(date +%s.%N) # Start timer for parsing

  # Check for explicit "error" field in the JSON response
  if jq -e '.error' "${temp_response}" > /dev/null 2>&1; then
    log_message "ERROR" "Ollama API returned an error:"
    jq '.' "${temp_response}" # Print the full error response
    # Log the error to metrics
    jq --arg error "$(jq -c . "${temp_response}")" '.error = $error' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
    rm "${temp_response}" # Clean up temp file
    play_sound "error"
    return 1 # Return error code
  fi

  # Extract Ollama's internal performance metrics if available
  local ollama_total_duration=$(jq -r '.total_duration // 0' "${temp_response}")
  local ollama_eval_count=$(jq -r '.eval_count // 0' "${temp_response}")
  local ollama_prompt_eval_count=$(jq -r '.prompt_eval_count // 0' "${temp_response}")
  local ollama_eval_duration=$(jq -r '.eval_duration // 0' "${temp_response}")
  local ollama_prompt_eval_duration=$(jq -r '.prompt_eval_duration // 0' "${temp_response}")

  # Convert nanosecond durations to seconds if necessary
  if [ "${ollama_total_duration}" -gt 1000000000 ]; then ollama_total_duration=$(printf "%.2f" $(echo "scale=2; ${ollama_total_duration}/1000000000" | bc)); fi
  if [ "${ollama_eval_duration}" -gt 1000000000 ]; then ollama_eval_duration=$(printf "%.2f" $(echo "scale=2; ${ollama_eval_duration}/1000000000" | bc)); fi
  if [ "${ollama_prompt_eval_duration}" -gt 1000000000 ]; then ollama_prompt_eval_duration=$(printf "%.2f" $(echo "scale=2; ${ollama_prompt_eval_duration}/1000000000" | bc)); fi

  # Add Ollama's metrics to the session log
  jq --arg total "${ollama_total_duration}" \
     --arg eval_c "${ollama_eval_count}" \
     --arg prompt_c "${ollama_prompt_eval_count}" \
     --arg eval_d "${ollama_eval_duration}" \
     --arg prompt_d "${ollama_prompt_eval_duration}" \
     '.ollama_metrics = {"total_duration_sec": $total, "eval_count": $eval_c, "prompt_eval_count": $prompt_c, "eval_duration_sec": $eval_d, "prompt_eval_duration_sec": $prompt_d}' \
     "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"

  # Extract the main response content using multiple fallback methods
  local RESPONSE=""
  if jq -e '.message.content' "${temp_response}" > /dev/null 2>&1; then
    RESPONSE=$(jq -r '.message.content' "${temp_response}")
  else
    log_message "DEBUG" "Primary jq extraction failed. Trying fallbacks..."
    # Fallback 1: grep and sed
    RESPONSE=$(grep -o '"content":"[^"]*"' "${temp_response}" | sed 's/"content":"//;s/"$//')
    # Fallback 2: perl regex (improved to handle escaped quotes)
    if [ -z "${RESPONSE}" ]; then
        log_message "DEBUG" "grep/sed fallback failed. Trying perl..."
        RESPONSE=$(perl -0777 -ne 'print $1 if /"content":\s*"(.*?)(?<!\\)"/s' "${temp_response}")
    fi
    # Fallback 3: python json parser
    if [ -z "${RESPONSE}" ]; then
        log_message "DEBUG" "perl fallback failed. Trying python..."
        RESPONSE=$(cat "${temp_response}" | python3 -c "import json, sys; d=json.load(sys.stdin); print(d.get('message', {}).get('content', ''))" 2>/dev/null)
    fi
  fi

  # Final check if response content is empty after all fallbacks
  if [ -z "${RESPONSE}" ]; then
    log_message "ERROR" "Failed to extract response content from Ollama."
    echo "Raw response:"
    cat "${temp_response}"
    jq --arg error "Empty or unparseable response content" '.error = $error' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
    rm "${temp_response}" # Clean up
    play_sound "error"
    return 1 # Return error code
  fi

  # Calculate response metrics (word count is a good proxy for token count)
  local response_char_count=$(echo "${RESPONSE}" | wc -c | tr -d ' ')
  local response_line_count=$(echo "${RESPONSE}" | wc -l | tr -d ' ')
  local response_word_count=$(echo "${RESPONSE}" | wc -w | tr -d ' ')

  # Add response metrics to the session log
  jq --arg chars "${response_char_count}" \
     --arg lines "${response_line_count}" \
     --arg words "${response_word_count}" \
     '.response_metrics = {"char_count": $chars, "line_count": $lines, "word_count": $words}' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"

  # Save the full response content to a file for debugging/analysis
  local response_file="${BENCHMARK_DIR}/response_${SESSION_ID}_${model//[:\/]/_}.md"
  echo "${RESPONSE}" > "${response_file}"
  log_message "DEBUG" "Saved full response to ${response_file}"

  # Clean up the temporary API response file
  rm "${temp_response}"

  local parse_end_time=$(date +%s.%N) # End timer for parsing
  local parse_duration=$(printf "%.2f" $(echo "${parse_end_time} - ${parse_start_time}" | bc))
  # Log response parsing operation
  log_benchmark "${current_script_header}" "${FILE_SIZE}" "${LINE_COUNT}" "${CHAR_COUNT}" "${model}" "response_parsing" "${parse_duration}" "${response_word_count}" "${SCRIPT_COMPLEXITY}" ""

  # --- Interactive Editing ---
  # If interactive mode is enabled, allow user to edit the response
  if [ "${interactive_mode}" = "true" ]; then
    log_message "INFO" "Opening documentation in editor for customization..."
    RESPONSE=$(edit_text "${RESPONSE}") # Call edit function
    if [ $? -eq 0 ]; then
        log_message "SUCCESS" "Documentation customized."
        # Recalculate response metrics after editing
        response_word_count=$(echo "${RESPONSE}" | wc -w | tr -d ' ')
        jq --arg words "${response_word_count}" '.response_metrics.word_count = $words' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"
    else
        log_message "WARNING" "Interactive editing failed or was skipped."
    fi
  fi

  # --- Update README.md ---
  log_message "INFO" "Updating README.md with ${readme_format} format..."
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  # Calculate total execution time for this function
  local end_time=$(date +%s.%N)
  TOTAL_EXECUTION_TIME=$(printf "%.2f" $(echo "${end_time} - ${start_time}" | bc))

  # Call the appropriate generation function based on the chosen format
  case "${readme_format}" in
      fancy)
          generate_fancy_readme "${current_script_header}" "${model}" "${RESPONSE}" "${timestamp}"
          ;;
      enhanced)
          generate_enhanced_readme "${current_script_header}" "${model}" "${RESPONSE}" "${timestamp}"
          ;;
      basic|*) # Default to basic format
          generate_basic_readme "${current_script_header}" "${model}" "${RESPONSE}" "${timestamp}"
          ;;
  esac

  log_message "SUCCESS" "README.md updated for ${current_script_header}"

  # --- Final Logging and Summary ---
  # Calculate estimation accuracy
  local accuracy_val=""
   if [ -n "$estimated_seconds" ] && [ "$estimated_seconds" -gt 0 ] && [ "$(echo "$TOTAL_EXECUTION_TIME > 0.01" | bc -l)" -eq 1 ]; then # Avoid division by zero/tiny
       accuracy_val=$(echo "scale=4; ${estimated_seconds} / ${TOTAL_EXECUTION_TIME}" | bc 2>/dev/null || echo "")
   fi

  # Log the total analysis time for this script
  log_benchmark "${current_script_header}" "${FILE_SIZE}" "${LINE_COUNT}" "${CHAR_COUNT}" "${model}" "total_analysis" "${TOTAL_EXECUTION_TIME}" "${response_word_count}" "${SCRIPT_COMPLEXITY}" "${accuracy_val}"

  # Update the main changelog file
  update_changelog "${current_script_header}" "${model}" "${TOTAL_EXECUTION_TIME}"

  # Generate and display the benchmark summary box
  generate_benchmark_summary "${model}" "${current_script_header}" "${TOTAL_EXECUTION_TIME}" "${request_duration}" "${parse_duration}" "${FILE_SIZE}" "${LINE_COUNT}" "${CHAR_COUNT}" "${response_word_count}" "${estimated_seconds}" "${SCRIPT_COMPLEXITY}"

  # Add final completion timestamp to the session's metrics log
  jq --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" '.completion_timestamp = $ts' "${METRICS_LOG}" > "${METRICS_LOG}.tmp" && mv "${METRICS_LOG}.tmp" "${METRICS_LOG}"

  # Play completion sound if enabled
  play_sound "complete"

  # Show a random tip
  show_tip

  return 0 # Indicate successful completion
}

# Function to export the generated README.md to other formats (HTML, PDF)
export_readme() {
  local format="$1" # Target format (html or pdf)
  local readme_file="${README}" # Path to the source README.md

  # Check if README.md exists
  if [ ! -f "${readme_file}" ]; then
    log_message "ERROR" "README.md not found in the current directory. Generate documentation first."
    play_sound "error"
    return 1
  fi

  # Check if pandoc is installed (required for export)
  if ! command -v pandoc &> /dev/null; then
    log_message "ERROR" "pandoc is required for export (--export). Please install pandoc (e.g., 'brew install pandoc')."
    play_sound "error"
    return 1
  fi

  # Determine output filename based on format
  local output_file="${readme_file%.*}.${format}" # Replace .md with .html or .pdf

  log_message "INFO" "Exporting ${readme_file} to ${format}: ${output_file}"

  # Execute pandoc command based on format
  case "${format}" in
    html)
      # Export to HTML with a basic Bootstrap theme for styling
      pandoc -s "${readme_file}" -o "${output_file}" --metadata title="Script Documentation" \
        --css "https://cdn.jsdelivr.net/npm/bootstrap@5.2.3/dist/css/bootstrap.min.css" \
        --toc --toc-depth=3 # Add table of contents
      ;;
    pdf)
      # Export to PDF. Requires a LaTeX engine (like pdflatex) or wkhtmltopdf installed.
      # Pandoc will try to find a suitable engine.
      log_message "INFO" "PDF export requires a LaTeX engine (like TinyTeX/MacTeX) or wkhtmltopdf installed."
      pandoc "${readme_file}" -o "${output_file}" --toc --toc-depth=3
      ;;
    *)
      # Handle unsupported formats
      log_message "ERROR" "Unsupported export format: '${format}'. Use 'html' or 'pdf'."
      play_sound "error"
      return 1
      ;;
  esac

  # Check pandoc exit status
  if [ $? -eq 0 ]; then
    log_message "SUCCESS" "Successfully exported to ${format}: ${output_file}"
    play_sound "complete"
  else
    log_message "ERROR" "Failed to export to ${format}. Check pandoc installation and dependencies (e.g., LaTeX for PDF)."
    play_sound "error"
    return 1
  fi

  return 0
}

# Function to watch a directory for new or modified script files
watch_directory() {
  local directory="$1" # Directory to watch
  local model="$2" # Model to use for documentation
  local process_existing="$3" # Boolean: true to process existing files first

  # Check if the watch directory exists
  if [ ! -d "${directory}" ]; then
    log_message "ERROR" "Watch directory '${directory}' does not exist."
    play_sound "error"
    exit 1
  fi

  # Check if fswatch is installed (required for watch mode)
  if ! command -v fswatch &> /dev/null; then
    log_message "ERROR" "fswatch is required for watch mode (--watch). Please install fswatch (e.g., 'brew install fswatch')."
    play_sound "error"
    exit 1
  fi

  log_message "INFO" "Starting watch mode on directory: ${directory}"
  log_message "INFO" "Using model: ${model}"
  log_message "INFO" "Press Ctrl+C to stop watching."

  # Keep track of processed files to avoid reprocessing on simple modifications
  # Using an associative array for efficient lookup
  declare -A processed_files_checksums

  # Process existing files first if requested
  if [ "${process_existing}" = "true" ]; then
    log_message "INFO" "Processing existing script files in ${directory}..."
    # Find script files (adjust extensions as needed)
    # Use -print0 and read -d '' for safer handling of filenames with spaces/special chars
    find "${directory}" -maxdepth 1 -type f \( -name "*.sh" -o -name "*.py" -o -name "*.js" -o -name "*.rb" -o -name "*.applescript" \) -print0 | while IFS= read -r -d $'\0' file; do
        log_message "INFO" "Processing existing file: ${file}"
        # Validate and generate README for the file, continue on error
        if validate_input_file "${file}" && generate_readme "${file}" "${model}" "${SKIP_ESTIMATE}" "${INTERACTIVE_MODE}" "${README_FORMAT}"; then
            # Store checksum to track changes only on success
            local checksum=$(md5 -q "${file}" 2>/dev/null || md5sum "${file}" | awk '{print $1}' 2>/dev/null)
            if [ -n "$checksum" ]; then
                processed_files_checksums["${file}"]=$checksum
            fi
        else
             log_message "ERROR" "Failed to process existing file: ${file}"
        fi
    done
    log_message "INFO" "Finished processing existing files."
  fi

  # Start watching the directory using fswatch
  # -0 uses null character as delimiter
  # -r watches recursively (remove if only top level is needed)
  # Filter for specific script extensions
  # Use --event Created --event Updated --event Renamed for more specific triggers if needed
  fswatch -0 -r -e ".*" -i "\\.(sh|py|js|rb|applescript)$" "${directory}" | while read -d "" event; do
    # Check if the event corresponds to a regular file that exists
    if [ -f "${event}" ]; then
      log_message "INFO" "Detected change in: ${event}"

      # Calculate checksum of the changed file
      local current_checksum=$(md5 -q "${event}" 2>/dev/null || md5sum "${event}" | awk '{print $1}' 2>/dev/null)
      local previous_checksum=${processed_files_checksums["${event}"]}

      # Process only if the file is new or its content has changed
      if [ -z "$previous_checksum" ] || [ -z "$current_checksum" ] || [ "$current_checksum" != "$previous_checksum" ]; then
          log_message "INFO" "Processing updated script: ${event}"
          # Validate and generate README, track errors
          if validate_input_file "${event}" && generate_readme "${event}" "${model}" "${SKIP_ESTIMATE}" "${INTERACTIVE_MODE}" "${README_FORMAT}"; then
              # Update checksum in our tracking map only on success
              if [ -n "$current_checksum" ]; then
                  processed_files_checksums["${event}"]=$current_checksum
              fi
          else
               log_message "ERROR" "Failed to process watched file: ${event}"
          fi
      else
          log_message "DEBUG" "Skipping ${event} (no content change detected)."
      fi
    else
        log_message "DEBUG" "Event target is not a file or does not exist: ${event}"
        # Optionally remove from checksum map if file deleted
        # unset processed_files_checksums["${event}"]
    fi
  done
}

# Function to process multiple files matching a glob pattern
batch_process() {
  local pattern="$1" # Glob pattern (e.g., "*.sh", "scripts/*.py")
  local model="$2" # Model to use

  log_message "INFO" "Starting batch processing for pattern: ${pattern}"

  local files_processed=0
  local files_found=0
  local processing_errors=0

  # Using zsh's globbing capabilities (ensure script runs with zsh)
  # Use nullglob to avoid errors if pattern matches nothing
  setopt localoptions nullglob
  # Use eval carefully, consider alternatives like find if pattern is complex or from untrusted source
  # local files=( $(find . -maxdepth 1 -name "${pattern}") ) # Example using find
  local files=( ${=pattern} ) # Use =pattern for word splitting based on shell settings
  unsetopt nullglob # Turn off nullglob after use

  files_found=${#files[@]}

  # Check if any files were found
  if [ $files_found -eq 0 ]; then
    log_message "WARNING" "No files found matching pattern: ${pattern}"
    return 1
  fi

  log_message "INFO" "Found ${files_found} files to process."

  # Process each found file
  local count=1
  for file in "${files[@]}"; do
    # Check if it's actually a file (globbing might include directories if pattern is loose)
    if [ -f "${file}" ]; then
      log_message "INFO" "Processing file ${count}/${files_found}: ${file}"
      # Validate and generate README for the file, track errors
      if validate_input_f