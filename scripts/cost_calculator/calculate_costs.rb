#!/usr/bin/env ruby
#!/opt/puppetlabs/puppet/bin/ruby
# Copyright 2018 Google Inc.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'json'
require 'net/http'
require 'puppet'
require 'puppet/face'
require 'uri'
require 'yaml'

if ARGV.length != 1
  puts 'FATAL: Usage calculate_costs <puppet_manifest.pp>'
  exit 1
end


def log(str) end

PRICING_DATA_URL = URI.parse(
  'https://cloudpricingcalculator.appspot.com/static/data/pricelist.json'
).freeze

PRICING_DATA = JSON.parse(Net::HTTP.get_response(PRICING_DATA_URL).body).freeze

USE_DISCOUNT_PERC = 0.709722222222222

def vm_cost(type, zone)
  region = zone.split('-')[0..-2].join('-')
  PRICING_DATA.dig('gcp_price_list',
                   "CP-COMPUTEENGINE-VMIMAGE-#{type.upcase}",
                   region)
end

def disk_cost(zone)
  region = zone.split('-')[0..-2].join('-')
  PRICING_DATA.dig('gcp_price_list',
                   'CP-COMPUTEENGINE-STORAGE-PD-CAPACITY',
                   region)
end

def calc_total(resources, field)
  resources.values
           .map(&:values)
           .flatten
           .map { |r| r[field] }
           .reduce(:+)
end

# Paths where to find the modules
mod_paths = [
  File.expand_path('~/.puppetlabs/etc/code/modules'),
  '/opt/puppetlabs/puppet/modules'
]

# Fetch all module metadata
mod_metadata = Puppet::Face[:module, :current].list(
  modulepath: mod_paths.join(':')
)[:modules_by_path]

# Find all Google modules
google_modules = mod_metadata.values.flatten.select { |m| m.author = 'Google' }

# Load all Google modules into namespace for function access
google_modules.each { |m| $LOAD_PATH.unshift File.join(m.path, 'lib') }

Puppet.initialize_settings

Puppet[:code] = File.read(ARGV[0])

node = Puppet::Node.new('testnode', facts: Puppet::Node::Facts.new('facts', {}))
node.add_server_facts({})

catalog = Puppet::Resource::Catalog.indirection.find(node.name, use_node: node)
ral_catalog = catalog.to_ral
ral_catalog.finalize

disks = {}
instances = {}

resources = ral_catalog.resources

def get_machine_type(res, resources)
  machine_ref = res.parameters[:machine_type].should
                   .instance_variable_get(:@title)

  resources.select { |r| r.is_a?(Puppet::Type::Gcompute_machine_type) }
           .select { |r| r.title == machine_ref }
           .first
end

def get_zone_name(machine_type, resources)
  zone_ref = machine_type[:zone].instance_variable_get(:@title)
  zone = resources.select { |r| r.is_a?(Puppet::Type::Gcompute_zone) }
                  .select { |r| r.title == zone_ref }
                  .first
  zone.parameters[:name].should
end

def calc_vm_price(res, resources)
  machine_type = get_machine_type(res, resources)
  machine_type_name = machine_type.parameters[:name].should

  zone_name = get_zone_name(machine_type, resources)

  price = vm_cost(machine_type_name, zone_name)

  {
    type: machine_type_name,
    zone: zone_name,
    price_hourly: price,
    price_monthly: price * 24 * 30 * USE_DISCOUNT_PERC
  }
end

resources.each do |res|
  if res.is_a?(Puppet::Type::Gcompute_disk)
    log "# Found disk #{res.name}"
    size_gb = res.parameters[:size_gb].should
    zone_name = res.parameters[:zone].should.instance_variable_get(:@title)

    price = disk_cost(zone_name)

    disks[res.name] = { size_gb: size_gb,
                        price_hourly: size_gb * price / 24 / 30,
                        price_monthly: size_gb * price }
  elsif res.is_a?(Puppet::Type::Gcompute_instance)
    log "# Found instance #{res.name}"
    instances[res.name] = calc_vm_price(res, resources)
  else
    log "# Ignoring #{res.class}"
  end
end

resources = {
  'instances' => instances,
  'disks' => disks
}

result = {
  'pricing' => {
    'total_hourly_usd' => calc_total(resources, :price_hourly),
    'total_monthly_usd' => calc_total(resources, :price_monthly),
    'usage_discount' => true,
    'exact_pricing' => false, # this is a rough approximation
    'quote_version' => PRICING_DATA['version'],
    'quote_updated' => PRICING_DATA['updated']
  },
  'resources' => resources
}

puts(result.to_yaml)
