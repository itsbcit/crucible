# frozen_string_literal: true

###
# These tests assume that the container has a defined command that stays running indefinitely.
# If the container runs a command without a wait loop, you'll have to redefine the whole testing procedure.
# For custom tests, override this file in local/tasks/test.rake and use the helpers in lib/test_helpers.rb.

desc 'Test container images'
task :test do
  check_podman!

  puts '*** Testing images ***'.green
  $images.each do |image|
    next unless image.test_image?

    puts "Image: #{image.build_name_tag}".pink

    image_id = image.image_id
    if image_id.nil?
      puts "Image #{image.build_name_tag} has not been built.".red
      exit 1
    end

    with_container(image_id, image.test_command) do |container|
      wait_for_running(container)
      wait_for_healthy(container)

      ###
      # put your custom image tests here
      ###
    end

    puts "Testing image #{image.build_tag} successful.".green
  end
end
