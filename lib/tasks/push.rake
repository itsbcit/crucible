# frozen_string_literal: true

require 'json'

# Check if podman has stored credentials for a given registry.
def registry_authenticated?(registry_url)
  auth_paths = [
    File.join(ENV.fetch('XDG_RUNTIME_DIR', '/run/user/' + Process.uid.to_s), 'containers/auth.json'),
    File.expand_path('~/.config/containers/auth.json'),
    File.expand_path('~/.docker/config.json')
  ]

  auth_paths.each do |path|
    next unless File.exist?(path)

    begin
      auth_data = JSON.parse(File.read(path))
      auths = auth_data['auths'] || {}
      return true if auths.key?(registry_url)
    rescue JSON::ParserError
      next
    end
  end
  false
end

desc 'Push to Registry'
task :push do
  check_podman!

  # keep track of image IDs and registries we've already handled
  seen_images = {}
  logged_in_registries = {}

  $images.each do |image|
    next unless image.push_image?

    puts "Image: #{image.build_name_tag}".pink

    # abort if image has not been built
    image_id = `podman image ls -q #{image.build_name_tag}`.strip
    if image_id.empty?
      puts "Image #{image.build_name_tag} has not been built.".red
      exit 1
    end

    puts "Image ID: #{image_id}"
    seen_images[image_id] = image.build_name_tag

    image.registries.each do |registry|
      if registry['url'].nil? or registry['url'] == 'docker.io'
        registry_url = ''
      else
        registry_url = registry['url']
      end

      # Only prompt login if not already authenticated and not already logged in this run
      login_key = registry['url'] || 'docker.io'
      unless logged_in_registries[login_key]
        if registry_authenticated?(login_key)
          puts "Already authenticated to #{login_key}".green
        else
          sh "podman login #{registry['url']}"
        end
        logged_in_registries[login_key] = true
      end

      image.tags.each do |tag|
        ron          = image.parts_join('/', registry_url, registry['org_name'])
        ron_name     = image.parts_join('/', ron, image.image_name)
        ron_name_tag = image.parts_join(':', ron_name, tag)

        # abort if tag doesn't exist or tag is pointing to a different image
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
