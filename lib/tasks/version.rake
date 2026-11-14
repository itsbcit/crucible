# frozen_string_literal: true

desc 'Show the crucible release of the Rakefile and lib/'
task :version do
  lib_version     = crucible_stamp(CRUCIBLE_LIB_VERSION)
  rakefile_commit = crucible_rakefile_commit
  puts "lib:      #{lib_version || 'unreleased checkout'}"
  puts "Rakefile: #{rakefile_commit ? rakefile_commit[0, 7] : 'no release stamp'}"
  if crucible_stamp(CRUCIBLE_LIB_COMMIT).nil?
    puts 'Unreleased crucible checkout; nothing to compare.'
  elsif (mismatch = crucible_version_mismatch)
    puts mismatch.yellow
  else
    puts "Rakefile and lib/ are both #{lib_version}.".green
  end
end

# Warn on every run, except the tasks that fix the mismatch and "version",
# which reports it itself. Warnings go to stderr so they never mix into
# output that callers capture.
unless (Rake.application.top_level_tasks & %w[install update version]).any?
  mismatch = crucible_version_mismatch
  warn "WARNING: #{mismatch}".yellow if mismatch
end
