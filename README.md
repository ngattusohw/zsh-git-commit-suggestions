# 🚀 Git Commit Message Suggestions for Zsh

An intelligent zsh plugin that generates concise, conventional commit messages based on your staged changes using AI providers like OpenAI or Anthropic.

## ✨ Features

- 🤖 **AI-Powered Suggestions**: Generates conventional commit messages using OpenAI or Anthropic
- ⚡ **Instant Tab Completion**: Press `Tab` to insert suggestions while typing `git commit -m "`
- 🔄 **Background Processing**: Non-blocking suggestion generation with loading states
- 🎯 **Concise Messages**: Generates single-line commits under 72 characters
- 🛡️ **Error Handling**: Graceful error states with helpful guidance
- 🔧 **Easy Configuration**: Simple setup wizard with `git-suggest-config`
- 🌍 **Environment Support**: Works with both config files and environment variables

## 📦 Installation

### Oh My Zsh

1. **Clone the repository:**

   ```bash
   git clone https://github.com/yourusername/zsh-git-commit-suggestions \
     $ZSH_CUSTOM/plugins/git-commit-completion
   ```

2. **Add to your plugins in `~/.zshrc`:**

   ```bash
   plugins=(... git-commit-completion)
   ```

3. **Reload your shell:**
   ```bash
   source ~/.zshrc
   ```

### Manual Installation

1. **Clone and source the plugin:**
   ```bash
   git clone https://github.com/yourusername/zsh-git-commit-suggestions
   echo "source /path/to/git-commit-completion.plugin.zsh" >> ~/.zshrc
   source ~/.zshrc
   ```

## ⚙️ Setup

### Quick Start

1. **Configure your AI provider:**

   ```bash
   git-suggest-config
   ```

2. **Choose your provider:**

   - **OpenAI API** (GPT-3.5-turbo)
   - **Anthropic API** (Claude-3-haiku)
   - **Local LLM** (coming soon)

3. **Stage some changes and commit:**
   ```bash
   git add .
   git commit -m "
   # Press Tab to insert AI-generated suggestion!
   ```

### Configuration Options

#### Option 1: Interactive Setup

```bash
git-suggest-config
```

#### Option 2: Environment Variables

```bash
export SUGGEST_PROVIDER="anthropic"  # or "openai"
export SUGGEST_LLM_TOKEN="your-api-token"
```

#### Option 3: Config File

The plugin creates `~/.git-suggest-config` with your settings.

## 🎮 Usage

### Basic Workflow

1. **Make your changes:**

   ```bash
   # Edit files
   vim src/components/Button.tsx
   ```

2. **Stage changes:**

   ```bash
   git add .
   # Plugin automatically analyzes diff in background
   ```

3. **Start commit:**
   ```bash
   git commit -m "
   # Suggestion appears automatically!
   # Press Tab to insert: "feat: ✨ add responsive button component"
   ```

### Loading States

The plugin shows helpful status indicators:

- 🔵 **Loading**: `⟳ Generating commit suggestion... (Press Tab to check if ready)`
- 🟢 **Ready**: `Suggested commit message: feat: ✨ add new feature`
- 🟡 **Unconfigured**: `⚠ LLM not configured. Run git-suggest-config to set up.`
- 🔴 **Error**: `✖ Error generating suggestion: No staged changes detected`

### Tab Retry Feature

If a suggestion is still loading, press `Tab` multiple times to retry:

- First Tab: Shows loading message
- Subsequent Tabs: Checks if suggestion is ready and inserts it

## 🤖 AI Providers

### OpenAI (GPT-3.5-turbo)

- **Setup**: Get API key from [OpenAI Platform](https://platform.openai.com/api-keys)
- **Cost**: Pay-per-use (~$0.001 per commit message)
- **Speed**: ~2-3 seconds

### Anthropic (Claude-3-haiku)

- **Setup**: Get API key from [Anthropic Console](https://console.anthropic.com/)
- **Cost**: Pay-per-use (~$0.0001 per commit message)
- **Speed**: ~1-2 seconds
- **Recommended**: Faster and cheaper than OpenAI

## 🎯 Example Suggestions

The plugin generates concise, conventional commit messages:

```bash
# Before (manual):
git commit -m "updated the user authentication system and fixed some bugs"

# After (AI-generated):
git commit -m "feat: ✨ improve user authentication with password validation"
git commit -m "fix: 🐛 resolve login timeout issue"
git commit -m "chore: 🔧 update dependencies to latest versions"
```

## 🔧 Configuration Commands

### View Current Config

```bash
git-suggest-config
# Shows both file-based and environment configuration
```

### Change Provider

```bash
git-suggest-config
# Select option 1 (OpenAI) or 2 (Anthropic)
```

### Clear Configuration

```bash
git-suggest-config
# Select option 5 to clear all settings
```

## 🐛 Troubleshooting

### Debug Logging

View detailed logs for troubleshooting:

```bash
cat /tmp/git-completion-debug.log
```

### Clear Debug Logs

```bash
rm /tmp/git-completion-debug.log
```

### Common Issues

**No suggestions appearing:**

- Check if files are staged: `git status`
- Verify configuration: `git-suggest-config`
- Check debug logs for errors

**Suggestion stuck loading:**

- Press `Tab` multiple times to retry
- Check your internet connection
- Verify API token is valid

**Permission denied errors:**

- Ensure `/tmp` is writable
- Check config file permissions: `ls -la ~/.git-suggest-config`

## 🛠️ Development

### Plugin Structure

```
git-commit-completion.plugin.zsh    # Main plugin file
├── Hooks (preexec, precmd)         # Git command detection
├── State Management                # Loading, Ready, Error states
├── LLM Providers                   # OpenAI, Anthropic integrations
├── Background Processing           # Non-blocking generation
└── Configuration                   # Setup and management
```

### Testing Changes

```bash
# Edit the plugin
vim $ZSH_CUSTOM/plugins/git-commit-completion/git-commit-completion.plugin.zsh

# Reload
source ~/.zshrc

# Test with debug logging
rm /tmp/git-completion-debug.log
git add . && git commit -m "
cat /tmp/git-completion-debug.log
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests and documentation
5. Submit a pull request

## 📄 License

MIT License - see LICENSE file for details

## 🎉 Acknowledgments

- Inspired by GitHub Copilot for terminal workflows
- Built with zsh hooks and widget system
- Powered by OpenAI and Anthropic APIs

---

**Made with ❤️ by ng3**
