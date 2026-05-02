# frozen_string_literal: true

# Reusable container lifecycle helpers for test tasks.
# Custom local/tasks/test.rake overrides can compose these
# to build multi-container test setups without duplicating code.

# Start a detached container and return its ID.
def start_container(tag, opts = '')
  container = `podman run --health-interval=2s -d #{opts} #{tag}`.strip
  unless $?.success?
    puts 'Container failed to start.'.red
    exit 1
  end
  container
end

# Wait for a container to reach "running" state.
# Returns the final state string.
def wait_for_running(container_id, timeout: 10)
  state = ''
  exitcode = nil
  error = nil

  printf 'Waiting for container startup'
  timeout.times do
    state = `podman inspect --format='{{.State.Status}}' #{container_id}`.strip
    exitcode = `podman inspect --format='{{.State.ExitCode}}' #{container_id}`.strip
    error = `podman inspect --format='{{.State.Error}}' #{container_id}`.strip
    exit 1 unless $?.success?
    break if state == 'running'

    if state == 'exited' && exitcode == '0'
      puts "\nContainer entrypoint or command exited cleanly. This container doesn't stay running without arguments, so it needs a custom test, or set test_command to \"sleep infinity\" for an infinite sleep.".yellow
      break
    elsif state == 'exited'
      puts "Container failed to reach \"running\" state. Got \"#{state}\"".red
      puts "Container exit code: #{exitcode}".yellow
      puts "Container error message: #{error}".yellow
      puts '--- begin container logs ---'.yellow
      puts `podman logs #{container_id}`
      puts '--- end container logs ---'.yellow
      exit 1
    end

    printf '.'
    sleep 1
  end
  puts # end of progress dots
  state
end

# Wait for a container's health check to report "healthy".
# Returns the final health status string.
def wait_for_healthy(container_id, timeout: 20)
  container_health = `podman inspect --format='{{.State.Health}}' #{container_id}`.strip
  return nil if container_health == '<nil>'

  printf 'Waiting for container healthy'
  health_status = ''
  timeout.times do
    health_status = `podman inspect --format='{{.State.Health.Status}}' #{container_id}`.strip
    exit 1 unless $?.success?
    break if health_status == 'healthy'

    printf '.'
    sleep 1
  end
  puts
  if health_status != 'healthy'
    puts "Container failed to reach \"healthy\" status. Got \"#{health_status}\"".red
    exit 1
  end
  health_status
end

# Kill and remove a container (idempotent).
def cleanup_container(container_id)
  state = `podman inspect --format='{{.State.Status}}' #{container_id} 2>/dev/null`.strip
  system("podman kill #{container_id}") if state == 'running'
  system("podman rm #{container_id}")
end

# Block form: run a container, yield its ID, and clean up in ensure.
def with_container(tag, opts = '')
  container_id = start_container(tag, opts)
  begin
    yield container_id
  ensure
    cleanup_container(container_id)
  end
end
