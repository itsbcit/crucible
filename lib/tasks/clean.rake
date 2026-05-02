# frozen_string_literal: true

desc 'Clean container build environment'
task :clean do
  check_podman!

  $images.each do |image|
    puts "Image: #{image.build_name_tag}".pink

    # delete image if it exists
    image_id = `podman image ls -q #{image.build_name_tag}`.strip
    sh "podman image rm -f #{image_id}" unless image_id.empty?

    # delete FROM image if it exists
    image_from = image.from
    unless image_from.nil?
      from_id = `podman image ls -q #{image_from}`.strip
      unless from_id.empty?
        puts "Deleting FROM image #{image_from}:".pink
        sh "podman image rm #{from_id}"
      end
    end

    image.registries.each do |registry|
      image.tags.each do |tag|
        ron          = image.parts_join('/', registry['url'], registry['org_name'])
        ron_name     = image.parts_join('/', ron, image.image_name)
        ron_name_tag = image.parts_join(':', ron_name, tag)

        image_tag_id = `podman image ls -q #{ron_name_tag}`.strip
        sh "podman image rm #{ron_name_tag}" unless image_tag_id.empty?
      end
    end
  end

  puts 'Clearing build artifacts:'.pink
  sh 'podman system prune --force'
end
