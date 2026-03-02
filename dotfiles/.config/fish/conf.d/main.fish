# Add Path
fish_add_path $HOME/.local/bin
fish_add_path $HOME/.opencode/bin
#######################################################
# GENERAL UTILITIES
#######################################################
alias v='nvim'
alias c='clear'
alias cls='clear'
alias da='date "+%Y-%m-%d %A %T %Z"'
alias h="history | grep "
alias p="ps aux | grep "
alias f="find . | grep "
alias checkcommand="type -a" # Fish uses -a for all types
alias python='python3'
alias py='python3'
function venv
    if not test -d .venv
        echo "Creating .venv..."
        python3 -m venv .venv
    end

    if test -f .venv/bin/activate.fish
        source .venv/bin/activate.fish
        echo "Environment activated."
    else
        echo "Error: .venv/bin/activate.fish not found!"
    end
end
alias sha1='openssl sha1'

# Modified Commands
alias cp='cp -i'
alias mv='mv -i'
alias rm='rm -iv'
alias mkdir='mkdir -p'
alias ps='ps auxf'
alias ping='ping -c 10'
alias less='less -R'
alias apt-get='sudo apt-get'
alias freshclam='sudo freshclam'
alias multitail='multitail --no-repeat -c'

#######################################################
# NAVIGATION
#######################################################
alias home='cd ~'
alias cd..='cd ..'
alias b='cd ..'
alias bb='cd ../..'
alias bbb='cd ../../..'
alias bbbb='cd ../../../..'
alias bd='cd $OLDPWD'
alias web='cd /var/www/html'

# Zoxide integration (Portable & Dynamic)
if test -x "$HOME/.local/bin/zoxide"
    $HOME/.local/bin/zoxide init fish | source
    $HOME/.local/bin/zoxide init fish --cmd cd | source
else if command -v zoxide >/dev/null
    zoxide init fish --cmd cd | source
    zoxide init fish | source
end

#######################################################
# FILE LISTING (EZA)
#######################################################
if command -v eza >/dev/null
    alias ls="eza --icons=auto"
    alias la='eza -Alh --icons=auto'
    alias lx='eza -lXBh --icons=auto'
    alias lk='eza -lSrh --icons=auto'
    alias lc='eza -lcrh --icons=auto'
    alias lu='eza -lurh --icons=auto'
    alias lr='eza -lRh --icons=auto'
    alias lt='eza -ltrh --icons=auto'
    alias lm='eza -alh | more'
    alias lw='eza -xAh --icons=auto'
    alias ll='eza -la --icons=auto'
    alias labc='eza -lap --icons=auto'
    alias lf="eza -l --icons=auto | grep -v '^d'"
    alias ldir="eza -l --icons=auto | grep '^d'"
    alias tree='eza --tree --icons'
else
    alias tree='tree -CAhF --dirsfirst'
end

#######################################################
# PERMISSIONS & DISK
#######################################################
alias mx='chmod a+x'
alias 000='chmod -R 000'
alias 644='chmod -R 644'
alias 666='chmod -R 666'
alias 755='chmod -R 755'
alias 777='chmod -R 777'

alias rmd='/bin/rm --recursive --force --verbose'
alias diskspace="du -S | sort -n -r | more"
alias folders='du -h --max-depth=1'
alias mountedinfo='df -hT'
alias treed='tree -ad' # Assuming eza/tree

#######################################################
# SYSTEM & NETWORK
#######################################################
alias topcpu="/bin/ps -eo pcpu,pid,user,args | sort -k 1 -r | head -10"
alias openports='netstat -nape --inet'
alias rebootsafe='sudo shutdown -r now'
alias rebootforce='sudo shutdown -r -n now'

# Advanced Network View
alias ipview="netstat -anpl | grep :80 | awk '{print \$5}' | cut -d: -f1 | sort | uniq -c | sort -n | sed -e 's/^ *//' -e 's/ *\$//'"

#######################################################
# ARCHIVES
#######################################################
alias mktar='tar -cvf'
alias mkbz2='tar -cvjf'
alias mkgz='tar -cvzf'
alias untar='tar -xvf'
alias unbz2='tar -xvjf'
alias ungz='tar -xvzf'

#######################################################
# GIT
#######################################################
alias ga='git add -A'
alias gs='git status'
alias gcm='git commit -am'
alias gpl='git pull origin'
alias gpo='git push origin'

#######################################################
# COMPLEX FUNCTIONS (BASH LOGIC TRANSLATED)
#######################################################

# Alert for long running commands
function alert
    set -l last_status $status
    set -l icon error
    if test $last_status -eq 0
        set icon terminal
    end
    notify-send --urgency=low -i $icon (history | head -n 1)
end

# Count files recursively
function countfiles
    for t in files links directories
        set -l type_flag (string sub -l 1 $t)
        echo (find . -type $type_flag | wc -l) $t
    end
end

# Follow all logs
function logs
    sudo find /var/log -type f -exec file {} + | grep text | cut -d' ' -f1 | sed -e 's/:$//g' | grep -v '[0-9]$' | xargs tail -f
end

# Folder sort by size
function folderssort
    find . -maxdepth 1 -type d -print0 | xargs -0 du -sk | sort -rn
end

# Quick check for existing keys
alias ssh-list="ls -al ~/.ssh/*.pub"

# Generate a new modern Ed25519 key (more secure/smaller than RSA)
# Usage: ssh-gen "your_email@example.com"
function ssh-gen
    ssh-keygen -t ed25519 -C "$argv[1]"
    eval (ssh-agent -c)
    ssh-add ~/.ssh/id_ed25519
end

# Copy public key to clipboard (Windows/WSL specific)
# This uses 'clip.exe' which is built into Windows
alias ssh-copy="cat ~/.ssh/id_ed25519.pub | clip.exe; echo 'Public key copied to Windows clipboard.'"

# Start the agent manually if it's not running
alias ssh-start="eval (ssh-agent -c)"

# Quickly edit ssh config
alias ssh-conf="v ~/.ssh/config"
