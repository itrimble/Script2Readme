# Script Analysis with Ollama (`analyze_with_ollama_picker_analysis.sh`)

**Author:** Ian Trimble  
**Version:** 1.0.0  
**Created:** April 28, 2025  

---

## Overview

The `analyze_with_ollama_picker_analysis.sh` script is a command-line tool designed to analyze script files using Ollama models and generate detailed Markdown documentation. It supports various script types, including shell and AppleScript, and provides extensive benchmarking to track performance metrics.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Installation](#installation)
3. [Usage](#usage)
4. [Configuration](#configuration)
5. [Output](#output)
6. [Troubleshooting](#troubleshooting)
7. [License](#license)

---

## Prerequisites

- **Operating System**: macOS
- **Required Tools**:
  - `jq`: For JSON processing.
  - `bc`: For mathematical calculations.
  - `curl`: For making API requests.
  - `ollama`: For running local language models.
- **Ollama Models**: At least one model must be installed (e.g., `qwen2.5:1.5b`).

### Install Prerequisites

Use [Homebrew](https://brew.sh) to install the required tools:

```sh
brew install jq bc curl ollama
```

---

## Installation

1. **Download the Script**  
   Save the script as `analyze_with_ollama_picker_analysis.sh` in your desired directory.

2. **Make the Script Executable**  
   Run the following command:

   ```sh
   chmod +x analyze_with_ollama_picker_analysis.sh
   ```

3. **Start the Ollama Server**  
   Ensure the Ollama server is running:

   ```sh
   ollama serve &
   ```

4. **Pull a Model**  
   Download at least one Ollama model:

   ```sh
   ollama pull qwen2.5:1.5b
   ```

---

## Usage

To analyze a script, run:

```sh
./analyze_with_ollama_picker_analysis.sh <input_file> [model]
```

- `<input_file>`: Path to the script file (e.g., `.sh`, `.scpt`).
- `[model]`: Optional. Specify an Ollama model (e.g., `qwen2.5:1.5b`).

If no model is specified, the script will prompt for selection or default to the first available model.

### Example

```sh
./analyze_with_ollama_picker_analysis.sh my_script.sh qwen2.5:1.5b
```

---

## Configuration

- **Benchmark Directory**: `${HOME}/ollama_benchmarks`  
  Stores benchmark logs and metrics.
- **README File**: `README.md` in the current directory.  
  Appends the generated documentation.

---

## Output

The script generates:

- **README.md**: Appends a new section with the analysis results.
- **Benchmark Logs**:
  - `benchmark_log.csv`: Detailed performance metrics.
  - `metrics_<session_id>.json`: Session-specific metrics.
  - `response_<session_id>.md`: Raw Ollama response.

---

## Troubleshooting

- **Model Not Found**:  
  - Ensure the model is installed: `ollama pull <model>`.
- **Dependency Errors**:  
  - Install missing tools: `brew install jq bc curl ollama`.
- **API Connection Issues**:  
  - Start the Ollama server: `ollama serve &`.

---

## License

This script is provided under the MIT License. See the generated README.md for full license details.