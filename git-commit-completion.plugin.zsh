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

# Global state variable
typeset -g _COMMIT_SUGGESTION=""

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
