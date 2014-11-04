
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

/etc/parabolized:
	sed "s/^SigLevel.*/#&\nSigLevel = Never/" -i /etc/pacman.conf
	pacman -U $(PACMAN_FLAGS) https://parabolagnulinux.org/packages/libre/any/parabola-keyring/download/
	pacman -U $(PACMAN_FLAGS) https://parabolagnulinux.org/packages/libre/any/pacman-mirrorlist/download/
	sed "/^SigLevel/d" -i /etc/pacman.conf
	sed "s/^#SigLevel/SigLevel/" -i /etc/pacman.conf
	sed "s,\[core\],[libre]\nInclude = /etc/pacman.d/mirrorlist\n\n&," -i /etc/pacman.conf
	rm -f /etc/pacman.d/mirrorlist
	mv /etc/pacman.d/mirrorlist{.pacnew,}
	pacman -Scc $(PACMAN_FLAGS)
	pacman -Syy $(PACMAN_FLAGS)
	pacman -S $(PACMAN_FLAGS) pacman
	pacman -Suu $(PACMAN_FLAGS)
	pacman -S $(PACMAN_FLAGS) your-freedom
	date +%s >/etc/parabolized
