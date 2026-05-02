# frozen_string_literal: true

desc 'Scan container images for vulnerabilities'
task :scan do
  check_podman!

  severity = ENV.fetch('SEVERITY', 'HIGH,CRITICAL')

  puts '*** Scanning images ***'.green
  $images.each do |image|
    next unless image.build_image?

    puts "Image: #{image.build_name_tag}".pink

    image_id = image.image_id
    if image_id.nil?
      puts "Image #{image.build_name_tag} has not been built.".red
      exit 1
    end

    sh "trivy image --exit-code 1 --severity #{severity} #{image_id}"
  end
end
