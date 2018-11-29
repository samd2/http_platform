# frozen_string_literal: true

tcb = 'http_platform'

raise 'Must set node[\'http_platform\'][\'admin_email\']' unless node[tcb]['admin_email']

include_recipe "#{tcb}::firewall" if node[tcb]['configure_firewall']

include_recipe "#{tcb}::cert" if node[tcb]['configure_cert'] # Must be after FQDN is set, so run a baseline first

include_recipe "#{tcb}::ca_cert" if node[tcb]['configure_ca_cert']

invalid_config = node[tcb]['configure_apache'] && !node[tcb]['configure_cert']
raise 'Cannot configure apache without configuring cert' if invalid_config

include_recipe "#{tcb}::apache" if node[tcb]['configure_apache']
