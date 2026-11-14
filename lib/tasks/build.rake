# frozen_string_literal: true

desc 'Build container images'
task :build do
  check_podman!

  puts '*** Building images ***'.green
  $images.each do |image|
    next unless image.build_image?

    build_tag = image.build_name_tag
    puts "Image: #{build_tag}".pink
    # sh aborts the task on a non-zero exit, so a failed hook stops the build.
    image.pre_build.each { |command| sh command }
    build_command = "podman build --platform #{image.build_platform} --iidfile #{image.iidfile} -f #{image.dockerfile} -t #{build_tag}"
    sh "#{build_command} ."

    # Label the image with its content fingerprint (see fingerprint.rb). The
    # package list is only known once the image exists, so this repeats the
    # build with the label added; every layer comes from cache.
    fingerprint = image_fingerprint(image)
    if fingerprint
      sh "#{build_command} --label #{FINGERPRINT_LABEL}=#{fingerprint} ."
      puts "Fingerprint: #{fingerprint}"
    else
      puts 'No fingerprint (no apk, rpm or dpkg in the image): it will always be pushed.'.yellow
    end
    puts "Image ID: #{image.image_id}"
  end
end
