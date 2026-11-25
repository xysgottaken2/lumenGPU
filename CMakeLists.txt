cmake_minimum_required(VERSION 3.21)
project(LumenGPU LANGUAGES CXX)
if(NOT WIN32)
  message(FATAL_ERROR "Native DXR renderer requires Windows SDK and Windows build tools.")
endif()
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
find_program(DXC_EXECUTABLE NAMES dxc REQUIRED)
include(FetchContent)
FetchContent_Declare(imgui GIT_REPOSITORY https://github.com/ocornut/imgui.git GIT_TAG v1.90.9 GIT_SHALLOW TRUE)
FetchContent_MakeAvailable(imgui)
add_executable(LumenGPU native/main.cpp native/protocol.hpp
  ${imgui_SOURCE_DIR}/imgui.cpp ${imgui_SOURCE_DIR}/imgui_draw.cpp ${imgui_SOURCE_DIR}/imgui_tables.cpp ${imgui_SOURCE_DIR}/imgui_widgets.cpp
  ${imgui_SOURCE_DIR}/backends/imgui_impl_win32.cpp ${imgui_SOURCE_DIR}/backends/imgui_impl_dx12.cpp)
target_include_directories(LumenGPU PRIVATE ${imgui_SOURCE_DIR})
target_compile_definitions(LumenGPU PRIVATE UNICODE _UNICODE)
target_link_libraries(LumenGPU PRIVATE d3d12 dxgi winhttp user32 d3dcompiler dwmapi)
if(MSVC)
  target_compile_options(LumenGPU PRIVATE /W4 /EHsc)
  set_property(TARGET LumenGPU PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()
add_custom_command(OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/trace.cso"
  COMMAND "${DXC_EXECUTABLE}" -T cs_6_5 -E main -O3 -Fo "${CMAKE_CURRENT_BINARY_DIR}/trace.cso" "${CMAKE_CURRENT_SOURCE_DIR}/native/trace.hlsl"
  DEPENDS native/trace.hlsl VERBATIM)
add_custom_command(OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/resolve.cso"
 COMMAND "${DXC_EXECUTABLE}" -T cs_6_5 -E resolve -O3 -Fo "${CMAKE_CURRENT_BINARY_DIR}/resolve.cso" "${CMAKE_CURRENT_SOURCE_DIR}/native/trace.hlsl"
 DEPENDS native/trace.hlsl VERBATIM)
add_custom_target(LumenShader ALL DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/trace.cso" "${CMAKE_CURRENT_BINARY_DIR}/resolve.cso")
add_dependencies(LumenGPU LumenShader)
add_custom_command(TARGET LumenGPU POST_BUILD COMMAND ${CMAKE_COMMAND} -E copy_if_different "${CMAKE_CURRENT_BINARY_DIR}/trace.cso" "$<TARGET_FILE_DIR:LumenGPU>/trace.cso" COMMAND ${CMAKE_COMMAND} -E copy_if_different "${CMAKE_CURRENT_BINARY_DIR}/resolve.cso" "$<TARGET_FILE_DIR:LumenGPU>/resolve.cso")

add_executable(LumenProtocolTest tests/protocol_test.cpp)
if(MSVC)
 target_compile_options(LumenProtocolTest PRIVATE /UNDEBUG)
endif()
add_custom_command(TARGET LumenProtocolTest POST_BUILD COMMAND "$<TARGET_FILE:LumenProtocolTest>" "${CMAKE_CURRENT_SOURCE_DIR}/tests/protocol_fixture.bin" VERBATIM)
