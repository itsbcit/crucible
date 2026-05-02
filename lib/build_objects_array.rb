# frozen_string_literal: true

def build_objects_array(options = {})
  metadata         = options.fetch(:metadata, {})
  default_metadata = options.fetch(:default_metadata, {})

  def metadata.fetch(key, default)
    return default unless key?(key)

    return self[key] unless self[key].nil?

    # return an empty instance of the default if metadata value is nil
    default.class.new
  end

  base_labels    = metadata.fetch('base_labels',    default_metadata['base_labels'])
  base_tags      = metadata.fetch('base_tags',      default_metadata['base_tags'])
  base_vars      = metadata.fetch('base_vars',      default_metadata['base_vars'])
  build_image    = metadata.fetch('build',          default_metadata['build'])
  build_platform = metadata.fetch('build_platform', default_metadata['build_platform'])
  image_name     = metadata.fetch('image_name',     default_metadata['image_name'])
  labels         = metadata.fetch('labels',         default_metadata['labels'])
  maintainer     = metadata.fetch('maintainer',     default_metadata['maintainer'])
  push_image     = metadata.fetch('push',           default_metadata['push'])
  registries     = metadata.fetch('registries',     default_metadata['registries'])
  tag_build_id   = metadata.fetch('tag_build_id',   default_metadata['tag_build_id'])
  tag_image      = metadata.fetch('tag',            default_metadata['tag'])
  tags           = metadata.fetch('tags',           default_metadata['tags']) + base_tags
  template_files = metadata.fetch('template_files', default_metadata['template_files'])
  test_command   = metadata.fetch('test_command',   default_metadata['test_command'])
  test_image     = metadata.fetch('test',           default_metadata['test'])
  variants       = metadata.fetch('variants',       default_metadata['variants'])
  vars           = metadata.fetch('vars',           default_metadata['vars'])
  versions       = metadata.fetch('versions',       default_metadata['versions'])

  raise('Can\'t proceed with empty image name (hint: metadata.yaml >> image_name)') if image_name.nil? || image_name.empty?
  
  objects_array = []
  
  versions.each do |version, version_params|
    version_params         = version_params.nil?                   ? {} : version_params
    version_labels         = version_params['labels'].nil?         ? {} : version_params['labels']
    version_registries     = version_params['registries'].nil?     ? [] : version_params['registries']
    version_tags           = version_params['tags'].nil?           ? [] : version_params['tags']
    version_template_files = version_params['template_files'].nil? ? [] : version_params['template_files']
    version_variants       = version_params['variants'].nil?       ? {} : version_params['variants']
    version_vars           = version_params['vars'].nil?           ? {} : version_params['vars']

    version_build_image    = version_params['build'].nil?          ? build_image    : version_params['build']
    version_build_platform = version_params['build_platform'].nil? ? build_platform : version_params['build_platform']
    version_maintainer     = version_params['maintainer'].nil?     ? maintainer     : version_params['maintainer']
    version_push_image     = version_params['push'].nil?           ? push_image     : version_params['push']
    version_tag_build_id   = version_params['tag_build_id'].nil?   ? tag_build_id   : version_params['tag_build_id']
    version_tag_image      = version_params['tag'].nil?            ? tag_image      : version_params['tag']
    version_test_command   = version_params['test_command'].nil?   ? test_command   : version_params['test_command']
    version_test_image     = version_params['test'].nil?           ? test_image     : version_params['test']

    variants   = variants.deep_merge(version_variants)

    variants.each do |variant, variant_params|
      variant_params         = variant_params.nil?                   ? {} : variant_params
      variant_labels         = variant_params['labels'].nil?         ? {} : variant_params['labels']
      variant_registries     = variant_params['registries'].nil?     ? [] : variant_params['registries']
      variant_tags           = variant_params['tags'].nil?           ? [] : variant_params['tags']
      variant_template_files = variant_params['template_files'].nil? ? [] : variant_params['template_files']
      variant_variants       = variant_params['variants'].nil?       ? {} : variant_params['variants']
      variant_vars           = variant_params['vars'].nil?           ? {} : variant_params['vars']

      variant_build_image    = variant_params['build'].nil?          ? version_build_image    : variant_params['build']
      variant_build_platform = variant_params['build_platform'].nil? ? version_build_platform : variant_params['build_platform']
      variant_maintainer     = variant_params['maintainer'].nil?     ? version_maintainer     : variant_params['maintainer']
      variant_push_image     = variant_params['push'].nil?           ? version_push_image     : variant_params['push']
      variant_tag_build_id   = variant_params['tag_build_id'].nil?   ? version_tag_build_id   : variant_params['tag_build_id']
      variant_tag_image      = variant_params['tag'].nil?            ? version_tag_image      : variant_params['tag']
      variant_test_command   = variant_params['test_command'].nil?    ? version_test_command   : variant_params['test_command']
      variant_test_image     = variant_params['test'].nil?           ? version_test_image     : variant_params['test']

      merged_registries = merge_registries(registries, version_registries, variant_registries)
      merged_registries = merged_registries.empty? ? [{ url: '', org_name: '' }] : merged_registries

      # make sure test_command isn't nil
      test_command = test_command.nil?                   ? ''           : test_command

    objects_array << ContainerImage.new(
        build_image: variant_build_image,
        build_platform: variant_build_platform,
        image_name: image_name,
        labels: base_labels.deep_merge(labels).deep_merge(version_labels).deep_merge(variant_labels),
        maintainer: variant_maintainer,
        push_image: variant_push_image,
        registries: merged_registries,
        tag_build_id: variant_tag_build_id,
        tag_image: variant_tag_image,
        tags: (tags + version_tags + variant_tags).uniq,
        template_files: (template_files + version_template_files + variant_template_files).uniq,
        test_command: variant_test_command,
        test_image: variant_test_image,
        variant: variant,
        vars: base_vars.deep_merge(vars).deep_merge(version_vars).deep_merge(variant_vars),
        version: version
      )
    end
  end

  objects_array
end
