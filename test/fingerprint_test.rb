# frozen_string_literal: true

require_relative 'test_helper'

# unchanged_since_published? decides whether a scheduled rebuild skips its
# push. Every unknown must count as changed (push), never as unchanged.
# podman and skopeo are stubbed as singleton methods on the test, which is the
# implicit receiver of the top-level helpers it calls.
class FingerprintTest < Minitest::Test
  def setup
    super
    ENV['BUILD_ID'] = '7'
    @image = ContainerImage.new(
      image_name: 'test', version: '1',
      registries: [{ 'url' => 'reg.example.com', 'org_name' => 'lib' }],
      tags: DEFAULT_METADATA['base_tags'] + DEFAULT_METADATA['tags']
    )
    @local = 'abc'
    @remote = Hash.new('abc')
    @have_skopeo = true
    @asked = []
    stub_tools
  end

  def stub_tools
    test = self
    define_singleton_method(:local_fingerprint) { |_id| test.instance_variable_get(:@local) }
    define_singleton_method(:remote_fingerprint) do |ref|
      test.instance_variable_get(:@asked) << ref
      test.instance_variable_get(:@remote)[ref]
    end
    define_singleton_method(:system) { |*_args| test.instance_variable_get(:@have_skopeo) }
  end

  def unchanged?
    out = nil
    capture_io { out = unchanged_since_published?(@image, 'id') }
    out
  end

  def test_all_published_tags_match
    assert unchanged?
    # b<id> tags are new every build and are not compared.
    assert_equal %w[reg.example.com/lib/test:1 reg.example.com/lib/test:1-latest], @asked
  end

  def test_one_tag_differs
    @remote['reg.example.com/lib/test:1-latest'] = 'old'
    refute unchanged?
  end

  def test_tag_not_published_or_unlabelled
    @remote['reg.example.com/lib/test:1'] = nil
    refute unchanged?
  end

  def test_no_local_fingerprint
    @local = nil
    refute unchanged?
  end

  def test_no_skopeo
    @have_skopeo = false
    refute unchanged?
  end
end
