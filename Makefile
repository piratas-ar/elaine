
PACKAGES?=base vim sudo git tmux
PACMAN_FLAGS?=--noconfirm --needed

/usr/bin/rsync:
	pacman -Sy $(PACMAN_FLAGS) rsync

/root/Repos:
	mkdir -p /root/Repos

# Carga un skel más seguro
/etc/skel/.ssh/authorized_keys: /root/Repos /usr/bin/rsync
	cd /root/Repos && git clone --branch=develop https://github.com/fauno/duraskel
	cd /root/Repos/duraskel && make install
