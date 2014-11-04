HOSTNAME=printdustry.com

PACMAN_FLAGS?=--noconfirm --needed
USERS?=fauno matus
PACKAGES?=rsync git make ruby find postfix sed etckeeper

# Reglas generales

## Crea todos los usuarios
users: PHONY $(USERS)

## Actualiza el sistema
upgrade: PHONY /usr/bin/etckeeper
	cd /etc && test -d .git || etckeeper init
	cd /etc && etckeeper commit "pre-upgrade"
	pacman -Syu $(PACMAN_FLAGS)

## Instala el servidor de correo
mail-server: PHONY /etc/postfix/main.cf

## Actualizar pacnew
# FIXME se rompe la salida de la terminal y hay que resetear
pacnew: PHONY 
	find /etc -name '*.pacnew' | while read f; do \
		vimdiff "$${f%%.pacnew}" "$$f" ;\
		rm -f "$$f" ;\
	done
	cd /etc && etckeeper commit "upgrade-pacnew"

# ---

# Setear el hostname
/etc/hostname:
	echo $(HOSTNAME) >$@

# Instalar paquetes con ejecutables del mismo nombre
$(patsubst %,/usr/bin/%,$(PACKAGES)): /usr/bin/%:
	pacman -Sy $(PACMAN_FLAGS) $*

/root/Repos:
	mkdir -p /root/Repos

/usr/bin/bundle:
	gem install --no-user-install bundler

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

# Instala ssl.git para administrar los certificados
/etc/ssl/Makefile: /usr/bin/bundle /usr/bin/git
	pacman -Sy $(PACMAN_FLAGS) gnutls
	cd /etc && git clone https://github.com/fauno/ssl ssl~
	cd /etc && mv ssl{,~~} && mv ssl{~,}
	cd /etc && cp ssl~~/certs/* ssl/certs/ || true
	cd /etc && cp ssl~~/private/* ssl/private/ || true
	rm -rf /etc/ssl~~

# Genera el certificado auto-firmado para este host
/etc/ssl/certs/$(HOSTNAME).crt: /etc/ssl/Makefile
	cd /etc/ssl && echo "$(HOSTNAME)" >domains
	cd /etc/ssl && make create-groups GROUP=personas
	cd /etc/ssl && make ssl-private-keys
	cd /etc/ssl && make ssl-self-signed-certs

# Configura postfix
/etc/postfix/main.cf: /etc/hostname /etc/ssl/certs/$(HOSTNAME).crt /usr/bin/postfix
	gpasswd -a postfix keys
	postconf -e mydomain='printdustry.com'
	postconf -e inet_interfaces='all'
	postconf -e 'local_recipient_maps = unix:passwd.byname $$alias_maps'
	postconf -e mynetworks_style='host'
	postconf -e home_mailbox='Maildir/'
	postconf -e inet_protocols='all'
# Seguridad
## Spam
	postconf -e smtpd_helo_restrictions='permit_mynetworks,permit_sasl_authenticated,reject_non_fqdn_helo_hostname,reject_invalid_helo_hostname,permit'
	postconf -e smtpd_recipient_restrictions='reject_non_fqdn_recipient,reject_unknown_recipient_domain,permit_mynetworks,permit_sasl_authenticated,reject_unauth_destination,reject_non_fqdn_sender,reject_unlisted_recipient'
	postconf -e smtpd_sender_restrictions='permit_mynetworks,permit_sasl_authenticated,reject_non_fqdn_sender,reject_unknown_sender_domain,permit'
	postconf -e smtpd_data_restrictions='reject_unauth_pipelining'
	postconf -e smtpd_client_restrictions='permit_mynetworks,permit_sasl_authenticated'
	postconf -e smtpd_relay_restrictions='permit_mynetworks,permit_sasl_authenticated,reject_unauth_destination'
## Usar TLS
	postconf -e smtpd_use_tls='yes'
	postconf -e smtpd_tls_auth_only='yes'
	postconf -e smtp_use_tls='yes'
	postconf -e smtp_tls_note_starttls_offer='yes'
## Crypto
	postconf -e smtpd_tls_CApath='/etc/ssl/certs'
	postconf -e smtpd_tls_key_file='/etc/ssl/private/$(HOSTNAME).key'
	postconf -e smtpd_tls_cert_file='/etc/ssl/certs/$(HOSTNAME).crt'
	postconf -e tls_random_source='dev:/dev/urandom'
## Diffie-Hellman
## DH en postfix: http://postfix.1071664.n5.nabble.com/Diffie-Hellman-parameters-td63096.html
	postconf -e smtpd_tls_dh1024_param_file='/etc/ssl/private/2048.dh'
	postconf -e smtpd_tls_dh512_param_file='/etc/ssl/private/512.dh'
## Preferir nuestros ciphers antes que los del cliente
	postconf -e tls_preempt_cipherlist='yes'
## Esto significa que no todos los mails van a intercambiarse por TLS, por lo
## que puede haber un ataque de degradación. Sin embargo nos quedamos sin hablar
## con servers que no tienen TLS habilitado.
	postconf -e smtpd_tls_security_level='may'
## Criptografía fuerte
	postconf -e smtpd_tls_eecdh_grade='strong'
	postconf -e smtpd_tls_mandatory_ciphers='high'
	postconf -e smtpd_tls_ciphers='medium'
## Excluir ciphers inseguros
	postconf -e smtpd_tls_exclude_ciphers='aNULL, MD5, DES, 3DES, DES-CBC3-SHA, RC4-SHA, AES256-SHA, AES128-SHA'
	postconf -e smtpd_tls_mandatory_protocols='TLSv1'
	postconf -e smtp_tls_ciphers='$$smtpd_tls_ciphers'
	postconf -e smtp_tls_mandatory_ciphers='$$smtpd_tls_mandatory_ciphers'
	postconf -e smtp_tls_protocols='!SSLv2, !SSLv3, TLSv1'
	postconf -e smtpd_tls_loglevel='0'
	postconf -e smtpd_tls_received_header='yes'
	postconf -e smtpd_tls_session_cache_timeout='3600s'
	systemctl enable postfix

# Un shortcut para declarar reglas sin contraparte en el filesystem
# Nota: cada vez que se usa uno, todas las reglas que llaman a la regla
# phony se ejecutan siempre
PHONY:
.PHONY: PHONY
