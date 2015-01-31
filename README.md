# Elaine

Elaine es un nodo pirata con las siguientes características:

* SMTP seguro. Postfix con TLS.  Filtros antispam livianos, sin análisis
  estadístico de contenido.
* IMAP seguro y autoorganizado.  Dovecot con TLS y filtros de
  autorganización de correo.  Por cada lista o etiqueta agregada a la
  dirección de correo (pirata+etiqueta@elaine), se crea una bandeja
  nueva.
* Webmail.  Roundcube.
* Listas de correo.  Mailman.
* HTTP seguro.  Nginx con TLS, PHP5 y Passenger (Ruby, Javascript)
* Jabber.  Prosody con autosubscripción de todas las miembros del
  servidor.
* SSH.  Las cuentas administrativas pueden loguearse como root por SSH,
  usando el reenvío de llaves del agente de SSH.
* Autenticación simple.  Todas las miembros del servidor tienen una
  cuenta en el sistema, aunque por defecto sin acceso SSH.  La
  autenticación se realiza por PAM.  Soporta cualquier servicio que
  soporte autenticación local o SASL (Dovecot).

## Sobre seguridad

* Se deshabilitan protocolos y ciphers inseguros (SSL, RC4, etc.)
* Se habilita Perfect Forward Secrecy.
* Las llaves generadas tienen al menos 3072 bits

## SSH para root

Habilitar el `ssh-agent` y añadir la llave local.  Conectarse al
servidor normalmente, redirigiendo el puerto y para ingresar como root.

```bash
eval $(ssh-agent)
ssh-add
ssh -fAN -L 2222:localhost:22 pirata@elaine
ssh -Ap 2222 root@localhost
```

Con esto no es necesario tener contraseña o sudo en elaine.

## TODO

* Autocifrado de correos con [gpgit](https://github.com/EtiennePerot/gpgit)
