# HMS bash completion
# Source this file or place it in /etc/bash_completion.d/hms

_hms() {
    local completions
    completions=$(hms --complete "$((COMP_CWORD + 1))" "${COMP_WORDS[@]}" 2>/dev/null)
    COMPREPLY=($(compgen -W "$completions" -- "${COMP_WORDS[$COMP_CWORD]}"))
}

complete -F _hms hms
