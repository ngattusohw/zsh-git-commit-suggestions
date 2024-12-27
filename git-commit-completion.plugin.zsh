# Save original PATH at the start of the script
typeset -g _ORIGINAL_PATH="$PATH"

# Debug log function with timestamp
_debug_log() {
    PATH="$_ORIGINAL_PATH" /bin/date +"[%H:%M:%S] $1" >> /tmp/git-completion-debug.log
}

# Function to manage state changes
_set_suggestion_state() {
    local new_state="$1"
    local error_msg="$2"

    typeset -g _SUGGESTION_STATE="$new_state"
    if [[ -n "$error_msg" ]]; then
        typeset -g _SUGGESTION_ERROR="$error_msg"
    else
        typeset -g _SUGGESTION_ERROR=""
    fi

    _debug_log "State changed to: $_SUGGESTION_STATE${error_msg:+ ($error_msg)}"
}

# Global state variables
typeset -g _CONFIG_FILE="${HOME}/.git-suggest-config"
typeset -g _COMMIT_SUGGESTION=""
typeset -g _CACHED_STAGED_DIFF=""
# Suggestion states
typeset -g _SUGGESTION_STATE="UNCONFIGURED"  # UNCONFIGURED, LOADING, ERROR, READY
typeset -g _SUGGESTION_ERROR=""
_debug_log "Initial state setup - State: $_SUGGESTION_STATE, Diff cached: ${_CACHED_STAGED_DIFF:+yes}"

# Function to update staged diff when files are staged
_update_staged_diff() {
    _debug_log "Starting diff update"
    if git rev-parse --is-inside-work-tree &>/dev/null; then
        _debug_log "Checking for staged changes..."
        local new_diff

        # Debug git status
        local git_status=$(git status --porcelain)
        _debug_log "Git status: $git_status"

        # Get both staged changes and new files
        new_diff=$(git diff --staged)
        _debug_log "Standard diff result: ${new_diff:+exists}"

        local new_files=$(git diff --staged --name-status | grep '^A' || true)
        _debug_log "Staged files status: $new_files"

        if [[ -n "$new_files" ]]; then
            _debug_log "New files detected: $new_files"
            # For new files, get their content
            while IFS= read -r line; do
                if [[ "$line" =~ ^A[[:space:]]+(.*) ]]; then
                    local file="${BASH_REMATCH[1]}"
                    _debug_log "Getting content for new file: $file"
                    if [[ -n "$file" && -f "$file" ]]; then
                        new_diff+=$'\n'"New file: $file"$'\n'
                        local file_content=$(git show ":${file}" 2>/dev/null || cat "$file" 2>/dev/null)
                        _debug_log "File content length: ${#file_content}"
                        new_diff+="$file_content"
                    else
                        _debug_log "File not found or empty path: $file"
                    fi
                fi
            done <<< "$new_files"
        fi

        # Debug the current state
        _debug_log "Final diff length: ${#new_diff}"

        if [[ -z "$new_diff" ]]; then
            _debug_log "No staged changes detected"
            typeset -g _CACHED_STAGED_DIFF=""
            return 1
        fi

        _debug_log "Current cached diff: ${_CACHED_STAGED_DIFF:+exists}"
        _debug_log "New diff: ${new_diff:+exists}"

        if [[ "$new_diff" != "$_CACHED_STAGED_DIFF" ]]; then
            typeset -g _CACHED_STAGED_DIFF="$new_diff"
            _debug_log "Updated cached diff: ${_CACHED_STAGED_DIFF:+exists}"
        fi
    fi
}

# Function to generate test suggestions
_generate_commit_suggestions() {
    _debug_log "=== Starting suggestion generation ==="
    _debug_log "Current state: $_SUGGESTION_STATE"
    _debug_log "Current diff cache: ${_CACHED_STAGED_DIFF:+exists}"

    if [[ -z "$SUGGEST_PROVIDER" ]]; then
        _set_suggestion_state "UNCONFIGURED"
        _debug_log "State change -> UNCONFIGURED (no provider)"
        return 1
    fi

    # Validate provider-specific configuration
    case $SUGGEST_PROVIDER in
        "openai"|"anthropic")
            if [[ -z "$SUGGEST_LLM_TOKEN" ]]; then
                _set_suggestion_state "ERROR" "No API token configured for $SUGGEST_PROVIDER"
                _debug_log "State change -> ERROR (no token)"
                return 1
            fi
            ;;
        "local")
            if [[ -z "$SUGGEST_LLM_PATH" ]]; then
                _set_suggestion_state "ERROR" "No model path configured"
                _debug_log "State change -> ERROR (no path)"
                return 1
            fi
            ;;
    esac

    _debug_log "Diff content length: ${#_CACHED_STAGED_DIFF}"
    if [[ -n "$_CACHED_STAGED_DIFF" ]]; then
        _debug_log "Diff preview: $(echo "$_CACHED_STAGED_DIFF" | head -n 1)"
    fi

    if [[ -z "$_CACHED_STAGED_DIFF" ]]; then
        _set_suggestion_state "ERROR" "No staged changes detected"
        _debug_log "State change -> ERROR (no diff)"
        return 1
    fi

    _set_suggestion_state "LOADING"
    _debug_log "Calling LLM provider"

    local suggestion
    suggestion=$(_llm_generate_suggestion "$_CACHED_STAGED_DIFF")
    local result=$?

    if [[ $result -ne 0 || -z "$suggestion" ]]; then
        _set_suggestion_state "ERROR" "Failed to generate suggestion"
        _debug_log "LLM generation failed"
        _debug_log "State immediately after error: $_SUGGESTION_STATE"
        return 1
    fi

    # Only set READY state after successful generation
    _set_suggestion_state "READY"
    _debug_log "Successfully generated suggestion"

    cat << EOF

Suggested commit message:
$suggestion
EOF
}

# Hook function to run after git commands
_git_command_hook() {
    local cmd="$1"
    _debug_log "Command received: $cmd"  # Log the exact command

    # Debug pattern matching
    if [[ "$cmd" =~ ^git[[:space:]]+ ]]; then
        _debug_log "Git command detected: $cmd"
    fi
    if [[ "$cmd" =~ ^ga[[:space:]]+ ]]; then
        _debug_log "Ga alias detected: $cmd"
    fi

    # More explicit pattern matching for git add commands
    if [[ "$cmd" =~ ^(git[[:space:]]+add|ga|git[[:space:]]+reset)[[:space:]]+ || "$cmd" =~ git[[:space:]]+add.*[[:space:]]+ ]]; then
        _debug_log "Git add command detected: $cmd"
        typeset -g _LAST_GIT_COMMAND="$cmd"
    fi
}

# Function to run after command completion
_post_git_command() {
    if [[ -n "$_LAST_GIT_COMMAND" ]]; then
        _debug_log "Processing completed git command: $_LAST_GIT_COMMAND"

        # Debug git status
        local git_status=$(git status --porcelain)
        _debug_log "Git status after command: $git_status"

        _debug_log "Running diff update"
        _update_staged_diff
        _debug_log "After update - Diff cached: ${_CACHED_STAGED_DIFF:+yes}"

        # Clear the last command
        typeset -g _LAST_GIT_COMMAND=""
    fi
}

# Add both hooks
autoload -U add-zsh-hook
add-zsh-hook preexec _git_command_hook
add-zsh-hook precmd _post_git_command

# Function to show suggestion
_show_suggestion() {
    print -P ""  # New line
    _debug_log "Current state when showing suggestion: $_SUGGESTION_STATE"
    case $_SUGGESTION_STATE in
        "UNCONFIGURED")
            print -P "%F{yellow}⚠ LLM not configured. Run %F{green}git-suggest-config%f%F{yellow} to set up.%f"
            ;;
        "LOADING")
            print -P "%F{blue}⟳ Generating commit suggestion...%f"
            ;;
        "ERROR")
            print -P "%F{red}✖ Error generating suggestion: $_SUGGESTION_ERROR%f"
            ;;
        "READY")
            if [[ -n "$1" ]]; then
                print -P "%F{8}$1%f"
            else
                print -P "%F{yellow}No suggestion available%f"
            fi
            ;;
    esac
}

# Format the complete message for acceptance
_format_complete_message() {
    echo "$_COMMIT_SUGGESTION" | awk '
        BEGIN { first = 1 }
        /^Suggested commit message:/ { next }
        /^$/ { if (!first) printf "\n"; next }
        /^feat/ { first = 0; printf "%s", $0; next }
        /^-/ { printf "\n%s", $0; next }
        { print $0 }
    ' | sed '/^$/d'
}

# Add at the top with other global variables
typeset -g _ORIGINAL_TAB_BINDING=""
typeset -g _TAB_BINDING_CHANGED=0

# Function to restore binding
_restore_tab_binding() {
    if [[ $_TAB_BINDING_CHANGED -eq 1 ]]; then
        bindkey '^I' complete-word
        _TAB_BINDING_CHANGED=0
        _debug_log "Restored original Tab binding"
    fi
}

# Add SIGINT trap
_handle_interrupt() {
    _restore_tab_binding
    # Restore original SIGINT behavior
    trap - INT
    # Send SIGINT to the current process
    kill -INT $$
}

# Set up the trap
trap '_handle_interrupt' INT

# Update the quote handler
_git_commit_quote_handler() {
    # Insert the quote first
    zle self-insert

    local current_buffer="$BUFFER"
    _debug_log "Buffer after quote: '$current_buffer'"

    # Check for git commit command
    if [[ "$current_buffer" =~ "(git commit|gc) -m \"$" ]]; then
        _debug_log "✓ Git commit command detected"

        if [[ $_TAB_BINDING_CHANGED -eq 0 ]]; then
            _ORIGINAL_TAB_BINDING=$(bindkey '^I')
            bindkey '^I' accept-suggestion
            _TAB_BINDING_CHANGED=1
            _debug_log "Temporarily bound Tab to accept-suggestion for git commit"
        fi

        _debug_log "State before generating suggestion: $_SUGGESTION_STATE"

        # Run in current shell to preserve state
        _generate_commit_suggestions > >(read -r suggestion; typeset -g _COMMIT_SUGGESTION="$suggestion")

        _debug_log "State after generating suggestion: $_SUGGESTION_STATE"
        _show_suggestion "$_COMMIT_SUGGESTION"

        # Force display update
        zle reset-prompt
    fi
}

# Add the preexec hook
add-zsh-hook preexec _restore_tab_binding

# Accept suggestion function
_accept_suggestion() {
    if [[ -n "$_COMMIT_SUGGESTION" ]]; then
        # Get the complete formatted message
        local formatted_message
        formatted_message=$(_format_complete_message)

        # Update buffer with full message
        BUFFER="${BUFFER}${formatted_message}"
        CURSOR=${#BUFFER}
        zle reset-prompt
    fi
}

# Create and bind the widgets
zle -N self-insert-quote _git_commit_quote_handler
zle -N accept-suggestion _accept_suggestion

# Bind keys
bindkey '"' self-insert-quote
bindkey '^I' accept-suggestion     # Tab key
bindkey '^[[C' accept-suggestion   # Right arrow

_debug_log "Git commit suggestion system loaded at $(date)"

# Configuration management functions
_load_config() {
    _debug_log "=== Loading configuration ==="
    if [[ -f "$_CONFIG_FILE" ]]; then
        # Source the config file to load variables
        source "$_CONFIG_FILE"
        _debug_log "Loaded config - Provider: $SUGGEST_PROVIDER, Token: ${SUGGEST_LLM_TOKEN:+set}"

        # Set initial state based on configuration
        if [[ -n "$SUGGEST_PROVIDER" && -n "$SUGGEST_LLM_TOKEN" ]]; then
            _set_suggestion_state "READY"
            _debug_log "Initial state set to READY (config valid)"
        else
            _set_suggestion_state "UNCONFIGURED"
            _debug_log "Initial state set to UNCONFIGURED (missing config)"
        fi
        return 0
    fi
    _set_suggestion_state "UNCONFIGURED"
    _debug_log "No configuration file found at $_CONFIG_FILE"
    return 1
}

# Function to save configuration
_save_config() {
    local provider="$1"
    local token="$2"
    local model_path="$3"

    # Restore PATH before running commands
    PATH="$_ORIGINAL_PATH"

    # Convert relative path to absolute path for local LLM
    if [[ "$provider" == "local" && -n "$model_path" ]]; then
        # Get absolute path
        model_path="$(cd "$(dirname "$model_path")" && pwd)/$(basename "$model_path")"
        _debug_log "Converted path to absolute: $model_path"
    fi

    # Create config content
    cat > "$_CONFIG_FILE" << EOF
# Git Commit Suggestions Configuration
# Generated on $(date)

SUGGEST_PROVIDER="$provider"
EOF

    # Add appropriate configuration based on provider
    case $provider in
        "openai"|"anthropic")
            echo "SUGGEST_LLM_TOKEN=\"$token\"" >> "$_CONFIG_FILE"
            ;;
        "local")
            echo "SUGGEST_LLM_PATH=\"$model_path\"" >> "$_CONFIG_FILE"
            ;;
    esac

    chmod 600 "$_CONFIG_FILE"  # Secure the file since it contains tokens
    _debug_log "Configuration saved to $_CONFIG_FILE"
}

# Update the configuration function
_git_suggest_config() {
    # Restore PATH at the start of the function
    PATH="$_ORIGINAL_PATH"

    echo "Git Commit Suggestions Configuration"
    echo "-----------------------------------"
    echo "1. OpenAI API"
    echo "2. Anthropic API"
    echo "3. Local LLM"
    echo "4. View current configuration"
    echo "5. Clear configuration"
    read "choice?Select option (1-5): "

    case $choice in
        1)
            read "token?Enter OpenAI API token: "
            _save_config "openai" "$token"
            ;;
        2)
            read "token?Enter Anthropic API token: "
            _save_config "anthropic" "$token"
            ;;
        3)
            read "path?Enter path to local LLM: "
            if [[ ! -f "$path" ]]; then
                echo "Warning: File does not exist at $path"
                read "continue?Continue anyway? (y/n): "
                [[ "$continue" != "y" ]] && return 1
            fi
            _save_config "local" "" "$path"
            ;;
        4)
            if [[ -f "$_CONFIG_FILE" ]]; then
                echo "\nCurrent configuration:"
                cat "$_CONFIG_FILE"
            else
                echo "\nNo configuration found."
            fi
            return 0
            ;;
        5)
            if [[ -f "$_CONFIG_FILE" ]]; then
                rm "$_CONFIG_FILE"
                # Clear environment variables
                unset SUGGEST_PROVIDER
                unset SUGGEST_LLM_TOKEN
                unset SUGGEST_LLM_PATH
                # Reset state
                _set_suggestion_state "UNCONFIGURED"
                echo "Configuration cleared."
                _debug_log "Configuration cleared and state reset to UNCONFIGURED"
            else
                echo "No configuration to clear."
            fi
            return 0
            ;;
        *)
            echo "Invalid option"
            return 1
            ;;
    esac

    echo "\nConfiguration saved!"
    _load_config  # Reload the configuration
}

# Load configuration on plugin start
_load_config

# Add configuration command (add at end of file)
alias git-suggest-config='_git_suggest_config'

# Add cleanup on plugin unload if possible
_cleanup_bindings() {
    _restore_tab_binding
}

# LLM Provider Interface
_llm_generate_suggestion() {
    local provider="$SUGGEST_PROVIDER"
    local diff="$1"

    case "$provider" in
        "openai")
            _openai_generate "$diff"
            ;;
        "anthropic")
            _anthropic_generate "$diff"
            ;;
        "local")
            _local_generate "$diff"
            ;;
        *)
            _debug_log "Unknown provider: $provider"
            _set_suggestion_state "ERROR" "Unknown provider: $provider"
            _debug_log "State change -> ERROR (unknown provider)"
            return 1
            ;;
    esac
}

# OpenAI Provider Implementation
_openai_generate() {
    local diff="$1"
    _debug_log "Generating suggestion using OpenAI"

    # Will implement the actual OpenAI call here
    return 1
}

# Anthropic Provider Implementation
_anthropic_generate() {
    local diff="$1"
    _debug_log "Generating suggestion using Anthropic"

    # Will implement the actual Anthropic call here
    return 1
}

# Local LLM Provider Implementation
_local_generate() {
    local diff="$1"
    _debug_log "Generating suggestion using Local LLM"

    # Will implement the actual local LLM call here
    return 1
}

