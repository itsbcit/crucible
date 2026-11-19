# frozen_string_literal: true

require_relative 'test_helper'

class BuildObjectsArrayTest < Minitest::Test
  MATRIX = {
    'image_name' => 'test',
    'versions'   => { '17' => {}, '18' => {} },
    'variants'   => { '' => {}, 'pgvector' => {} }
  }.freeze

  def cells(images)
    images.map { |i| [i.version, i.variant] }
  end

  def test_version_by_variant_matrix
    assert_equal [%w[17 base], %w[17 pgvector], %w[18 base], %w[18 pgvector]],
                 cells(images_for(MATRIX)).map { |v, x| [v, x.empty? ? 'base' : x] }
  end

  def test_unversioned_repo_is_one_image
    images = images_for('image_name' => 'test')
    assert_equal [['', '']], cells(images)
  end

  def test_empty_image_name_raises
    assert_raises(RuntimeError) { images_for('versions' => { '1' => {} }) }
  end

  def test_de_version_is_rejected
    error = assert_raises(RuntimeError) { images_for('image_name' => 'test', 'vars' => { 'de_version' => '1' }) }
    assert_match(/ce_version/, error.message)
  end

  # 3b70668: a variant override under one version applied to every version
  # processed after it.
  def test_per_version_variant_override_does_not_leak
    metadata = MATRIX.merge(
      'versions' => { '17' => { 'variants' => { 'pgvector' => { 'vars' => { 'pgv' => '0.7' } } } }, '18' => {} }
    )
    by_cell = images_for(metadata).to_h { |i| [[i.version, i.variant], i] }
    assert_equal '0.7', by_cell[%w[17 pgvector]].vars['pgv']
    assert_nil by_cell[%w[18 pgvector]].vars['pgv']
  end

  def test_vars_merge_top_version_variant
    metadata = {
      'image_name' => 'test',
      'vars'       => { 'a' => 'top', 'b' => 'top', 'c' => 'top' },
      'versions'   => { '1' => { 'vars' => { 'b' => 'version', 'c' => 'version' } } },
      'variants'   => { '' => { 'vars' => { 'c' => 'variant' } } }
    }
    vars = images_for(metadata).first.vars
    assert_equal %w[top version variant], vars.values_at('a', 'b', 'c')
    assert_equal DEFAULT_METADATA['base_vars']['tini_version'], vars['tini_version']
  end

  def test_pre_build_concatenates_levels_in_order
    metadata = {
      'image_name' => 'test',
      'pre_build'  => ['top'],
      'versions'   => { '1' => { 'pre_build' => ['version'] } },
      'variants'   => { '' => { 'pre_build' => ['variant <%= version %>'] } }
    }
    assert_equal ['top', 'version', 'variant 1'], images_for(metadata).first.pre_build
  end

  def test_scan_options_inherit_and_override
    metadata = MATRIX.merge(
      'scan_report_only' => true,
      'versions'         => { '17' => { 'scan_ignore_unfixed' => true }, '18' => {} },
      'variants'         => { '' => {}, 'pgvector' => { 'scan_report_only' => false } }
    )
    by_cell = images_for(metadata).to_h { |i| [[i.version, i.variant], i] }
    assert by_cell[['17', '']].scan_report_only?
    refute by_cell[%w[17 pgvector]].scan_report_only?
    assert_equal '--ignore-unfixed', by_cell[['17', '']].scan_ignore_unfixed_flag
    assert_nil by_cell[['18', '']].scan_ignore_unfixed_flag
  end

  def test_scan_ignore_unfixed_rejects_non_boolean
    error = assert_raises(RuntimeError) { images_for('image_name' => 'test', 'scan_ignore_unfixed' => 'yes') }
    assert_match(/scan_ignore_unfixed/, error.message)
  end

  def test_depends_on_is_carried_through
    metadata = MATRIX.merge('variants' => { '' => {}, 'pgvector' => { 'depends_on' => '' } })
    by_variant = images_for(metadata).select { |i| i.version == '17' }.to_h { |i| [i.variant, i] }
    assert_nil by_variant[''].depends_on
    assert_equal '', by_variant['pgvector'].depends_on
  end

  def test_filter_applies_by_default_and_not_with_filter_false
    ENV['VERSION'] = '18'
    assert_equal %w[18 18], images_for(MATRIX, true).map(&:version)
    assert_equal 4, images_for(MATRIX, false).size
  end
end
