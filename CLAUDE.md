# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build/Run Commands
- Run script: `./script2readme.sh [OPTIONS] <input_file> [model]`
- List available models: `./script2readme.sh --list-models`
- Enable debug mode: `./script2readme.sh --debug <input_file>`
- Run with specific model: `./script2readme.sh <input_file> codellama:7b`
- Skip time estimation: `./script2readme.sh --no-estimate <input_file>`

## Code Style Guidelines
- **Shell Scripting**: Use zsh/bash with proper shebangs
- **Formatting**: Use 2-space indentation for shell scripts
- **Functions**: Document with descriptive comments above each function
- **Variables**: Use uppercase for constants, lowercase for local variables
- **Error Handling**: Check command exit status with `if [ $? -ne 0 ]` pattern
- **Debugging**: Use set -x for debug mode
- **JSON**: Use jq for JSON manipulation with proper quoting
- **File Operations**: Always check if files/directories exist before using
- **Dependencies**: Validate all dependencies using check_dependencies() function
- **Benchmarking**: Use log_benchmark() for tracking performance metrics
- **Metrics**: Track execution time with $(date +%s.%N) for high precision