# Model Compatibility Guide for script2readme

This guide explains the compatibility issues with different Ollama models and provides workarounds to get the best results with each model.

## Model Analysis

Based on testing, here's how different models perform with the script2readme tool:

| Model | Compatibility | Issues | Workarounds |
|-------|--------------|--------|-------------|
| qwen2.5-coder:7b | ✅ Excellent | None | Default choice for best results |
| deepseek-coder:latest | ⚠️ Partial | Doesn't follow format instructions | Enhanced prompting applied automatically |
| codellama:7b | ⚠️ Partial | Doesn't follow format instructions | Enhanced prompting applied automatically |
| codellama:13b | ⚠️ Partial | Doesn't follow format instructions | Enhanced prompting applied automatically |
| deepseek-coder:6.7b | ⚠️ Partial | Sometimes works | Try multiple runs if it fails |

## Understanding the Issues

The issue with models like deepseek-coder:latest and codellama:7b is not with the API itself, but with how these models interpret and follow formatting instructions. Instead of generating structured markdown READMEs with proper headers and sections, they tend to produce general summaries of the script.

When analyzing your test results, I noticed:

1. **API responses work** - The models do respond and generate content
2. **Content structure is incorrect** - They don't follow the markdown format instructions
3. **Content quality varies** - Some models provide more detailed analysis than others

## Automatic Enhancements

The latest version of script2readme includes automatic enhancements for problematic models:

1. **Enhanced prompting** - Models that have shown formatting issues will receive stronger, more explicit instructions
2. **Format enforcement** - The prompt specifically emphasizes following exact markdown structure
3. **Response validation** - Better parsing to extract useful content even from poorly formatted responses

## Best Practices

For best results with script2readme:

1. **Start with qwen2.5-coder:7b** - This model consistently produces well-formatted READMEs
2. **Try different models** - Different models may provide different insights
3. **Check the README output** - Review the generated documentation for correctness and completeness
4. **Run with debug** - Use `--debug` flag if you encounter issues to get more information

## Future Improvements

Future versions of script2readme may include:

1. **Model-specific templates** - Customized prompts optimized for each model
2. **Response post-processing** - Automatic reformatting of poorly structured responses
3. **Quality scoring** - Evaluation of response quality to select best results

## Technical Details

The enhanced prompting system works by:

1. Detecting problematic models at runtime
2. Applying a specialized system prompt with explicit format requirements
3. Using more direct language to ensure format compliance
4. Adding numbered instructions and examples

This approach has shown better results with models that would otherwise produce unstructured content.