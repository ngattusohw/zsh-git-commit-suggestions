# zsh-git-commit-suggestions

This is a work in progress repo

## Goal

Allow for inline suggestions for git commit messages for git cli users, generated based on the diff from the staged files

## Todo

Detect git add commands
Query diff against configured llm and store result for quick viewing experience for user
configurable llm choice, either local or remote
set up docs

## How to update the zsh plugin

`vim $ZSH_CUSTOM/plugins/git-commit-completion/git-commit-completion.plugin.zsh`

To view the debug logs run `cat /tmp/git-completion-debug.log`

after making changes, run `source ~/.zshrc` to reload the plugin

after every run, delete the debug log file `rm /tmp/git-completion-debug.log  # Clear old logs`

### Discussion around delay based approach for detecting git add commands

#### Why this approach?

1. **Simplicity**: No external dependencies required
2. **Cross-platform**: Works consistently across different systems
3. **Non-blocking**: Running in background prevents shell freezing
4. **User Experience**: 0.1s delay is imperceptible to users

#### Potential Side Effects

- Very rare cases where diff might be missed if git takes longer than 0.1s to update index
- Small memory overhead from background processes
- Theoretical race conditions in high-frequency staging operations

#### Alternative Approaches Considered

1. **Git Post-Index-Change Hook**

   - Would be ideal but not provided natively by Git
   - Would require Git configuration changes

2. **File System Watcher**

   - More robust solution using `inotifywait`
   - Requires additional system dependencies
   - Platform-specific implementation needed

3. **Git Status Polling**
   - Could actively check git status until changes detected
   - More resource intensive
   - Potential for blocking shell operations

#### Future Improvements

If the current approach proves problematic, we could implement a more robust solution using a combination of:

- Multiple retry attempts
- File system watchers where available
- Configurable delay times

For now, the delay-based approach provides the best balance of reliability and simplicity.

## Implementation Details

### Git Staging Detection

...

### Suggestion State Management

The plugin uses a state-based system to handle different stages of commit message generation and display appropriate feedback to users.

#### States

- **UNCONFIGURED**: No LLM configuration detected

  - Displays: `⚠ LLM not configured. Run git-suggest-config to set up.`
  - Occurs when neither API token nor local LLM path is set

- **LOADING**: Generating suggestion

  - Displays: `⟳ Generating commit suggestion...`
  - Shows when waiting for LLM response

- **ERROR**: Something went wrong

  - Displays: `✖ Error generating suggestion: [error message]`
  - Common cases: no staged changes, LLM API errors

- **READY**: Suggestion available
  - Displays: The formatted commit message suggestion
  - Normal operation state

#### User Experience

Users will see different colored indicators based on the state:

- Yellow (⚠) for configuration warnings
- Blue (⟳) for loading states
- Red (✖) for errors
- Normal text for suggestions

#### Configuration

Users can configure their LLM preference using `git-suggest-config`:

1. OpenAI API
2. Anthropic API
3. Local LLM

The configuration command will guide users through setting up their preferred option.

#### State Flow

1. Plugin checks for configuration on load
2. When files are staged, diff is cached
3. On `git commit -m "`, plugin:
   - Verifies configuration
   - Checks for staged changes
   - Generates suggestion if all prerequisites met
   - Shows appropriate state message to user
