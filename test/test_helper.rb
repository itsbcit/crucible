# frozen_string_literal: true

# Shared setup for crucible's own tests. Run them all with:
#
#   ruby test/all.rb
#
# They need only Ruby and the minitest gem: no podman, trivy, skopeo or
# network. Nothing here ships to consumers; the release zip holds lib/ only.

require 'minitest/autorun'
require 'erb'
require 'fileutils'
require 'open3'
require 'rake'
require 'tmpdir'
require 'yaml'

CRUCIBLE_ROOT = File.expand_path('..', __dir__)

# Load lib/ the way the Rakefile does, tasks included, so tests can call the
# helpers the tasks define (e.g. unchanged_since_published? in push.rake).
Dir.glob(File.join(CRUCIBLE_ROOT, 'lib/*.rb')).sort.each { |f| load f }
Dir.glob(File.join(CRUCIBLE_ROOT, 'lib/tasks/*.rake')).sort.each { |f| load f }

DEFAULT_METADATA = YAML.safe_load(File.read(File.join(CRUCIBLE_ROOT, 'lib/metadata-defaults.yaml')))

module CrucibleTest
  # Every test runs in its own empty directory: ContainerImage reads and
  # writes .build_id in the working directory.
  def setup
    super
    @saved_env = ENV.to_h
    %w[VERSION VARIANT BUILD_ID KEEP_BUILD SCAN_REPORT_ONLY BUILD_PLATFORM CI_COMMIT_SHA].each { |k| ENV.delete(k) }
    @tmpdir = Dir.mktmpdir('crucible-test')
    @olddir = Dir.pwd
    Dir.chdir(@tmpdir)
  end

  def teardown
    Dir.chdir(@olddir)
    FileUtils.rm_rf(@tmpdir)
    ENV.replace(@saved_env)
    super
  end

  # The image matrix for a metadata hash, unfiltered unless filter is true.
  # filter is positional: with a keyword, a braceless string-keyed hash
  # argument would be taken as keywords. The metadata is copied because
  # build_objects_array defines a singleton method on the hash it is given.
  def images_for(metadata, filter = false)
    build_objects_array(metadata: Marshal.load(Marshal.dump(metadata)),
                        default_metadata: Marshal.load(Marshal.dump(DEFAULT_METADATA)), filter: filter)
  end

  # Runs "rake woodpecker" in a scratch consumer repo (the real Rakefile and
  # lib/) and returns [parsed pipeline, raw YAML]. Raises with rake's output
  # if it fails; use rake_woodpecker_error for the expected-failure case.
  def generate_pipeline(metadata)
    out, ok = run_rake_woodpecker(metadata)
    raise "rake woodpecker failed:\n#{out}" unless ok

    # Explicit encoding: the header has a non-ASCII dash, and in a container
    # with no locale Ruby would read the file as US-ASCII.
    raw = File.read('.woodpecker/build.yaml', encoding: 'UTF-8')
    [YAML.safe_load(raw), raw]
  end

  # The metadata.yaml error message from a failing "rake woodpecker".
  def rake_woodpecker_error(metadata)
    out, ok = run_rake_woodpecker(metadata)
    flunk "rake woodpecker succeeded, expected it to fail:\n#{out}" if ok
    out[/metadata\.yaml: .*/] || out
  end

  def run_rake_woodpecker(metadata)
    FileUtils.cp(File.join(CRUCIBLE_ROOT, 'Rakefile'), '.')
    FileUtils.cp_r(File.join(CRUCIBLE_ROOT, 'lib'), '.')
    File.write('metadata.yaml', metadata.to_yaml)
    out, status = Open3.capture2e('rake', 'woodpecker')
    [out, status.success?]
  end

  # Temporarily replaces a top-level constant (e.g. a release stamp).
  def with_const(name, value)
    old = Object.const_get(name)
    Object.send(:remove_const, name)
    Object.const_set(name, value)
    yield
  ensure
    Object.send(:remove_const, name)
    Object.const_set(name, old)
  end
end

class Minitest::Test
  include CrucibleTest
end
