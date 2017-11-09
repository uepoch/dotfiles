# GEM CONFIG
#

export GEM_HOME=$(ruby -e 'puts Gem.user_dir')
export PATH="$GEM_HOME/bin:$PATH"


alias dock='docker'


alias zshreload='source $HOME/.zshrc'
alias zshconfig='vim ~/.dotfiles/zshrc'
alias zz='zshconfig && zshreload'

alias kec2='KITCHEN_YAML=".kitchen.ec2.yml"'
alias kdock='KITCHEN_YAML=".kitchen.docker.yml"'
alias bex='bundle exec'
alias bi='bundle install'
alias kni='bex knife'
alias kit='bex kitchen'

alias yy='yaourt'
