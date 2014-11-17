$rcmail_config['plugins'][] = 'password';
$rcmail_config['password_driver'] = 'chpasswd';
$rcmail_config['password_chpasswd_cmd'] = '/usr/bin/sudo /usr/share/doc/roundcube-plugins/examples/chpass-wrapper.py';
