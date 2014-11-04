
PACKAGES?=base vim sudo git tmux
PACMAN_FLAGS?=--noconfirm --needed
USERS?=fauno matus
PACKAGES?=rsync git make ruby find

$(patsubst %,/usr/bin/%,$(PACKAGES)):
	pacman -Sy $(PACMAN_FLAGS) $@

/root/Repos:
	mkdir -p /root/Repos

# Carga un skel más seguro
/etc/skel/.ssh/authorized_keys: /root/Repos /usr/bin/rsync /usr/bin/make /usr/bin/git
	cd /root/Repos && git clone --branch=develop https://github.com/fauno/duraskel
	cd /root/Repos/duraskel && make install

# Paraboliza la instalación
# https://wiki.parabola.nu/Migration_From_Arch
/etc/parabolized: /usr/bin/sed
	sed "s/^SigLevel.*/#&\nSigLevel = Never/" -i /etc/pacman.conf
	pacman -U $(PACMAN_FLAGS) https://parabolagnulinux.org/packages/libre/any/parabola-keyring/download/
	pacman -U $(PACMAN_FLAGS) https://parabolagnulinux.org/packages/libre/any/pacman-mirrorlist/download/
	sed "/^SigLevel/d" -i /etc/pacman.conf
	rm -f /etc/pacman.d/mirrorlist /etc/pacman.conf
	mv /etc/pacman.d/mirrorlist{.pacnew,}
	mv /etc/pacman.conf{.pacnew,}
	echo -e "[pcr]\nInclude = /etc/pacman.d/mirrorlist" >>/etc/pacman.conf
	pacman -Scc $(PACMAN_FLAGS)
	pacman -Syy $(PACMAN_FLAGS)
	pacman -S $(PACMAN_FLAGS) pacman
	pacman -Suu $(PACMAN_FLAGS)
	pacman -S $(PACMAN_FLAGS) your-freedom
	date +%s >/etc/parabolized

# Crea los usuarios y les da acceso
$(USERS): /etc/skel/.ssh/authorized_keys
	getent passwd $@ || useradd -m -g users -G wheel $@
# Inseguridad
	echo "$@:cambiame" | chpasswd
# Seguridad
	cat ssh/$@.pub >/home/$@/.ssh/authorized_keys

# Crea todos los usuarios
users: PHONY $(USERS)

# Configura nginx
/etc/nginx/nginx.conf: /usr/bin/git /usr/bin/find
	pacman -Sy $(PACMAN_FLAGS) nginx-passenger
	rm -r /etc/nginx
	cd /etc && git clone https://github.com/fauno/nginx-config nginx
	rm -v /etc/nginx/sites/*.conf
# Seguridad
	chown -R root:root /etc/nginx
	find /etc/nginx -type d -exec chmod 750 {} \;
	find /etc/nginx -type f -exec chmod 640 {} \;

# Un shortcut para declarar reglas sin contraparte en el filesystem
PHONY:
.PHONY: PHONY
