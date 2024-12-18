# Debug log function with timestamp
_debug_log() {
    echo "[$(date '+%H:%M:%S')] $1" >> /tmp/git-completion-debug.log
}

# Function to generate test suggestions (without LLM for now)
_generate_commit_suggestions() {
    _debug_log "Generating suggestions..."
    
    # Get staged changes
    local diff_output=$(git diff --staged)
    _debug_log "Diff output length: ${#diff_output}"
    
    # For testing, return some static suggestions
    echo "test: add new feature"
    echo "test: fix bug in module"
    echo "test: update documentation"
    _debug_log "Generated test suggestions"
}

# Custom completion function for git commit -m
_git_commit_message_completion() {
    _debug_log "\n--- New completion attempt ---"
    _debug_log "All words: ${words[*]}"
    _debug_log "Current word: ${words[CURRENT]}"
    _debug_log "CURRENT index: $CURRENT"
    
    local curcontext="$curcontext" state line
    typeset -A opt_args
    
    # Check for both git commit and gc alias
    if [[ ${words[1]} == "git" && ${words[2]} == "commit" ]] || [[ ${words[1]} == "gc" ]]; then
        _debug_log "Git commit command detected"
        
        # Look for -m flag
        local found_m=false
        local quote_pos
        for ((i = 1; i <= CURRENT; i++)); do
            if [[ ${words[i]} == "-m" ]]; then
                found_m=true
                quote_pos=$((i + 1))
                break
            fi
        done
        
        _debug_log "Found -m flag: $found_m"
        _debug_log "Quote position: $quote_pos"
        
        if $found_m && [[ ${words[quote_pos]} == '"' || ${words[quote_pos]} == "'" ]]; then
            _debug_log "Completion conditions met - generating suggestions"
            
            # Get suggestions
            local suggestions=$(_generate_commit_suggestions)
            
            # Format suggestions for completion
            local formatted_suggestions=(${(f)suggestions})
            
            _debug_log "Offering suggestions: $formatted_suggestions"
            
            # Add suggestions to completion
            _describe 'commit message suggestions' formatted_suggestions
            
            return 0
        fi
    fi
    
    _debug_log "Completion conditions not met - falling through"
    return 1
}

# Function to toggle autosuggestions
_toggle_autosuggestions() {
    if [[ "$BUFFER" =~ "^(git commit|gc).*-m \"" ]]; then
        ZSH_AUTOSUGGEST_STRATEGY=()
    else
        ZSH_AUTOSUGGEST_STRATEGY=(history)
    fi
}

# Add our toggle function to the precmd hook
autoload -Uz add-zsh-hook
add-zsh-hook precmd _toggle_autosuggestions

# Register the completion function
compdef _git_commit_message_completion git
compdef _git_commit_message_completion gc

_debug_log "Completion script loaded at $(date)"
