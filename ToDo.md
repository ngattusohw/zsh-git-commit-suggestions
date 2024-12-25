## ToDo

### Configuration Management

- [ ] Implement persistent configuration storage (~/.git-suggest-config)
- [ ] Add configuration validation
- [ ] Support multiple configuration profiles
- [ ] Add command to view current configuration

### LLM Integration

- [ ] Create LLM provider abstraction layer
- [ ] Implement OpenAI provider
- [ ] Implement Anthropic provider
- [ ] Add local model support
- [ ] Add rate limiting and token usage tracking
- [ ] Implement async operations to prevent shell blocking

### Prompt Engineering

- [ ] Design base prompt template
- [ ] Allow for custom prompt templates
- [ ] Add repository context to prompts (file types, repo name)
- [ ] Implement diff size optimization (handle large changes)
- [ ] Add diff preprocessing for better LLM understanding

### Error Handling

- [ ] Add API error handling (rate limits, network issues)
- [ ] Implement token validation
- [ ] Add graceful fallbacks for errors
- [ ] Improve error messaging to users

### User Experience

- [ ] Add progress indicators for long-running operations
- [ ] Improve suggestion formatting
- [ ] Add command to view suggestion history
- [ ] Add ability to regenerate suggestions
- [ ] Add debug mode for troubleshooting

### Testing & Documentation

- [ ] Add unit tests for core functionality
- [ ] Add integration tests for LLM providers
- [ ] Create user documentation
- [ ] Add configuration examples
- [ ] Document prompt templates
