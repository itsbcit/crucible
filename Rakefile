# frozen_string_literal: true

require 'erb'
require 'fileutils'
require 'tempfile'
require 'yaml'
require 'open-uri'

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

  filter_version = ENV['VERSION']
  filter_variant = ENV['VARIANT']
  $images.select! { |i| i.version == filter_version } if filter_version
  $images.select! { |i| i.variant == filter_variant } if filter_variant
end

desc 'Install Rakefile support files'
task :install do
  crucible_ref = ENV['CRUCIBLE_REF']

  if crucible_ref
    # Download archive for a specific branch or tag.
    # GitHub's /archive/<ref>.zip works for both branches and tags.
    archive_url = "https://github.com/itsbcit/crucible/archive/#{crucible_ref}.zip"
    extract_dir = "crucible-#{crucible_ref}"
    puts "Installing crucible lib and Rakefile from ref: #{crucible_ref}".green
    URI.parse(archive_url).open do |archive|
      tempfile = Tempfile.new(['crucible', '.zip'])
      File.open(tempfile.path, 'wb') { |f| f.write(archive.read) }
      tmpdir = Dir.mktmpdir
      system('unzip', '-q', tempfile.path, '-d', tmpdir)
      tempfile.unlink
      FileUtils.remove_entry('lib') if File.exist?('lib')
      FileUtils.mv(File.join(tmpdir, extract_dir, 'lib'), '.')
      FileUtils.cp(File.join(tmpdir, extract_dir, 'Rakefile'), 'Rakefile')
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
