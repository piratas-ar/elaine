Makefile de migración y configuración de partidopirata.com.ar.

Fue probada y adaptada Ubuntu Server Trusty :(


**IMPORTANTE:** La versión genérica, sin migración, está en la rama
cleanup.  Si querés configurar un servidor en base a elaine, usá esa
rama :)


Leer http://pad.partidopirata.com.ar/p/Migraci%C3%B3nServer

## Migrar mails

TODOS

    make PASSWORD=cambiame migrate-all-the-emails

De un pirata

    make PASSWORD=cambiame /home/fauno/Maildir

