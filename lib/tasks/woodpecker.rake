# frozen_string_literal: true

require 'shellwords'

desc 'Render .woodpecker/build.yaml from the image matrix'
task :woodpecker do
  raise 'metadata.yaml not found' unless File.exist?('metadata.yaml')
  raise 'lib/ not found — run rake install first' unless File.exist?('lib')

  all_images = build_objects_array(
    metadata: YAML.safe_load(File.read('metadata.yaml')),
    default_metadata: YAML.safe_load(File.read('lib/metadata-defaults.yaml')),
    # The pipeline is generated from the whole matrix even if VERSION or
    # VARIANT is set in the calling environment.
    filter: false
  )

  ci_image  = 'bcit.io/library/woodpecker-crucible:latest'
  when_push = [{ 'event' => %w[push manual], 'branch' => 'main' }]
  # Scheduled rebuilds. Steps filter on this cron *name*, so nothing runs until
  # a cron called "rebuild" is created for the repo in Woodpecker, e.g.
  #   woodpecker-cli repo cron add --repo ORG/REPO --name rebuild \
  #     --branch main --schedule '0 11 * * *'
  # A cron with any other name triggers none of these steps.
  cron_name = 'rebuild'
  when_cron = [{ 'event' => 'cron', 'cron' => cron_name }]
  auth_setup = [
    'mkdir -p /root/.docker',
    'printf \'%s\' "$HARBOR_CONFIG" > /root/.docker/config.json'
  ]
  base_env = {
    'HARBOR_CONFIG'      => { 'from_secret' => 'harbor_config' },
    'REGISTRY_AUTH_FILE' => '/root/.docker/config.json'
  }

  steps = []

  # Every step runs "rake update", not "rake install": install refreshes lib/
  # but never the committed Rakefile, so CI ran a current lib/ with whatever
  # Rakefile was last committed (TUX-6950). update fetches both from the same
  # release, and every crucible Rakefile since v1.0.0 has it (TUX-6952).
  #
  # render step: stamps a new build ID, re-renders Containerfiles and pipeline
  steps << {
    'name'        => 'render',
    'image'       => ci_image,
    'pull'        => true,
    'privileged'  => true,
    'when'        => when_push + when_cron,
    'environment' => base_env,
    'commands'    => auth_setup + ['rake update', 'rake template', 'rake woodpecker']
  }

  # One build step per version x variant.
  #
  # These validate only: build, test and scan, with no tag/push. Publishing is
  # the tag steps' job. Running both on a tagged release commit meant two
  # pipelines racing to push the identical tags from the same commit, and it
  # also moved :latest on every push to main, so consumers tracking :latest
  # picked up unreleased commits.
  #
  # Rebuild steps are the same matrix on the "rebuild" cron, plus tag/push.
  # They republish the version metadata.yaml already holds, so base-image and
  # package fixes ship without a commit or a new git tag. They run after the
  # render step like push builds do, so each scheduled run gets a fresh build
  # ID and its b<id> tag never overwrites an earlier build's.
  # Scope each step to exactly its own image.
  #
  # An unset VARIANT matches every variant, so in a repo with variants the
  # base-variant step must select the base image explicitly with an empty
  # VARIANT; otherwise it builds (and in rebuild/tag steps, pushes) every
  # variant of its version, racing the variant steps that push the same
  # images (TUX-6951). The empty value is exported in the commands rather than
  # set in the step environment, so it cannot be lost as an empty YAML value.
  has_variants = all_images.any? { |i| !i.variant.empty? }
  scope_env = lambda do |image|
    env = base_env.merge('KEEP_BUILD' => '1')
    env['VERSION'] = image.version unless image.version.empty?
    env['VARIANT'] = image.variant unless image.variant.empty?
    env
  end
  scope_commands = lambda do |image|
    image.variant.empty? && has_variants ? ["export VARIANT=''"] : []
  end

  [['build', when_push, []], ['rebuild', when_cron, ['rake tag', 'rake push']]].each do |prefix, step_when, publish|
    all_images.each do |image|
      variant_label = image.variant.empty? ? 'base' : image.variant
      step_name     = [prefix, image.version, variant_label].reject(&:empty?).join('-')

      step_depends = ['render']
      if image.depends_on
        dep_label = image.depends_on.empty? ? 'base' : image.depends_on
        dep_name  = [prefix, image.version, dep_label].reject(&:empty?).join('-')
        step_depends << dep_name
      end

      steps << {
        'name'        => step_name,
        'image'       => ci_image,
        'pull'        => true,
        'privileged'  => true,
        'depends_on'  => step_depends,
        'when'        => step_when,
        'environment' => scope_env.call(image),
        'commands'    => auth_setup + scope_commands.call(image) + [
          'rake update',
          'rake template',
          'rake build',
          'rake test',
          'rake scan'
        ] + publish
      }
    end
  end

  # Tag steps: publish what a "v<version>" git tag names.
  #
  # Each versioned image's tag step runs only on a tag naming its own version
  # ("<version>" or "v<version>"). Deriving VERSION from the tag in every step
  # instead made every tag step of a multi-version repo build the tagged
  # version, so N steps raced to push the same images (TUX-6951).
  #
  # Gating on the ref alone would let a tag matching no version skip every
  # step and go green with nothing published, so a check-tag step runs on
  # every tag and fails unless the tag names a version in metadata.yaml. That
  # keeps the git tag and metadata.yaml checked against each other.
  #
  # Images with no version (no versions: key) still get a tag step, on any
  # tag: there is nothing for the tag to agree with. Skipping them instead
  # left unversioned repos (e.g. a base image published only as :latest) with
  # no publish step at all, and every pipeline went green while nothing
  # reached the registry.
  versions = all_images.map(&:version).reject(&:empty?).uniq
  unless versions.empty?
    patterns = versions.map { |v| Shellwords.escape(v) }.join('|')
    steps << {
      'name'     => 'check-tag',
      'image'    => ci_image,
      'pull'     => true,
      'when'     => [{ 'event' => 'tag' }],
      'commands' => [
        "case \"${CI_COMMIT_TAG#v}\" in #{patterns}) ;; " \
          "*) echo \"Tag $CI_COMMIT_TAG names no version in metadata.yaml: #{versions.join(' ')}\"; exit 1 ;; esac"
      ]
    }
  end

  all_images.each do |image|
    variant_label = image.variant.empty? ? 'base' : image.variant
    step_name     = ['tag', image.version, variant_label].reject(&:empty?).join('-')

    step_when = if image.version.empty?
                  [{ 'event' => 'tag' }]
                else
                  ["refs/tags/#{image.version}", "refs/tags/v#{image.version}"].map do |ref|
                    { 'event' => 'tag', 'ref' => ref }
                  end
                end

    steps << {
      'name'        => step_name,
      'image'       => ci_image,
      'pull'        => true,
      'privileged'  => true,
      'when'        => step_when,
      'environment' => scope_env.call(image),
      'commands'    => auth_setup + scope_commands.call(image) + [
        'rake update',
        'rake template',
        'rake build',
        'rake test',
        'rake scan',
        'rake tag',
        'rake push'
      ]
    }
  end

  FileUtils.mkdir_p('.woodpecker')
  File.open('.woodpecker/build.yaml', 'w') do |f|
    f.puts '# Generated by rake woodpecker — do not edit by hand'
    # Deep-copy each step separately so no two steps share a Hash/Array;
    # Psych would otherwise emit &1/*1 anchors for the shared when/env blocks.
    # (One Marshal round-trip of the whole array would preserve the sharing.)
    unshared = steps.map { |step| Marshal.load(Marshal.dump(step)) }
    f.puts({ 'steps' => unshared }.to_yaml.sub(/\A---\n/, ''))
  end

  puts 'Rendered .woodpecker/build.yaml'.green
end
