with import <nixpkgs> {};

mkShell {
  packages = [
    SDL2
    SDL2.dev
    vulkan-headers
    vulkan-loader
    vulkan-validation-layers
    vulkan-tools
  ];

  nativeBuildInputs = with pkgs; [ 
  ];

  VULKAN_SDK = "${vulkan-headers}";
  VK_LAYER_PATH = "${vulkan-validation-layers}/share/vulkan/explicit_layer.d";
}
