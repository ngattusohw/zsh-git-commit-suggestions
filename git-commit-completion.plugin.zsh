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
                if [[ "$line" =~ ^A[[:space:]]+(.+)$ ]]; then
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

    # Return just the suggestion without formatting
    echo "$suggestion"
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

        # If we have staged changes, start generating a suggestion in the background
        if [[ -n "$_CACHED_STAGED_DIFF" ]]; then
            _debug_log "Starting background suggestion generation after git add"

            # Clear existing suggestion when starting new generation
            # TODO: We might not have to do this since global vars are not a thing
            typeset -g _COMMIT_SUGGESTION=""
            _set_suggestion_state "LOADING"

            local parent_pid=$$
            _debug_log "Parent PID: $parent_pid"
            # Create temporary files
            local tmp_file="/tmp/git-suggestion-temp-diff-${parent_pid}"
            local suggestion_state_file="/tmp/git-suggestion-state-${parent_pid}"
            local suggestion_file="/tmp/git-suggestion-${parent_pid}"
            local plugin_path="${0:A}"
            echo "$_CACHED_STAGED_DIFF" > "$tmp_file"

            # Use a helper function to safely background the process
            _run_background_suggestion "$tmp_file" "$suggestion_file" "$suggestion_state_file" "$plugin_path"
        fi

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
    _debug_log "Current suggestion: ${_COMMIT_SUGGESTION:+exists}"

    case $_SUGGESTION_STATE in
        "UNCONFIGURED")
            if [[ -n "$SUGGEST_LLM_TOKEN" ]]; then
                print -P "%F{yellow}⚠ Configuration detected in environment but no provider set. Run %F{green}git-suggest-config%f%F{yellow} to complete setup.%f"
            else
                print -P "%F{yellow}⚠ LLM not configured. Run %F{green}git-suggest-config%f%F{yellow} to set up.%f"
            fi
            ;;
        "LOADING")
            print -P "%F{blue}⟳ Generating commit suggestion... (Press Tab to check if ready)%f"
            ;;
        "ERROR")
            print -P "%F{red}✖ Error generating suggestion: $_SUGGESTION_ERROR%f"
            ;;
        "READY")
            if [[ -n "$_COMMIT_SUGGESTION" ]]; then
                print -P "%F{green}Suggested commit message:%f\n$_COMMIT_SUGGESTION"
                rm -f "/tmp/git-suggestion-state-${$}"
                rm -f "/tmp/git-suggestion-${$}"
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


        # Check for any completed background job (success or error)
        local suggestion_file="/tmp/git-suggestion-${$}"
        local state_file="/tmp/git-suggestion-state-${$}"
        local error_file="${suggestion_file%.tmp}.error"

        if [[ -f "$state_file" ]]; then
            local bg_state=$(cat "$state_file")
            if [[ "$bg_state" == "READY" && -f "$suggestion_file" ]]; then
                _debug_log "Existing suggestion found"
                _COMMIT_SUGGESTION=$(cat "$suggestion_file")
                _set_suggestion_state "READY"
                rm -f "$suggestion_file" "$state_file" "$error_file"
                _debug_log "Loaded and cleaned up suggestion files"
            elif [[ "$bg_state" == "ERROR" ]]; then
                local error_msg="Failed to generate suggestion"
                if [[ -f "$error_file" ]]; then
                    error_msg=$(cat "$error_file")
                fi
                _set_suggestion_state "ERROR" "$error_msg"
                rm -f "$suggestion_file" "$state_file" "$error_file"
                _debug_log "Loaded error state: $error_msg"
            fi
        fi

         # Use existing suggestion if available
        if [[ "$_SUGGESTION_STATE" == "READY" && -n "$_COMMIT_SUGGESTION" ]]; then
            _debug_log "Using existing suggestion"
            _show_suggestion
        else
            _debug_log "No cached suggestion available"
            _show_suggestion
        fi


        # # Get and show suggestion
        # _COMMIT_SUGGESTION=$(_generate_commit_suggestions)
        # _show_suggestion "$_COMMIT_SUGGESTION"


        # Run in current shell to preserve state
        # _generate_commit_suggestions > >(read -r suggestion; typeset -g _COMMIT_SUGGESTION="$suggestion")

        # # If we don't have a suggestion yet, generate one
        # if [[ "$_SUGGESTION_STATE" != "READY" ]]; then
        #     _debug_log "No suggestion ready, generating one now"
        #     _set_suggestion_state "LOADING"
        #     _show_suggestion

        #     # Generate the suggestion
        #     _generate_commit_suggestions
        # else
        #     _debug_log "Suggestion already available"
        #     _show_suggestion
        # fi

        # Force display update
        zle reset-prompt
    fi
}

# Add the preexec hook
add-zsh-hook preexec _restore_tab_binding

# Accept suggestion function
_accept_suggestion() {
    # Check for completed background job if in LOADING state
    if [[ "$_SUGGESTION_STATE" == "LOADING" ]]; then
        local suggestion_file="/tmp/git-suggestion-${$}"
        local state_file="/tmp/git-suggestion-state-${$}"
        local error_file="${suggestion_file%.tmp}.error"

        if [[ -f "$state_file" ]]; then
            local bg_state=$(cat "$state_file")
            if [[ "$bg_state" == "READY" && -f "$suggestion_file" ]]; then
                _COMMIT_SUGGESTION=$(cat "$suggestion_file")
                _set_suggestion_state "READY"
                rm -f "$suggestion_file" "$state_file" "$error_file"
                _debug_log "Loaded completed suggestion from background job"
            elif [[ "$bg_state" == "ERROR" ]]; then
                local error_msg="Failed to generate suggestion"
                if [[ -f "$error_file" ]]; then
                    error_msg=$(cat "$error_file")
                fi
                _set_suggestion_state "ERROR" "$error_msg"
                rm -f "$suggestion_file" "$state_file" "$error_file"
                _debug_log "Loaded error state from background job: $error_msg"
            fi
        fi
    fi

    if [[ -n "$_COMMIT_SUGGESTION" && "$_SUGGESTION_STATE" == "READY" ]]; then
        # Get the complete formatted message
        local formatted_message
        formatted_message=$(_format_complete_message)

        # Update buffer with full message
        BUFFER="${BUFFER}${formatted_message}"
        CURSOR=${#BUFFER}
        zle reset-prompt
    elif [[ "$_SUGGESTION_STATE" == "LOADING" ]]; then
        print -P "%F{blue}⟳ Still generating... Press Tab again to check.%f"
        zle reset-prompt
    elif [[ "$_SUGGESTION_STATE" == "ERROR" ]]; then
        print -P "%F{red}✖ Error: $_SUGGESTION_ERROR%f"
        if [[ "$_SUGGESTION_ERROR" == *"API key"* || "$_SUGGESTION_ERROR" == *"token"* ]]; then
            print -P "%F{yellow}Run %F{green}git-suggest-config%f%F{yellow} to fix your API configuration.%f"
        elif [[ "$_SUGGESTION_ERROR" == *"No staged changes"* ]]; then
            print -P "%F{yellow}Stage some changes with %F{green}git add%f%F{yellow} first.%f"
        else
            print -P "%F{yellow}Run %F{green}git-suggest-config%f%F{yellow} to check your configuration.%f"
        fi
        zle reset-prompt
    elif [[ "$_SUGGESTION_STATE" == "UNCONFIGURED" ]]; then
        if [[ -n "$SUGGEST_LLM_TOKEN" ]]; then
            print -P "%F{yellow}⚠ Token found in environment but no provider configured.%f"
            print -P "%F{yellow}Run %F{green}git-suggest-config%f%F{yellow} to complete setup, or set SUGGEST_PROVIDER env var.%f"
        else
            print -P "%F{yellow}⚠ LLM not configured. Run %F{green}git-suggest-config%f%F{yellow} to set up.%f"
        fi
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
            echo "\nCurrent configuration:"
            echo "======================"

            local config_found=false

            # Check file-based configuration
            if [[ -f "$_CONFIG_FILE" ]]; then
                echo "\n📁 File-based configuration ($_CONFIG_FILE):"
                cat "$_CONFIG_FILE"
                config_found=true
            else
                echo "\n📁 File-based configuration: None found"
            fi

            # Check environment-based configuration
            echo "\n🌍 Environment-based configuration:"
            if [[ -n "$SUGGEST_PROVIDER" ]]; then
                echo "  SUGGEST_PROVIDER: $SUGGEST_PROVIDER"
                config_found=true
            else
                echo "  SUGGEST_PROVIDER: Not set"
            fi

            if [[ -n "$SUGGEST_LLM_TOKEN" ]]; then
                local token_preview="${SUGGEST_LLM_TOKEN:0:8}...${SUGGEST_LLM_TOKEN: -4}"
                echo "  SUGGEST_LLM_TOKEN: $token_preview (${#SUGGEST_LLM_TOKEN} chars)"
                config_found=true
            else
                echo "  SUGGEST_LLM_TOKEN: Not set"
            fi

            if [[ -n "$SUGGEST_LLM_PATH" ]]; then
                echo "  SUGGEST_LLM_PATH: $SUGGEST_LLM_PATH"
                config_found=true
            else
                echo "  SUGGEST_LLM_PATH: Not set"
            fi

            # Show effective configuration status
            echo "\n🎯 Effective status:"
            if [[ -n "$SUGGEST_PROVIDER" || -n "$SUGGEST_LLM_TOKEN" ]]; then
                if [[ -n "$SUGGEST_LLM_TOKEN" ]]; then
                    echo "  ✅ Ready to generate suggestions (using environment token)"
                elif [[ -n "$SUGGEST_PROVIDER" && -f "$_CONFIG_FILE" ]]; then
                    # Reload config to check file-based token
                    source "$_CONFIG_FILE"
                    if [[ -n "$SUGGEST_LLM_TOKEN" ]]; then
                        echo "  ✅ Ready to generate suggestions (using file-based config)"
                    else
                        echo "  ⚠️  Provider set but no token available"
                    fi
                else
                    echo "  ⚠️  Provider set but no token available"
                fi
            else
                echo "  ❌ Not configured - run git-suggest-config to set up"
            fi

            if ! $config_found; then
                echo "\n💡 No configuration found anywhere."
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

    # Ensure we have required variables
    if [[ -z "$SUGGEST_LLM_TOKEN" ]]; then
        _debug_log "OpenAI token not found"
        return 1
    fi

    # Test with minimal request first
    local test_request='{"model":"gpt-3.5-turbo","messages":[{"role":"system","content":"test"},{"role":"user","content":"test"}]}'

    local test_response
    test_response=$(curl -s -S -H "Content-Type: application/json" \
                        -H "Authorization: Bearer $SUGGEST_LLM_TOKEN" \
                        -d "$test_request" \
                        "https://api.openai.com/v1/chat/completions" 2>&1)

    _debug_log "Test response: $test_response"

    if [[ "$test_response" == *"error"* ]]; then
        _debug_log "Test request failed"
        return 1
    fi

    # If test passed, proceed with real request
    # Create a clean version of the diff for JSON
    local escaped_diff
    escaped_diff=$(echo "$diff" | LC_ALL=C sed '
        s/[^[:print:]\n]//g
        s/\\/\\\\/g
        s/"/\\"/g
        s/$/\\n/g
    ' | tr -d '\r')

    # Debug the escaped content
    _debug_log "First line of escaped diff: $(echo "$escaped_diff" | head -n1)"

    # Create temporary file for JSON request
    local tmp_json
    tmp_json=$(mktemp)
    #test

    # Write JSON to temp file
    cat > "$tmp_json" << EOF
{
    "model": "gpt-3.5-turbo",
    "messages": [
        {
            "role": "system",
            "content": "Generate concise, single-line git commit messages from diffs. Use conventional commit format (feat/fix/chore/etc) with an emoji. Keep under 72 characters. Focus on the main purpose, not implementation details. Examples: 'feat: ✨ add user authentication', 'fix: 🐛 resolve login timeout', 'chore: 🔧 update dependencies'. No backticks or special quotes."
        },
        {
            "role": "user",
            "content": "Generate a commit message for this diff:\n\n${escaped_diff}"
        }
    ]
}
EOF

    _debug_log "Request JSON file created: $tmp_json"
    _debug_log "First 100 chars of request: $(head -c 100 "$tmp_json")"

    # Make the API call using the file
    local response
    local http_response
    http_response=$(curl -s -S -i -H "Content-Type: application/json" \
                        -H "Authorization: Bearer $SUGGEST_LLM_TOKEN" \
                        -d "@$tmp_json" \
                        "https://api.openai.com/v1/chat/completions" 2>&1)

    # Clean up temp file
    rm -f "$tmp_json"

    local result=$?
    local http_code=$(echo "$http_response" | grep -i "^HTTP" | tail -n1 | awk '{print $2}')
    response=$(echo "$http_response" | awk 'BEGIN{RS="\r\n\r\n"} NR==2')

    _debug_log "OpenAI API call result: $result"
    _debug_log "HTTP Status: $http_code"
    _debug_log "Response: $response"

    if [[ $result -ne 0 || $http_code -ne 200 ]]; then
        # Try to extract error message from response
        local error_message
        error_message=$(echo "$response" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
        if [[ -n "$error_message" ]]; then
            _debug_log "OpenAI API error: $error_message"
        fi
        _debug_log "OpenAI API call failed"
        return 1
    fi

    #Added comments for demo

    #Hi my name is jake

    # Extract message using more reliable pattern
    local message
    message=$(echo "$response" | grep -o '"content": *"[^"]*"' | cut -d'"' -f4)

    if [[ -z "$message" ]]; then
        _debug_log "Failed to extract message from response"
        _debug_log "Response was: $response"
        return 1
    fi

    if [[ "$message" == "ERROR: NO_CHANGES" ]]; then
        _debug_log "LLM reported no changes"
        return 1
    fi

    _debug_log "Successfully extracted message: $message"
    typeset -g _COMMIT_SUGGESTION="$message"  # Store in global variable
    echo "$message"
    return 0
}

# Anthropic Provider Implementation
_anthropic_generate() {
    local diff="$1"
    _debug_log "Generating suggestion using Anthropic"

    # Ensure we have required variables
    if [[ -z "$SUGGEST_LLM_TOKEN" ]]; then
        _debug_log "Anthropic token not found"
        return 1
    fi

    # Test with minimal request first
    local test_request='{"model":"claude-3-haiku-20240307","max_tokens":10,"messages":[{"role":"user","content":"test"}]}'

    local test_response
    test_response=$(curl -s -S -H "Content-Type: application/json" \
                        -H "x-api-key: $SUGGEST_LLM_TOKEN" \
                        -H "anthropic-version: 2023-06-01" \
                        -d "$test_request" \
                        "https://api.anthropic.com/v1/messages" 2>&1)

    _debug_log "Test response: $test_response"

    if [[ "$test_response" == *"error"* ]]; then
        _debug_log "Test request failed"
        return 1
    fi

    # If test passed, proceed with real request
    # Create a clean version of the diff for JSON
    local escaped_diff
    escaped_diff=$(echo "$diff" | LC_ALL=C sed '
        s/[^[:print:]\n]//g
        s/\\/\\\\/g
        s/"/\\"/g
        s/$/\\n/g
    ' | tr -d '\r')

    # Debug the escaped content
    _debug_log "First line of escaped diff: $(echo "$escaped_diff" | head -n1)"

    # Create temporary file for JSON request
    local tmp_json
    tmp_json=$(mktemp)

    # Write JSON to temp file - Anthropic format
    cat > "$tmp_json" << EOF
{
    "model": "claude-3-haiku-20240307",
    "max_tokens": 200,
    "messages": [
        {
            "role": "user",
            "content": "Generate a concise, single-line git commit message from this diff. Use conventional commit format (feat/fix/chore/etc) with an emoji. Keep it under 72 characters. Focus on the main purpose, not implementation details. Examples: 'feat: ✨ add user authentication', 'fix: 🐛 resolve login timeout', 'chore: 🔧 update dependencies'. No backticks or special quotes.\n\nDiff:\n${escaped_diff}"
        }
    ]
}
EOF

    _debug_log "Request JSON file created: $tmp_json"
    _debug_log "First 100 chars of request: $(head -c 100 "$tmp_json")"

    # Make the API call using the file
    local response
    local http_response
    http_response=$(curl -s -S -i -H "Content-Type: application/json" \
                        -H "x-api-key: $SUGGEST_LLM_TOKEN" \
                        -H "anthropic-version: 2023-06-01" \
                        -d "@$tmp_json" \
                        "https://api.anthropic.com/v1/messages" 2>&1)

    # Clean up temp file
    rm -f "$tmp_json"

    local result=$?
    local http_code=$(echo "$http_response" | grep -i "^HTTP" | tail -n1 | awk '{print $2}')
    response=$(echo "$http_response" | awk 'BEGIN{RS="\r\n\r\n"} NR==2')

    _debug_log "Anthropic API call result: $result"
    _debug_log "HTTP Status: $http_code"
    _debug_log "Response: $response"

    if [[ $result -ne 0 || $http_code -ne 200 ]]; then
        # Try to extract error message from response
        local error_message
        error_message=$(echo "$response" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
        if [[ -n "$error_message" ]]; then
            _debug_log "Anthropic API error: $error_message"
        fi
        _debug_log "Anthropic API call failed"
        return 1
    fi

    # Extract message from Anthropic response format
    local message
    # Anthropic response format: {"content":[{"type":"text","text":"MESSAGE"}]}

    _debug_log "Raw response length: ${#response}"
    _debug_log "Response starts with: $(echo "$response" | head -c 100)"
    _debug_log "Response ends with: $(echo "$response" | tail -c 50)"

    # Remove any non-printable characters that might cause issues
    local clean_response=$(echo "$response" | tr -cd '[:print:]\n')
    _debug_log "Cleaned response length: ${#clean_response}"

    # Try manual parsing first (more reliable for our use case)
    message=$(echo "$clean_response" | sed 's/.*"text":"//; s/"}].*//')
    _debug_log "Manual extraction result: '$message'"

    # If manual parsing failed and jq is available, try jq as fallback
    if [[ -z "$message" && -n "$(command -v jq)" ]]; then
        _debug_log "Manual parsing failed, trying jq"
        message=$(echo "$clean_response" | jq -r '.content[0].text' 2>/dev/null)
        _debug_log "jq extraction result: '$message'"
    fi

    # Handle escaped newlines and convert emojis
    if [[ -n "$message" ]]; then
        message=$(echo "$message" | sed 's/\\n/\n/g')
        message=$(echo "$message" | sed 's/:sparkles:/✨/g; s/:rocket:/🚀/g; s/:bug:/🐛/g; s/:wrench:/🔧/g; s/:zap:/⚡/g')
        _debug_log "Final processed message: '$message'"
    else
        _debug_log "All extraction methods failed - empty result"
    fi

    if [[ -z "$message" ]]; then
        _debug_log "Failed to extract message from response"
        _debug_log "Response was: $response"
        return 1
    fi

    if [[ "$message" == "ERROR: NO_CHANGES" ]]; then
        _debug_log "LLM reported no changes"
        return 1
    fi

    _debug_log "Successfully extracted message: $message"
    typeset -g _COMMIT_SUGGESTION="$message"  # Store in global variable
    echo "$message"
    return 0
}

# Local LLM Provider Implementation
_local_generate() {
    local diff="$1"
    _debug_log "Generating suggestion using Local LLM"

    # Will implement the actual local LLM call here
    return 1
}

# Helper function for safe background processing
_run_background_suggestion() {
    local tmp_file="$1"
    local suggestion_file="$2"
    local suggestion_state_file="$3"
    local plugin_path="$4"

    # Pass current config to background process via environment
    local bg_provider="$SUGGEST_PROVIDER"
    local bg_token="$SUGGEST_LLM_TOKEN"
    local bg_path="$SUGGEST_LLM_PATH"

    # Validate inputs before starting background process
    [[ -z "$tmp_file" || -z "$suggestion_file" || -z "$suggestion_state_file" ]] && return 1
    [[ ! -f "$tmp_file" ]] && return 1

    # Use a simpler background approach with complete output suppression and error handling
    {
        # Log start of background process
        echo "[$(date '+%H:%M:%S')] Background process started" >> /tmp/git-completion-debug.log 2>/dev/null

        # Ensure we have access to required resources
        [[ -w "/tmp" ]] || { echo "[$(date '+%H:%M:%S')] No write access to /tmp" >> /tmp/git-completion-debug.log 2>/dev/null; exit 1; }
        [[ -r "$tmp_file" ]] || { echo "[$(date '+%H:%M:%S')] Cannot read input file: $tmp_file" >> /tmp/git-completion-debug.log 2>/dev/null; exit 1; }

        # Set config for background process
        export SUGGEST_PROVIDER="$bg_provider"
        export SUGGEST_LLM_TOKEN="$bg_token"
        export SUGGEST_LLM_PATH="$bg_path"

        echo "[$(date '+%H:%M:%S')] Config set: provider=$SUGGEST_PROVIDER" >> /tmp/git-completion-debug.log 2>/dev/null

        # Restore PATH for external commands
        PATH="$_ORIGINAL_PATH"

        # Read the diff directly instead of re-sourcing
        local diff_content=$(cat "$tmp_file")
        echo "[$(date '+%H:%M:%S')] About to generate suggestion, diff length: ${#diff_content}" >> /tmp/git-completion-debug.log 2>/dev/null

        # Call the LLM provider directly based on the provider type
        local suggestion=""
        case "$SUGGEST_PROVIDER" in
            "anthropic")
                # Anthropic API call
                local escaped_diff=$(echo "$diff_content" | LC_ALL=C sed 's/[^[:print:]\n]//g; s/\\/\\\\/g; s/"/\\"/g' | tr -d '\r' | tr '\n' ' ')
                local tmp_json=$(mktemp)

                # Construct JSON properly without placeholders
                cat > "$tmp_json" << EOF
{
    "model": "claude-3-haiku-20240307",
    "max_tokens": 200,
    "messages": [
        {
            "role": "user",
            "content": "Generate a concise, single-line git commit message from this diff. Use conventional commit format (feat/fix/chore/etc) with an emoji. Keep it under 72 characters. Focus on the main purpose, not implementation details. Examples: 'feat: ✨ add user authentication', 'fix: 🐛 resolve login timeout', 'chore: 🔧 update dependencies'. No backticks or special quotes.\\n\\nDiff:\\n${escaped_diff}"
        }
    ]
}
EOF

                local response=$(curl -s -H "Content-Type: application/json" \
                    -H "x-api-key: $SUGGEST_LLM_TOKEN" \
                    -H "anthropic-version: 2023-06-01" \
                    -d "@$tmp_json" \
                    "https://api.anthropic.com/v1/messages")

                # Extract suggestion using the same method as the main function
                suggestion=$(echo "$response" | sed 's/.*"text":"//; s/"}].*//' | sed 's/\\n/\n/g; s/:sparkles:/✨/g; s/:rocket:/🚀/g; s/:bug:/🐛/g; s/:wrench:/🔧/g; s/:zap:/⚡/g')
                rm -f "$tmp_json"
                ;;
            *)
                echo "[$(date '+%H:%M:%S')] Unsupported provider: $SUGGEST_PROVIDER" >> /tmp/git-completion-debug.log 2>/dev/null
                ;;
        esac

        local gen_result=$?
        echo "[$(date '+%H:%M:%S')] Generation result: $gen_result, suggestion length: ${#suggestion}" >> /tmp/git-completion-debug.log 2>/dev/null

        if [[ -n "$suggestion" ]]; then
            echo "[$(date '+%H:%M:%S')] We have a suggestion from the background process: $suggestion" >> /tmp/git-completion-debug.log 2>/dev/null
            # Clean up the suggestion text - remove any extra formatting
            suggestion=$(echo "$suggestion" | sed '/^$/d')
            echo "$suggestion" > "$suggestion_file" 2>/dev/null
            echo "READY" > "$suggestion_state_file" 2>/dev/null
            echo "[$(date '+%H:%M:%S')] Files written successfully" >> /tmp/git-completion-debug.log 2>/dev/null
        else
            # Write error state if generation failed
            echo "[$(date '+%H:%M:%S')] Background generation failed, writing error state" >> /tmp/git-completion-debug.log 2>/dev/null
            echo "ERROR" > "$suggestion_state_file" 2>/dev/null
            echo "${_SUGGESTION_ERROR:-Failed to generate suggestion}" > "${suggestion_file%.tmp}.error" 2>/dev/null
        fi
        rm -f "$tmp_file" 2>/dev/null
        echo "[$(date '+%H:%M:%S')] Background process completed" >> /tmp/git-completion-debug.log 2>/dev/null
    } </dev/null >/dev/null 2>&1 &!
}

