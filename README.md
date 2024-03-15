# Pallas cogs as Docker containers

# Setup

- `docker-context/pallas` is a _git submodule_. You should clone this repo with
`git clone --recursive <this repo's url>`. If you've already cloned it without
that, do `git submodule update --init --recursive`
- install docker on the host system
- `$ docker run hello-world` should work

# Disclaimers

This repo uses Vaporware's fork of Plunder ("Pallas"). For now, it's not too far
off the upstream, but as Pallas continues building toward a system that can support end-user
apps it may drift further.

One major difference in this Docker+Pallas context is **the runtime forces cogs
to attach to port 8080**. This is _only_ reasonable in Docker (or maybe other
specific contexts). Standard Plunder/Pallas currently chooses a random port for
each new cog. This makes Docker use infeasible.

In the future, Vaporware will supply a Pallas image on a Docker registry
somewhere so you can simply pull it. For now, you have to build it yourself, and
it's gonna take a little while.

# Building cog-specific images

This process gets you an image that just runs a single cog on a ship in a container.

In step 1, a build phase creates all the pallas dependencies, followed by a
runtime phase that takes just the binaries needed and starts a fresh image. This
keeps the runtime container relatively trim (but more can be done, see `TODO`
below).
Alternatively, you can just pull our pre-built image.

Both steps 2 and 3 rely on step 1, so definitely do Step 1 first. If you want to
build a cog-specific container, go from 1 -> 3. if you just want a basic sire
container, go from 1 -> 2.

1. Get a base Pallas image:
  - Option 1: Pull from Docker Hub registry (Recommended):
    - Pull the image: `$ docker pull deathtothecorporation/pallas-deps`
    - Tag it for use here `$ docker tag deathtothecorporation/pallas-deps pallas-deps-no-pallas-dir:latest`
  - Option 2: Build it yourself: Build a base ubuntu image that has the pallas binaries without all the Haskell stack stuff: `$ docker build -f Dockerfile.base-pallas-deps -t pallas-deps-no-pallas-dir .` (**note the dot at the end!**)
    - If there are pallas updates you need to integrate, pass `--no-cache` here to make sure `stack install` runs again. If you're running this for the first time, the `--no-cache` is irrelevant
    - `stack install` will take a long time.
    - This works by first doing a `builder` stage that uses Stack to build pallas.
      Then a `runtime` stage creates a fresh ubuntu image, copying in the binaries
      from the `builder` stage. The resulting `runtime` image is much smaller than
      the `builder` image - it's pretty much just the plunder binaries and some other
      dependencies. In step 3, we'll bring in the sire files on their own and,
      combining the binaries from this image and the sire files from the
      docker-context, we can run pallas.
2. (Optional, probably skip) Get a sire image (pallas deps plus sire directory and nothing else): `$ docker build -f Dockerfile.basic-pallas-sire -t just-sire .`
    - uses the `pallas-deps-no-pallas-dir` image as a base.
    - this image isn't actually used in this project, but it might be useful to get a sire-only image
3. Build and run a cog-specific image:
    1. Create a `Dockerfile.<some-name-for-your-cog>` based off `Dockerfile.cog-template`
        - in the above template, `<your-cog-ui-and-start-files>` will be specific to
          your app, but typically will contain built UI files and a `start.sh`
          entrypoint for docker to run. Any ENV variables that may be necessary can be
          caught by this `.sh` file and used to help bootstrap the cog.
        - Note also: `FROM pallas-deps-no-pallas-dir:latest` - this is the name of
          the image created in step #1.
        - See `docker-context/image-gallery-app/start.sh` for an example. For instance, these
          lines:
            ```
              SIRE_FILE="sire/demo_image_gallery.sire"
              UI_DIR="image-gallery/image-gallery-ui"
            ```
          Determine the sire file and the ui directory (the build UI files from
          above step) that will be uploaded on boot.
    2. Build the image: `$ docker build -f Dockerfile.<some-name-for-your-cog> -t mycog .`
    3. Start that cog: `docker run -e "ANY_ENV_YOU_NEED=goes-here" -p <some-host-port>:8080 mycog`
        - Or use an env file `docker run --env-file .env mycog`
        - For testing, you probably want to pass `-it -name <some-name>` to keep the
        container interactive if you want watch the logs, etc.

**By the end of step 3 above, you should have a docker image that boots up a plunder
ship running a single cog, nearly instantaneously.**  
This is useful for local development on various host machines, or for hosted
environments.


# Just gimmie a Sire repl!

Okay.

## The easy way:

1. `$ docker pull deathtothecorporation/sire-repl`
2. `$ docker run -it deathtothecorporation/sire-repl`

## The harder way:

1. Get a base image from step 1 above.
2. Build a repl image: `docker build -f Dockerfile.sire-repl -t repl .`
3. Finally, start a container: `docker run -it repl`

This runs `plunder sire sire/prelude.sire`. See the `prelude.sire` file if
you're curious about how it works.

---

# TODO:

- [x] create a new base image that doesn't copy in the plunder directory
- [x] then create a docker-context/plunder that only has the base plunder sire files (maybe as a submodule)
- [x] then create an image per "app" (image, pfp, plunterr, etc).
- [x] deal with ports.
  - idea 1: have cogs always choose a single port, then `docker run -p
  [host_port]:[deterministic_cog_port] image_name`
- [x] update sh scripts to use docker images /bins
- [x] include plunder/pallas as a submodule
- [ ] try an alpine build for much smaller size - will be harder to get the build right though
- [ ] trim binaries in runtime stage
- [x] push pallas image to a private docker hub to avoid having to rebuild
- [ ] rename image tags in Dockerfiles so that manual tagging isn't required
      after pulling from registry
