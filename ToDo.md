## ToDo

## Known Issues

- ~~Job control messages (process IDs) are displayed when running background suggestion generation~~ ✅ FIXED

### Configuration Management

- [x] Implement persistent configuration storage (~/.git-suggest-config)
- [x] Add basic configuration validation
- [x] Improve configuration display to show both file and environment sources
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
- [x] Implement Anthropic provider
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
- [x] Improve error state persistence and display
- [x] Add Tab retry mechanism for loading states
- [x] Fix job control messages during background processing
- [ ] Enhance API error handling (rate limits, network issues)
- [ ] Implement token validation
- [ ] Add graceful fallbacks for errors
- [ ] Enhance error messaging with troubleshooting steps
- [ ] Add error logging and reporting
- [ ] Implement retry mechanisms for transient failures

### User Experience & Onboarding

- [x] Add state-based feedback messages
- [x] Improve diff detection and caching
- [x] Fix loading state display issues
- [x] Add Tab retry mechanism for suggestions
- [x] **Improve onboarding experience for new users**
  - [x] Add interactive setup wizard
  - [x] Create guided first-run experience with welcome messages
  - [x] Add smart defaults and recommendations
  - [x] Add provider comparison with speed/cost information
- [x] **Auto-detection and smart configuration**
  - [x] Auto-detect existing API keys in environment (OPENAI_API_KEY, ANTHROPIC_API_KEY)
  - [x] Suggest optimal provider based on available keys
  - [x] Validate API keys during setup with real API tests
- [x] **User-friendly setup process**
  - [x] Simplify configuration flow with enhanced menu
  - [x] Add setup validation with real API tests
  - [x] Provide clear success/failure feedback
  - [x] Add step-by-step guidance with helpful links
- [ ] **Documentation and examples**
  - [x] Add quick start guide in setup wizard
  - [ ] Include common setup examples in documentation
  - [ ] Show sample commit messages during setup
- [x] **First-time user experience**
  - [x] Add welcome message and tips
  - [x] Provide usage examples after setup
  - [x] Add helpful hints for common workflows
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
- [ ] **Create comprehensive user documentation**
  - [ ] Write detailed README with installation guide
  - [ ] Add setup and configuration documentation
  - [ ] Include troubleshooting section
  - [ ] Add FAQ for common issues
- [ ] **Installation and setup instructions**
  - [ ] Add multiple installation methods
  - [ ] Include dependency requirements
  - [ ] Provide platform-specific instructions
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
