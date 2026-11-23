# Code generated from protocol XML by Scripts/generate-protocols.sh. Linked
# into the compositor, so it isn't installed.

add_library(CShellProtocols STATIC
  protocols.c)

target_include_directories(CShellProtocols
  PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
  PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR})
