# Raiden

A 3D graphics library using WGPU

## Setup

### Install SDL3

#### Linux

_NOTE: Your distro may have a pre-built package available
(e.g. [Arch](https://archlinux.org/packages/extra/x86_64/sdl3/))_
* Clone the SDL3 repository: `git clone https://github.com/libsdl-org/SDL`
* Navigate to the repository `cd SDL`
* Run:
    - `cmake -S . -B build`
    - `cmake --build build`
* This will install the compiled libraries to `/usr/local`:
  `sudo cmake --install build --prefix /usr/local`
  If you would like to go somewhere else, replace it in the command.
* Add the path used above to your `LD_LIBRARY_PATH` within your `.bashrc`
  if it is not already present

### Install the Odin compiler

Here are the installation instructions: <https://odin-lang.org/docs/install/>

I recommend cloning the repo and building it yourself if you already have LLVM
installed.  Once built, just make sure you add the location of the repo (or
extracted zip folder if you went with the download method) to your `PATH`.

## TODO

- [ ] Offscreen rendering
- [ ] Sphere primitive
- [ ] Cylinder primitive
- [ ] Basic lighting model
- [ ] User-defined meshes
    - [ ] STL parsing
    - [ ] Jet color mapping
- [ ] Ray collision for selections
    - [ ] Start of UI system
- [ ] Browser application use
- [ ] Add C bindings
    - [ ] Add Python bindings
