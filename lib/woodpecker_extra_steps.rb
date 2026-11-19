# frozen_string_literal: true

# Extra Woodpecker steps declared in metadata.yaml and wired in around the
# steps rake woodpecker generates:
#
#   woodpecker:
#     pre_steps:              # run before build, rebuild and tag steps
#       - name: fetch-source
#         image: alpine/git
#         commands: [...]
#     post_steps:             # run after the tag steps have published
#       - name: bump-manifest
#         ...
#     post_steps_on_rebuild: true   # post steps also follow rebuild steps
#
# Each entry is a raw Woodpecker step, copied through as written. Only when:
# and depends_on are filled in, and only if the entry does not set them.
#
# Every dependency the wiring adds is optional. Woodpecker drops steps whose
# when: does not match before resolving depends_on, and fails the whole
# pipeline on a dependency it cannot find unless it is marked optional
# (Woodpecker 3.15+). A tag pipeline for v18 has no tag-17-* steps, and a pre
# step with a narrower when: than its dependents is absent from some events.

WOODPECKER_SECTION_KEYS = %w[pre_steps post_steps post_steps_on_rebuild].freeze
GENERATED_STEP_NAMES    = %w[render setup check-tag].freeze
GENERATED_STEP_PREFIXES = %w[build- rebuild- tag-].freeze

# Validates the woodpecker: section of metadata.yaml and returns its steps as
# { pre: [...], post: [...], post_on_rebuild: bool }, deep-copied so the
# wiring never mutates (or shares objects with) the metadata.
def woodpecker_extra_steps(metadata)
  section = metadata['woodpecker']
  return { pre: [], post: [], post_on_rebuild: false } if section.nil?
  raise 'metadata.yaml: woodpecker must be a mapping' unless section.is_a?(Hash)

  unknown = section.keys - WOODPECKER_SECTION_KEYS
  raise "metadata.yaml: unknown woodpecker key(s): #{unknown.join(', ')}" unless unknown.empty?

  on_rebuild = section.fetch('post_steps_on_rebuild', false)
  unless [true, false].include?(on_rebuild)
    raise "metadata.yaml: woodpecker.post_steps_on_rebuild must be true or false, not #{on_rebuild.inspect}"
  end

  seen = []
  extra = %w[pre_steps post_steps].map do |key|
    entries = section[key] || []
    raise "metadata.yaml: woodpecker.#{key} must be a list of steps" unless entries.is_a?(Array)

    entries.each_with_index.map do |step, index|
      where = "woodpecker.#{key}[#{index}]"
      raise "metadata.yaml: #{where} must be a mapping (a Woodpecker step)" unless step.is_a?(Hash)

      name = step['name']
      raise "metadata.yaml: #{where} has no name" if name.nil? || (name.is_a?(String) && name.empty?)
      raise "metadata.yaml: #{where} name must be a string, not #{name.inspect}" unless name.is_a?(String)
      raise "metadata.yaml: #{where} name '#{name}' is used more than once" if seen.include?(name)
      if GENERATED_STEP_NAMES.include?(name) || GENERATED_STEP_PREFIXES.any? { |p| name.start_with?(p) }
        raise "metadata.yaml: #{where} name '#{name}' clashes with generated step names " \
              "(#{(GENERATED_STEP_NAMES + GENERATED_STEP_PREFIXES.map { |p| "#{p}*" }).join(', ')})"
      end

      seen << name
      Marshal.load(Marshal.dump(step))
    end
  end

  { pre: extra[0], post: extra[1], post_on_rebuild: on_rebuild }
end

# Returns the generated steps with the extra steps wired in: pre steps first,
# post steps last.
def wire_woodpecker_extra_steps(steps, extra)
  by_prefix = lambda do |*prefixes|
    steps.select { |s| prefixes.any? { |p| s['name'].start_with?("#{p}-") } }
  end
  # Union of the targets' when conditions, so a step with no when: of its own
  # runs on exactly the events its targets run on.
  when_union = ->(targets) { targets.flat_map { |s| s['when'] }.uniq }
  optional   = ->(name) { { 'name' => name, 'optional' => true } }

  pre_targets = by_prefix.call('build', 'rebuild', 'tag')
  extra[:pre].each do |pre|
    pre['when'] ||= when_union.call(pre_targets)
    pre_targets.each { |s| s['depends_on'] = (s['depends_on'] || []) + [optional.call(pre['name'])] }
  end

  post_targets = extra[:post_on_rebuild] ? by_prefix.call('tag', 'rebuild') : by_prefix.call('tag')
  extra[:post].each do |post|
    post['when']       ||= when_union.call(post_targets)
    post['depends_on'] ||= post_targets.map { |s| optional.call(s['name']) }
  end

  extra[:pre] + steps + extra[:post]
end
