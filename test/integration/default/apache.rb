# frozen_string_literal: true

require_relative '../helpers'

node = json('/opt/chef/run_record/last_chef_run_node.json')['automatic']

if node['platform_family'] == 'debian'
  conf_available_dir = '/etc/apache2/conf-available'
  conf_enabled_dir = '/etc/apache2/conf-enabled'
  sites_available_dir = '/etc/apache2/sites-available'
  sites_enabled_dir = '/etc/apache2/sites-enabled'
  module_command = 'apache2ctl'
elsif node['platform_family'] == 'rhel'
  conf_available_dir = '/etc/httpd/conf-available'
  conf_enabled_dir = '/etc/httpd/conf-enabled'
  sites_available_dir = '/etc/httpd/sites-available'
  sites_enabled_dir = '/etc/httpd/sites-enabled'
  module_command = 'httpd'
else
  raise "Platform family not recognized: #{node['platform_family']}"
end

describe package(apache_service(node)) do
  it { should be_installed }
  its(:version) { should match(/^2\.4/) }
end

describe service(apache_service(node)) do
  it { should be_installed }
  it { should be_enabled }
  it { should be_running }
end

['', '/'].each do |page|
  describe http('http://localhost:80' + page) do
    its(:status) { should cmp 301 }
    its(:body) { should match('https://funny.business') }
  end

  describe http('https://localhost:443' + page, ssl_verify: false) do
    its(:status) { should cmp 200 }
  end
end

describe http('https://localhost:443/index.html', ssl_verify: false) do
  its(:status) { should cmp 200 }
end

describe apache_conf do
  its('AllowOverride') { should eq ['None'] }
  its('Listen') { should match ['*:80', '*:443'] }
end

describe file(conf_available_dir + '/ssl_params.conf') do
  it { should exist }
  it { should be_file }
  it { should be_mode 0o644 }
  it { should be_owned_by 'root' }
  it { should be_grouped_into 'root' }
  if node['platform_family'] == 'debian'
    its(:content) { should match "SSLOpenSSLConfCmd DHParameters #{path_to_dh_params(node)}" }
    # its(:content) { should match 'RedirectMatch 404 ".*"' }
  end
end

describe file(conf_enabled_dir + '/ssl_params.conf') do
  it { should exist }
  it { should be_symlink }
  it { should be_mode 0o644 }
  it { should be_owned_by 'root' }
  it { should be_grouped_into 'root' }
  its(:link_path) { should eq conf_available_dir + '/ssl_params.conf' }
end

describe apache_conf(conf_available_dir + '/ssl_params.conf') do
  its('SSLProtocol') { should eq ['All -SSLv2 -SSLv3 -TLSv1 -TLSv1.1'] }
  its('SSLCipherSuite') { should eq ['HIGH:!aNULL:!kRSA:!SHA:@STRENGTH'] }
  its('SSLInsecureRenegotiation') { should eq ['off'] }
end

describe file(conf_enabled_dir + '/ssl_params.conf') do
  it { should exist }
  it { should be_symlink }
  it { should be_mode 0o644 }
  it { should be_owned_by 'root' }
  it { should be_grouped_into 'root' }
  its(:link_path) { should eq conf_available_dir + '/ssl_params.conf' }
end

describe file(sites_available_dir + '/000-site.conf') do
  it { should exist }
  it { should be_file }
  it { should be_mode 0o644 }
  it { should be_owned_by 'root' }
  it { should be_grouped_into 'root' }

  its(:content) { should match 'Redirect permanent "/" "https://funny.business/"' }
end

describe file(sites_available_dir + '/ssl-site.conf') do
  it { should exist }
  it { should be_file }
  it { should be_mode 0o644 }
  it { should be_owned_by 'root' }
  it { should be_grouped_into 'root' }

  its(:content) { should match 'SSLEngine on' }
  its(:content) { should match "SSLCertificateFile #{path_to_self_signed_cert(node)}" }
  its(:content) { should match "SSLCertificateKeyFile #{path_to_self_signed_key(node)}" }
  its(:content) { should match '<Directory />\s+Require all granted' }
end

describe file(sites_enabled_dir + '/000-site.conf') do
  it { should exist }
  it { should be_symlink }
  it { should be_mode 0o644 }
  it { should be_owned_by 'root' }
  it { should be_grouped_into 'root' }
  its(:link_path) { should eq sites_available_dir + '/000-site.conf' }
end

describe file(sites_enabled_dir + '/ssl-site.conf') do
  it { should exist }
  it { should be_symlink }
  it { should be_mode 0o644 }
  it { should be_owned_by 'root' }
  it { should be_grouped_into 'root' }
  its(:link_path) { should eq sites_available_dir + '/ssl-site.conf' }
end

describe bash('apachectl configtest') do
  its(:exit_status) { should eq 0 }
  its(:stderr) { should match 'Syntax OK' } # Yep, output is on stderr
  its(:stdout) { should eq '' }
end

describe bash("#{module_command} -M") do
  its(:exit_status) { should eq 0 }
  its(:stderr) { should eq '' }
  its(:stdout) { should match 'headers_module' }
  its(:stdout) { should match 'rewrite_module' }
  its(:stdout) { should match 'ssl_module' }
end
