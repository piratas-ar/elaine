$rcmail_config['default_host'] = 'ssl://imap.{{HOSTNAME}}';

# PHP5 no valida nuestros certificados
$rcmail_config['imap_conn_options'] = array(
  'ssl' => array(
    'verify_peer' => false,
    'cafile'      => '/etc/ssl/certs/ca-certificates.crt'
));
$rcmail_config['default_port'] = 993;

$rcmail_config['smtp_server'] = 'tls://smtp.{{HOSTNAME}}';
$rcmail_config['smtp_user'] = '%u';
$rcmail_config['smtp_pass'] = '%p';

# PHP5 no valida nuestros certificados
$rcmail_config['smtp_conn_options'] = array(
  'ssl' => array(
    'verify_peer' => false,
    'cafile'      => '/etc/ssl/certs/ca-certificates.crt'
));

# Usar HELO
$rcmail_config['smtp_helo_host'] = '%d';

# Seguridad
$rcmail_config['force_https'] = true;
$rcmail_config['use_https'] = true;
$rcmail_config['http_received_header'] = true;
$rcmail_config['http_received_header_encrypt'] = true;

# Dominio
$rcmail_config['username_domain'] = '%d';
$rcmail_config['mail_domain'] = '%d';

# User Agent
$rcmail_config['useragent'] = 'Partido Pirata/'.RCMAIL_VERSION;
$rcmail_config['product_name'] = 'Partido Pirata';

# I18n
$rcmail_config['language'] = 'es';
$rcmail_config['timezone'] = 'America/Argentina/Buenos_Aires';
