# HTTP Platform Cookbook

[![License](https://img.shields.io/github/license/ualaska-it/http_platform.svg)](https://github.com/ualaska-it/http_platform)
[![GitHub Tag](https://img.shields.io/github/tag/ualaska-it/http_platform.svg)](https://github.com/ualaska-it/http_platform)
[![Build status](https://ci.appveyor.com/api/projects/status/u6bbg97hw0ep5wmj/branch/master?svg=true)](https://ci.appveyor.com/project/UAlaska/http-platform/branch/master)

__Maintainer: OIT Systems Engineering__ (<ua-oit-se@alaska.edu>)

## Purpose

Configures an HTTPS server with a certificate and secure cipher and protocol suites.
This cookbook configures only the server and modules.
This is sufficient to spin up a stand-alone frontend node.
See [django_platform](https://github.com/UAlaska-IT/django_platform) for an example of deploying an application on top of http_platform.
Configurations for load balancers, proxies, back ends and other pieces of the web infrastructure are out of scope.
Custom conf files can be injected to add such things as needed.

This cookbook is intended as a base for rapidly building websites and as such favors convention over configuration.

* Every host _redirects_ HTTP requests to HTTPS
* Multiple host names are supported, but hosts are little more than name aliases
* Host share these attributes
  * Certificate - all host names are listed as subject alternative names on the certificate
  * Redirects
  * Rewrite rules
  * Error documents
  * Configs
  * Content (root and access directories)
* Host are distinguished by
  * Log files
  * Log levels

Default security settings are tight and appropriate for a static web page or pure PHP application (e.g. MediaWiki).
Other technologies may require other policies.
For example, CSRF in Django/Rails requires enabling referrer in header.
See [www policies](#www) below.

### Full server install

A functioning web server can be spun up by including `http_platform::default`.
Currently only Apache is supported.
Nginx will be added in the future.

Host names are always populated as plain-www pairs and each pair shares logging.
Either plain, www, or both hosts can be listed.

While convention is favored over configuration, almost all logic is placed in an auxiliary config file that is included in bare-minimum virtual hosts.
For example:

```text
<VirtualHost *:443>
  ServerName www.funny.business

  ErrorLog ${APACHE_LOG_DIR}/funny.business.error.log
  CustomLog ${APACHE_LOG_DIR}/funny.business.access.log combined
  LogLevel warn

  Include conf.d/ssl-host.conf
</VirtualHost>
```

This allows the install and host-enumeration logic in this cookbook to be used with entirely custom configurations.
See `node['http_platform']['apache']['paths_to_additional_configs']` below.

### Certificate install

The certificate handling logic can be used standalone.
The workflow for doing so is below.

```ruby
include_recipe 'http_platform::local_cert'

# Optional; use if the firewall is not configured by server recipes
include_recipe 'http_platform::firewall'

# Install the web server
# Use path_to_ssl_cert, path_to_ssl_key as helpers
...

include_recipe 'http_platform::certbot_cert' if node['http_platform']['configure_lets_encrypt_cert']
```

Three sources are supported for certificates.
This cookbook always creates a private key, Self-Signed (SS) certificate, and Certificate Signing Request (CSR).
By default, hosts are configured to use the SS certificate for encryption.

A certificate can also be fetched from the Chef server as a Vault secret.
Typically, the CSR generated by this cookbook is sent to a certificate authority to obtain a trusted certificate.
Once the trusted certificate is obtained, it is placed in Vault and the node configured to fetch it.
Otherwise, if a key-certificate pair is generated by other means, the private key can be included in the Vault item and used for encryption.
See `node['http_platform']['key']['vault_item_key']`.

Lastly, a trusted certificate can be fetched from Let's Encrypt.
See notes about Certbot below.

If multiple certificates are configured, the hosts will use the certificate with highest precedence.
Precedence is as follows.

`Vault > Lets Encrypt > Self Signed`

#### Notes about Certbot

Certbot uses the web server to complete an ACME challenge from the certificate authority.
To use Certbot the server must be:

* Started
* World visible

To start the server, its configurations must be valid.
Namely, the certificate and key the hosts point to must exist on the file system.
Therefore Certbot creates a chicken and egg situation between the server and certificate.

The workflow chosen by this cookbook breaks the cycle by spreading configuration over two runs.
Path helpers take into account both precedence and existence of certificates.
If the node is configured to use credentials from Let's Encrypt (`node['http_platform']['configure_lets_encrypt_cert']`):

* On the first Chef run, the server will be configured to use the SS cert because path_to_ssl_cert and path_to_ssl_key will point to SS credentials.
* At the end of the first run, the Certbot cert will be fetched.
* On the second Chef run, path_to_ssl_cert and path_to_ssl_key will point the server logic at the credentials that Cerbot fetched on first run.

Certbot is necessarily run in non-interactive mode and the [Terms of Service for Let's Encrypt](https://letsencrypt.org/repository/) are accepted as part of this.
Therefore, use of this recipe constitutes accepting the [Terms of Service for Let's Encrypt](https://letsencrypt.org/repository/).

## Requirements

### Chef

This cookbook requires Chef 14+

### Platforms

Supported Platform Families:

* Debian
  * Ubuntu, Mint
* Red Hat Enterprise Linux
  * Amazon, CentOS, Oracle

Platforms validated via Test Kitchen:

* Ubuntu
* Debian
* CentOS
* Oracle
* Fedora
* Amazon

### Dependencies

This cookbook does not constrain its dependencies because it is intended as a utility library.
It should ultimately be used within a wrapper cookbook.

## Resources

This cookbook provides no custom resources.

## Recipes

### http_platform::default

This recipe configures a server, encryption, hosts, and access.
The certificate and CSR will be recreated if the FQDN of the node changes, so this should be done earlier in the Chef run before any http_platform recipes execute.

### http_platform::local_cert

Creates a private key and both SS certificate and CSR corresponding to this key.
May fetch a certificate and key from Vault.
Included by the default recipe.

### http_platform::certbot_cert

Uses a previously installed server to fetch a trusted certificate from Let's Encrypt by using Certbot.
Included by the default recipe.

### http_platform::firewall

Adds rules that accept incoming connections for HTTP and HTTPS.
Included by the default recipe.

## Attributes

### default

Default attributes control the features of the platform.

* `node['http_platform']['configure_firewall']`.
Defaults to `true`.
Determines if the firewall is configured.
* `node['http_platform']['configure_cert']`.
Defaults to `true`.
Determines if a private key, self-signed certificate, CSR, and possibly other certificates are created.
* `node['http_platform']['configure_server']`.
Defaults to `'apache'`.
The HTTP server to configure.
Allowed values are `'apache'`, `'nginx'`, `'webroot'`, `'standalone'`'.
To not configure any server, set the value to anything that evaluates to false.

To run the default recipe a server must be installed.
Currently only Apache is supported.

All allowed values can be used to install a trusted certificate only.
Certbot supports custom agents that are robust for Apache and Nginx _system_ installs.
For installations that do not support standard system commands for Apache/Nginx, the `'webroot'` method can be used.
The `'webroot'` method supports most server installations provided that the server will serve files from the $HTTP_ROOT/.well-known directory.
If all else fails, `'standalone'` can be specified to run a standalone server to install the certificate.
The standalone server will conflict with any running server if it attempts to bind to the same ports.
Therefore, this method requires stopping any running web server.
See `node['http_platform']['cert']['standalone_stop_command']` and `node['http_platform']['cert']['standalone_start_command']`.

These flags control trusted certificate usage.
These attributes have no effect if `node['http_platform']['configure_cert']` is `false`.
See above for certificate precedence.

* `node['http_platform']['configure_vault_cert']`.
Defaults to `false`.
Determines if a certificate is fetched from Chef vault.
Has no effect if `node['http_platform']['configure_cert']` is false.
* `node['http_platform']['configure_lets_encrypt_cert']`.
Defaults to `false`.
Determines if a certificate is fetching using Certbot.
Requires Apache running on a world-visible server.
Has no effect if `node['http_platform']['configure_cert']` is false.

Several attributes control security.
The philosophy of this cookbook is to favor security over compatibility or performance.
However, the cipher and protocol generators are optimistic and will automatically add new ciphers and protocols on future distros.
This is done by defining support in the negative: a candidate list is generated and unsecure algorithms removed.
This is done mostly to reduce the burden of managing a platform-dependent list of supported ciphers over time.

* `node['http_platform']['cipher_generator']`.
Defaults to `'HIGH:!aNULL:!kRSA:!SHA:@STRENGTH'`.
This is the string used to generate a list of candidate ciphers using [OpenSSL](https://www.openssl.org/docs/man1.1.0/apps/ciphers.html).
The precise list of ciphers generated depends on both OpenSSL version and compile options and will be specific to a distribution.
The meaning of this string is 'All ciphers that use encryption with "high" strength rating - but not null authentication, RSA key exchange, or SHA hashing - ordered by strength'.
This generator is sufficient to generate a tight cipher suite on Ubuntu 18, Ubuntu 16, or CentOS 7.
Older distros may require more exclusions.
* `node['http_platform']['ciphers_to_remove']`.
Defaults to `['-CBC-']`.
This is a list of regular expressions.
Any cipher matching one or more of these regexes will be removed from the final list of ciphers.
This attribute is used primarily to remove algorithms that cannot be specified as a group, as is done with `kRSA` above.
By default, any cipher that uses [cipher block chaining](https://en.wikipedia.org/wiki/Block_cipher_mode_of_operation) will be removed.
Note that `node.default['apache']['mod_ssl']['cipher_suite']` is set within a recipe to the final list of ciphers generated here.
* `node['http_platform']['ssl_protocol']`.
Defaults to `'All -SSLv2 -SSLv3 -TLSv1 -TLSv1.1'`.
This is the string used to specify protocol versions to be used.
On Ubuntu 18, Ubuntu 16 and CentOS 7 this results in only TLSv1.2.
TLSv1.3 will be automatically supported when it becomes available but explicit TLSv1.3 is not commonly supported at this time.
Note that `node.default['apache']['mod_ssl']['ssl_protocol']` is set to the value of `node['http_platform']['ssl_protocol']` within a recipe.
* `node['http_platform']['apache']['use_stapling']`.
Defaults to `true`.
Enable stapling of the certificate.
Stapling will not be configured if a self-signed certificate is used.
* `node['http_platform']['apache']['paths_to_additional_configs']`.
Defaults to `{ 'conf.d/ssl-host.conf' => '' }`.
A hash of relative paths to additional config files to be included by all HTTPS hosts.
The default is the config file generated based on the attributes of this cookbook.
Most clients will merge this hash to add additional configs as desired, but an entirely custom host configuration is hereby supported.

The default security settings are sufficient to earn an 'A+' grade on [Qualys SSL Server Test](https://www.ssllabs.com/ssltest/).
If compatibility is a concern, the ciphers should be loosened.
For high-traffic servers, less costly ciphers are advisable.

### apache

Apache attributes control the server configuration.

* `node['http_platform']['apache']['install_test_suite']`.
Defaults to `false`.
If true, installs support for running `apachectl fullstatus` for troubleshooting.
This includes a command-line browser (elinks) and the Apache status module.
Because 'localhost' will redirect to the default HTTPS host, to perform local testing it is advisable to either poison the hosts file on the host machine or to explicitly specify HTTPS protocol (and port if forwarded), e.g. 'https://localhost:8043'.

* `node['http_platform']['apache']['extra_mods_to_install']`.
Defaults to `{}`.
A hash of Apache mods to install; e.g. `{ 'wsgi -> '' }`.
Modules 'headers', 'rewrite', and 'ssl' are always installed.
Include the mod name only, e.g. 'php', without prefix 'mod_' or suffix '_mod'
See the [Apache cookbook](https://github.com/sous-chefs/apache2#recipes) for a list of modules

* `node['http_platform']['admin_email']`.
Defaults to `nil`.
This must be set or an exception is raised.
This also serves as the default email for the CSR.
Note that `node.default['apache']['contact']` is set to the value of `node['http_platform']['admin_email']` within a recipe.

### cert

Cert attributes specify the fields of the PKI certificate and the parameters of the private key.

* `node['http_platform']['cert']['expiration_days']`.
Defaults to `365`.
The number of days until expiration for the SS certificate and and the CSR.
* `node['http_platform']['cert']['rsa_bits']`.
Defaults to `2048`.
The number of bits in the private key.
Currently only RSA keys are supported.
* `node['http_platform']['cert']['dh_param']['bits']`.
Defaults to `2048`.
The number of bits used for the Diffie-Hellman (DH) key exchange.
Currently DH is configured only on Debian-based distros.

The attributes below are given defaults but should typically be changed.

* `node['http_platform']['cert']['country']`.
Defaults to `'US'`.
The host country.
* `node['http_platform']['cert']['state']`.
Defaults to `'Alaska'`.
The host state, clients will typically want to override this:)
* `node['http_platform']['cert']['locale']`.
Defaults to `'Fairbanks'`.
The host city.
Almost surely not correct for a client.

The following attributes must be set if the cert is being created.

* `node['http_platform']['cert']['organization']`.
Defaults to `nil`.
The name of the host organization.
* `node['http_platform']['cert']['org_unit']`.
Defaults to `nil`.
The name of the unit, e.g. division, hosting the machine.

The attributes below default to reasonable values.

* `node['http_platform']['cert']['common_name']`.
Defaults to `nil`.
If nil, the FQDN of the node is used.
* `node['http_platform']['cert']['email']`.
Defaults to `nil`.
If nil, the value of `node['http_platform']['admin_email']` is used.

The attributes below control fetching of a certificate from a server vault.

* `node['http_platform']['cert']['vault_data_bag']`.
Defaults to `'certs'`.
The name of the Vault data bag from which to fetch the certificate.
* `node['http_platform']['cert']['vault_bag_item']`.
Defaults to `nil`.
The item inside the data bag (json file).
If nil, Defaults to the FQDN of the node.
* `node['http_platform']['cert']['vault_item_key']`.
Defaults to `'cert'`.
The key for the certificate within the json object.
* `node['http_platform']['key']['vault_item_key']`.
Defaults to `nil`.
The key for the private key within the json object.
This will typically be nil because the generated CSR will be used to create a certificate for the generated private key.
However, a key will be manually placed on the system if this is non-nil, e.g. for use in Test Kitchen.

An example vault item is show below, assuming `node['http_platform']['cert']['vault_item_key']` is set to `cert` and `node['http_platform']['key']['vault_item_key']` is set to `key`.

```json
{
  "cert": "-----BEGIN CERTIFICATE----...-----END CERTIFICATE-----\n",
  "key": "-----BEGIN RSA PRIVATE KEY-----...-----END RSA PRIVATE KEY-----\n"
}
```

Two attributes control the standalone server.
The challenge must be conducted over ports 80 and 443.
Therefore an existing web server that listens on these ports must be stopped to complete the challenge.
These have no effect unless `node['http_platform']['configure_server']` is set to `'standalone'`.
To run no command commands, leave these as empty strings.

* `node['http_platform']['cert']['standalone_stop_command']`.
Defaults to `''`.
The command to stop the web server.
Will be run before fetching the certbot cert.
* `node['http_platform']['cert']['standalone_start_command']`.
Defaults to `''`.
The command to start the web server.
Will be run after fetching the certbot cert.

### firewall

Firewall attributes control firewall settings.

* `node['http_platform']['firewall']['enable_http']`.
Defaults to `true`.
Determines if world-accessible HTTP is allowed.

World-accessible HTTPS is _always_ allowed.
If custom HTTP/HTTPS rules are desired, e.g. remote access from only specific CIDRs, then `node['http_platform']['configure_firewall']` can be set to `false` and the desired rules created elsewhere.

Please note:

* This cookbook uses the [firewall cookbook](https://github.com/chef-cookbooks/firewall) to create firewall rules so will conflict with other methods if configured.
* An SSH rule __must__ be created outside of this cookbook or communication will be lost to the node after this cookbook is run. The `firewall::default` rule is used to initialize the firewall, and this recipe respects all attributes of the [firewall cookbook](https://github.com/chef-cookbooks/firewall).
Notably, a world-accessible SSH rule can be created by setting `node['firewall']['allow_ssh']` to `true`.

### www

WWW settings configure the application and hosts.

* `node['http_platform']['www']['document_root']`.
Defaults to `'/var/www/html'`.
The absolute path to the directory where web documents are located.

* `node['http_platform']['www']['remove_default_index']`.
Defaults to `true`.
Some distributions provide a default document at $HTTP_ROOT/index.html.
If this flag is true any such document will be removed.
* `node['http_platform']['www']['create_default_index']`.
Defaults to `false`.
If true, an extremely simple html page will be created at $HTTP_ROOT/index.html.
This can be used for initial troubleshooting.
This setting overrides `node['http_platform']['www']['remove_default_index']`.

* `node['http_platform']['www']['access_directories']`.
Defaults to `{ '/' => '' }`.
A hash of directories and files to which to allow http access.
Each key is a relative path from `node['http_platform']['www']['document_root']` to the directory.
Each value is either a single file name or a list of file names in that directory.
To allow access recursively to all files in a directory, use an empty string or empty list as the value.

* `node['http_platform']['www']['error_documents']`.
Defaults to `{}`.
A mapping from status code to relative path to error document, e.g. { 404 => '/404_kitten.php' }.
Error documents are shared by all hosts.

* `node['http_platform']['www']['additional_aliases']`.
Defaults to `{}`.
This cookbook always creates plain (default host) and www hosts for the FQDN.
This is a map of additional hosts to options, e.g. { 'other.url' => { 'log_level' -> 'info' } }.
Options can also be set for the FQDN host pair by including that as well.
If both the plain and www host are included, these are treated as independent and can be given different options.
Otherwise the plain and www hosts will be created as a matched pair with identical options.
The options currently recognized are:
  * 'log_level'.
  Defaults to 'warn'.
  See the [Apache documentation](https://httpd.apache.org/docs/2.4/mod/core.html#loglevel).
  * 'log_prefix'.
  Defaults to the plain host name.
  For example, on Ubuntu the default access log for 'www.other.url' will be '/var/log/apache2/other.url.access.log'.

* `node['http_platform']['www']['redirect_rules']`.
Defaults to `[]`.
This is an array of hashes representing redirect rules; these will be matched first to last.
The fields of a rule are:
  * 'comment'.
  Optional.
  Will be placed above the rule.
  * 'from_regex'.
  Required.
  The regex for the incoming URL.
  * 'to_regex'.
  Required.
  The regex for the target URL.

* `node['http_platform']['www']['rewrite_rules']`.
Defaults to `[]`.
An array of hashes representing rewrite rules; these will be matched first to last.
Rewrite rules are evaluated after redirect rules.
This attribute only generates 'RewriteRule' entries.
For other rewrite logic, custom config files must be used.
This attribute will eventually support generating both Apache and Nginx rules for the range of logic it supports.
The fields of a rule are:
  * 'comment'.
  Optional.
  Will be placed above the rule.
  * 'url_regex'.
  Required.
  The regex for the URL.
  * 'path_regex'.
  Required.
  The regex for the generated relative file path.
  * 'flags'.
  Optional.
  The flags for the rule, e.g. '[L,NC]'.
  See the [Apache documentation](https://httpd.apache.org/docs/2.4/rewrite/flags.html).

Several attributes control header policy.
Any of these attributes can be set to nil to prevent the policy from being generated.

* `node['http_platform']['www']['header_policy']['referrer']`.
Defaults to `"no-referrer"`.
Determines if referrer is always omitted from headers.
* `node['http_platform']['www']['header_policy']['x_frame']`.
Defaults to `DENY`.
Determines if frame content is blocked.
* `node['http_platform']['www']['header_policy']['x_content']`.
Defaults to `nosniff`.
Determines if no sniff policy is set in headers.
* `node['http_platform']['www']['header_policy']['xss']`.
Defaults to `"1; mode=block"`.
Determines XSS control is set in headers.

Content policy is not fully implemented and it is recommended to create a config to lock down content.
Any of these attributes can be set to nil to prevent the policy from being generated.

* `node['http_platform']['www']['header_policy']['base_uri']`.
Defaults to `'none'`.
The URIs allowed in the base element.

## Examples

This is an application cookbook; no custom resources are provided.
See recipes and attributes for details of what this cookbook does.

## Development

See CONTRIBUTING.md and TESTING.md.

### ToDo

* Content policy parameters
