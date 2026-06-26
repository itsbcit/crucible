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
