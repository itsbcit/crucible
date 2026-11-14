# frozen_string_literal: true

desc 'Push to Registry'
task :push do
  check_podman!

  seen_images = {}

  $images.each do |image|
    next unless image.push_image?

    puts "Image: #{image.build_name_tag}".pink

    image_id = image.image_id
    if image_id.nil?
      puts "Image #{image.build_name_tag} has not been built.".red
      exit 1
    end

    puts "Image ID: #{image_id}"
    seen_images[image_id] = image.build_name_tag

    if ENV['CRUCIBLE_SKIP_UNCHANGED'] && unchanged_since_published?(image, image_id)
      puts 'Unchanged: every published tag already has this fingerprint, not pushing.'.green
      next
    end

    image.registries.each do |registry|
      if registry['url'].nil? or registry['url'] == 'docker.io'
        registry_url = ''
      else
        registry_url = registry['url']
      end

      image.tags.each do |tag|
        ron          = image.parts_join('/', registry_url, registry['org_name'])
        ron_name     = image.parts_join('/', ron, image.image_name)
        ron_name_tag = image.parts_join(':', ron_name, tag)

        image_tag_id = `podman image ls -q #{ron_name_tag}`.strip
        if image_tag_id.empty?
          puts "Tag not found: Image #{image.build_name_tag} has not been tagged with #{ron_name_tag}".red
          exit 1
        elsif (image_tag_id != image_id) && !(seen_images[image_tag_id].nil?)
          puts "#{ron_name_tag} tagged to #{seen_images[image_tag_id]} : tag conflict likely.".red
          exit 1
        end

        sh "podman push #{ron_name_tag}"
      end
    end
  end
end

# True when the image's fingerprint label matches the label on every published
# non-build tag in every registry. Scheduled rebuilds set
# CRUCIBLE_SKIP_UNCHANGED so they publish only real changes; tag-triggered
# publishes always push. Anything unknown (no fingerprint, no skopeo, a tag not
# published yet or published without a label) counts as changed.
def unchanged_since_published?(image, image_id)
  fingerprint = local_fingerprint(image_id)
  return false if fingerprint.nil?

  unless system('command -v skopeo >/dev/null 2>&1')
    puts 'skopeo not found: cannot compare with the published image, pushing.'.yellow
    return false
  end

  # b<id> tags are new on every build, so they never match and are not
  # compared; they are skipped along with the rest when nothing changed.
  stable_tags = image.tags.reject { |tag| tag.include?(image.build_suffix) }
  return false if stable_tags.empty?

  image.registries.all? do |registry|
    registry_url = registry['url'].nil? || registry['url'] == 'docker.io' ? 'docker.io' : registry['url']
    ron_name = image.parts_join('/', registry_url, registry['org_name'], image.image_name)

    stable_tags.all? do |tag|
      published = remote_fingerprint("#{ron_name}:#{tag}")
      puts "  #{ron_name}:#{tag}: #{published == fingerprint ? 'same' : 'differs'}"
      published == fingerprint
    end
  end
end
