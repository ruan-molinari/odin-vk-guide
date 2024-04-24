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

// constants
USE_VALIDATION_LAYER :: false

VulkanEngine :: struct {
  is_initialized:        bool,
  frame_number:          u32,
  stop_rendering:        bool,
  window_extent:         vk.Extent2D,
  window:                ^sdl.Window,
  instance:              ^vkb.Instance, // Vulkan library handle
  chosen_gpu:            ^vkb.Physical_Device, // GPU chosen as defauld device
  device:                ^vkb.Device, // Vulkan device for commands
  surface:               vk.SurfaceKHR, // Vulkan window surface
  swapchain:             ^vkb.Swapchain,
  swapchain_format:      vk.Format,
  swapchain_images:      []vk.Image,
  swapchain_image_views: []vk.ImageView,
}

@(private)
_ctx: ^VulkanEngine

// initializes everything in the engine
engine_init :: proc() -> (err: Error) {
  // only one instanced engine is allowed
  assert(_ctx == nil, "Cannot have more than one istance of VulkanEngine")
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

  if _ctx.window == nil {
    log.errorf("Failed to create window: [%s]", sdl.GetErrorString())
    return .Create_Window_Failed
  }
  defer if err != nil do sdl.DestroyWindow(_ctx.window)

  fmt.println("SDL initialized")

  if res := engine_init_vulkan(); res != nil {
    log.errorf("Failed to initialize Vulkan: [%v]", res)
    return res
  }
  defer if err != nil {
    // TODO: flush deletor here
    // engine_flush_deletors()
		engine_deinit_vulkan()   
  }

  fmt.println("Vulkan initialized")

  if res := engine_init_swapchain(); res != nil {
    log.errorf("Failed to initialize swapchain: [%v]", res)
    return res
  }
  defer if err != nil do engine_destroy_swapchain()

  fmt.println("Vulkan initialized")

  engine_init_commands()

  engine_init_sync_structures()

  // everything went fine
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

engine_init_vulkan :: proc() -> (err: Error) {
  b_instance := vkb.init_instance_builder() or_return
  defer vkb.destroy_instance_builder(&b_instance)

  // make the vulkan instance with basic debug features
  vkb.instance_set_app_name(&b_instance, "Example Vulkan application")
  vkb.instance_request_validation_layers(&b_instance, USE_VALIDATION_LAYER)
  vkb.instance_use_default_debug_messenger(&b_instance)
  vkb.instance_require_api_version(&b_instance, vk.API_VERSION_1_3)

  _ctx.instance = vkb.build_instance(&b_instance) or_return
  defer vkb.destroy_instance(_ctx.instance)

  // ------ surface initialization
  if !sdl.Vulkan_CreateSurface(_ctx.window, _ctx.instance.ptr, &_ctx.surface) {
    log.errorf("SDL couldn't create Vulkan surface: %s", sdl.GetError())
    return
  }

  // Vulkan 1.3 feature
  features_13 := vk.PhysicalDeviceVulkan13Features {
    dynamicRendering = true,
    synchronization2 = true,
  }

  // Vulkan 1.2 features
  features_12 := vk.PhysicalDeviceVulkan12Features {
    bufferDeviceAddress = true,
    descriptorIndexing  = true,
  }

  // use vk-bootstrap to select a GPU.
  // we want a GPU that can write to the SDL surface and supports Vulkan 1.3
  // with the correct features
  selector := vkb.init_physical_device_selector(_ctx.instance) or_return
  defer vkb.destroy_physical_device_selector(&selector)

  vkb.selector_set_minimum_version(&selector, vk.API_VERSION_1_3)
  vkb.selector_set_required_features_13(&selector, features_13)
  vkb.selector_set_required_features_12(&selector, features_12)
  vkb.selector_set_surface(&selector, _ctx.surface)

  fmt.println(selector)
  _ctx.chosen_gpu = vkb.select_physical_device(&selector) or_return
  defer if err != nil do vkb.destroy_physical_device(_ctx.chosen_gpu)



  // creates the final vulkan device
  b_device := vkb.init_device_builder(_ctx.chosen_gpu) or_return
  defer if err != nil do vkb.destroy_device_builder(&b_device)

  _ctx.device = vkb.build_device(&b_device) or_return
  defer if err != nil do vkb.destroy_device(_ctx.device)

  return nil
}

engine_create_swapchain :: proc(width, height: u32) -> (err: Error) {
  _ctx.swapchain_format = .B8G8R8A8_UNORM

  b_swapchain: vkb.Swapchain_Builder = vkb.init_swapchain_builder(_ctx.chosen_gpu, _ctx.device, _ctx.surface) or_return
  defer vkb.destroy_swapchain_builder(&b_swapchain)

  vkb.swapchain_builder_set_desired_format(
    &b_swapchain,
    vk.SurfaceFormatKHR{ format = _ctx.swapchain_format, colorSpace = .SRGB_NONLINEAR })
  vkb.swapchain_builder_set_present_mode(&b_swapchain, .FIFO_RELAXED)
  vkb.swapchain_builder_set_desired_extent(&b_swapchain, width, height)
  vkb.swapchain_builder_add_image_usage_flags(&b_swapchain, {.TRANSFER_DST})

  _ctx.swapchain = vkb.build_swapchain(&b_swapchain) or_return

  _ctx.swapchain_images = vkb.swapchain_get_images(_ctx.swapchain) or_return
  _ctx.swapchain_image_views = vkb.swapchain_get_image_views(_ctx.swapchain) or_return

  return nil
}

engine_init_swapchain :: proc() -> (err: Error) {
  engine_create_swapchain(_ctx.window_extent.width, _ctx.window_extent.height) or_return
  return nil
}



engine_init_commands :: proc() {

}

engine_init_sync_structures :: proc() {

}

// draw loop
engine_draw :: proc() {
}

engine_destroy_swapchain :: proc() {
  vkb.swapchain_destroy_image_views(_ctx.swapchain, &_ctx.swapchain_image_views)
  delete(_ctx.swapchain_image_views)
  delete(_ctx.swapchain_images)
  vkb.destroy_swapchain(_ctx.swapchain)
}

engine_deinit_vulkan :: proc() {
    vkb.destroy_device(_ctx.device)
    vkb.destroy_physical_device(_ctx.chosen_gpu)
    vkb.destroy_surface(_ctx.instance, _ctx.surface)
    vkb.destroy_instance(_ctx.instance)
}

// shuts down the engine
engine_cleanup :: proc () {

  if _ctx.is_initialized {

    engine_destroy_swapchain()

    engine_deinit_vulkan()

    sdl.DestroyWindow(_ctx.window)
    sdl.Quit()
  }
  // frees allocated memory
  free(_ctx)
}


