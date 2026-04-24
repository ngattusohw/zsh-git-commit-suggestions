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
        "openai"|"anthropic"|"grok")
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
    _debug_log "Calling LLM provider with smart diff analysis"

    # Use smart diff analysis for large commits
    local processed_diff
    processed_diff=$(_analyze_and_summarize_diff "$_CACHED_STAGED_DIFF")
    _debug_log "Processed diff length: ${#processed_diff}"

    local suggestion
    suggestion=$(_llm_generate_suggestion "$processed_diff")
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
# Note: Tab binding is handled dynamically in _git_commit_quote_handler
# only when in a git commit context, then restored by _restore_tab_binding

_debug_log "Git commit suggestion system loaded at $(date)"

# Configuration management functions with multi-provider support
_load_config() {
    _debug_log "=== Loading multi-provider configuration ==="
    if [[ -f "$_CONFIG_FILE" ]]; then
        # Source the config file to load variables
        source "$_CONFIG_FILE"

        # Use SUGGEST_ACTIVE_PROVIDER if available, fallback to SUGGEST_PROVIDER
        local active_provider="${SUGGEST_ACTIVE_PROVIDER:-$SUGGEST_PROVIDER}"

        # Set the appropriate token based on active provider
        case "$active_provider" in
            "openai")
                [[ -n "$SUGGEST_OPENAI_TOKEN" ]] && export SUGGEST_LLM_TOKEN="$SUGGEST_OPENAI_TOKEN"
                ;;
            "anthropic")
                [[ -n "$SUGGEST_ANTHROPIC_TOKEN" ]] && export SUGGEST_LLM_TOKEN="$SUGGEST_ANTHROPIC_TOKEN"
                ;;
            "grok")
                [[ -n "$SUGGEST_GROK_TOKEN" ]] && export SUGGEST_LLM_TOKEN="$SUGGEST_GROK_TOKEN"
                ;;
            "local")
                # Local LLM uses path instead of token
                [[ -n "$SUGGEST_LOCAL_PATH" ]] && export SUGGEST_LLM_PATH="$SUGGEST_LOCAL_PATH"
                ;;
        esac

        # Ensure SUGGEST_PROVIDER is set for backward compatibility
        [[ -n "$active_provider" ]] && export SUGGEST_PROVIDER="$active_provider"

        _debug_log "Loaded config - Active Provider: $active_provider, Token: ${SUGGEST_LLM_TOKEN:+set}"
        _debug_log "Available providers: OpenAI:${SUGGEST_OPENAI_TOKEN:+✓} Anthropic:${SUGGEST_ANTHROPIC_TOKEN:+✓} Grok:${SUGGEST_GROK_TOKEN:+✓} Local:${SUGGEST_LOCAL_PATH:+✓}"

        # Set initial state based on configuration
        local has_valid_config=false
        case "$active_provider" in
            "openai"|"anthropic"|"grok")
                [[ -n "$SUGGEST_LLM_TOKEN" ]] && has_valid_config=true
                ;;
            "local")
                [[ -n "$SUGGEST_LLM_PATH" ]] && has_valid_config=true
                ;;
        esac

        if $has_valid_config; then
            _set_suggestion_state "READY"
            _debug_log "Initial state set to READY (config valid)"
        else
            _set_suggestion_state "UNCONFIGURED"
            _debug_log "Initial state set to UNCONFIGURED (missing config for active provider)"
        fi
        return 0
    fi
    _set_suggestion_state "UNCONFIGURED"
    _debug_log "No configuration file found at $_CONFIG_FILE"
    return 1
}

# Function to save configuration with multi-provider support
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

    # Load existing configuration to preserve other provider tokens
    local existing_openai=""
    local existing_anthropic=""
    local existing_grok=""
    local existing_local=""

    if [[ -f "$_CONFIG_FILE" ]]; then
        existing_openai=$(grep "SUGGEST_OPENAI_TOKEN=" "$_CONFIG_FILE" 2>/dev/null | cut -d'"' -f2)
        existing_anthropic=$(grep "SUGGEST_ANTHROPIC_TOKEN=" "$_CONFIG_FILE" 2>/dev/null | cut -d'"' -f2)
        existing_grok=$(grep "SUGGEST_GROK_TOKEN=" "$_CONFIG_FILE" 2>/dev/null | cut -d'"' -f2)
        existing_local=$(grep "SUGGEST_LOCAL_PATH=" "$_CONFIG_FILE" 2>/dev/null | cut -d'"' -f2)
    fi

    # Set the new token/path for the specified provider
    case $provider in
        "openai")
            existing_openai="$token"
            ;;
        "anthropic")
            existing_anthropic="$token"
            ;;
        "grok")
            existing_grok="$token"
            ;;
        "local")
            existing_local="$model_path"
            ;;
    esac

    # Create enhanced config content with all providers
    cat > "$_CONFIG_FILE" << EOF
# Git Commit Suggestions Configuration
# Multi-provider support - Generated on $(date)

# Active provider
SUGGEST_ACTIVE_PROVIDER="$provider"

# Legacy variable for backward compatibility
SUGGEST_PROVIDER="$provider"
EOF

    # Add all provider tokens (only if they exist)
    [[ -n "$existing_openai" ]] && echo "SUGGEST_OPENAI_TOKEN=\"$existing_openai\"" >> "$_CONFIG_FILE"
    [[ -n "$existing_anthropic" ]] && echo "SUGGEST_ANTHROPIC_TOKEN=\"$existing_anthropic\"" >> "$_CONFIG_FILE"
    [[ -n "$existing_grok" ]] && echo "SUGGEST_GROK_TOKEN=\"$existing_grok\"" >> "$_CONFIG_FILE"
    [[ -n "$existing_local" ]] && echo "SUGGEST_LOCAL_PATH=\"$existing_local\"" >> "$_CONFIG_FILE"

    # Add legacy token variable for backward compatibility
    case $provider in
        "openai"|"anthropic"|"grok")
            echo "SUGGEST_LLM_TOKEN=\"$token\"" >> "$_CONFIG_FILE"
            ;;
        "local")
            echo "SUGGEST_LLM_PATH=\"$model_path\"" >> "$_CONFIG_FILE"
            ;;
    esac

    chmod 600 "$_CONFIG_FILE"  # Secure the file since it contains tokens
    _debug_log "Multi-provider configuration saved to $_CONFIG_FILE"
}

# Helper function for typewriter text animation
_animate_text() {
    local text="$1"
    local delay="${2:-0.03}"

    for (( i=0; i<${#text}; i++ )); do
        echo -n "${text:$i:1}"
        sleep "$delay"
    done
    echo ""
}

# Enhanced configuration function with improved onboarding
_git_suggest_config() {
    # Restore PATH at the start of the function
    PATH="$_ORIGINAL_PATH"

    # Animated GAT ASCII art header (just the art, not everything)
    echo ""
    echo "    ╔═══════════════════════════════════════════════════════════╗"
    echo "    ║                                                           ║"
    sleep 0.2
    echo "    ║   ████████   █████████  ████████                          ║"
    sleep 0.2
    echo "    ║   ██         ██     ██     ██                             ║"
    sleep 0.2
    echo "    ║   ██  ████   █████████     ██                             ║"
    sleep 0.2
    echo "    ║   ██    ██   ██     ██     ██                             ║"
    sleep 0.2
    echo "    ║   ████████   ██     ██     ██                             ║"
    echo "    ║                                                           ║"
    echo "    ║          🤖 Git AI Tool - Smart Commit Messages           ║"
    echo "    ║                                                           ║"
    echo "    ╚═══════════════════════════════════════════════════════════╝"
    echo ""

    # Dramatic pause before showing the rest
    sleep 0.7

    # Check if this is first-time setup
    local is_first_time=false
    local has_config=false
    if [[ ! -f "$_CONFIG_FILE" && -z "$SUGGEST_PROVIDER" && -z "$SUGGEST_LLM_TOKEN" ]]; then
        is_first_time=true
    else
        has_config=true
    fi

    # Welcome message for first-time users (no animation)
    if $is_first_time; then
        echo "🚀 Welcome to Git Commit Suggestions!"
        echo "====================================="
        echo ""
        echo "This plugin generates AI-powered commit messages based on your staged changes."
        echo "Let's get you set up with an AI provider to start generating suggestions!"
        echo ""
    else
        echo "🔧 Git Commit Suggestions Configuration"
        echo "======================================="
        echo ""
    fi

    # Show current configuration if it exists (no animation)
    if $has_config; then
        echo "📋 Current Configuration:"
        echo "========================"

        # Determine current provider and status
        local current_provider=""
        local current_status=""
        local token_preview=""

        if [[ -n "$SUGGEST_PROVIDER" ]]; then
            current_provider="$SUGGEST_PROVIDER"
        elif [[ -f "$_CONFIG_FILE" ]]; then
            # Load from config file
            local temp_provider=$(grep "SUGGEST_PROVIDER=" "$_CONFIG_FILE" 2>/dev/null | cut -d'"' -f2)
            [[ -n "$temp_provider" ]] && current_provider="$temp_provider"
        fi

        if [[ -n "$SUGGEST_LLM_TOKEN" ]]; then
            token_preview="${SUGGEST_LLM_TOKEN:0:8}...${SUGGEST_LLM_TOKEN: -4}"
            current_status="✅ Active"
        elif [[ -f "$_CONFIG_FILE" ]]; then
            local temp_token=$(grep "SUGGEST_LLM_TOKEN=" "$_CONFIG_FILE" 2>/dev/null | cut -d'"' -f2)
            if [[ -n "$temp_token" ]]; then
                token_preview="${temp_token:0:8}...${temp_token: -4}"
                current_status="✅ Active"
            fi
        fi

        if [[ -n "$current_provider" ]]; then
            case "$current_provider" in
                "openai")
                    echo "  🤖 Provider: OpenAI API (GPT-3.5-turbo)"
                    ;;
                "anthropic")
                    echo "  🧠 Provider: Anthropic API (Claude-3-haiku)"
                    ;;
                "local")
                    echo "  🏠 Provider: Local LLM"
                    ;;
                "grok")
                    echo "  ⚡ Provider: Grok API (xAI)"
                    ;;
                *)
                    echo "  ❓ Provider: $current_provider"
                    ;;
            esac

            if [[ -n "$token_preview" ]]; then
                echo "  🔑 Token: $token_preview"
            fi
            echo "  📊 Status: $current_status"
        else
            echo "  ⚠️  No valid configuration found"
        fi
        echo ""
    fi

    # Auto-detect existing API keys in environment
    local detected_openai=""
    local detected_anthropic=""
    local detected_grok=""
    local has_detections=false

    if [[ -n "$OPENAI_API_KEY" ]]; then
        detected_openai="$OPENAI_API_KEY"
        has_detections=true
    fi

    if [[ -n "$ANTHROPIC_API_KEY" ]]; then
        detected_anthropic="$ANTHROPIC_API_KEY"
        has_detections=true
    fi

    if [[ -n "$GROK_API_KEY" ]]; then
        detected_grok="$GROK_API_KEY"
        has_detections=true
    fi

    # Show auto-detected keys (no animation)
    if $has_detections; then
        echo "🔍 Auto-detected API keys in your environment:"
        [[ -n "$detected_openai" ]] && echo "  ✅ OpenAI API key found (${detected_openai:0:8}...)"
        [[ -n "$detected_anthropic" ]] && echo "  ✅ Anthropic API key found (${detected_anthropic:0:8}...)"
        [[ -n "$detected_grok" ]] && echo "  ✅ Grok API key found (${detected_grok:0:8}...)"
        echo ""
        echo "🚀 QUICK SETUP:"
        echo "0. ⚡ Configure ALL detected providers at once (recommended!)"
        echo ""
    fi

    # Menu with recommendations and current config indicators (no animation)
    echo "Choose your AI provider:"
    echo ""

    # OpenAI option with current config indicator
    echo -n "1. 🤖 OpenAI API (GPT-3.5-turbo)"
    if [[ "$current_provider" == "openai" && "$current_status" == "✅ Active" ]]; then
        echo " 🟢 CURRENTLY ACTIVE"
    else
        echo ""
    fi
    echo "   • Speed: ~2-3 seconds"
    echo "   • Cost: ~\$0.001 per commit"
    echo "   • Quality: Excellent"
    [[ -n "$detected_openai" ]] && echo "   🔍 Auto-detected key available!"
    echo ""

    # Anthropic option with current config indicator
    echo -n "2. 🧠 Anthropic API (Claude-3-haiku)"
    if [[ "$current_provider" == "anthropic" && "$current_status" == "✅ Active" ]]; then
        echo " 🟢 CURRENTLY ACTIVE"
    else
        echo " ⭐ RECOMMENDED"
    fi
    echo "   • Speed: ~1-2 seconds (fastest)"
    echo "   • Cost: ~\$0.0001 per commit (cheapest)"
    echo "   • Quality: Excellent + concise"
    [[ -n "$detected_anthropic" ]] && echo "   🔍 Auto-detected key available!"
    echo ""

    # Grok option with current config indicator
    echo -n "3. ⚡ Grok API (xAI)"
    if [[ "$current_provider" == "grok" && "$current_status" == "✅ Active" ]]; then
        echo " 🟢 CURRENTLY ACTIVE"
    else
        echo " 🆕 NEW!"
    fi
    echo "   • Speed: ~1-3 seconds"
    echo "   • Cost: ~\$0.0005 per commit"
    echo "   • Quality: Excellent + real-time context"
    [[ -n "$detected_grok" ]] && echo "   🔍 Auto-detected key available!"
    echo ""

    # Local LLM option with current config indicator
    echo -n "4. 🏠 Local LLM (coming soon)"
    if [[ "$current_provider" == "local" && "$current_status" == "✅ Active" ]]; then
        echo " 🟢 CURRENTLY ACTIVE"
    else
        echo ""
    fi
    echo "   • Speed: Variable"
    echo "   • Cost: Free (after setup)"
    echo "   • Quality: Depends on model"
    echo ""

    # Show quick switching options for configured providers
    local configured_providers=($(_get_configured_providers))
    if [[ ${#configured_providers[@]} -gt 1 ]]; then
        echo "⚡ Quick Switch (no re-entry needed):"
        local switch_options=()
        for provider in "${configured_providers[@]}"; do
            if [[ "$provider" != "$current_provider" ]]; then
                case "$provider" in
                    "openai") echo "   s1. 🤖 Switch to OpenAI" && switch_options+=("s1:openai") ;;
                    "anthropic") echo "   s2. 🧠 Switch to Anthropic" && switch_options+=("s2:anthropic") ;;
                    "grok") echo "   s3. ⚡ Switch to Grok" && switch_options+=("s3:grok") ;;
                    "local") echo "   s4. 🏠 Switch to Local LLM" && switch_options+=("s4:local") ;;
                esac
            fi
        done
        echo ""
    fi

    echo "5. 📋 View current configuration"
    echo "6. 🗑️  Clear configuration"
    echo ""

    # Coffee support section
    echo "─────────────────────────────────────────────────────────────────"
    echo "☕ Enjoying this plugin? Buy the creator a coffee!"
    echo "   💖 https://buymeacoffee.com/ngattusohw"
    echo "   ⭐ Star the repo: https://github.com/ngattusohw/git-commit-suggestions"
    echo "─────────────────────────────────────────────────────────────────"
    echo ""

        local menu_options="1-6"
    if $has_detections; then
        menu_options="0-6"
    fi
    if [[ ${#configured_providers[@]} -gt 1 ]]; then
        if $has_detections; then
            menu_options="0-6, s1-s4"
        else
            menu_options="1-6, s1-s4"
        fi
    fi

    read "choice?Select option ($menu_options): "

    case $choice in
        0)
            echo ""
            echo "🚀 Auto-configuring ALL detected providers..."
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

            local setup_count=0
            local setup_providers=()

            # Configure OpenAI if detected
            if [[ -n "$detected_openai" ]]; then
                echo ""
                echo "🤖 Setting up OpenAI..."
                echo "🧪 Testing API key..."
                if _test_openai_key "$detected_openai"; then
                    _save_config "openai" "$detected_openai"
                    echo "✅ OpenAI configured successfully!"
                    setup_count=$((setup_count + 1))
                    setup_providers+=("OpenAI")
                else
                    echo "❌ OpenAI API key test failed"
                    echo "🔍 Testing with verbose output..."
                    _test_openai_key "$detected_openai" "true"  # Show verbose error details
                fi
            fi

            # Configure Anthropic if detected
            if [[ -n "$detected_anthropic" ]]; then
                echo ""
                echo "🧠 Setting up Anthropic..."
                echo "🧪 Testing API key..."
                if _test_anthropic_key "$detected_anthropic"; then
                    _save_config "anthropic" "$detected_anthropic"
                    echo "✅ Anthropic configured successfully!"
                    setup_count=$((setup_count + 1))
                    setup_providers+=("Anthropic")
                else
                    echo "❌ Anthropic API key test failed"
                    echo "🔍 Testing with verbose output..."
                    _test_anthropic_key "$detected_anthropic" "true"  # Show verbose error details
                fi
            fi

            # Configure Grok if detected
            if [[ -n "$detected_grok" ]]; then
                echo ""
                echo "⚡ Setting up Grok..."
                echo "🧪 Testing API key..."
                if _test_grok_key "$detected_grok"; then
                    _save_config "grok" "$detected_grok"
                    echo "✅ Grok configured successfully!"
                    setup_count=$((setup_count + 1))
                    setup_providers+=("Grok")
                else
                    echo "❌ Grok API key test failed"
                    echo "🔍 Testing with verbose output..."
                    _test_grok_key "$detected_grok" "true"  # Show verbose error details
                fi
            fi

            echo ""
            if [[ $setup_count -gt 0 ]]; then
                echo "🎉 AMAZING! $setup_count provider(s) configured successfully!"
                echo "✅ Configured: ${setup_providers[*]}"
                echo ""
                echo "🚀 You can now:"
                echo "  • Use any provider for commit suggestions"
                echo "  • Switch between providers instantly: git-suggest-switch <provider>"
                echo "  • Run git-suggest-config to change active provider"
                echo ""

                # Set the last configured provider as active (prefer Anthropic if available)
                local preferred_provider=""
                for provider in "anthropic" "grok" "openai"; do
                    if [[ " ${setup_providers[*]} " =~ " ${provider^} " ]]; then
                        preferred_provider="$provider"
                        break
                    fi
                done

                if [[ -n "$preferred_provider" ]]; then
                    echo "🎯 Setting $preferred_provider as your active provider (recommended for best performance/cost)"
                    _switch_provider "$preferred_provider"
                fi

                _show_success_message "Multi-Provider Setup"
            else
                echo "❌ No providers could be configured. Please check your API keys."
                return 1
            fi
            return 0
            ;;
        1)
            echo ""
            echo "🤖 Setting up OpenAI API..."
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━"

            local token=""
            if [[ -n "$detected_openai" ]]; then
                echo "🔍 Found OpenAI API key in environment: ${detected_openai:0:8}..."
                read "use_detected?Use this key? (y/n): "
                if [[ "$use_detected" == "y" ]]; then
                    token="$detected_openai"
                    echo "✅ Using auto-detected OpenAI key"
                fi
            fi

            if [[ -z "$token" ]]; then
                echo ""
                echo "📝 Get your API key from: https://platform.openai.com/api-keys"
                echo "💡 Tip: Look for 'sk-' followed by a long string"
                read "token?Enter OpenAI API token: "
            fi

                        if [[ -n "$token" ]]; then
                echo "🧪 Testing API key..."
                if _test_openai_key "$token" "true"; then  # Always use verbose mode
            _save_config "openai" "$token"
                    echo "✅ OpenAI configured successfully!"
                    _show_success_message "OpenAI"
                else
                    echo ""
                    echo "💡 Please check your key and try again."
                    return 1
                fi
            else
                echo "❌ No API key provided."
                return 1
            fi
            ;;
        2)
            echo ""
            echo "🧠 Setting up Anthropic API..."
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━"

            local token=""
            if [[ -n "$detected_anthropic" ]]; then
                echo "🔍 Found Anthropic API key in environment: ${detected_anthropic:0:8}..."
                read "use_detected?Use this key? (y/n): "
                if [[ "$use_detected" == "y" ]]; then
                    token="$detected_anthropic"
                    echo "✅ Using auto-detected Anthropic key"
                fi
            fi

            if [[ -z "$token" ]]; then
                echo ""
                echo "📝 Get your API key from: https://console.anthropic.com/"
                echo "💡 Tip: Look for 'sk-ant-' followed by a long string"
                read "token?Enter Anthropic API token: "
            fi

                        if [[ -n "$token" ]]; then
                echo "🧪 Testing API key..."
                if _test_anthropic_key "$token" "true"; then  # Always use verbose mode
            _save_config "anthropic" "$token"
                    echo "✅ Anthropic configured successfully!"
                    _show_success_message "Anthropic"
                else
                    echo ""
                    echo "💡 Please check your key and try again."
                    return 1
                fi
            else
                echo "❌ No API key provided."
                return 1
            fi
            ;;
        3)
            echo ""
            echo "⚡ Setting up Grok API..."
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━"

            local token=""
            if [[ -n "$detected_grok" ]]; then
                echo "🔍 Found Grok API key in environment: ${detected_grok:0:8}..."
                read "use_detected?Use this key? (y/n): "
                if [[ "$use_detected" == "y" ]]; then
                    token="$detected_grok"
                    echo "✅ Using auto-detected Grok key"
                fi
            fi

            if [[ -z "$token" ]]; then
                echo ""
                echo "📝 Get your API key from: https://console.x.ai/"
                echo "💡 Tip: Look for 'xai-' followed by a long string"
                read "token?Enter Grok API token: "
            fi

            if [[ -n "$token" ]]; then
                echo "🧪 Testing API key..."
                if _test_grok_key "$token" "true"; then  # Always use verbose mode
                    _save_config "grok" "$token"
                    echo "✅ Grok configured successfully!"
                    _show_success_message "Grok"
                else
                    echo ""
                    echo "💡 Please check your key and try again."
                    return 1
                fi
            else
                echo "❌ No API key provided."
                return 1
            fi
            ;;
        4)
            echo ""
            echo "🏠 Local LLM Setup"
            echo "━━━━━━━━━━━━━━━━━━"
            echo "🚧 Local LLM support is coming soon!"
            echo "📧 For now, please use OpenAI, Anthropic, or Grok API."
            echo ""
            read "path?Enter path to local LLM (experimental): "
            if [[ ! -f "$path" ]]; then
                echo "⚠️  Warning: File does not exist at $path"
                read "continue?Continue anyway? (y/n): "
                [[ "$continue" != "y" ]] && return 1
            fi
            _save_config "local" "" "$path"
            echo "⚠️  Local LLM configured (experimental)"
            ;;
        5)
            _show_current_configuration
            return 0
            ;;
        6)
            _clear_configuration
            return 0
            ;;
        s1)
            echo ""
            echo "⚡ Switching to OpenAI..."
            _switch_provider "openai"
            return 0
            ;;
        s2)
            echo ""
            echo "⚡ Switching to Anthropic..."
            _switch_provider "anthropic"
            return 0
            ;;
        s3)
            echo ""
            echo "⚡ Switching to Grok..."
            _switch_provider "grok"
            return 0
            ;;
        s4)
            echo ""
            echo "⚡ Switching to Local LLM..."
            _switch_provider "local"
            return 0
            ;;
        *)
            echo "❌ Invalid option"
            return 1
            ;;
    esac

    # Reload configuration after successful setup
    _load_config
}

# Function to test OpenAI API key with verbose error reporting
_test_openai_key() {
    local token="$1"
    local verbose="${2:-false}"

    # Use temporary files to capture both status and response
    local response_file=$(mktemp)

    local http_code
    http_code=$(curl -s -w "%{http_code}" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d '{"model":"gpt-3.5-turbo","messages":[{"role":"user","content":"test"}],"max_tokens":1}' \
        -o "$response_file" \
        "https://api.openai.com/v1/chat/completions" 2>&1)

    local curl_exit_code=$?
    local response_body=$(cat "$response_file" 2>/dev/null)

    # Show detailed error if verbose mode or if test fails
    if [[ "$verbose" == "true" || $curl_exit_code -ne 0 || "$http_code" != "200" ]]; then
        echo ""
        echo "🔍 Detailed API Test Results:"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "📡 Endpoint: https://api.openai.com/v1/chat/completions"
        echo "🔑 Token: ${token:0:8}...${token: -8}"
        echo "📊 HTTP Status: $http_code"

        if [[ $curl_exit_code -ne 0 ]]; then
            echo "❌ Network Error: Failed to connect to OpenAI API"
        elif [[ "$http_code" != "200" ]]; then
            echo "❌ API Error Response:"
            if [[ -n "$response_body" ]]; then
                local error_message=$(echo "$response_body" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
                [[ -n "$error_message" ]] && echo "   Message: $error_message"

                case "$http_code" in
                    "401") echo "   🔐 Invalid API key - check https://platform.openai.com/api-keys" ;;
                    "429") echo "   ⏱️ Rate limited - wait and try again" ;;
                    "500"|"502"|"503") echo "   🔧 OpenAI server error - try again later" ;;
                esac
            fi
        else
            echo "✅ API Key Valid!"
        fi
    fi

    rm -f "$response_file"
    [[ $curl_exit_code -eq 0 && "$http_code" == "200" ]]
}

# Function to test Anthropic API key with verbose error reporting
_test_anthropic_key() {
    local token="$1"
    local verbose="${2:-false}"

    # Use temporary files to capture both status and response
    local response_file=$(mktemp)

    local http_code
    http_code=$(curl -s -w "%{http_code}" \
        -H "x-api-key: $token" \
        -H "Content-Type: application/json" \
        -H "anthropic-version: 2023-06-01" \
        -d '{"model":"claude-3-5-haiku-20241022","max_tokens":1,"messages":[{"role":"user","content":"test"}]}' \
        -o "$response_file" \
        "https://api.anthropic.com/v1/messages" 2>&1)

    local curl_exit_code=$?
    local response_body=$(cat "$response_file" 2>/dev/null)

    # Show detailed error if verbose mode or if test fails
    if [[ "$verbose" == "true" || $curl_exit_code -ne 0 || "$http_code" != "200" ]]; then
        echo ""
        echo "🔍 Detailed API Test Results:"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "📡 Endpoint: https://api.anthropic.com/v1/messages"
        echo "🔑 Token: ${token:0:8}...${token: -8}"
        echo "📊 HTTP Status: $http_code"

        if [[ $curl_exit_code -ne 0 ]]; then
            echo "❌ Network Error: Failed to connect to Anthropic API"
        elif [[ "$http_code" != "200" ]]; then
            echo "❌ API Error Response:"
            if [[ -n "$response_body" ]]; then
                local error_message=$(echo "$response_body" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
                [[ -n "$error_message" ]] && echo "   Message: $error_message"

                case "$http_code" in
                    "401") echo "   🔐 Invalid API key - check https://console.anthropic.com/" ;;
                    "429") echo "   ⏱️ Rate limited - wait and try again" ;;
                    "500"|"502"|"503") echo "   🔧 Anthropic server error - try again later" ;;
                esac
            fi
        else
            echo "✅ API Key Valid!"
        fi
    fi

    rm -f "$response_file"
    [[ $curl_exit_code -eq 0 && "$http_code" == "200" ]]
}

# Function to test Grok API key with verbose error reporting
_test_grok_key() {
    local token="$1"
    local verbose="${2:-false}"

    # Use temporary files to capture both status and response
    local response_file=$(mktemp)
    local headers_file=$(mktemp)

    local http_code
    http_code=$(curl -s -w "%{http_code}" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d '{"model":"grok-beta","max_tokens":1,"messages":[{"role":"user","content":"test"}]}' \
        -o "$response_file" \
        -D "$headers_file" \
        "https://api.x.ai/v1/chat/completions" 2>&1)

    local curl_exit_code=$?
    local response_body=$(cat "$response_file" 2>/dev/null)

    # Debug info
    _debug_log "Grok API test - HTTP Code: $http_code, Curl Exit: $curl_exit_code"
    _debug_log "Grok API test - Response: $response_body"

    # Show detailed error if verbose mode or if test fails
    if [[ "$verbose" == "true" || $curl_exit_code -ne 0 || "$http_code" != "200" ]]; then
        echo ""
        echo "🔍 Detailed API Test Results:"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "📡 Endpoint: https://api.x.ai/v1/chat/completions"
        echo "🔑 Token: ${token:0:8}...${token: -8}"
        echo "📊 HTTP Status: $http_code"
        echo "🔄 Curl Exit Code: $curl_exit_code"

        if [[ $curl_exit_code -ne 0 ]]; then
            echo "❌ Network Error: Failed to connect to Grok API"
            echo "💡 Check your internet connection and try again"
        elif [[ "$http_code" != "200" ]]; then
            echo "❌ API Error Response:"
            if [[ -n "$response_body" ]]; then
                # Try to extract error message
                local error_message=$(echo "$response_body" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
                local error_type=$(echo "$response_body" | grep -o '"type":"[^"]*"' | cut -d'"' -f4)
                local error_code=$(echo "$response_body" | grep -o '"code":"[^"]*"' | cut -d'"' -f4)

                if [[ -n "$error_message" ]]; then
                    echo "   Message: $error_message"
                fi
                if [[ -n "$error_type" ]]; then
                    echo "   Type: $error_type"
                fi
                if [[ -n "$error_code" ]]; then
                    echo "   Code: $error_code"
                fi

                # Common error handling
                case "$http_code" in
                    "400")
                        if [[ "$response_body" == *"Incorrect API key"* ]]; then
                            echo ""
                            echo "🔐 Invalid API Key:"
                            echo "   • The API key format is incorrect"
                            echo "   • Grok keys should start with 'xai-'"
                            echo "   • Get a valid key from https://console.x.ai/"
                        else
                            echo ""
                            echo "❓ Bad Request (HTTP 400)"
                            echo "   • Raw response: $response_body"
                        fi
                        ;;
                    "401")
                        echo ""
                        echo "🔐 Authentication Failed:"
                        echo "   • Invalid API key format"
                        echo "   • Key may be expired or revoked"
                        echo "   • Check your token at https://console.x.ai/"
                        ;;
                    "403")
                        echo ""
                        echo "🚫 Access Forbidden:"
                        echo "   • API key lacks required permissions"
                        echo "   • Account may not have access to Grok API"
                        echo "   • Contact xAI support if this persists"
                        ;;
                    "404")
                        if [[ "$response_body" == *"grok-beta does not exist"* || "$response_body" == *"grok-3-beta does not exist"* || "$response_body" == *"does not have access to it"* ]]; then
                            echo ""
                            echo "🚫 Model Access Issue:"
                            echo "   • Your account doesn't have access to Grok models"
                            echo "   • Available models: grok-3-beta (latest) or grok-beta (older)"
                            echo "   • Your account may need API access enabled"
                            echo "   • Contact xAI support at https://console.x.ai/"
                            local team_id=$(echo "$response_body" | grep -o 'team [a-f0-9-]*' | cut -d' ' -f2)
                            [[ -n "$team_id" ]] && echo "   • Your team ID: $team_id"
                            echo ""
                            echo "💡 Troubleshooting steps:"
                            echo "   1. Verify your API key at https://console.x.ai/"
                            echo "   2. Check if your account has Grok API access"
                            echo "   3. Try the grok-beta model instead"
                        else
                            echo ""
                            echo "❓ Not Found (HTTP 404)"
                            echo "   • Raw response: $response_body"
                        fi
                        ;;
                    "429")
                        echo ""
                        echo "⏱️ Rate Limited:"
                        echo "   • Too many requests"
                        echo "   • Wait a moment and try again"
                        ;;
                    "500"|"502"|"503")
                        echo ""
                        echo "🔧 Server Error:"
                        echo "   • Grok API is experiencing issues"
                        echo "   • Try again in a few minutes"
                        ;;
                    *)
                        echo ""
                        echo "❓ Unexpected Error (HTTP $http_code)"
                        echo "   • Raw response: $response_body"
                        ;;
                esac
            else
                echo "   (No response body)"
            fi
        else
            echo "✅ API Key Valid!"
        fi
    fi

    # Cleanup
    rm -f "$response_file" "$headers_file"

    # Return success if HTTP 200
    [[ $curl_exit_code -eq 0 && "$http_code" == "200" ]]
}

# Function to show success message with next steps
_show_success_message() {
    local provider="$1"
    echo ""
    echo "🎉 Setup Complete!"
    echo "━━━━━━━━━━━━━━━━━"
    echo "✅ $provider API configured and tested"
    echo "🚀 You're ready to generate AI commit messages!"
    echo ""
    echo "💡 How to use:"
    echo "  1. Make some changes to your code"
    echo "  2. Stage them: git add ."
    echo "  3. Start commit: git commit -m \""
    echo "  4. Press Tab to insert AI suggestion!"
    echo ""
    echo "🔧 Run 'git-suggest-config' anytime to change settings"
    echo ""
    echo "─────────────────────────────────────────────────────"
    echo "☕ Loving the AI suggestions? Support the creator!"
    echo "   💖 https://buymeacoffee.com/ngattusohw"
    echo "   ⭐ https://github.com/ngattusohw/git-commit-suggestions"
    echo "─────────────────────────────────────────────────────"
    echo ""
}

# Function to show current configuration (extracted for reusability)
_show_current_configuration() {
    echo ""
    echo "📋 Current Configuration"
    echo "═══════════════════════"

    local config_found=false

    # Check file-based configuration
    if [[ -f "$_CONFIG_FILE" ]]; then
        echo ""
        echo "📁 File-based configuration ($_CONFIG_FILE):"
        cat "$_CONFIG_FILE"
        config_found=true
    else
        echo ""
        echo "📁 File-based configuration: None found"
    fi

    # Check environment-based configuration
    echo ""
    echo "🌍 Environment-based configuration:"
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
    echo ""
    echo "🎯 Effective status:"
    if [[ -n "$SUGGEST_PROVIDER" || -n "$SUGGEST_LLM_TOKEN" ]]; then
        if [[ -n "$SUGGEST_LLM_TOKEN" ]]; then
            echo "  ✅ Ready to generate suggestions (using environment token)"
        elif [[ -n "$SUGGEST_PROVIDER" && -f "$_CONFIG_FILE" ]]; then
            # Reload config to check file-based token
            source "$_CONFIG_FILE" 2>/dev/null
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
        echo ""
        echo "💡 No configuration found anywhere."
        echo "🚀 Run 'git-suggest-config' to get started!"
    fi
}

# Function to clear configuration (extracted for reusability)
_clear_configuration() {
    echo ""
    echo "🗑️  Clear Configuration"
    echo "═════════════════════"

    if [[ -f "$_CONFIG_FILE" || -n "$SUGGEST_PROVIDER" || -n "$SUGGEST_LLM_TOKEN" ]]; then
        echo "⚠️  This will remove all git-suggest configuration."
        read "confirm?Are you sure? (y/n): "
        if [[ "$confirm" == "y" ]]; then
            [[ -f "$_CONFIG_FILE" ]] && rm "$_CONFIG_FILE"
            # Clear environment variables in current session
            unset SUGGEST_PROVIDER
            unset SUGGEST_LLM_TOKEN
            unset SUGGEST_LLM_PATH
            # Reset state
            _set_suggestion_state "UNCONFIGURED"
            echo "✅ Configuration cleared successfully."
            echo "🚀 Run 'git-suggest-config' to set up again."
            _debug_log "Configuration cleared and state reset to UNCONFIGURED"
        else
            echo "❌ Clear cancelled."
        fi
    else
        echo "💡 No configuration to clear."
    fi
}

# Load configuration on plugin start
_load_config

# Quick provider switching function
_switch_provider() {
    local new_provider="$1"

    if [[ -z "$new_provider" ]]; then
        echo "Usage: git-suggest-switch <provider>"
        echo "Available providers: openai, anthropic, grok, local"
        return 1
    fi

    # Check if config file exists
    if [[ ! -f "$_CONFIG_FILE" ]]; then
        echo "❌ No configuration found. Run 'git-suggest-config' to set up first."
        return 1
    fi

    # Load current config
    source "$_CONFIG_FILE"

    # Check if the requested provider is configured
    local has_provider=false
    case "$new_provider" in
        "openai")
            [[ -n "$SUGGEST_OPENAI_TOKEN" ]] && has_provider=true
            ;;
        "anthropic")
            [[ -n "$SUGGEST_ANTHROPIC_TOKEN" ]] && has_provider=true
            ;;
        "grok")
            [[ -n "$SUGGEST_GROK_TOKEN" ]] && has_provider=true
            ;;
        "local")
            [[ -n "$SUGGEST_LOCAL_PATH" ]] && has_provider=true
            ;;
        *)
            echo "❌ Unknown provider: $new_provider"
            echo "Available providers: openai, anthropic, grok, local"
            return 1
            ;;
    esac

    if ! $has_provider; then
        echo "❌ Provider '$new_provider' is not configured."
        echo "💡 Run 'git-suggest-config' to set up $new_provider first."
        return 1
    fi

    # Update the active provider in config file
    sed -i.bak "s/SUGGEST_ACTIVE_PROVIDER=\".*\"/SUGGEST_ACTIVE_PROVIDER=\"$new_provider\"/" "$_CONFIG_FILE"
    sed -i.bak "s/SUGGEST_PROVIDER=\".*\"/SUGGEST_PROVIDER=\"$new_provider\"/" "$_CONFIG_FILE"
    rm -f "$_CONFIG_FILE.bak"

    # Reload configuration
    _load_config

    # Show confirmation
    local provider_name=""
    case "$new_provider" in
        "openai") provider_name="🤖 OpenAI (GPT-3.5-turbo)" ;;
        "anthropic") provider_name="🧠 Anthropic (Claude-3-haiku)" ;;
        "grok") provider_name="⚡ Grok (xAI)" ;;
        "local") provider_name="🏠 Local LLM" ;;
    esac

    echo "✅ Switched to $provider_name"
    echo "🚀 Ready to generate commit suggestions!"
}

# Function to get available configured providers
_get_configured_providers() {
    local providers=()

    if [[ -f "$_CONFIG_FILE" ]]; then
        source "$_CONFIG_FILE"
        [[ -n "$SUGGEST_OPENAI_TOKEN" ]] && providers+=("openai")
        [[ -n "$SUGGEST_ANTHROPIC_TOKEN" ]] && providers+=("anthropic")
        [[ -n "$SUGGEST_GROK_TOKEN" ]] && providers+=("grok")
        [[ -n "$SUGGEST_LOCAL_PATH" ]] && providers+=("local")
    fi

    echo "${providers[@]}"
}

# Add configuration command (add at end of file)
alias git-suggest-config='_git_suggest_config'
alias git-suggest-switch='_switch_provider'

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
        "grok")
            _grok_generate "$diff"
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
            "content": "Generate concise, single-line git commit messages from diffs or commit analysis. Use conventional commit format (feat/fix/chore/etc) with an emoji. Keep under 72 characters. For large commits, focus on the main theme rather than individual changes. Examples: 'feat: ✨ add user authentication', 'fix: 🐛 resolve login timeout', 'chore: 🔧 update dependencies', 'refactor: 🔄 restructure auth system', 'feat: ✨ implement user dashboard (5 components)'. No backticks or special quotes."
        },
        {
            "role": "user",
            "content": "Generate a commit message for this change:\n\n${escaped_diff}"
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
    local test_request='{"model":"claude-3-5-haiku-20241022","max_tokens":10,"messages":[{"role":"user","content":"test"}]}'

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
    "model": "claude-3-5-haiku-20241022",
    "max_tokens": 200,
    "messages": [
        {
            "role": "user",
            "content": "Generate a concise, single-line git commit message from this diff or commit analysis. Use conventional commit format (feat/fix/chore/etc) with an emoji. Keep it under 72 characters. For large commits, focus on the main theme rather than individual changes. Examples: 'feat: ✨ add user authentication', 'fix: 🐛 resolve login timeout', 'chore: 🔧 update dependencies', 'refactor: 🔄 restructure auth system', 'feat: ✨ implement user dashboard (5 components)'. No backticks or special quotes.\n\nChange:\n${escaped_diff}"
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

# Grok Provider Implementation
_grok_generate() {
    local diff="$1"
    _debug_log "Generating suggestion using Grok API"

    # Ensure we have required variables
    if [[ -z "$SUGGEST_LLM_TOKEN" ]]; then
        _debug_log "Grok token not found"
        return 1
    fi

    # Test with grok-3-beta first, fallback to grok-beta
    local test_request='{"model":"grok-3-beta","max_tokens":1,"messages":[{"role":"user","content":"test"}]}'

    local test_response
    test_response=$(curl -s -S -H "Content-Type: application/json" \
                        -H "Authorization: Bearer $SUGGEST_LLM_TOKEN" \
                        -d "$test_request" \
                        "https://api.x.ai/v1/chat/completions" 2>&1)

    # If grok-3-beta fails, try grok-beta as fallback
    if [[ "$test_response" == *"does not exist"* || "$test_response" == *"not found"* ]]; then
        _debug_log "grok-3-beta not available, trying grok-beta"
        test_request='{"model":"grok-beta","max_tokens":1,"messages":[{"role":"user","content":"test"}]}'
        test_response=$(curl -s -S -H "Content-Type: application/json" \
                            -H "Authorization: Bearer $SUGGEST_LLM_TOKEN" \
                            -d "$test_request" \
                            "https://api.x.ai/v1/chat/completions" 2>&1)
    fi

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

    # Write JSON to temp file - Grok format (try grok-3-beta first)
    cat > "$tmp_json" << EOF
{
    "model": "grok-3-beta",
    "max_tokens": 200,
    "messages": [
        {
            "role": "user",
            "content": "Generate a concise, single-line git commit message from this diff or commit analysis. Use conventional commit format (feat/fix/chore/etc) with an emoji. Keep it under 72 characters. For large commits, focus on the main theme rather than individual changes. Examples: 'feat: ✨ add user authentication', 'fix: 🐛 resolve login timeout', 'chore: 🔧 update dependencies', 'refactor: 🔄 restructure auth system', 'feat: ✨ implement user dashboard (5 components)'. No backticks or special quotes.\n\nChange:\n${escaped_diff}"
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
                        "https://api.x.ai/v1/chat/completions" 2>&1)

    # Clean up temp file
    rm -f "$tmp_json"

    local result=$?
    local http_code=$(echo "$http_response" | grep -i "^HTTP" | tail -n1 | awk '{print $2}')
    response=$(echo "$http_response" | awk 'BEGIN{RS="\r\n\r\n"} NR==2')

    _debug_log "Grok API call result: $result"
    _debug_log "HTTP Status: $http_code"
    _debug_log "Response: $response"

    if [[ $result -ne 0 || $http_code -ne 200 ]]; then
        # If grok-3-beta fails, try grok-beta as fallback
        if [[ "$response" == *"grok-3-beta does not exist"* || "$response" == *"does not have access to it"* ]]; then
            _debug_log "grok-3-beta failed, trying grok-beta fallback"

            # Update the JSON file to use grok-beta
            cat > "$tmp_json" << EOF
{
    "model": "grok-beta",
    "max_tokens": 200,
    "messages": [
        {
            "role": "user",
            "content": "Generate a concise, single-line git commit message from this diff or commit analysis. Use conventional commit format (feat/fix/chore/etc) with an emoji. Keep it under 72 characters. For large commits, focus on the main theme rather than individual changes. Examples: 'feat: ✨ add user authentication', 'fix: 🐛 resolve login timeout', 'chore: 🔧 update dependencies', 'refactor: 🔄 restructure auth system', 'feat: ✨ implement user dashboard (5 components)'. No backticks or special quotes.\n\nChange:\n${escaped_diff}"
        }
    ]
}
EOF

            # Retry with grok-beta
            http_response=$(curl -s -S -i -H "Content-Type: application/json" \
                                -H "Authorization: Bearer $SUGGEST_LLM_TOKEN" \
                                -d "@$tmp_json" \
                                "https://api.x.ai/v1/chat/completions" 2>&1)

            result=$?
            http_code=$(echo "$http_response" | grep -i "^HTTP" | tail -n1 | awk '{print $2}')
            response=$(echo "$http_response" | awk 'BEGIN{RS="\r\n\r\n"} NR==2')

            _debug_log "Grok fallback API call result: $result"
            _debug_log "Grok fallback HTTP Status: $http_code"
            _debug_log "Grok fallback Response: $response"
        fi

        # If still failing after fallback
        if [[ $result -ne 0 || $http_code -ne 200 ]]; then
            # Try to extract error message from response
            local error_message
            error_message=$(echo "$response" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
            if [[ -n "$error_message" ]]; then
                _debug_log "Grok API error: $error_message"
            fi
            _debug_log "Grok API call failed"
            return 1
        fi
    fi

    # Extract message from Grok response format
    local message
    # Grok response format: {"content":[{"type":"text","text":"MESSAGE"}]}

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
    "model": "claude-3-5-haiku-20241022",
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
            "openai")
                # OpenAI API call
                local escaped_diff=$(echo "$diff_content" | LC_ALL=C sed 's/[^[:print:]\n]//g; s/\\/\\\\/g; s/"/\\"/g' | tr -d '\r' | tr '\n' ' ')
                local tmp_json=$(mktemp)

                # Construct JSON properly without placeholders
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

                local response=$(curl -s -H "Content-Type: application/json" \
                    -H "Authorization: Bearer $SUGGEST_LLM_TOKEN" \
                    -d "@$tmp_json" \
                    "https://api.openai.com/v1/chat/completions")

                # Extract suggestion using the same method as the main function
                suggestion=$(echo "$response" | grep -o '"content": *"[^"]*"' | cut -d'"' -f4)
                rm -f "$tmp_json"
                ;;
            "grok")
                # Grok API call
                local escaped_diff=$(echo "$diff_content" | LC_ALL=C sed 's/[^[:print:]\n]//g; s/\\/\\\\/g; s/"/\\"/g' | tr -d '\r' | tr '\n' ' ')
                local tmp_json=$(mktemp)

                # Construct JSON properly without placeholders
                cat > "$tmp_json" << EOF
{
    "model": "grok-beta",
    "max_tokens": 200,
    "messages": [
        {
            "role": "user",
            "content": "Generate a concise, single-line git commit message from this diff. Use conventional commit format (feat/fix/chore/etc) with an emoji. Keep it under 72 characters. Focus on the main purpose, not implementation details. Examples: 'feat: ✨ add user authentication', 'fix: 🐛 resolve login timeout', 'chore: 🔧 update dependencies'. No backticks or special quotes.\n\nDiff:\n${escaped_diff}"
        }
    ]
}
EOF

                local response=$(curl -s -H "Content-Type: application/json" \
                    -H "Authorization: Bearer $SUGGEST_LLM_TOKEN" \
                    -d "@$tmp_json" \
                    "https://api.x.ai/v1/chat/completions")

                # Extract suggestion using the same method as the main function
                suggestion=$(echo "$response" | sed 's/.*"text":"//; s/"}].*//' | sed 's/\\n/\n/g; s/:sparkles:/✨/g; s/:rocket:/🚀/g; s/:bug:/🐛/g; s/:wrench:/🔧/g; s/:zap:/⚡/g')
                rm -f "$tmp_json"
                ;;
            "local")
                echo "[$(date '+%H:%M:%S')] Local LLM not supported in background process" >> /tmp/git-completion-debug.log 2>/dev/null
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

# Smart diff analysis and summarization for large commits
_analyze_and_summarize_diff() {
    local diff="$1"
    local max_size="${2:-8000}"  # Default 8KB limit for LLM context

    _debug_log "=== Smart Diff Analysis ==="
    _debug_log "Raw diff size: ${#diff} characters"

    # If diff is small enough, return as-is
    if [[ ${#diff} -le $max_size ]]; then
        _debug_log "Diff is small enough, sending as-is"
        echo "$diff"
        return 0
    fi

    # Get file statistics
    local files_changed=$(git diff --staged --name-only | wc -l | tr -d ' ')
    local lines_added=$(git diff --staged --numstat | awk '{sum+=$1} END {print sum+0}')
    local lines_removed=$(git diff --staged --numstat | awk '{sum+=$2} END {print sum+0}')

    _debug_log "Files changed: $files_changed, Lines +$lines_added/-$lines_removed"

    # Categorize files by type and importance
    local core_files=()
    local config_files=()
    local test_files=()
    local doc_files=()
    local generated_files=()
    local other_files=()

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue

        case "$file" in
            # Generated/noise files (usually skip)
            package-lock.json|yarn.lock|composer.lock|Pipfile.lock|Gemfile.lock)
                generated_files+=("$file") ;;
            **/node_modules/**|**/vendor/**|**/.next/**|**/dist/**|**/build/**)
                generated_files+=("$file") ;;

            # Configuration files
            *.config.js|*.config.ts|webpack.config.*|babel.config.*|tsconfig.json|*.env*|Dockerfile|docker-compose.*)
                config_files+=("$file") ;;
            package.json|requirements.txt|Gemfile|composer.json|*.toml|*.yaml|*.yml)
                config_files+=("$file") ;;

            # Test files
            **/*test*|**/*spec*|**/tests/**|**/__tests__/**|*.test.*|*.spec.*)
                test_files+=("$file") ;;

            # Documentation
            *.md|*.rst|*.txt|docs/**|**/docs/**)
                doc_files+=("$file") ;;

            # Core application files
            *.js|*.ts|*.jsx|*.tsx|*.py|*.rb|*.php|*.java|*.go|*.rs|*.c|*.cpp|*.h)
                core_files+=("$file") ;;

            # Everything else
            *)
                other_files+=("$file") ;;
        esac
    done <<< "$(git diff --staged --name-only)"

    _debug_log "Categorized files: core=${#core_files[@]}, config=${#config_files[@]}, test=${#test_files[@]}, docs=${#doc_files[@]}, generated=${#generated_files[@]}, other=${#other_files[@]}"

    # Build intelligent summary
    local summary=""

    # Add statistics header
    summary+="COMMIT ANALYSIS:\n"
    summary+="Files: $files_changed changed (+$lines_added/-$lines_removed lines)\n\n"

    # Prioritize core files - get actual meaningful changes
    if [[ ${#core_files[@]} -gt 0 ]]; then
        summary+="CORE CHANGES:\n"
        for file in "${core_files[@]:0:10}"; do  # Limit to first 10 core files
            local file_diff=$(git diff --staged "$file" | head -n 20)  # First 20 lines of each file
            if [[ -n "$file_diff" ]]; then
                summary+="File: $file\n"
                summary+="$(echo "$file_diff" | grep '^[+-]' | head -n 8)\n\n"  # Show actual changes
            fi
        done

        # If we have many core files, just list the rest
        if [[ ${#core_files[@]} -gt 10 ]]; then
            summary+="Additional core files: ${core_files[@]:10}\n\n"
        fi
    fi

    # Summarize other categories
    if [[ ${#config_files[@]} -gt 0 ]]; then
        summary+="CONFIG CHANGES:\n"
        printf '%s\n' "${config_files[@]}" | head -n 5
        summary+="\n"
        [[ ${#config_files[@]} -gt 5 ]] && summary+="(+$((${#config_files[@]} - 5)) more config files)\n\n"
    fi

    if [[ ${#test_files[@]} -gt 0 ]]; then
        summary+="TEST CHANGES:\n"
        printf '%s\n' "${test_files[@]}" | head -n 5
        summary+="\n"
        [[ ${#test_files[@]} -gt 5 ]] && summary+="(+$((${#test_files[@]} - 5)) more test files)\n\n"
    fi

    if [[ ${#doc_files[@]} -gt 0 ]]; then
        summary+="DOCUMENTATION:\n"
        printf '%s\n' "${doc_files[@]}"
        summary+="\n\n"
    fi

    if [[ ${#generated_files[@]} -gt 0 ]]; then
        summary+="GENERATED/DEPS: ${#generated_files[@]} files (package-lock.json, etc.)\n\n"
    fi

    # Detect common patterns
    if [[ $files_changed -gt 20 ]]; then
        summary+="PATTERN: Large refactoring or migration (${files_changed} files)\n"
    elif [[ ${#test_files[@]} -gt ${#core_files[@]} ]]; then
        summary+="PATTERN: Test-heavy changes\n"
    elif [[ ${#doc_files[@]} -gt 0 && ${#core_files[@]} -eq 0 ]]; then
        summary+="PATTERN: Documentation-only changes\n"
    elif [[ ${#config_files[@]} -gt ${#core_files[@]} ]]; then
        summary+="PATTERN: Configuration/setup changes\n"
    fi

    _debug_log "Generated smart summary, length: ${#summary}"
    echo "$summary"
    return 0
}

