cmake_minimum_required(VERSION 3.28)
project(cheshire_hip_tests LANGUAGES CXX HIP)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_HIP_STANDARD 17)
if(NOT CMAKE_HIP_ARCHITECTURES)
  set(CMAKE_HIP_ARCHITECTURES gfx1201 gfx1100)
endif()
find_package(hip REQUIRED)

add_executable(hello_hip hello_hip.hip)
target_link_libraries(hello_hip PRIVATE hip::device)

add_executable(mipmap_tex mipmap_tex.hip)
target_link_libraries(mipmap_tex PRIVATE hip::device)

add_executable(membridge_probe membridge_probe.hip)
target_link_libraries(membridge_probe PRIVATE hip::device)

add_executable(bridge_test bridge_test.hip)
target_include_directories(bridge_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../compat/include)
target_link_libraries(bridge_test PRIVATE hip::device)

add_executable(half_tex half_tex.hip)
target_link_libraries(half_tex PRIVATE hip::device)

add_executable(launch_bench launch_bench.hip)
target_link_libraries(launch_bench PRIVATE hip::device)
