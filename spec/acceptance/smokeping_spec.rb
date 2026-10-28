# frozen_string_literal: true

require 'spec_helper_acceptance'

# smokeping isn't packaged in EPEL 10
describe 'smokeping', unless: fact('os.family') == 'RedHat' && fact('os.release.major').to_i >= 10 do
  def smokeping_manifest
    <<~PUPPET
      # On EL smokeping comes from EPEL (and needs CRB), which the module doesn't manage
      if $facts['os']['family'] == 'RedHat' {
        yumrepo { 'crb':
          enabled => '1',
          before  => Class['smokeping'],
        }
        # postfix provides /usr/sbin/sendmail, without which smokeping won't start
        package { ['epel-release', 'postfix']:
          ensure => installed,
          before => Class['smokeping'],
        }
      }

      class { 'smokeping':
        mode       => 'standalone',
        cgiurl     => 'http://localhost/smokeping/smokeping.cgi',
        master_url => 'http://localhost/smokeping/smokeping.cgi',
        targets    => {
          'Local'     => {
            'menu'      => 'Local',
            'pagetitle' => 'Local targets',
          },
          'localhost' => {
            'hierarchy_level'  => 2,
            'hierarchy_parent' => 'Local',
            'menu'             => 'localhost',
            'host'             => '127.0.0.1',
          },
        },
      }
    PUPPET
  end

  # The daemon creates the RRD files after the first run and the module then sets their group/mode,
  # so converge once and wait for the RRDs before checking idempotency
  before(:all) do
    apply_manifest(smokeping_manifest, catch_failures: true)
    shell('timeout 120 sh -c "until find /var/lib/smokeping -name localhost.rrd | grep -q .; do sleep 2; done"')
  end

  it_behaves_like 'an idempotent resource' do
    let(:manifest) { smokeping_manifest }
  end

  describe package('smokeping') do
    it { is_expected.to be_installed }
  end

  describe file('/etc/smokeping/config.d/Targets') do
    its(:content) { is_expected.to match(%r{^\*\*\* Targets \*\*\*$}) }
    its(:content) { is_expected.to match(%r{^@include /etc/smokeping/config.d/targets.d/1-Local$}) }
  end

  describe file('/etc/smokeping/config.d/targets.d/1-Local') do
    its(:content) { is_expected.to match(%r{^\+ Local$}) }
    its(:content) { is_expected.to match(%r{^@include /etc/smokeping/config.d/targets.d/2-localhost$}) }
  end

  describe file('/etc/smokeping/config.d/targets.d/2-localhost') do
    its(:content) { is_expected.to match(%r{^\+\+ localhost$}) }
    its(:content) { is_expected.to match(%r{^host = 127\.0\.0\.1$}) }
  end

  describe command('smokeping --check') do
    its(:exit_status) { is_expected.to eq 0 }
  end

  describe service('smokeping') do
    it { is_expected.to be_enabled }
    it { is_expected.to be_running }
  end
end
