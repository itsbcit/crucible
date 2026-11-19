# frozen_string_literal: true

require_relative 'test_helper'

class VersionTest < Minitest::Test
  LIB = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
  OTHER = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'

  def test_unexpanded_stamp_reads_as_nil
    assert_nil crucible_stamp('$Format:%H$')
    assert_equal 'v1.0.0', crucible_stamp('v1.0.0')
  end

  # crucible's own checkout has unexpanded placeholders: nothing to compare.
  def test_no_warning_in_crucible_checkout
    assert_nil crucible_version_mismatch
  end

  def test_matching_stamps
    with_const(:CRUCIBLE_LIB_COMMIT, LIB) do
      with_rakefile_commit(LIB) { assert_nil crucible_version_mismatch }
    end
  end

  def test_mismatched_stamps
    with_const(:CRUCIBLE_LIB_COMMIT, LIB) do
      with_const(:CRUCIBLE_LIB_VERSION, 'v9.9.9') do
        with_rakefile_commit(OTHER) do
          assert_match(/Rakefile \(bbbbbbb\) does not match crucible lib \(v9\.9\.9\)/, crucible_version_mismatch)
        end
      end
    end
  end

  # Rakefiles before v1.5.0 define no CRUCIBLE_RAKEFILE_COMMIT.
  def test_unstamped_rakefile
    with_const(:CRUCIBLE_LIB_COMMIT, LIB) do
      with_rakefile_commit(nil) { assert_match(/older than v1\.5\.0/, crucible_version_mismatch) }
    end
  end

  def with_rakefile_commit(value)
    defined = Object.const_defined?(:CRUCIBLE_RAKEFILE_COMMIT)
    old = Object.const_get(:CRUCIBLE_RAKEFILE_COMMIT) if defined
    Object.send(:remove_const, :CRUCIBLE_RAKEFILE_COMMIT) if defined
    Object.const_set(:CRUCIBLE_RAKEFILE_COMMIT, value) if value
    yield
  ensure
    Object.send(:remove_const, :CRUCIBLE_RAKEFILE_COMMIT) if Object.const_defined?(:CRUCIBLE_RAKEFILE_COMMIT)
    Object.const_set(:CRUCIBLE_RAKEFILE_COMMIT, old) if defined
  end
end
