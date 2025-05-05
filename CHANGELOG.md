# Script to README Generator Changelog

## Version 1.5.0 - 2025-04-29
- Significantly enhanced system prompt for more comprehensive and better structured READMEs
- Added specific section requirements with mandatory templates for consistent documentation
- Implemented model-specific prompt optimizations for deepseek-coder and codellama models
- Improved time estimation algorithm with model-specific timing adjustments
- Extended minimum processing times to ensure high-quality output from all models
- Enhanced markdown formatting instructions with specific guidelines for code blocks and lists
- Added word count requirements for more thorough documentation
- Improved error handling during API requests with better feedback

## Version 1.4.3 - 2025-04-29
- Enhanced prompt engineering for more comprehensive READMEs
- Added colorized output for better terminal experience
- Improved base64 file detection and decoding
- Added "Did you know" tips system for user guidance
- Enhanced README output with detailed script metadata table
- Added model performance information section
- Improved JSON request handling for special characters
- Fixed API error handling and response parsing

## Version 1.4.2 - 2025-04-29
- Fixed additional issues with historical factor calculation
- Added comprehensive validation for historical performance data
- Implemented bounds checking for historical factors (0-100)
- Enhanced logging for better troubleshooting of performance data
- Added detection of invalid division operations in calculations
- Improved fallback to default values with descriptive warnings
- Added detailed log messages when historical data is not found
- Ensured all estimation factors are properly validated

## Version 1.4.1 - 2025-04-29
- Fixed critical bug in time estimation calculation causing zero estimates
- Added extensive validation for all calculation factors
- Improved factor debugging with detailed logging
- Ensured size factor is always at least 1.0
- Added safeguards against zero or empty values in any factor
- Fixed potential division by zero errors
- Enhanced logging of calculation factors for better debugging
- Ensured non-zero estimates for all models regardless of calculation

## Version 1.4.0 - 2025-04-29
- Enhanced documentation quality with rich markdown formatting
- Increased timeout limits from 5 to 15 minutes for all models
- Added much more generous buffers on estimated times (3x instead of 1.5x)
- Set minimum timeout of 5 minutes for all models regardless of file size
- Added model-specific minimums with significantly increased values
- Expanded model detection to include more large models (grok, phi, etc.)
- Added detailed section templates for comprehensive READMEs
- Improved markdown formatting instructions for higher quality output

## Version 1.3.3 - 2025-04-29
- Improved time estimation based on previous benchmarks
- Added model-specific timing adjustments for better accuracy
- Added file size scaling for large files
- Fixed estimation math errors with proper validation
- Enhanced error handling for deepseek-coder:latest model
- Added specialized timing minimum for qwen2.5-coder:7b
- Improved progress reporting for large files

## Version 1.3.2 - 2025-04-29
- Added request timeout handling and recovery
- Added improved error detection for model responses
- Added fallback content extraction for different model formats
- Added detailed timestamps to changelog entries
- Added formatted whitespace in README outputs
- Added model recommendations when request fails
- Moved changelog to project root directory
- Added support for decompiling .scpt files with osadecompile

## Version 1.3.1 - 2025-04-29

### 2025-04-29
- Generated README for analyze_with_ollama_picker_analysis.sh with deepseek-coder:6.7b (24.79s) at 2025-04-29 16:18:50
- Generated README for analyze_with_ollama_picker_analysis.sh with qwen2.5-coder:7b (34.81s) at 2025-04-29 16:17:39
- Generated README for analyze_with_ollama_picker_analysis.sh with deepseek-coder:latest (5.36s) at 2025-04-29 16:16:34
- Generated README for analyze_with_ollama_picker_analysis.sh with qwen2.5-coder:7b (52.64s) at 2025-04-29 15:35:21
- Generated README for analyze_with_ollama_picker_analysis.sh with qwen2.5-coder:7b (60.42s) at 2025-04-29 15:02:25
- Generated README for analyze_with_ollama_picker_analysis.sh with codellama:7b (26.38s) at 2025-04-29 14:28:26
- Generated README for analyze_with_ollama_picker_analysis.sh with codellama:13b (53.18s) at 2025-04-29 14:26:38
- Generated README for analyze_with_ollama_picker_analysis.sh with deepseek-coder:latest (4.81s) at 2025-04-29 14:25:29
- Generated README for analyze_with_ollama_picker_analysis.sh with deepseek-coder:6.7b (36.63s) at 2025-04-29 14:04:55
- Generated README for analyze_with_ollama_picker_analysis.sh with deepseek-coder:6.7b (35.40s) at 2025-04-29 14:01:01
- Generated README for analyze_with_ollama_picker_analysis.sh with qwen2.5-coder:7b (31.61s) at 2025-04-29 13:59:06
- Generated README for analyze_with_ollama_picker_analysis.sh with deepseek-coder:latest (11.47s) at 2025-04-29 13:57:57
- Generated README for analyze_with_ollama_picker_analysis.sh with deepseek-coder:latest (24.21s) at 2025-04-29 13:38:43
- Generated README for analyze_with_ollama_picker_analysis.sh with deepseek-coder:latest (9.92s) at 2025-04-29 13:06:47
- Generated README for analyze_with_ollama_picker_analysis.sh with qwen2.5-coder:7b (54.91s) at 2025-04-29 11:54:25
- Generated README for analyze_with_ollama_picker_analysis.sh with qwen2.5-coder:7b (54.84s)
- Generated README for analyze_with_ollama_picker_analysis.sh with deepseek-coder:latest (5.84s)
- Added dynamic model detection and complexity calculation
- Created model performance database for better time estimates
- Improved time estimation based on script complexity
- Added historical performance logging for models
- Enhanced error handling and reporting
- Moved changelog to project root directory
- Added support for decompiling .scpt files with osadecompile

## Version 1.3.0 - 2025-04-29

### 2025-04-29
- Generated README for analyze_with_ollama_picker_analysis.sh with deepseek-coder:6.7b (24.79s) at 2025-04-29 16:18:50
- Generated README for analyze_with_ollama_picker_analysis.sh with qwen2.5-coder:7b (34.81s) at 2025-04-29 16:17:39
- Generated README for analyze_with_ollama_picker_analysis.sh with deepseek-coder:latest (5.36s) at 2025-04-29 16:16:34
- Generated README for analyze_with_ollama_picker_analysis.sh with qwen2.5-coder:7b (52.64s) at 2025-04-29 15:35:21
- Generated README for analyze_with_ollama_picker_analysis.sh with qwen2.5-coder:7b (60.42s) at 2025-04-29 15:02:25
- Generated README for analyze_with_ollama_picker_analysis.sh with codellama:7b (26.38s) at 2025-04-29 14:28:26
- Generated README for analyze_with_ollama_picker_analysis.sh with codellama:13b (53.18s) at 2025-04-29 14:26:38
- Generated README for analyze_with_ollama_picker_analysis.sh with deepseek-coder:latest (4.81s) at 2025-04-29 14:25:29
- Generated README for analyze_with_ollama_picker_analysis.sh with deepseek-coder:6.7b (36.63s) at 2025-04-29 14:04:55
- Generated README for analyze_with_ollama_picker_analysis.sh with deepseek-coder:6.7b (35.40s) at 2025-04-29 14:01:01
- Generated README for analyze_with_ollama_picker_analysis.sh with qwen2.5-coder:7b (31.61s) at 2025-04-29 13:59:06
- Generated README for analyze_with_ollama_picker_analysis.sh with deepseek-coder:latest (11.47s) at 2025-04-29 13:57:57
- Generated README for analyze_with_ollama_picker_analysis.sh with deepseek-coder:latest (24.21s) at 2025-04-29 13:38:43
- Generated README for analyze_with_ollama_picker_analysis.sh with deepseek-coder:latest (9.92s) at 2025-04-29 13:06:47
- Generated README for analyze_with_ollama_picker_analysis.sh with qwen2.5-coder:7b (54.91s) at 2025-04-29 11:54:25
- Generated README for analyze_with_ollama_picker_analysis.sh with qwen2.5-coder:7b (54.84s)
- Generated README for analyze_with_ollama_picker_analysis.sh with deepseek-coder:latest (5.84s)
- Added dynamic model detection and complexity calculation
- Created model performance database for better time estimates
- Improved time estimation based on script complexity
- Added historical performance logging for models
- Enhanced error handling and reporting
