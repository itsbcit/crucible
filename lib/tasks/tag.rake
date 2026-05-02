# frozen_string_literal: true

desc 'Tag container images'
task :tag do
  check_podman!

  # keep track of image IDs we've seen and make sure we're not creating conflicting tags
  seen_images = {}

  puts '*** Tagging images ***'.green
  $images.each do |image|
    next unless image.tag_image?

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

        # abort if we're trying to overwrite a tag already assigned to a different image in this run
        image_tag_id = `podman image ls -q #{ron_name_tag}`.strip
        if !seen_images[image_tag_id].nil? && (image_tag_id != image_id)
          puts "#{ron_name_tag} already tagged to #{seen_images[image_tag_id]}\nTag conflict! Check tags in metadata.yaml or \"rake clean\".".red
          exit 1
        end

        sh "podman tag #{image_id} #{ron_name_tag}"
      end
    end
  end
end
