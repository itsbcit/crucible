# frozen_string_literal: true

desc 'Scan container images for vulnerabilities'
task :scan do
  check_podman!

  severity = ENV.fetch('SEVERITY', 'HIGH,CRITICAL')

  puts '*** Scanning images ***'.green
  $images.each do |image|
    next unless image.build_image?

    build_tag = image.build_name_tag
    puts "Image: #{build_tag}".pink
    sh "trivy image --exit-code 1 --severity #{severity} #{build_tag}"
  end
end
