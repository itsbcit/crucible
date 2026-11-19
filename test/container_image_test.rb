# frozen_string_literal: true

require_relative 'test_helper'

class ContainerImageTest < Minitest::Test
  def image(**opts)
    ContainerImage.new(image_name: 'test', **opts)
  end

  def test_new_build_id_is_written_and_reused
    first = image.build_id
    refute_equal 0, first
    assert_equal first.to_s, File.read('.build_id')
    assert_equal first, image.build_id
  end

  def test_build_id_from_environment
    ENV['BUILD_ID'] = '12345'
    assert_equal 'b12345', image.build_suffix
  end

  def test_build_name_tag
    ENV['BUILD_ID'] = '7'
    assert_equal 'local/test:17-pgvector-b7', image(version: '17', variant: 'pgvector').build_name_tag
    assert_equal 'local/test:b7', image.build_name_tag
  end

  def test_tags_render_erb_and_drop_empty
    ENV['BUILD_ID'] = '7'
    tags = DEFAULT_METADATA['base_tags'] + DEFAULT_METADATA['tags']
    assert_equal %w[17 17-b7 17-latest], image(version: '17', tags: tags).tags
    assert_equal %w[17], image(version: '17', tags: tags, tag_build_id: false).tags - ['17-latest']
    assert_equal %w[b7 latest], image(tags: tags).tags
  end

  def test_git_sha_prefers_ci_commit_sha
    ENV['CI_COMMIT_SHA'] = '0123456789abcdef'
    assert_equal '0123456', image.git_sha
  end

  def test_dir
    assert_equal '.', image.dir
    assert_equal '17-pgvector', image(version: '17', variant: 'pgvector').dir
  end

  def test_scan_ignore_unfixed_flag
    assert_nil image.scan_ignore_unfixed_flag
    assert_equal '--ignore-unfixed', image(scan_ignore_unfixed: true).scan_ignore_unfixed_flag
    assert_equal '--ignore-unfixed=false', image(scan_ignore_unfixed: false).scan_ignore_unfixed_flag
  end

  def test_scan_report_only_from_metadata_or_environment
    refute image.scan_report_only?
    assert image(scan_report_only: true).scan_report_only?
    ENV['SCAN_REPORT_ONLY'] = '1'
    assert image.scan_report_only?
  end

  def test_build_platform_environment_override
    ENV['BUILD_PLATFORM'] = 'linux/arm64'
    assert_equal 'linux/arm64', image.build_platform
  end
end
