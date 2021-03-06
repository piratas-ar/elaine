# Asegurarse que usemos bash para todo
SHELL=/bin/bash

# La contraseña por defecto para nuevos piratas
PASSWORD=
GROUP=piratas
HOSTNAME=partidopirata.com.ar

APT_FLAGS?=--assume-yes
USERS?=fauno seykron aza
# El grupo que tiene permisos en sudo
SUDO_GROUP=sudo
# Versión de ubuntu
UBUNTU=trusty
PACKAGES?=rsync git make ruby find postfix sed etckeeper haveged

# MySQL
# El comando para ejecutar consultas en mysql (sin contraseña)
MYSQL=mysql

# Ubicación de bundler
BUNDLER=/usr/local/bin/bundle
# Paquete de gnutls
GNUTLS=gnutls-bin

# Mailman
MAILMAN_DIR=/var/lib/mailman
MAILMAN_HOST=asambleas.partidopirata.com.ar

# Postfix
# Si postfix corre en una chroot
POSTFIX_PROXY=proxy:
# Chequeos antispam
POSTFIX_CHECKS=header body smtp_header
POSTFIX_CHECKS_FILES=$(patsubst %,/etc/postfix/%_checks,$(POSTFIX_CHECKS))

# Plugins de collectd
COLLECTD_PLUGINS=syslog cpu entropy interface load memory network uptime users
# La dirección IP y puerto del maestro de collectd, para el plugin
# network
COLLECTD_MASTER='"2001:1291:200:83ab:249a:2ef4:9cad:1d9e" "25826"'

# Filtros de mail
SIEVE_FILES=$(wildcard etc/dovecot/sieve/*.sieve) /etc/dovecot/conf.d/90-sieve.conf

# Reglas generales y de mantenimiento

## Crea una pirata
pirata: /home/$(PIRATA)

## Crea todos los usuarios
users: PHONY $(USERS)

## Actualiza el sistema
upgrade: PHONY /usr/bin/etckeeper
	cd /etc && test -d .git || etckeeper init
	cd /etc && etckeeper commit "pre-upgrade"
	apt-get update $(APT_FLAGS)
	apt-get upgrade $(APT_FLAGS)

## Instala el servidor de correo
mail-server: PHONY /etc/dovecot/dovecot.conf $(POSTFIX_CHECKS_FILES) /etc/postfix/virtual /etc/postfix-policyd-spf-python/policyd-spf.conf /etc/nginx/sites/autoconfig.$(HOSTNAME).conf

# Instala el servidor de correo con soporte para filtros
# Va aparte porque modifica la infraestructura de postfix+dovecot,
# haciendo que postfix entregue mail a dovecot en lugar de directamente
# al filesystem
mail-server-filters: PHONY mail-server $(SIEVE_FILES)
	sed "s/^protocols = .*/& lmtp/" -i /etc/dovecot/dovecot.conf
	sed "s/^\(auth_username_format = \).*/\1%%Ln/" -i /etc/dovecot/conf.d/10-auth.conf
	sed "s,unix_listener lmtp,unix_listener /var/spool/postfix/private/dovecot-lmtp," \
		-i /etc/dovecot/conf.d/10-master.conf
	postconf -e mailbox_transport='lmtp:unix:private/dovecot-lmtp'

## Instala mailman
mailman: PHONY /etc/default/fcgiwrap
	# los archivos en public son symlinks a private
	chmod o+x /var/lib/mailman/archives/private
	newaliases
	service postfix restart
	service mailman restart

# Instala el webmail
webmail: /etc/roundcube/main.inc.php /etc/sudoers.d/roundcube

# Instala jabber
jabber: /etc/prosody/conf.d/$(HOSTNAME).cfg.lua /etc/prosody/$(GROUP).txt

# Arregla las vulnerabilidades encontradas por https://weakdh.org/
weakdh:
	cd /etc/nginx ; git pull
# Asegurarse que tenga los cambios que queremos
	grep -q ssl_dhparam /etc/nginx/nginx.conf
# Seguridad
	chown -R root:root /etc/nginx
	find /etc/nginx -type d -exec chmod 750 {} \;
	find /etc/nginx -type f -exec chmod 640 {} \;
# Dovecot
	sed "s/{{HOSTNAME}}/$(HOSTNAME)/g" etc/dovecot/conf.d/10-ssl.conf >/etc/dovecot/conf.d/10-ssl.conf
# Postfix
	postconf -e smtpd_tls_exclude_ciphers='aNULL, MD5, DES, 3DES, DES-CBC3-SHA, RC4-SHA, AES256-SHA, AES128-SHA, eNULL, EXPORT, RC4, PSK, aECDH, EDH-DSS-DES-CBC3-SHA, EDH-RSA-DES-CDC3-SHA, KRB5-DE5, CBC3-SHA'
# Reiniciar todo
	service postfix reload
	service nginx reload
	service dovecot restart
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

/home/$(PIRATA): /home/%:
	@echo "Testeando que hayamos seteado PIRATA, PASSWORD y GROUP"
	test -n "$(PIRATA)"
	test -n "$(PASSWORD)"
	test -n "$(GROUP)"
	getent group $(GROUP) || groupadd --system $(GROUP)
# Los piratas se crean sin acceso por shell aunque después se puede
# cambiar
	getent passwd $* || \
		useradd --home-dir $@ \
		        --create-home \
						--shell /bin/false \
						--gid $(GROUP) \
						$* && \
		echo "$*:$(PASSWORD)" | chpasswd
# Los homes son solo accesibles para cada pirata
	chmod 700 $@

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

/etc/ssh/sshd_config: PHONY
	apt-get install $(APT_FLAGS) openssh-server openssh-client
	sed "s/^#\?\(PermitRootLogin\).*/\1 no/" -i $@
	sed "s/^#\?\(PermitEmptyPasswords\).*/\1 no/" -i $@
	sed "s/^#\?\(PasswordAuthentication\).*/\1 no/" -i $@
	sed "s/^#\?\(AllowAgentForwarding\).*/\1 yes/" -i $@
	grep -q "AllowGroups $(GROUP)" $@ || echo "AllowGroups $(GROUP)" >>$@

# Habilita a los usuarios a loguearse como root forwardeando su llave
# privada con ssh-agent:
#
# ssh $(HOSTNAME)
# ssh root@$(HOSTNAME)
/root/.ssh/authorized_keys: /etc/ssh/sshd_config
	grep -q "^Match Host localhost$$" $< || \
		sed "s/{{SUDO_GROUP}}/$(SUDO_GROUP)/g" etc/ssh/only_root >>$<
	install -d -o root -g root -m 700 /root/.ssh
	cat ssh/*.pub >$@
	chmod 600 $@

# Crea los usuarios y les da acceso
$(USERS): /etc/skel/.ssh/authorized_keys
	getent group $(GROUP) || groupadd --system $(GROUP)
	getent passwd $@ || useradd -m -g $(GROUP) -G $(SUDO_GROUP) $@
	getent passwd $@ && gpasswd -a $@ $(SUDO_GROUP)
	getent passwd $@ && chsh --shell /bin/bash $@
# Inseguridad
	echo "$@:cambiame" | chpasswd
# Seguridad
	test -f ssh/$@.pub && cat ssh/$@.pub >/home/$@/.ssh/authorized_keys

# Configura nginx
/etc/nginx/sites/$(HOSTNAME).conf: /usr/bin/git /usr/bin/find /etc/apt/sources.list.d/passenger.list
	apt-get install $(APT_FLAGS) nginx-extras passenger
	@echo "Los archivos anteriores de nginx quedan en /etc/nginx~"
	@mv /etc/nginx /etc/nginx~
	cd /etc && git clone https://github.com/fauno/nginx-config nginx
# Eliminar todos los sitios menos el pseudo sitio zz_nowww que es útil
	rm -v /etc/nginx/sites/!(zz_nowww).conf
# Seguridad
	chown -R root:root /etc/nginx
	find /etc/nginx -type d -exec chmod 750 {} \;
	find /etc/nginx -type f -exec chmod 640 {} \;
	touch $@

# Instala ssl.git para administrar los certificados
/etc/ssl/Makefile: $(BUNDLER) /usr/bin/git
	apt-get install $(APT_FLAGS) $(GNUTLS)
	cd /etc && git clone https://github.com/fauno/ssl ssl~
	cd /etc && mv ssl ssl~~ && mv ssl~ ssl
	cd /etc && cp -a ssl~~/certs/* ssl/certs/ || true
	cd /etc && cp -a ssl~~/private/* ssl/private/ || true
	rm -rf /etc/ssl~~
	chmod 755 /etc/ssl
	cd /etc/ssl && make ssl-dirs
	cd /etc/ssl && make create-groups GROUP=personas
	cd /etc/ssl && make ssl-dh-params
	update-ca-certificates

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
	postconf -e recipient_delimiter='+'
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
	postconf -e smtpd_tls_exclude_ciphers='aNULL, MD5, DES, 3DES, DES-CBC3-SHA, RC4-SHA, AES256-SHA, AES128-SHA, eNULL, EXPORT, RC4, PSK, aECDH, EDH-DSS-DES-CBC3-SHA, EDH-RSA-DES-CDC3-SHA, KRB5-DE5, CBC3-SHA'
	postconf -e smtpd_tls_mandatory_protocols='TLSv1'
	postconf -e smtp_tls_ciphers='$$smtpd_tls_ciphers'
	postconf -e smtp_tls_mandatory_ciphers='$$smtpd_tls_mandatory_ciphers'
	postconf -e smtp_tls_protocols='!SSLv2, !SSLv3, TLSv1'
	postconf -e smtpd_tls_loglevel='0'
	postconf -e smtpd_tls_received_header='yes'
	postconf -e smtpd_tls_session_cache_timeout='3600s'

# Configura master.cf
# ATENCION es un target phony porque master.cf siempre existe
/etc/postfix/master.cf: PHONY /usr/sbin/postfix
	grep -qw "^tlsproxy" $@ || cat etc/postfix/master.d/tlsproxy.cf >>$@
	grep -qw "^submission" $@ || cat etc/postfix/master.d/submission.cf >>$@
	# para que postscreen funcione hay que comentar este
	sed "s/^smtp .* smtpd/#&/" -i $@
	grep -q "^smtp .* postscreen$$" $@ || cat etc/postfix/master.d/postscreen.cf >>$@

# Chequeos de postfix que nos ahorran un montón de spam
$(POSTFIX_CHECKS_FILES): /etc/postfix/%: /etc/postfix/main.cf
	postconf -e $*='pcre:$@'
	cat etc/postfix/$* >$@

# Inicia la base de datos de direcciones virtuales
/etc/postfix/virtual: /etc/postfix/main.cf
	touch $@
	postmap $@
	postconf -e virtual_alias_maps='hash:$@'

# Chequea SPF
/etc/postfix-policyd-spf-python/policyd-spf.conf: /etc/postfix/main.cf
	apt-get install $(APT_FLAGS) postfix-policyd-spf-python
	postconf -e smtpd_recipient_restrictions='$(shell postconf smtpd_recipient_restrictions | cut -d"=" -f2), check_policy_service unix:private/policyd-spf'
	postconf -e policyd-spf_time_limit='3600s'
	grep -q "^policyd-spf" /etc/postfix/master.cf || \
		cat etc/postfix/master.d/policyd-spf.cf >>/etc/postfix/master.cf

# Instala y configura dovecot
#
# La autenticación es por los usuarios del sistema.  Cada usuario del
# sistema con login tiene una cuenta de correo.
/etc/dovecot/dovecot.conf: /etc/postfix/main.cf /etc/prosody/prosody.cfg.lua
	# servicios que se autentican en dovecot
	getent group auth || groupadd --system auth
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
# Solo los piratas pueden loguearse en dovecot
	grep -q "pam_succeed_if\.so" /etc/pam.d/dovecot || \
		sed '2s/^/auth required pam_succeed_if.so user ingroup $(GROUP)\n&/' -i /etc/pam.d/dovecot
	
# Instala los archivos de sieve si estaban perdidos
$(SIEVE_FILES):
	install -Dm640 --owner dovecot --group dovecot $@ /$@

# Cada pirata tiene un maildir
/etc/skel/Maildir:
	install -dm 700 $@

# Prosody
/etc/prosody/prosody.cfg.lua:
	apt-get install $(APT_FLAGS) prosody
	gpasswd -a prosody keys

/usr/lib/prosody/modules/mod_auth_dovecot.lua: /etc/prosody/prosody.cfg.lua
	apt-get install $(APT_FLAGS) lua-dbi-mysql lua-sec mercurial
	cd /etc/prosody && hg clone http://prosody-modules.googlecode.com/hg/ modules
	apt-get purge $(APT_FLAGS) mercurial
	chown -R prosody:prosody /etc/prosody/modules
	ln -s /etc/prosody/modules/mod_auth_dovecot/*.lua /usr/lib/prosody/modules/

/etc/prosody/conf.d/$(HOSTNAME).cfg.lua: /usr/lib/prosody/modules/mod_auth_dovecot.lua
	@echo "Testeando que hayamos seteado PASSWORD y GROUP"
	test -n "$(PASSWORD)"
	test -n "$(GROUP)"
	sed -e "s/{{HOSTNAME}}/$(HOSTNAME)/g" \
	    -e "s/{{GROUP}}/$(GROUP)/g" \
			-e "s/{{PASSWORD}}/$(PASSWORD)/g" \
			etc/prosody/conf.d/hostname.cfg.lua >$@
	chown prosody:prosody $@
	chmod 640 $@
	echo "create database prosody; grant all privileges on prosody.* to 'prosody' identified by '$(PASSWORD)'; flush privileges;" | $(MYSQL)

# Script que actualiza el group_file
/etc/cron.daily/update_prosody_groups: /%:
	apt-get install $(APT_FLAGS) libuser
	install -Dm750 $* $@
	sed -e "s/{{HOSTNAME}}/$(HOSTNAME)/g" \
	    -e "s/{{GROUP}}/$(GROUP)/g" \
			$* >$@

/etc/prosody/$(GROUP).txt: /etc/prosody/prosody.cfg.lua /etc/cron.daily/update_prosody_groups
	touch $@
	chmod 640 $@
	chown prosody:prosody $@
	/etc/cron.daily/update_prosody_groups

# Instalar mailman
/var/lib/mailman: /etc/postfix/main.cf
	cat "$(BACKUP_DIR)/usr/lib/mailman/Mailman/mm_cfg.py" >/etc/mailman/mm_cfg.py
	postconf -e relay_domains='$(MAILMAN_HOST)'
	postconf -e transport_maps='hash:/etc/postfix/transport'
	postconf -e mailman_destination_recipient_limit='1'
	postconf -e alias_maps='hash:/etc/aliases hash:/var/lib/mailman/data/aliases'
	grep -qw "^mailman" /etc/postfix/master.cf || cat etc/postfix/master.d/mailman.cf >>/etc/postfix/master.cf
	grep -qw "^$(MAILMAN_HOST)" /etc/postfix/transport || echo "$(MAILMAN_HOST)  mailman:" >>/etc/postfix/transport
	postmap /etc/postfix/transport

# Nginx-Passenger para ubuntu
/etc/apt/sources.list.d/passenger.list:
	echo "deb https://oss-binaries.phusionpassenger.com/apt/passenger $(UBUNTU) main" >$@
	chmod 600 $@
	chown root:root $@
	apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 561F9B9CAC40B2F7
	apt-get update $(APT_FLAGS)

# Instalar PHP-FPM
/etc/php5/fpm/php.ini:
	apt-get install $(APT_FLAGS) php5-fpm php5-mysql
	find /etc/php5 -type f -print0 | \
		xargs -0 sed -i "s/www-data/http/g"
	
/etc/default/fcgiwrap:
	echo "FCGI_CHILDREN=1" >$@
	echo "FCGI_SOCKET=/var/run/fcgiwrap.sock" >>$@
	echo "FCGI_USER=http" >>$@
	echo "FCGI_GROUP=www-data" >>$@
	echo "FCGI_SOCKET_OWNER=http" >>$@
	echo "FCGI_SOCKET_GROUP=http" >>$@

/etc/collectd/collectd.conf:
	apt-get install $(APT_FLAGS) collectd-core
	for plugin in $(COLLECTD_PLUGINS); do \
		echo "LoadPlugin $$plugin" >>$@ ;\
	done
	test -n "$(COLLECTD_MASTER)" && \
	echo '<Plugin network>Server $(COLLECTD_MASTER)</Plugin>' >>$@

/etc/php5/fpm/conf.d/mcrypt.ini:
	ln -s /etc/php5/mods-available/mcrypt.ini $@

# Generar la cadena de cifrado de contraseñas
des_key=$(shell dd if=/dev/urandom bs=24 count=1 2>/dev/null| base64 -w 23 | head -n1)
# Instalar y configurar roundcube
/etc/roundcube/main.inc.php: /etc/php5/fpm/conf.d/mcrypt.ini
	# php5 evita que se instale apache
	apt-get install $(APT_FLAGS) php5 roundcube rouncube-plugins roundcube-plugins-extra
	chown -R http:http /var/lib/roundcube/temp /var/log/roundcube
	chown root:http /etc/roundcube/*.php
	sed "s/{{HOSTNAME}}/$(HOSTNAME)/g" etc/roundcube/main.inc.php >>$@
	echo "$$rcmail_config['des_key'] = '$(des_key)';" >>$@

# Permite a los piratas cambiar sus contraseñas desde el webmail
/etc/sudoers.d/roundcube:
	cat etc/sudoers.d/roundcube >$@
	chmod +x /usr/share/doc/roundcube-plugins/examples/chpass-wrapper.py
	cat etc/roundcube/passwd.inc.php >>/etc/roundcube/main.inc.php

# Autoconfiguración de Thunderbird
/etc/nginx/sites/autoconfig.$(HOSTNAME).conf:
	echo "server {\n  server_name autoconfig.$(HOSTNAME);\n}" >$@

/srv/http/autoconfig.$(HOSTNAME)/mail/config-v1.1.xml: %/config-v1.1.xml: /etc/nginx/sites/autoconfig.$(HOSTNAME).conf
	install --directory --mode 750 --group http --owner nobody $*
	sed -e "s/{{HOSTNAME}}/$(HOSTNAME)/g" \
	    -e "s/{{GROUP}}/$(GROUP)/g" \
			config-v1.1.xml >$@
	chown nobody:http $@
	chmod 640 $@

# Un shortcut para declarar reglas sin contraparte en el filesystem
# Nota: cada vez que se usa uno, todas las reglas que llaman a la regla
# phony se ejecutan siempre
PHONY:
.PHONY: PHONY
