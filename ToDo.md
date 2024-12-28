## ToDo

## Known Issues

- Job control messages (process IDs) are displayed when running background suggestion generation

### Configuration Management

- [x] Implement persistent configuration storage (~/.git-suggest-config)
- [x] Add basic configuration validation
- [ ] Enhance configuration validation (API key formats, file permissions)
- [ ] Support multiple configuration profiles
- [x] Add command to view current configuration
- [x] Add command to clear configuration
- [ ] Add configuration backup/restore functionality

### LLM Integration

- [x] Create basic LLM provider structure
- [x] Complete LLM provider abstraction layer
- [x] Implement OpenAI provider (basic functionality)
- [ ] Enhance OpenAI provider with better error handling
- [ ] Implement Anthropic provider
- [x] Add initial local model support
- [ ] Enhance local model support (model validation, format checking)
- [ ] Add rate limiting and token usage tracking
- [ ] Implement async operations to prevent shell blocking
- [ ] Add provider-specific configuration validation

### Prompt Engineering

- [x] Design base prompt template
- [ ] Extract prompt logic into shared function for all providers
- [ ] Allow for custom prompt templates
- [ ] Add repository context to prompts (file types, repo name)
- [ ] Implement diff size optimization (handle large changes)
- [ ] Add diff preprocessing for better LLM understanding
- [ ] Add template validation
- [ ] Add prompt versioning and migration support

### Error Handling

- [x] Implement basic state management
- [x] Add basic error messaging
- [x] Add basic API error handling
- [ ] Enhance API error handling (rate limits, network issues)
- [ ] Implement token validation
- [ ] Add graceful fallbacks for errors
- [ ] Enhance error messaging with troubleshooting steps
- [ ] Add error logging and reporting
- [ ] Implement retry mechanisms for transient failures

### User Experience

- [x] Add state-based feedback messages
- [x] Improve diff detection and caching
- [ ] Fix loading state display issues
- [ ] Move suggestion generation to git add for better performance
- [ ] Add progress indicators for long-running operations
- [ ] Improve suggestion formatting
- [ ] Add command to view suggestion history
- [ ] Add ability to regenerate suggestions
- [x] Add debug logging
- [ ] Add debug mode toggle for users
- [ ] Add color configuration options
- [ ] Add suggestion preview in status bar

### Testing & Documentation

- [ ] Add unit tests for core functionality
- [ ] Add integration tests for LLM providers
- [ ] Create user documentation
- [ ] Add configuration examples
- [ ] Document prompt templates
- [ ] Add troubleshooting guide
- [ ] Create contribution guidelines
- [ ] Add performance benchmarks
- [ ] Document debug log format
- [ ] Add examples of successful prompts and responses

### Performance & Optimization

- [x] Basic diff caching mechanism
- [ ] Optimize diff caching mechanism
- [ ] Add suggestion caching
- [ ] Implement lazy loading for providers
- [ ] Add memory usage optimization
- [ ] Improve startup time
- [ ] Add background processing for suggestions

### Security

- [x] Add basic token security (file permissions)
- [ ] Add token encryption
- [ ] Implement secure token storage
- [ ] Add provider-specific security measures
- [ ] Add security documentation
- [ ] Add token rotation support
