# frozen_string_literal: true

require 'erb'
require 'fileutils'
require 'tempfile'
require 'yaml'
require 'open-uri'

# Release commit, stamped by git archive (see .gitattributes). lib/ compares
# it with its own to warn when the Rakefile and lib/ come from different
# releases.
CRUCIBLE_RAKEFILE_COMMIT = '$Format:%H$'

Dir.glob('lib/*.rb').each { |l| load l unless File.exist?("local/#{l[4..-1]}") } if Dir.exist?('lib')
Dir.glob('local/*.rb').each { |l| load l } if Dir.exist?('local')

if File.exist?('metadata.yaml')
  local_metadata = YAML.safe_load(File.read('metadata.yaml'))
else
  puts('WARNING: metadata.yaml not found.')
  local_metadata = {}
end

puts('WARNING: Rakefile library not found.') unless File.exist?('lib')

if File.exist?('lib/metadata-defaults.yaml')
  default_metadata = YAML.safe_load(File.read('lib/metadata-defaults.yaml'))
else
  puts('WARNING: metadata defaults not found.')
  default_metadata = {}
end

if File.exist?('metadata.yaml') && File.exist?('lib')
  $images = build_objects_array(
    metadata: local_metadata,
    default_metadata: default_metadata
  )
end

desc 'Install Rakefile support files'
task :install do
  crucible_ref = ENV['CRUCIBLE_REF']

  if crucible_ref
    # Download archive for a specific branch or tag.
    # GitHub's /archive/<ref>.zip works for both branches and tags.
    archive_url = "https://github.com/itsbcit/crucible/archive/#{crucible_ref}.zip"
    # No .green here: colorize lives in lib/, which may not exist yet.
    puts "Installing crucible lib and Rakefile from ref: #{crucible_ref}"
    URI.parse(archive_url).open do |archive|
      tempfile = Tempfile.new(['crucible', '.zip'])
      File.open(tempfile.path, 'wb') { |f| f.write(archive.read) }
      tmpdir = Dir.mktmpdir
      system('unzip', '-q', tempfile.path, '-d', tmpdir)
      tempfile.unlink
      # The archive's top-level directory is named after the resolved ref (a
      # short SHA expands to the full SHA, a "v" tag may lose its "v"), so find
      # it rather than predicting it. Check before removing lib/, so a bad ref
      # cannot leave the repo with no lib/ at all.
      extract_dir = Dir.glob(File.join(tmpdir, 'crucible-*')).first
      unless extract_dir && File.directory?(File.join(extract_dir, 'lib'))
        FileUtils.remove_entry(tmpdir)
        abort "No lib/ found in #{archive_url}; existing lib/ left untouched."
      end
      FileUtils.remove_entry('lib') if File.exist?('lib')
      FileUtils.mv(File.join(extract_dir, 'lib'), '.')
      FileUtils.cp(File.join(extract_dir, 'Rakefile'), 'Rakefile')
      FileUtils.remove_entry(tmpdir)
    end
  else
    # Download lib zip from latest release
    URI.parse('https://github.com/itsbcit/crucible/releases/latest/download/crucible-lib.zip').open do |archive|
      FileUtils.remove_entry('lib') if File.exist?('lib')
      tempfile = Tempfile.new(['lib', '.zip'])
      File.open(tempfile.path, 'wb') { |f| f.write(archive.read) }
      system('unzip', tempfile.path)
      tempfile.unlink
    end
  end
end

desc 'Update Rakefile to latest release version'
task :update do
  Rake::Task[:install].invoke
  # When CRUCIBLE_REF is set, rake install already copies the Rakefile from the archive
  unless ENV['CRUCIBLE_REF']
    URI.parse('https://github.com/itsbcit/crucible/releases/latest/download/Rakefile').open do |rakefile|
      File.open('Rakefile', 'wb') { |f| f.write(rakefile.read) }
    end
  end
end

Dir.glob('lib/tasks/*.rake').each { |l| load l unless File.exist?("local/tasks/#{l[10..-1]}") } if Dir.exist?('lib/tasks')
Dir.glob('local/tasks/*.rake').each { |l| load l } if Dir.exist?('local/tasks')
