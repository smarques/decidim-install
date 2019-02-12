#!/bin/bash
#
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

echo -e "***********************************************************************"
echo -e "* \e[31mWARNING:\e[0m                                                 *"
echo -e "* This program will try to install automatically Decidim and all      *"
echo -e "* related software. This includes Nginx, Passenger, Ruby and other.   *"
echo -e "* \e[33mUSE IT ONLY IN A FRESHLY INSTALLED UBUNTU 18.04 SYSTEM\e[0m   *"
echo -e "* No guarantee whatsoever that it won't break your system!            *"
echo -e "*                                                                     *"
echo -e "* (c) Ivan Vergés <ivan (at) platoniq.net>                            *"
echo -e "* https://github.com/Platoniq/decidim-install                         *"
echo -e "*                                                                     *"
echo -e "***********************************************************************"

set -e
RUBY_VERSION="2.5.1"
VERBOSE=

info() {
	echo -e "$1"
}
yellow() {
	echo -e "\e[33m$1\e[0m"
}
green() {
	echo -e "\e[32m$1\e[0m"
}
red() {
	echo -e "\e[31m$1\e[0m"
}
exit_help() {
	info "\nUsage:"
	info " $0 [OPTIONS] [FOLDER]\n"
	info "Installs Decidim into FOLDER and all necessary dependencies in Ubuntu 18.04\n"
	info "This script tries to be idempotent (ie: it can be run repeatedly)\n"
	info "OPTIONS:"
	info " -y          Do not ask for confirmation to run the script"
	info " -v          Be verbose (when possible)"
	info " -h          Show this help"
	info " -s[step]    Skip the [step] specified. Multiple steps can be"
	info "             specified with several -s options"
	info " -o[step]    Execute only the [step] specified. Multiple steps can be"
	info "             specified with several -o options\n"
	info "Valid steps are (in order of execution):"
	info " check     Check if we are using Ubuntu 18.04"
	info " prepare   Update system, configure timezone"
	info " rbenv     Install ruby through rbenv"
	trap - EXIT
	exit
}
abort() {
	red "Aborted by the user!"
	trap - EXIT
	exit
}
cleanup() {
	rv=$?
	if [ "$rv" -ne 0 ]; then
		red "Something went wrong! Aborting!"
		exit $rv
	else
		green "Finished successfully!"
	fi
}

step_check() {
	green "Checking current system..."
	if [ "$EUID" -eq 0 ]; then
		red "Please do not run this script as root"
		info "User a normal user with sudo permissions"
		info "sudo password will be asked when necessary"
		exit 1
	fi
	if [ $(awk -F= '/^ID=/{print $2}' /etc/os-release) != "ubuntu" ]; then
		red "Not an ubuntu system!"
		cat /etc/os-release
		exit 1
	fi
	if [ $(awk -F= '/^VERSION_ID=/{print $2}' /etc/os-release) != '"18.04"' ]; then
		red "Not ubuntu 18.04!"
		awk -F= '/^VERSION_ID=/{print $2}' /etc/os-release
		exit 1
	fi
}

step_prepare() {
	green "Updating system"
	sudo apt update
	sudo apt -y upgrade
	sudo apt -y autoremove
	green "Configuring timezone"
	sudo dpkg-reconfigure tzdata
	green "Installing necessary software"
	sudo apt-get -y install autoconf bison build-essential libssl-dev libyaml-dev \
		 libreadline6-dev zlib1g-dev libncurses5-dev libffi-dev libgdbm-dev
}

init_rbenv() {
	export PATH="$HOME/.rbenv/bin:$PATH"
	eval "$(rbenv init -)"
}
step_rbenv() {
	# pause EXIT trap
	trap - EXIT

	info "Installing rbenv"
	if [ -d "$HOME/.rbenv" ]; then
		yellow "$HOME/.rbenv already exists!"
	else
		info "Installing rbenv from GIT source"
		git clone https://github.com/rbenv/rbenv.git $HOME/.rbenv
	fi
	if grep -Fxq 'export PATH="$HOME/.rbenv/bin:$PATH"' "$HOME/.bashrc" ; then
		yellow "$HOME/.rbenv/bin already in PATH"
	else
		info "Installing $HOME/.rbenv/bin in PATH"
		echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> "$HOME/.bashrc"
	fi
	if grep -Fxq 'eval "$(rbenv init -)"' "$HOME/.bashrc" ; then
		yellow "rbenv init already in bashrc"
	else
		info "Installing rbenv init in bashrc"
		echo 'eval "$(rbenv init -)"' >> "$HOME/.bashrc"
	fi
	init_rbenv
	if rbenv version | grep -Fq ".rbenv/version"; then
		green "rbenv successfully installed"
	else
		red "Something went wrong installing rbenv."
		red "rbenv does not appear to be a bash function"
		info "You might want to perform this step manually"
		type rbenv
		exit 1
	fi
	# resume EXIT trap
	trap cleanup EXIT

	if [ -d "$HOME/.rbenv/plugins/ruby-build" ]; then
		yellow "$HOME/.rbenv/plugins/ruby-build already exists!"
	else
		info "Installing ruby-build from GIT source"
		git clone https://github.com/rbenv/ruby-build.git $HOME/.rbenv/plugins/ruby-build
	fi

	if rbenv install -l | grep -Fq "$RUBY_VERSION"; then
		green "Ruby $RUBY_VERSION rbenv available for installation"
	fi

	if [ $(rbenv global) == "$RUBY_VERSION" ]; then
		yellow "Ruby $RUBY_VERSION already installed"
	else
		info "Installing ruby $RUBY_VERSION, please be patient, it's going to be a while..."
		rbenv install 2.5.1 -f $VERBOSE
		rbenv global 2.5.1
	fi

	if [[ $(ruby -v) == "ruby $RUBY_VERSION"* ]]; then
		green "$(ruby -v) installed successfully"
		info "It is recommended to logout and login again to activate .bashrc"
	fi
}

step_gems() {
	info "Installing generator dependencies"
	sudo apt install -y nodejs imagemagick libpq-dev
	init_rbenv
	info "Installing bundler"
	if [ -f "$HOME/.gemrc" ] ; then
		yellow "$HOME/.gemrc already created"
	else
		info "Creating $HOME/.gemrc"
		echo "gem: --no-document" > $HOME/.gemrc
	fi

	info "Installing bundler"
	gem install bundler
	gem update --system
	if [[ $(gem env home) == *".rbenv/versions/$RUBY_VERSION/lib/ruby/gems/"* ]]; then
		green "Gems environment installed successfully"
	else
		red "gem home failed! $(gem env home)!"
		exit 1
	fi
	info "Installing Decidim gem"
	gem install decidim
}

FOLDER=
CONF_SECRET=
CONF_DATABASE=
CONF_DB_USER=decidim_app
CONF_DB_PASS=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13 ; echo '')
CONF_DB_HOST=localhost
CONF_DB_NAME=decidim_prod
step_decidim() {
	if [ -z "$FOLDER" ]; then
		yellow "Please specify a folder to install decidim"
		info "Runt $0 with -h to view options for this script"
		exit 0
	fi
	init_rbenv
	green "Installing Decidim in $FOLDER"
	if [ -d "$FOLDER" ]; then
		yellow "$FOLDER already exists, trying to install gems anyway"
	else
		decidim "$FOLDER"
	fi

	cd $(realpath $FOLDER)

	if grep -Fq 'gem "figaro"' Gemfile ; then
		info "Gem figaro already installed"
	else
		bundle add figaro --skip-install
	fi
	if grep -Fq 'gem "passenger"' Gemfile ; then
		info "Gem passenger already installed"
	else
		bundle add passenger --group production --skip-install
	fi
	if grep -Fq 'gem "delayed_job_active_record"' Gemfile ; then
		info "Gem delayed_job_active_record already installed"
	else
		bundle add delayed_job_active_record --group production --skip-install
	fi
	if grep -Fq 'gem "daemons"' Gemfile ; then
		info "Gem daemons already installed"
	else
		bundle add daemons --group production --skip-install
	fi
	bundle install

	if [ -f "./config/application.yml" ]; then
		yellow "config/application.yml already present"
	else
		green "Creating config/application.yml with automatic values"
		touch ./config/application.yml
	fi

	if ! grep -Fq 'SECRET_KEY_BASE:' ./config/application.yml ; then
		echo "SECRET_KEY_BASE: $(rake secret)" >> ./config/application.yml
	fi
	CONF_SECRET=$(awk '/SECRET_KEY_BASE\:/{print $2}' config/application.yml)

	if ! grep -Fq 'DATABASE_URL:' ./config/application.yml ; then
		echo "DATABASE_URL: postgres://$CONF_DB_USER:$CONF_DB_PASS@$CONF_DB_HOST/$CONF_DB_NAME" >> ./config/application.yml
	fi
}

get_conf_vars() {
	if [ -z "$FOLDER" ]; then
		yellow "Please specify a folder to install decidim"
		info "Runt $0 with -h to view options for this script"
		exit 0
	fi
	init_rbenv
	cd $(realpath $FOLDER)

	CONF_DATABASE=$(awk '/DATABASE_URL\:/{print $2}' config/application.yml)
	re="postgres\:\/\/(.+):(.+)@(.+)/(.+)"
	if [[ "$CONF_DATABASE" =~ $re ]]; then
		CONF_DB_USER="${BASH_REMATCH[1]}";
		CONF_DB_PASS="${BASH_REMATCH[2]}";
		CONF_DB_HOST="${BASH_REMATCH[3]}";
		CONF_DB_NAME="${BASH_REMATCH[4]}";
	fi

	if [ -z "$CONF_DB_USER" ]; then
		red "Couldn't extract database user from config/application.yml!"
		exit 1
	fi
	if [ -z "$CONF_DB_PASS" ]; then
		red "Couldn't extract database password from config/application.yml!"
		exit 1
	fi
	if [ -z "$CONF_DB_HOST" ]; then
		red "Couldn't extract database host from config/application.yml!"
		exit 1
	fi
	if [ -z "$CONF_DB_NAME" ]; then
		red "Couldn't extract database name from config/application.yml!"
		exit 1
	fi
}

step_postgres() {
	get_conf_vars
	green "Installing PostgreSQL"
	sudo apt -y install postgresql

	if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$CONF_DB_USER'" | grep -q 1 ; then
		yellow "User $CONF_DB_USER already exists in postgresql"
	else
		info "Creating user $CONF_DB_USER"
		sudo -u postgres psql -c "CREATE USER $CONF_DB_USER WITH SUPERUSER CREATEDB NOCREATEROLE PASSWORD '$CONF_DB_PASS'"
	fi

}

STEPS=("check" "prepare" "rbenv" "gems" "decidim" "postgres")
SKIP=()
ONLY=()
install() {
	if [[ "${ONLY[@]}" ]]; then
		SKIP=()
		for step in "${STEPS[@]}"; do
			if [[ " ${ONLY[*]} " != *" $step "* ]]; then
				SKIP+=("$step")
			fi
		done
		echo ${SKIP[@]}
	fi
	for i in "${!STEPS[@]}"; do
		step=${STEPS[i]}
		if [[ " ${SKIP[*]} " == *" $step "* ]]; then
			red "Skipping step $i: $step"
		else
			yellow "Step $i: $step "
			"step_$step"
		fi
	done
}

start() {
	trap cleanup EXIT
	trap abort INT TERM
	install
}

confirm() {
	while true; do
	    read -p "Do you wish to continue? [y/N]" yn
	    case $yn in
	        [Yy]* ) start; break;;
	        [Nn]* ) exit;;
	        * ) abort;;
	    esac
	done
}

CONFIRM=1
while getopts yhvs:o: option; do
	case "${option}" in
		y ) yellow "No asking for confirmation"; CONFIRM=0;;
		h ) exit_help;;
		v ) VERBOSE="-v";;
		s ) SKIP+=("$OPTARG");;
		o ) ONLY+=("$OPTARG");;
	esac
done
shift $(($OPTIND - 1))
FOLDER="$1"

if [ "$CONFIRM" == "1" ]; then
	confirm
else
	start
fi
