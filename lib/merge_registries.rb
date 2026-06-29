# frozen_string_literal: true

# Normalize registry hash so that 'project' and 'org' are treated as aliases
# for 'org_name'. The canonical key is 'org_name'; aliases take lower priority.
def normalize_registry(registry)
  return registry if registry.key?('org_name')

  %w[project org].each do |alias_key|
    if registry.key?(alias_key)
      registry = registry.merge('org_name' => registry[alias_key])
      break
    end
  end

  registry
end

# merge three arrays of registry hashes
def merge_registries(left, centre, right)
    raise "Expected Array, got #{left.class} in argument 1" unless left.is_a?(Array)
    raise "Expected Array, got #{centre.class} in argument 1" unless centre.is_a?(Array)
    raise "Expected Array, got #{right.class} in argument 2" unless right.is_a?(Array)

    registries_hash_left   = {}
    registries_hash_centre = {}
    registries_hash_right  = {}
    registries             = []

    left.each do |registry|
        registry = normalize_registry(registry)
        registries_hash_left["#{registry['url']}/#{registry['org_name']}"] = registry
    end

    centre.each do |registry|
        registry = normalize_registry(registry)
        registries_hash_centre["#{registry['url']}/#{registry['org_name']}"] = registry
    end

    right.each do |registry|
        registry = normalize_registry(registry)
        registries_hash_right["#{registry['url']}/#{registry['org_name']}"] = registry
    end

    registries_merged = registries_hash_left.deep_merge(registries_hash_centre)
    registries_merged = registries_merged.deep_merge(registries_hash_right)

    registries_merged.each do |registry_org, registry|
        registries << registry
    end

    registries
end
