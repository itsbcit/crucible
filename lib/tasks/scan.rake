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

    # Export to a docker-format archive and scan that, rather than passing the
    # image reference to trivy directly.
    #
    # Trivy resolves a local image by talking to a container runtime socket. It
    # has none inside the woodpecker-crucible CI container, and on a rootless
    # podman workstation it probes a RELATIVE path ("podman/podman.sock") so it
    # misses $XDG_RUNTIME_DIR/podman/podman.sock. With no socket it falls
    # through to its "remote" resolver and tries to pull from Docker Hub:
    #
    #   unable to find the specified image "sha256:..." in
    #   [docker containerd podman remote]
    #   remote error: GET https://index.docker.io/v2/library/sha256/manifests/...
    #   UNAUTHORIZED: authentication required
    #
    # Passing the tag instead of the digest does not help; the problem is the
    # missing socket, not the reference format.
    #
    # The archive format matters: "--format oci-archive" is rejected by trivy
    # with "file manifest.json not found in tar".
    archive = File.join(Dir.tmpdir,
                        "trivy-#{image.image_name}-#{image.build_suffix}.tar")
    begin
      sh "podman save --format docker-archive -o #{archive} #{image_id}"
      sh "trivy image --scanners vuln --skip-version-check " \
         "--exit-code 1 --severity #{severity} --input #{archive}"
    ensure
      FileUtils.rm_f(archive)
    end
  end
end
