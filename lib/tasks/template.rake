# frozen_string_literal: true

desc 'Update Containerfile templates'
task :template do
  dummy = ContainerImage.new(image_name: 'dummy')
  dummy.new_build_id if ENV['KEEP_BUILD'].nil?
  build_id = dummy.build_id
  dummy = nil
  puts "*** New Build ID: #{build_id} ***".green
  puts '*** Rendering templates ***'.green

  $images.each do |image|
    image.build_id = build_id
    puts "Image: #{image.build_name_tag}"
    dir = image.dir
    FileUtils.mkdir_p(dir) unless Dir.exist?(dir)

    # TODO: implement per-"version-variant" rendered files
    image.template_files.each do |file|
      unless File.exist?(file)
        puts "WARNING: file not found: #{file}".red
        next
      end
      # if this is an ERB template...
      # TODO: rewrite this using ruby File methods basename, extname, etc
      if (file.size > 4) && (file[-4..-1] == '.erb')
        # render the file without .erb extension
        outfile = file[0..-5]
        puts "\tRendering #{dir}/#{outfile}"
        render_template(file, "#{dir}/#{outfile}", binding)
      else
        next if dir == '.'

        # Deprecation warning
        puts "\tWARNING: #{file} is not a templated file: not copying!".yellow
      end
    end

    search_dirs = [dir]
    search_dirs << image.variant if image.variant != ''
    search_dirs << image.version if image.version != ''
    search_dirs << '.'

    template_src = nil
    search_dirs.each do |search_dir|
      ['Containerfile.erb', 'Dockerfile.erb'].each do |name|
        candidate = search_dir == '.' ? name : "#{search_dir}/#{name}"
        if File.exist?(candidate)
          template_src = candidate
          break
        end
      end
      break if template_src
    end

    if template_src
      puts "\tRendering #{dir}/Containerfile from #{template_src}"
      render_template(template_src, "#{dir}/Containerfile", binding)
    else
      puts "\tNo Containerfile template to render".yellow
    end
  end
end
