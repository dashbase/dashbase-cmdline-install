#!/bin/sh
set -e

# This script is meant for quick & easy install via:
#   $ curl -fsSL get.dashbase.io -o get_dashbase-cli.sh
#   $ sh get_dashbase-cli.sh
#
# NOTE: Make sure to verify the contents of the script
#       you downloaded matches the contents of install.sh
#       located at https://github.com/dashbase/dashbase-cmdline-install
#       before executing.
#
# Git commit from https://github.com/dashbase/dashbase-cmdline-install when
# the script was uploaded (Should only be modified by upload job):
SCRIPT_COMMIT_SHA=ce36df53ccfc4e8c5eb41b858225b7eac25a59a7

command_exists() {
	command -v "$@" > /dev/null 2>&1
}

get_distribution() {
	lsb_dist=""
	# Every system that we officially support has /etc/os-release
	if [ -r /etc/os-release ]; then
		lsb_dist="$(. /etc/os-release && echo "$ID")"
	fi
	# Returning an empty string here should be alright since the
	# case statements don't act unless you provide an actual value
	echo "$lsb_dist"
}

# Check if this is a forked Linux distro
check_forked() {

	# Check for lsb_release command existence, it usually exists in forked distros
	if command_exists lsb_release; then
		# Check if the `-u` option is supported
		set +e
		lsb_release -a -u > /dev/null 2>&1
		lsb_release_exit_code=$?
		set -e

		# Check if the command has exited successfully, it means we're in a forked distro
		if [ "$lsb_release_exit_code" = "0" ]; then
			# Print info about current distro
			cat <<-EOF
			You're using '$lsb_dist' version '$dist_version'.
			EOF

			# Get the upstream release info
			lsb_dist=$(lsb_release -a -u 2>&1 | tr '[:upper:]' '[:lower:]' | grep -E 'id' | cut -d ':' -f 2 | tr -d '[:space:]')
			dist_version=$(lsb_release -a -u 2>&1 | tr '[:upper:]' '[:lower:]' | grep -E 'codename' | cut -d ':' -f 2 | tr -d '[:space:]')

			# Print info about upstream distro
			cat <<-EOF
			Upstream release is '$lsb_dist' version '$dist_version'.
			EOF
		else
			if [ -r /etc/debian_version ] && [ "$lsb_dist" != "ubuntu" ] && [ "$lsb_dist" != "raspbian" ]; then
				# We're Debian and don't even know it!
				lsb_dist=debian
				dist_version="$(sed 's/\/.*//' /etc/debian_version | sed 's/\..*//')"
				case "$dist_version" in
					9)
						dist_version="stretch"
					;;
					8|'Kali Linux 2')
						dist_version="jessie"
					;;
					7)
						dist_version="wheezy"
					;;
				esac
			fi
		fi
	fi
}

do_install() {
	echo "Executing dashbase-cli install script, commit: $SCRIPT_COMMIT_SHA"
	# TODO: Move this to after we figure out the distribution and the version
	#       to check whether or not we support that distro-version on that arch
	architecture=$(uname -m)
	case $architecture in
		# supported
		amd64|x86_64)
			;;
		# not supported
		*)
			cat >&2 <<-EOF
			Error: $architecture is not supported.
			EOF
			exit 1
			;;
	esac

	if command_exists dashbase-cli; then
		cat >&2 <<-'EOF'
			Warning: the "dashbase-cli" command appears to already exist on this system.

			If you already have dashbase-cli installed, this script can cause trouble, which is
			why we're displaying this warning.

			If you want to upgrade "dashbase-cli" you can use "(sudo) pip install dashbase --upgrade"
		EOF
		exit 0
	fi

	user="$(id -un 2>/dev/null || true)"

	sh_c='sh -c'
	if [ "$user" != 'root' ]; then
		if command_exists sudo; then
			sh_c='sudo -E sh -c'
		elif command_exists su; then
			sh_c='su -c'
		else
			cat >&2 <<-'EOF'
			Error: this installer needs the ability to run commands as root.
			We are unable to find either "sudo" or "su" available to make this happen.
			EOF
			exit 1
		fi
	fi

	curl=''
	if command_exists curl; then
		curl='curl -sSL'
	elif command_exists wget; then
		curl='wget -qO-'
	elif command_exists busybox && busybox --list-modules | grep -q wget; then
		curl='busybox wget -qO-'
	fi

	# perform some very rudimentary platform detection
	lsb_dist=$( get_distribution )
	lsb_dist="$(echo "$lsb_dist" | tr '[:upper:]' '[:lower:]')"

	case "$lsb_dist" in
		ubuntu)
			if command_exists lsb_release; then
				dist_version="$(lsb_release --codename | cut -f2)"
			fi
			if [ -z "$dist_version" ] && [ -r /etc/lsb-release ]; then
				dist_version="$(. /etc/lsb-release && echo "$DISTRIB_CODENAME")"
			fi
		;;

		debian|raspbian)
			dist_version="$(sed 's/\/.*//' /etc/debian_version | sed 's/\..*//')"
			case "$dist_version" in
				9)
					dist_version="stretch"
				;;
				8)
					dist_version="jessie"
				;;
				7)
					dist_version="wheezy"
				;;
			esac
		;;

		*)
			if command_exists lsb_release; then
				dist_version="$(lsb_release --codename | cut -f2)"
			fi
			if [ -z "$dist_version" ] && [ -r /etc/os-release ]; then
				dist_version="$(. /etc/os-release && echo "$VERSION_ID")"
			fi
		;;

	esac

	# Check if this is a forked Linux distro
	check_forked

	# Run setup for each distro accordingly
	install_python() {
	    curl -L https://raw.githubusercontent.com/pyenv/pyenv-installer/master/bin/pyenv-installer | bash
	    echo 'export PATH="$HOME/.pyenv/bin:$PATH"' >> ${bashfile}
        echo 'eval "$(pyenv init -)"' >> ${bashfile}
        echo 'eval "$(pyenv virtualenv-init -)"' >> ${bashfile}
        export PATH="$HOME/.pyenv/bin:$PATH"
        eval "$(pyenv init -)"
        eval "$(pyenv virtualenv-init -)"
        pyenv install 2.7.13
        pyenv global 2.7.13
        echo "Change python version to 2.7.13"
        echo "You can change back using 'pyenv global system'."
	}
    install_dashbase_cli() {
        # if don't specify version will have problem on some release
        python -m pip install dashbase==1.0.0rc8.post3
    }
    bashfile=$HOME/.bashrc
    if [ ! -f ${bashfile} ]; then
        bashfile=$HOME/.bash_profile
    fi
	case "$lsb_dist" in
		ubuntu|debian)
			pre_reqs="apt-transport-https ca-certificates curl"
			if [ "$lsb_dist" = "debian" ] && [ "$dist_version" = "wheezy" ]; then
				pre_reqs="$pre_reqs python-software-properties"
				backports="deb http://ftp.debian.org/debian wheezy-backports main"
				if ! grep -Fxq "$backports" /etc/apt/sources.list; then
					(set -x; $sh_c "echo \"$backports\" >> /etc/apt/sources.list")
				fi
			else
				pre_reqs="$pre_reqs software-properties-common"
			fi
			if ! command -v gpg > /dev/null; then
				pre_reqs="$pre_reqs gnupg"
			fi
			(
                set -x
                $sh_c 'apt-get update'
                $sh_c "apt-get install -y -q $pre_reqs"
                $sh_c 'apt-get update'
                $sh_c 'apt-get install -y software-properties-common'
                if [ "$lsb_dist" = "debian" ] && [ "$dist_version" = "jessie" ]; then
				    $sh_c 'echo "deb http://http.debian.net/debian jessie-backports main" > /etc/apt/sources.list.d/jessie-backports.list'
				    $sh_c 'apt-get update'
				    $sh_c 'apt-get install -y -t jessie-backports ca-certificates-java'
                fi
                $sh_c 'apt-get install -y build-essential libssl-dev openjdk-8-jre-headless libffi-dev gcc g++ wget curl git'
                install_python
                install_dashbase_cli
                echo "We have changed python version to 2.7.13"
                echo "You can change back using 'pyenv global system'."
		echo "Please refresh your env using 'source ~/.bashrc' before using dashbase-cli."
			)
			exit 0
			;;
		centos|amzn|rhel|fedora)
			if [ "$lsb_dist" = "fedora" ]; then
				if [ "$dist_version" -lt "24" ]; then
					echo "Error: Only Fedora >=24 are supported"
					exit 1
				fi
				pkg_manager="dnf"
				config_manager="dnf config-manager"
				enable_channel_flag="--set-enabled"
				pre_reqs="dnf-plugins-core"
			else
				pkg_manager="yum"
				config_manager="yum-config-manager"
				enable_channel_flag="--enable"
				pre_reqs="yum-utils"
			fi
			(
				set -x
				$sh_c "$pkg_manager -y update"
				$sh_c "$pkg_manager install -y -q $pre_reqs"
				$sh_c "$pkg_manager -y install gcc gcc-c++ kernel-devel libxslt-devel libffi-devel openssl-devel java-1.8.0-openjdk wget curl git"
				install_python
				install_dashbase_cli
				echo "We have changed python version to 2.7.13"
                echo "You can change back using 'pyenv global system'."
		                if [ "$lsb_dist" = "amzn" ]; then
				    $sh_c 'update-alternatives --set java /usr/lib/jvm/jre-1.8.0-openjdk.x86_64/bin/java'
				fi
				echo "Please refresh your env using 'source ~/.bashrc' before using dashbase-cli."
			)
			exit 0
			;;
	esac

	# intentionally mixed spaces and tabs here -- tabs are stripped by "<<-'EOF'", spaces are kept in the output
	cat >&2 <<-'EOF'

	Either your platform is not easily detectable or is not supported by this
	installer script.
	Please visit the following URL for more detailed installation instructions:

	https://www.dashbase.io/

	EOF
	exit 1
}

# wrapped up in a function so that we have some protection against only getting
# half the file during "curl | sh"
do_install
