cmake_minimum_required(VERSION 3.16)

project(cpu-boost-switcher VERSION 0.1.13 LANGUAGES C)

if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
    set(CMAKE_INSTALL_PREFIX
        "$ENV{HOME}/.local"
        CACHE PATH "Install prefix" FORCE
    )
endif()

include(GNUInstallDirs)

set(PLASMOID_ID "io.github.szumak75.cpu-boost-switcher")
set(KDE_INSTALL_PLASMA_PLASMOIDS_DIR
    "${CMAKE_INSTALL_DATADIR}/plasma/plasmoids"
    CACHE PATH "Install path for Plasma widgets"
)

install(DIRECTORY package/
    DESTINATION "${KDE_INSTALL_PLASMA_PLASMOIDS_DIR}/${PLASMOID_ID}"
)
