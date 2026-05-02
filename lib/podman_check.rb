# frozen_string_literal: true

# Verify that podman is available and responsive
def check_podman!
  unless system('podman info > /dev/null 2>&1')
    abort 'podman is not available. Install podman and ensure it is running.' \
          "\n  macOS: brew install podman && podman machine init && podman machine start" \
          "\n  Linux: https://podman.io/docs/installation"
  end
end
