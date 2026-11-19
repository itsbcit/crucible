# frozen_string_literal: true

require_relative 'test_helper'

class MergeRegistriesTest < Minitest::Test
  def test_project_and_org_are_aliases_for_org_name
    assert_equal 'p', normalize_registry('url' => 'r', 'project' => 'p')['org_name']
    assert_equal 'o', normalize_registry('url' => 'r', 'org' => 'o')['org_name']
    assert_equal 'n', normalize_registry('url' => 'r', 'org_name' => 'n', 'project' => 'p')['org_name']
  end

  def test_same_registry_merges_later_levels_win
    top     = [{ 'url' => 'r', 'org_name' => 'o', 'extra' => 'top' }]
    version = [{ 'url' => 'r', 'project' => 'o', 'extra' => 'version' }]
    merged  = merge_registries(top, version, [])
    assert_equal 1, merged.size
    assert_equal 'version', merged.first['extra']
  end

  def test_different_registries_accumulate
    merged = merge_registries([{ 'url' => 'a', 'org_name' => 'o' }], [], [{ 'url' => 'b', 'org_name' => 'o' }])
    assert_equal %w[a b], merged.map { |r| r['url'] }
  end

  def test_rejects_non_arrays
    assert_raises(RuntimeError) { merge_registries({}, [], []) }
  end
end
