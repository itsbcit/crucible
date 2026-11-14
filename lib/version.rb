# frozen_string_literal: true

# Release stamps, filled in by git archive (export-subst, see .gitattributes)
# when the release assets are built. In a git checkout of crucible itself
# they stay as unexpanded $Format placeholders.
CRUCIBLE_LIB_VERSION = '$Format:%(describe:tags)$'
CRUCIBLE_LIB_COMMIT  = '$Format:%H$'

def crucible_stamp(value)
  value.start_with?('$Format') ? nil : value
end

def crucible_rakefile_commit
  defined?(CRUCIBLE_RAKEFILE_COMMIT) ? crucible_stamp(CRUCIBLE_RAKEFILE_COMMIT) : nil
end

# A Rakefile that does not match lib/ is how TUX-6950 happened: CI's
# "rake install" refreshes lib/ but never the committed Rakefile. Rakefiles
# from before v1.4.9 define no CRUCIBLE_RAKEFILE_COMMIT at all.
def crucible_version_mismatch
  lib_commit = crucible_stamp(CRUCIBLE_LIB_COMMIT)
  return nil if lib_commit.nil? # crucible's own checkout: nothing to compare

  rakefile_commit = crucible_rakefile_commit
  return nil if rakefile_commit == lib_commit

  rakefile = rakefile_commit ? rakefile_commit[0, 7] : 'older than v1.4.9'
  "Rakefile (#{rakefile}) does not match crucible lib " \
    "(#{crucible_stamp(CRUCIBLE_LIB_VERSION) || lib_commit[0, 7]}). " \
    'Run "rake update" and commit the Rakefile.'
end
