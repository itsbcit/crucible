# frozen_string_literal: true

desc 'Render .woodpecker/build.yaml from the image matrix'
task :woodpecker do
  raise 'metadata.yaml not found' unless File.exist?('metadata.yaml')
  raise 'lib/ not found — run rake install first' unless File.exist?('lib')

  all_images = build_objects_array(
    metadata: YAML.safe_load(File.read('metadata.yaml')),
    default_metadata: YAML.safe_load(File.read('lib/metadata-defaults.yaml'))
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

  # render step: stamps a new build ID, re-renders Containerfiles and pipeline
  steps << {
    'name'        => 'render',
    'image'       => ci_image,
    'pull'        => true,
    'privileged'  => true,
    'when'        => when_push + when_cron,
    'environment' => base_env,
    'commands'    => auth_setup + ['rake install', 'rake template', 'rake woodpecker']
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

      env = base_env.merge('KEEP_BUILD' => '1')
      env['VERSION'] = image.version unless image.version.empty?
      env['VARIANT'] = image.variant unless image.variant.empty?

      steps << {
        'name'        => step_name,
        'image'       => ci_image,
        'pull'        => true,
        'privileged'  => true,
        'depends_on'  => step_depends,
        'when'        => step_when,
        'environment' => env,
        'commands'    => auth_setup + [
          'rake install',
          'rake template',
          'rake build',
          'rake test',
          'rake scan'
        ] + publish
      }
    end
  end

  # Tag steps: build what a "v<version>" git tag names.
  #
  # VERSION is derived from the tag rather than hardcoded, so the tag and
  # metadata.yaml are checked against each other on every tagged build. The
  # VERSION filter aborts when it matches no image, which turns a tag that
  # disagrees with metadata.yaml into a failed pipeline instead of a silent
  # rebuild of whatever version metadata.yaml happens to hold.
  #
  # A leading "v" is stripped so both "v1.2.0" and "1.2.0" work.
  #
  # Images with no version (no versions: key) still get a tag step, without
  # the VERSION check: there is nothing for the tag to agree with, so any tag
  # publishes them. Skipping them instead left unversioned repos (e.g. a base
  # image published only as :latest) with no publish step at all, and every
  # pipeline went green while nothing reached the registry.
  all_images.each do |image|
    variant_label = image.variant.empty? ? 'base' : image.variant
    step_name     = ['tag', image.version, variant_label].reject(&:empty?).join('-')

    env = base_env.merge('KEEP_BUILD' => '1')
    env['VARIANT'] = image.variant unless image.variant.empty?

    version_from_tag = image.version.empty? ? [] : ['export VERSION="${CI_COMMIT_TAG#v}"']

    steps << {
      'name'        => step_name,
      'image'       => ci_image,
      'pull'        => true,
      'privileged'  => true,
      'when'        => [{ 'event' => 'tag' }],
      'environment' => env,
      'commands'    => auth_setup + version_from_tag + [
        'rake install',
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
