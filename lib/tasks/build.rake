# frozen_string_literal: true

desc 'Build container images'
task :build do
  check_podman!

  puts '*** Building images ***'.green
  $images.each do |image|
    next unless image.build_image?

    build_tag = image.build_name_tag
    puts "Image: #{build_tag}".pink
    sh "podman build --platform #{image.build_platform} -f #{image.dockerfile} -t #{build_tag} ."
    image_id = `podman image ls -q #{build_tag}`.strip
    puts "Image ID: #{image_id}"
  end
end
