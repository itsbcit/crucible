# frozen_string_literal: true

require 'digest'
require 'shellwords'

# Content fingerprints, so a scheduled rebuild that produced nothing new does
# not republish.
#
# Every build stamps a new build_id label, so a rebuild of unchanged content is
# still a new image digest. Republishing it daily moved every tag to a new
# digest, which made "did the image change?" checks downstream (e.g. pgsql-bby's
# quadlet playbook comparing image IDs) fire every day, and pushed out older
# b<id> tags under Harbor's keep-the-last-30 retention.
#
# The fingerprint covers the rendered Containerfile without its build_id line
# (so a CMD or ENV change counts) and the image's installed package list. It is
# stored as an image label at build time; rake push compares it with the label
# on each published tag.

FINGERPRINT_LABEL = 'crucible.fingerprint'

# First package manager found wins. An image with none, or without sh, gets no
# fingerprint and is always pushed.
PACKAGE_LIST_COMMAND = 'if command -v apk >/dev/null 2>&1; then apk info -v; ' \
                       'elif command -v rpm >/dev/null 2>&1; then rpm -qa; ' \
                       'elif command -v dpkg-query >/dev/null 2>&1; then dpkg-query -W; ' \
                       'else exit 1; fi'

# Returns the fingerprint of a built image, or nil when it cannot be computed.
def image_fingerprint(image)
  return nil if image.image_id.nil? || !File.exist?(image.dockerfile)

  containerfile = File.readlines(image.dockerfile).reject { |line| line.include?('build_id') }.join
  packages = `podman run --rm --entrypoint sh #{image.image_id} -c #{Shellwords.escape(PACKAGE_LIST_COMMAND)} 2>/dev/null`
  return nil unless $?.success? && !packages.strip.empty?

  Digest::SHA256.hexdigest(containerfile + packages.lines.sort.join)
end

# Fingerprint label on a local image, or nil.
def local_fingerprint(image_id)
  label = `podman image inspect --format '{{index .Config.Labels "#{FINGERPRINT_LABEL}"}}' #{image_id} 2>/dev/null`.strip
  label.empty? || label == '<no value>' ? nil : label
end

# Fingerprint label on a published tag, read with skopeo (no pull), or nil
# when the tag does not exist, has no label, or cannot be read.
def remote_fingerprint(ron_name_tag)
  label = `skopeo inspect --no-tags --format '{{index .Labels "#{FINGERPRINT_LABEL}"}}' docker://#{ron_name_tag} 2>/dev/null`.strip
  $?.success? && !label.empty? && label != '<no value>' ? label : nil
end
