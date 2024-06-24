with import <nixpkgs> {};

mkShell {
  packages = [
    glfw
    vulkan-headers
    vulkan-loader
    vulkan-validation-layers
    vulkan-tools
  ];

  nativeBuildInputs = with pkgs.buildPackages; [ 
    glfw
  ];

  VULKAN_SDK = "${vulkan-headers}";
  VK_LAYER_PATH = "${vulkan-validation-layers}/share/vulkan/explicit_layer.d";
}
