# Stage 1: build the application using Nix
FROM ubuntu:latest as builder

# Enable flakes globally
ENV NIX_CONF_DIR=/etc/nix
RUN echo 'experimental-features = nix-command flakes' >> /etc/nix/nix.conf

# Copy local plunder directory to docker image
COPY ./plunder /plunder
WORKDIR /plunder

# Use `nix develop` in a non-interactive way to set up the environment and then build the project with `stack`
# RUN nix develop .#plunder --command "stack build"
RUN nix develop -c stack build

# Stage 2: Create the *runtime* container
FROM ubuntu:latest

# Copy the build artifact from the builder stage
COPY --from=builder /plunder/.stack-work /plunder/.stack-work
# TODO: Here, adjust the copy path '/app/result' based on where the build artifacts are located

# Set the working directory to where you've copied your build artifacts
WORKDIR /plunder

# (Optional) If your application requires runtime dependencies, install them here

# The command to start the application
CMD ["nix", "develop", "-c", "plunder"]
