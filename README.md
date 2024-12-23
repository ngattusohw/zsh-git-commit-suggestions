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
