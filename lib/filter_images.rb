# frozen_string_literal: true

# Restrict an image list to the VERSION and/or VARIANT environment variables.
#
# This lives in lib/ rather than the Rakefile because consumers commit their
# Rakefile and CI only runs "rake install", which refreshes lib/ but never the
# Rakefile. Logic in the Rakefile therefore reaches a consumer only when
# someone remembers "rake update"; until v1.4.8 this filter sat there, and
# container-qgis-server (TUX-6950) built every version in every per-version
# step on a Rakefile that predated it.
def filter_images(images, version: ENV['VERSION'], variant: ENV['VARIANT'])
  return images unless version || variant

  selected = images
  selected = selected.select { |i| i.version == version } if version
  selected = selected.select { |i| i.variant == variant } if variant

  # A filter matching nothing is an error, not an empty success.
  #
  # Without this, every task iterates an empty $images and exits 0: "rake
  # build" prints "Building images" and builds none, "rake tag" tags none,
  # "rake push" pushes none -- a green pipeline that produced no artifact.
  # This bit container-wolfi-nginx when a version key was renamed in
  # metadata.yaml but the generated .woodpecker/build.yaml still passed the
  # old VERSION, and the failure was only noticed when a downstream deploy
  # could not pull the image that was never published.
  if selected.empty?
    wanted = []
    wanted << "VERSION=#{version}" if version
    wanted << "VARIANT=#{variant}" if variant
    have = images.map { |i| "VERSION=#{i.version.empty? ? '(none)' : i.version} VARIANT=#{i.variant.empty? ? '(none)' : i.variant}" }
    abort "No image in metadata.yaml matches #{wanted.join(' ')}.\n" \
          "Available:\n  #{have.uniq.join("\n  ")}\n" \
          'If the version matrix changed, re-run "rake woodpecker" to regenerate the pipeline.'
  end

  selected
end
