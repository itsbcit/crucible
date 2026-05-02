# frozen_string_literal: true

desc 'Patch existing images with security updates'
task :patch do
  check_podman!

  patch_cmd = ENV.fetch('PATCH_CMD', 'apk upgrade --no-cache')

  puts '*** Patching images ***'.green
  $images.each do |image|
    next unless image.build_image?

    # Determine which image to patch
    if ENV['PATCH_BASE']
      base_tag = ENV['PATCH_BASE']
    else
      base_tag = image.build_name_tag
    end

    puts "Patching: #{base_tag}".pink

    # Verify the base image exists
    image_id = `podman image ls -q #{base_tag}`.strip
    if image_id.empty?
      puts "Base image #{base_tag} not found. Build or pull it first.".red
      exit 1
    end

    # Determine patch suffix (increment pN based on existing patches)
    patch_num = 1
    loop do
      candidate = "#{base_tag}-p#{patch_num}"
      existing = `podman image ls -q #{candidate}`.strip
      break if existing.empty?

      patch_num += 1
    end
    patch_tag = "#{base_tag}-p#{patch_num}"

    puts "Patch tag: #{patch_tag}".yellow
    puts "Patch command: #{patch_cmd}".yellow

    # Create a container from the base image, apply the patch, commit
    container = `podman create #{base_tag} sleep infinity`.strip
    unless $?.success?
      puts 'Failed to create patch container.'.red
      exit 1
    end

    begin
      sh "podman start #{container}"
      sh "podman exec #{container} sh -c '#{patch_cmd}'"
      sh "podman commit #{container} #{patch_tag}"
      puts "Patched image: #{patch_tag}".green
    ensure
      system("podman kill #{container} 2>/dev/null")
      system("podman rm #{container}")
    end
  end
end
