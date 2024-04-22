package main

// Core
import "core:container/queue"
import "core:log"
import "core:math"
import "core:time"
import "core:fmt"

// Vendor
import sdl "vendor:sdl2"
import vk "vendor:vulkan"

// Libs
import "libs:vkb"
import "libs:vma"

// Debug libs
import "libs:imgui"
import imgui_sdl2 "libs:imgui/imgui_impl_sdl2"
import imgui_vk "libs:imgui/imgui_impl_vulkan"

VulkanEngine :: struct {
  is_initialized: bool,
  frame_number:   u32,
  stop_rendering: bool,
  window_extent:  vk.Extent2D,
  window:         ^sdl.Window,
}

@(private)
_ctx: ^VulkanEngine

// initializes everything in the engine
engine_init :: proc() -> (err: Error) {
  // only one instanced engine is allowed
  assert(_ctx == nil)
  _ctx = new(VulkanEngine) or_return

  if res := sdl.Init({.VIDEO}); res != 0 {
    log.errorf("Failed to initialize SDL: [%s]", sdl.GetError())
    return .SDL_Init_Failed
  }
  defer if err != nil do sdl.Quit()
  
  window_flags: sdl.WindowFlags = {.VULKAN}

  _ctx.window_extent = { 800, 600 }

  _ctx.window = sdl.CreateWindow(
    "VulkanEngine",
    sdl.WINDOWPOS_UNDEFINED,
    sdl.WINDOWPOS_UNDEFINED,
    i32(_ctx.window_extent.width),
    i32(_ctx.window_extent.height),
    window_flags,
  )

  _ctx.is_initialized = true

  return nil
}

// run main loop
engine_run :: proc() {
  event := new(sdl.Event)
  b_quit := false

  stop_rendering := false

  // main loop
  for !b_quit {
    // handle events on queue
    for sdl.PollEvent(event) != false {
      // close the window when user alt-F4s or clicks the X button

      if event.type == .QUIT {
        b_quit = true
      }

      if event.type == .WINDOWEVENT {
        if event.window.event == .MINIMIZED {
          stop_rendering = true
        }

        if event.window.event == .RESTORED {
          stop_rendering = false
        }
      }

      if event.type == .KEYDOWN {
        fmt.println(event.key.keysym.sym)
      }

      // do not draw if the window is minimized
      if stop_rendering {
        // throttle the spinning to avoid the endless spinning
        time.sleep(100 * time.Millisecond)
        continue
      }
      engine_draw()
    }
  }
}

// draw loop
engine_draw :: proc() {
}

// shuts down the engine
engine_cleanup :: proc () {
  if _ctx.is_initialized {
    sdl.DestroyWindow(_ctx.window)
  }
  // frees allocated memory
  free(_ctx)
}
