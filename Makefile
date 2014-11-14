# La contraseña por defecto para nuevos piratas
PASSWORD=
GROUP=piratas
HOSTNAME=partidopirata.com.ar

APT_FLAGS?=--assume-yes
USERS?=fauno seykron aza
PACKAGES?=rsync git make ruby find postfix sed etckeeper haveged

# Ubicación de bundler
BUNDLER=/usr/local/bin/bundle
# Paquete de gnutls
GNUTLS=gnutls-bin

# Dónde están los backups
BACKUP_DIR=/home/fauno/threepwood

# Migración del correo
MAILDIRS=$(BACKUP_DIR)/var/vmail/partidopirata.com.ar
MAILUSERS=$(shell ls "$(MAILDIRS)")
MAILHOMES=$(patsubst %,/home/%/Maildir,$(MAILUSERS))

# Mailman
MAILMAN_DIR=/var/lib/mailman
MAILMAN_HOST=asambleas.partidopirata.com.ar

# Si postfix corre en una chroot
POSTFIX_PROXY=proxy:

# Reglas generales y de mantenimiento

## Crea todos los usuarios
users: PHONY $(USERS)

## Actualiza el sistema
upgrade: PHONY /usr/bin/etckeeper
	cd /etc && test -d .git || etckeeper init
	cd /etc && etckeeper commit "pre-upgrade"
	apt-get update $(APT_FLAGS)
	apt-get upgrade $(APT_FLAGS)

## Instala el servidor de correo
mail-server: PHONY /etc/postfix/master.cf /etc/postfix/main.cf /etc/dovecot/dovecot.conf

## Migra todos los correos
migrate-all-the-emails: PHONY $(MAILHOMES)

## Instala y migra mailman
mailman: PHONY /var/lib/mailman/archives/public/general
	newaliases
	service postfix restart
	service mailman restart

# ---

# Reglas por archivo
#
# El objetivo de cada regla es terminar con un archivo.  Si se vuelve a
# correr la regla pero el archivo existe, se la considera completa.
#
# Luego de cada regla se definen sus dependencias (otros archivos y sus
# procedimientos), por lo que se va armando un árbol de dependencias.
#
# Los objetivos "phony" se ejecutan siempre.  Tienen que ser los de más
# alto nivel porque si un archivo depende de un objetivo phony se va a
# ejecutar cada vez.
#
# En make, cada línea es un comando que se corre en una shell separada,
# por lo que no se mantiene el estado entre cada una (ni siquiera dentro
# de una misma regla).  Por eso si se ejecutan comandos en serie hay que
# encadenarlos con "&&" o "; \" donde "\" es el último carácter de la
# línea.

# Setear el hostname
/etc/hostname:
	echo $(HOSTNAME) >$@

# Instalar paquetes con ejecutables del mismo nombre
# La primera parte le agrega el path completo a cada uno de los binarios
# de PACKAGES, la segunda mantiene el nombre del paquete en la variable
# "$*"
$(patsubst %,/usr/bin/%,$(PACKAGES)): /usr/bin/%:
	apt-get install $(APT_FLAGS) $*

$(patsubst %,/usr/sbin/%,$(PACKAGES)): /usr/sbin/%:
	apt-get install $(APT_FLAGS) $*

/root/Repos:
	mkdir -p /root/Repos

$(BUNDLER):
	gem install --no-user-install bundler

# Carga un skel más seguro
/etc/skel/.ssh/authorized_keys: /root/Repos /usr/bin/rsync /usr/bin/make /usr/bin/git
	cd /root/Repos && test -d duraskel/.git || git clone --branch=develop https://github.com/fauno/duraskel
	cd /root/Repos/duraskel && make install

/etc/ssh/sshd_config:
	apt-get install $(APT_FLAGS) openssh-server openssh-client
	sed "s/^#\?\(PermitRootLogin\).*/\1 no/" -i $@
	sed "s/^#\?\(PasswordAuthentication\).*/\1 no/" -i $@
	sed "s/^#\?\(AllowAgentForwarding\).*/\1 yes/" -i $@
	sed "s/^#\?\(AllowGroups\).*/\1 users/" -i $@

# Habilita a los usuarios a loguearse como root forwardeando su llave
# privada con ssh-agent:
#
# ssh $(HOSTNAME)
# ssh root@$(HOSTNAME)
/root/.ssh/authorized_keys: /etc/ssh/sshd_config
	grep -q "^Match Host localhost$$" $< && \
		cat etc/ssh/only_root >>$<
	install -d -o root -g root -m 700 /root/.ssh
	cat ssh/*.pub >$@
	chmod 600 $@

# Crea los usuarios y les da acceso
$(USERS): /etc/skel/.ssh/authorized_keys
	getent passwd $@ || useradd -m -g users -G wheel $@
# Inseguridad
	echo "$@:cambiame" | chpasswd
# Seguridad
	cat ssh/$@.pub >/home/$@/.ssh/authorized_keys

# Configura nginx
/etc/nginx/nginx.conf: /usr/bin/git /usr/bin/find
	apt-get install $(APT_FLAGS) nginx-passenger
	rm -r /etc/nginx
	cd /etc && git clone https://github.com/fauno/nginx-config nginx
	rm -v /etc/nginx/sites/*.conf
# Seguridad
	chown -R root:root /etc/nginx
	find /etc/nginx -type d -exec chmod 750 {} \;
	find /etc/nginx -type f -exec chmod 640 {} \;

# Instala ssl.git para administrar los certificados
/etc/ssl/Makefile: $(BUNDLER) /usr/bin/git
	apt-get install $(APT_FLAGS) $(GNUTLS)
	cd /etc && git clone https://github.com/fauno/ssl ssl~
	cd /etc && mv ssl ssl~~ && mv ssl~ ssl
	cd /etc && cp ssl~~/certs/* ssl/certs/ || true
	cd /etc && cp ssl~~/private/* ssl/private/ || true
	rm -rf /etc/ssl~~
	chmod 755 /etc/ssl
	cd /etc/ssl && make ssl-dirs
	cd /etc/ssl && make create-groups GROUP=personas
	cd /etc/ssl && make ssl-dh-params

# Genera el certificado auto-firmado para este host
/etc/ssl/certs/$(HOSTNAME).crt: /etc/ssl/Makefile
	cd /etc/ssl && echo "$(HOSTNAME)" >domains
	cd /etc/ssl && make ssl-private-keys
	cd /etc/ssl && make ssl-self-signed-certs

# Configura postfix
/etc/postfix/main.cf: /etc/hostname /etc/ssl/certs/$(HOSTNAME).crt /usr/sbin/postfix
	apt-get install $(APT_FLAGS) postfix-pcre
	sed "s/@@DISTRO@@/$(GROUP)/g" /usr/share/postfix/main.cf.dist >$@
	gpasswd -a postfix keys
	postconf -e sendmail_path='/usr/sbin/sendmail'
	postconf -e newaliases_path='/usr/bin/newaliases'
	postconf -e mailq_path='/usr/bin/mailq'
	postconf -e setgid_group='postdrop'
	postconf -e manpage_directory='/usr/share/man'
	postconf -e sample_directory='/etc/postfix/sample'
	postconf -e readme_directory='/usr/share/doc/postfix'
	postconf -e html_directory='no'
	postconf -e soft_bounce='yes'
	postconf -e mydomain='$(HOSTNAME)'
	postconf -e mydestination='$$mydomain'
	postconf -e inet_interfaces='all'
	postconf -e 'local_recipient_maps = $(POSTFIX_PROXY)unix:passwd.byname $$alias_maps'
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

/etc/postfix/master.cf: PHONY /usr/sbin/postfix
	grep -qw "^tlsproxy" $@ || cat etc/postfix/master.d/tlsproxy.cf >>$@
	grep -qw "^submission" $@ || cat etc/postfix/master.d/submission.cf >>$@

# Instala y configura dovecot
#
# La autenticación es por los usuarios del sistema.  Cada usuario del
# sistema con login tiene una cuenta de correo.
/etc/dovecot/dovecot.conf: /etc/postfix/main.cf /etc/prosody/prosody.cfg.lua
	# servicios que se autentican en dovecot
	groupadd --system auth
	gpasswd -a postfix auth
	gpasswd -a prosody auth
	apt-get install $(APT_FLAGS) dovecot-imapd dovecot-pop3d dovecot-sieve dovecot-lmtpd
# Pisa la configuración del paquete con la nuestra
	rsync -av --delete-after etc/dovecot/ /etc/dovecot/
# Seguridad
	chown -R dovecot:dovecot /etc/dovecot
	find /etc/dovecot -type f -exec chmod 640 {} \;
	find /etc/dovecot -type d -exec chmod 750 {} \;
# Configura el hostname
	find /etc/dovecot -type f -print0 | xargs -0 sed -i "s/{{HOSTNAME}}/$(HOSTNAME)/g"
# Habilita postfix a autenticar usuarios en dovecot
	postconf -e smtpd_sasl_type='dovecot'
	postconf -e smtpd_sasl_path='private/auth'
	postconf -e smtpd_sasl_auth_enable='yes'
	postconf -e smtpd_sasl_security_options='noanonymous'
	postconf -e smtp_sasl_security_options='noanonymous'
	postconf -e broken_sasl_auth_clients='yes'
	postconf -e smtpd_sasl_local_domain='$$myhostname'

# Cada pirata tiene un maildir
/etc/skel/Maildir:
	install -dm 700 $@

# Migra los correos de cada usuario creándoles cuentas en el sistema con
# una contraseña por defecto
$(MAILHOMES): /home/%/Maildir: /etc/skel/Maildir
	@echo "Testeando que hayamos seteado PASSWORD y GROUP"
	test -n "$(PASSWORD)"
	test -n "$(GROUP)"
	getent group $(GROUP) || groupadd --system $(GROUP)
# Los piratas se crean sin acceso por shell aunque después se puede
# cambiar
	getent passwd $* || \
		useradd --home-dir /home/$* \
		        --create-home \
						--shell /bin/false \
						--gid $(GROUP) \
						$* && \
		echo "$*:$(PASSWORD)" | chpasswd
# Migra los correos
	rsync -av "$(MAILDIRS)/$*/" "$@/"
# Corrige permisos
# Los homes son solo accesibles para cada pirata
	chmod 700 /home/$*
# Los mails también
	find "$@" -type f -print0 | xargs -0 chmod 600
	find "$@" -type d -print0 | xargs -0 chmod 700
	chown -R $*:$(GROUP) "$@"

/etc/prosody/prosody.cfg.lua:
	apt-get install $(APT_FLAGS) prosody

# Instalar mailman
/var/lib/mailman: /etc/postfix/main.cf
	apt-get install $(APT_FLAGS) mailman
	cat "$(BACKUP_DIR)/usr/lib/mailman/Mailman/mm_cfg.py" >/etc/mailman/mm_cfg.py
	postconf -e relay_domains='$(MAILMAN_HOST)'
	postconf -e transport_maps='hash:/etc/postfix/transport'
	postconf -e mailman_destination_recipient_limit='1'
	postconf -e alias_maps='hash:/etc/aliases hash:/var/lib/mailman/data/aliases'
	grep -qw "^mailman" /etc/postfix/master.cf || cat etc/postfix/master.d/mailman.cf >>/etc/postfix/master.cf
	grep -qw "^$(MAILMAN_HOST)" /etc/postfix/transport || echo "$(MAILMAN_HOST)  mailman:" >>/etc/postfix/transport
	postmap /etc/postfix/transport

# Migrar el archivo de mailman
/var/lib/mailman/archives/public/general: /var/lib/mailman
	@echo "Testeando que MAILMAN_DIR no esté vacío"
	test -n "$(MAILMAN_DIR)"
	rsync -av "$(BACKUP_DIR)/$(MAILMAN_DIR)/" "$(MAILMAN_DIR)"
	chown -R list:list "$(MAILMAN_DIR)"

# Un shortcut para declarar reglas sin contraparte en el filesystem
# Nota: cada vez que se usa uno, todas las reglas que llaman a la regla
# phony se ejecutan siempre
PHONY:
.PHONY: PHONY
