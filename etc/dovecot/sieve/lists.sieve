require [ "regex", "fileinto", "imap4flags", "variables", "envelope" ];

# Catch mail tagged as Spam, except Spam retrained and delivered to the box
if allof (header :regex "X-DSPAM-Result" "^(Spam|Virus|Bl[ao]cklisted)$",
          not header :contains "X-DSPAM-Reclassified" "Innocent") {
  # Mark as read
  setflag "\\Seen";
  # Move into the Junk folder
  fileinto "Spam";
  # Stop processing here
  stop;
}

# split out the various list forms
# Mailman & other lists using list-id
if exists "list-id" {
        if header :regex "list-id" "<([a-z0-9-]+)[.@]" {
                set :lower "listname" "${1}";
                fileinto "INBOX.Listas.${listname}";
        } else {
            if header :regex "list-id" "^\\s*<?([a-z0-9-]+)[.@]" {
                set :lower "listname" "${1}";
                fileinto "INBOX.Listas.${listname}";
            } else {
                fileinto "INBOX.Listas.unknown";
            }
        }
        stop;}
# Listar and mailman like
elsif exists "x-list-id" {
        if header :regex "x-list-id" "<([a-z0-9-]+)\\\\." {
                set :lower "listname" "${1}";
                fileinto "INBOX.Listas.${listname}";
        } else {
                fileinto "INBOX.Listas.unknown";
        }
        stop;}
# Ezmlm
elsif exists "mailing-list" {
        if header :regex "mailing-list" "([a-z0-9-]+)@" {
                set :lower "listname" "${1}";
                fileinto "INBOX.Listas.${listname}";
        } else {
                fileinto "INBOX.Listas.unknown";
        }
        stop;}
# York lists service
elsif exists "x-mailing-list" {
        if header :regex "x-mailing-list" "^\\s*([a-z0-9-]+)@?" {
                set :lower "listname" "${1}";
                fileinto "INBOX.Listas.${listname}";
        } else {
                fileinto "INBOX.Listas.unknown";
        }
        stop;}
# Smartlist
elsif exists "x-loop" {
        # I don't have any of these to compare against now
        fileinto "INBOX.Listas.unknown";
        stop;}
# poorly identified
elsif envelope :contains "from" "owner-" {
        if envelope :regex "from" "owner-([a-z0-9-]+)-outgoing@" {
                set :lower "listname" "${1}";
                fileinto "INBOX.Listas.${listname}";
        } elsif envelope :regex "from" "owner-([a-z0-9-]+)@" {
                set :lower "listname" "${1}";
                fileinto "INBOX.Listas.${listname}";
        } elsif header :regex "Sender" "owner-([a-z0-9-]+)@" {
                set :lower "listname" "${1}";
                fileinto "INBOX.Listas.${listname}";
        } else {
                fileinto "INBOX.Listas.unknown";
        }
        stop;}
# other poorly identified
elsif  envelope :contains "from" "-request" {
        if envelope :regex "from" "([a-z0-9-]+)-request@" {
                set :lower "listname" "${1}";
                fileinto "INBOX.Listas.${listname}";
        } else {
                fileinto "INBOX.Listas.unknown";
        }
        stop;}
