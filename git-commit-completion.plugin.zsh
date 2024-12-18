# Debug log function with timestamp
_debug_log() {
    echo "[$(date '+%H:%M:%S')] $1" >> /tmp/git-completion-debug.log
}

# Function to generate test suggestions (without LLM for now)
_generate_commit_suggestions() {
    _debug_log "Generating suggestions..."
    echo "test: add new feature"
    _debug_log "Generated test suggestion"
}

# Function to check buffer and set suggestion
_git_commit_buffer_check() {
    local buf="$BUFFER"
    _debug_log "\n--- Checking buffer ---"
    _debug_log "Current buffer: '$buf'"
    
    # Check if we're in a git commit command with an open quote
    if [[ "$buf" =~ "(git commit|gc) -m \"$" ]]; then
        _debug_log "✓ Git commit command detected"
        local suggestion=$(_generate_commit_suggestions)
        POSTDISPLAY="$suggestion"
        _debug_log "Set suggestion: '$suggestion'"
    else
        _debug_log "✗ Not a git commit command"
        POSTDISPLAY=""
    fi
    
    zle reset-prompt
}

# Create the widget
function git_commit_suggest() {
    _git_commit_buffer_check
}

# Accept suggestion function
function accept_suggestion() {
    if [ -n "$POSTDISPLAY" ]; then
        BUFFER="${BUFFER}${POSTDISPLAY}"
        POSTDISPLAY=""
        zle reset-prompt
    fi
}

# Set up the widgets
zle -N git_commit_suggest
zle -N accept_suggestion
zle -N zle-line-pre-redraw git_commit_suggest

# Bind keys for accepting suggestion
bindkey '^I' accept_suggestion     # Tab key
bindkey '^[[C' accept_suggestion   # Right arrow

_debug_log "Git commit suggestion system loaded at $(date)"
