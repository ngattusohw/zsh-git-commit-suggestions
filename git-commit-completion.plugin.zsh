# Debug log function with timestamp
_debug_log() {
    echo "[$(date '+%H:%M:%S')] $1" >> /tmp/git-completion-debug.log
}

# Function to generate test suggestions
_generate_commit_suggestions() {
    cat << 'EOF'

Suggested commit message:
feat(auth): implement new user authentication system
- Add OAuth2 integration with Google, GitHub providers
- Implement MFA support with Time-based OTP
- Add secure session management and token refresh
EOF
}

# Global state variables
typeset -g _COMMIT_SUGGESTION=""
typeset -g _CACHED_STAGED_DIFF=""

# Function to update cached diff when files are staged
_update_staged_diff() {
    if git rev-parse --is-inside-work-tree &>/dev/null; then
        _debug_log "Checking for staged changes..."
        local new_diff
        new_diff=$(git diff --staged)

        # Debug the current state
        if [[ -z "$new_diff" ]]; then
            _debug_log "No staged changes detected"
        fi

        if [[ "$new_diff" != "$_CACHED_STAGED_DIFF" ]]; then
            _CACHED_STAGED_DIFF="$new_diff"
            if [[ -n "$new_diff" ]]; then
                _debug_log "Updated cached diff: $(echo "$new_diff" | head -n 1)"
                _debug_log "Cached diff: $_CACHED_STAGED_DIFF"
            fi
        else
            _debug_log "Diff unchanged from previous state"
        fi
    else
        _debug_log "Not in a git repository"
    fi
}

# Hook function to run after git commands
_git_command_hook() {
    local cmd="$1"
    if [[ "$cmd" == "git add"* || "$cmd" == "ga"* || "$cmd" == "git reset"* ]]; then
        _debug_log "Git add/reset detected, scheduling diff update"
        # Add a small delay to ensure git has finished staging
        (sleep 0.1 && _update_staged_diff &)
    fi
}

# Add the hook to precmd for constant monitoring
autoload -U add-zsh-hook
add-zsh-hook preexec _git_command_hook

# Function to show suggestion
_show_suggestion() {
    print -P ""  # New line
    print -P "%F{8}$1%f"
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

# Function to handle the quote character
_git_commit_quote_handler() {
    # Insert the quote first
    zle self-insert

    local current_buffer="$BUFFER"
    _debug_log "Buffer after quote: '$current_buffer'"

    # Check for git commit command
    if [[ "$current_buffer" =~ "(git commit|gc) -m \"$" ]]; then
        _debug_log "✓ Git commit command detected"

        # Get and show suggestion
        _COMMIT_SUGGESTION=$(_generate_commit_suggestions)
        _show_suggestion "$_COMMIT_SUGGESTION"

        # Force display update
        zle reset-prompt
    fi
}

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
