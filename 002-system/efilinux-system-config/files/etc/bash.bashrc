case $- in
    *i*) ;;
    *) return ;;
esac

shopt -s checkwinsize cmdhist histappend
HISTCONTROL=ignoreboth:erasedups
HISTSIZE=2000
HISTFILESIZE=4000
export HISTCONTROL HISTSIZE HISTFILESIZE

bind 'set completion-ignore-case on'
bind 'set completion-map-case on'
bind 'set show-all-if-ambiguous on'
bind 'set colored-stats on'
bind '"\e[A": history-search-backward'
bind '"\e[B": history-search-forward'

if [[ -r /usr/share/bash-completion/bash_completion ]]; then
    source /usr/share/bash-completion/bash_completion
fi

backup() {
    if (( $# != 1 )); then
        printf 'usage: backup FILE\n' >&2
        return 2
    fi
    cp -- "$1" "$1.bak"
}

copy() {
    if (( $# == 2 )) && [[ -d $1 ]]; then
        cp -r -- "${1%/}" "$2"
    else
        cp -- "$@"
    fi
}

alias ls='ls --color=auto --group-directories-first'
alias la='ls -A --color=auto --group-directories-first'
alias ll='ls -lh --color=auto --group-directories-first'
alias l.='ls -A --color=auto | grep -E "^\."'
alias grep='grep --color=auto'
alias egrep='grep -E --color=auto'
alias fgrep='grep -F --color=auto'
alias df='df -h'
alias free='free -h'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias psmem='ps auxf | sort -nr -k 4'
alias psmem10='ps auxf | sort -nr -k 4 | head -10'

__efilinux_prompt_command() {
    local status=$?
    local identity_color='\[\e[1;32m\]'
    local status_part=

    if (( EUID == 0 )); then
        identity_color='\[\e[1;31m\]'
    fi
    if (( status != 0 )); then
        status_part="\[\e[1;31m\][$status]\[\e[0m\] "
    fi

    PS1="${status_part}${identity_color}\u\[\e[0;36m\]@\h\[\e[0m\] \[\e[1;34m\]\w\[\e[0m\] ${identity_color}\\$\[\e[0m\] "
}
PROMPT_COMMAND=__efilinux_prompt_command
