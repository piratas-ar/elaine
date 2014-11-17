VirtualHost "{{HOSTNAME}}"
  plugin_paths = { "/etc/prosody/modules" }

  modules_enabled = {
    "groups";
  }

  modules_disabled = {
    "register";
  }

  allow_registration = false;
  groups_file = "/etc/prosody/{{GROUP}}.txt";

  authentication = "dovecot";
  dovecot_auth_socket = "/run/dovecot/auth-prosody";
  auth_append_host = false;

  storage = "sql";
  sql = {
    driver = "MySQL";
    database = "prosody";
    username = "prosody";
    host = "localhost";
    password = "{{PASSWORD}}";
  }

  ssl = {
    key = "/etc/ssl/private/{{HOSTNAME}}.key";
    certificate = "/etc/ssl/certs/{{HOSTNAME}}.crt";
  }
