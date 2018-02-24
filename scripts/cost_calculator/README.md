# Puppet Cost Estimator

This tool provides an estimate of the costs of applying a manifest by the user
to a Google Compute Platform project.

## Requirements & Setup

- Ruby 2.5.0
- Bundler

It requires Ruby and bundler gem:

    gem install bundler    # installs Bundler gem
    bundler install        # installs modules required by the tool

## Usage

    bundle exec calculate_costs <puppet-manifest.pp>

Example:

    bundle exec calculate_costs /home/nelsona/my_app_setup.pp

## Output

The tool produces a YAML file with the results and costs.

Running this tools against the example shipped with the Google Compute Engine
module ([examples/instance.pp][example-instance]), it outputs:

    ---
    pricing:
      total_hourly_usd: 0.050277777777777775
      total_monthly_usd: 26.272499999999994
      usage_discount: true
      exact_pricing: false
      quote_version: v1.23
      quote_updated: 21-February-2018
    resources:
      instances:
        instance-test:
          :type: n1-standard-1
          :zone: us-central1-a
          :price_hourly: 0.0475
          :price_monthly: 24.272499999999994
      disks:
        instance-test-os-1:
          :size_gb: 50
          :price_hourly: 0.0027777777777777775
          :price_monthly: 2.0

## Limitations

This is a prototype tool and operates under various assumptions:

- Only supports Google Compute Engine instance and disks
- Assumes a use discount of 30%

This tool is not supported and provides a rough estimate only of the costs. For
exact cost calculations refer to either:

1. [Google Cloud Platform Pricing Calculator][calculator]
2. [Google Compute Engine Pricing Documentation][pricing]

[pricing]: https://cloud.google.com/compute/pricing
[calculator]: https://cloud.google.com/products/calculator
[example-instance]: https://github.com/GoogleCloudPlatform/puppet-google-compute/blob/3bf42d13dd3c56143065fe4bd3a189a9cee54c22/examples/instance.pp
