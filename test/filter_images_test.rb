# frozen_string_literal: true

require_relative 'test_helper'

class FilterImagesTest < Minitest::Test
  def images
    images_for(
      'image_name' => 'test',
      'versions'   => { '17' => {}, '18' => {} },
      'variants'   => { '' => {}, 'pgvector' => {} }
    )
  end

  def cells(selected)
    selected.map { |i| [i.version, i.variant] }
  end

  def test_no_filter_returns_everything
    assert_equal 4, filter_images(images, version: nil, variant: nil).size
  end

  def test_version_only
    assert_equal [['17', ''], %w[17 pgvector]], cells(filter_images(images, version: '17', variant: nil))
  end

  def test_variant_only
    assert_equal [%w[17 pgvector], %w[18 pgvector]], cells(filter_images(images, version: nil, variant: 'pgvector'))
  end

  # Generated base-variant steps export VARIANT='' to select only the base
  # image; unset VARIANT would match every variant.
  def test_empty_variant_selects_base_only
    assert_equal [['18', '']], cells(filter_images(images, version: '18', variant: ''))
  end

  def test_reads_environment_by_default
    ENV['VERSION'] = '18'
    ENV['VARIANT'] = 'pgvector'
    assert_equal [%w[18 pgvector]], cells(filter_images(images))
  end

  # A filter matching nothing must abort, never return an empty list: every
  # task would then be a silent no-op and the pipeline would go green.
  def test_no_match_aborts
    _out, err = capture_subprocess_io do
      assert_raises(SystemExit) { filter_images(images, version: '16', variant: nil) }
    end
    assert_match(/No image in metadata.yaml matches VERSION=16/, err)
  end
end
