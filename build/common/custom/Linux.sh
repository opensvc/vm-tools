#!/bin/bash

function install_golang
{
    version=${1:-1.26.0}
    url=https://dl.google.com/go/go${version}.linux-amd64.tar.gz

    echo "Installing golang $version"

    basedir=/root/god-$version
    [[ ! -d $basedir ]] && {
        echo mkdir $basedir
        mkdir $basedir || exit 1

    echo "download to $basedir: curl -s -o - $url | tar xzf -"
    cd $basedir && curl -s -o - $url | tar xzf - || exit 1

    echo "installing go and gofmt to /usr/bin"
    ln -sf $basedir/go/bin/go /usr/bin/go || exit 1
    ln -sf $basedir/go/bin/gofmt /usr/bin/gofmt || exit 1
    cd -
    }

    /usr/bin/go version
}

[[ -x /opt/archives/docker/docker.restore.sh ]] && {
	echo "Loading Docker/Podman images"
	/opt/archives/docker/docker.restore.sh
}

[[ ! -d /var/log/journal ]] && {
	echo "Enabling journald persistency"
        mkdir -p /var/log/journal
}

install_golang
