cmake_minimum_required(VERSION 3.16)

project(kde6-cpu-boost-switcher VERSION 0.1.15 LANGUAGES CXX)

if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
    set(CMAKE_INSTALL_PREFIX
        "$ENV{HOME}/.local"
        CACHE PATH "Install prefix" FORCE
    )
endif()

include(GNUInstallDirs)
set(CMAKE_AUTOMOC ON)

set(PLASMOID_ID "io.github.szumak75.cpu-boost-switcher")
set(KAUTH_HELPER_ID "io.github.szumak75.kde6cpuboostswitcher.helper")
set(KAUTH_CLIENT_NAME "cpuboost-kauth-client")
set(KAUTH_HELPER_NAME "cpuboost-kauth-helper")
set(RESTORE_TOOL_NAME "cpuboost-restore-state")
set(RESTORE_TOOL_INSTALL_DIR "${CMAKE_INSTALL_FULL_LIBEXECDIR}/${PROJECT_NAME}")
set(RESTORE_TOOL_SYSTEM_PATH "/usr/${CMAKE_INSTALL_LIBEXECDIR}/${PROJECT_NAME}/${RESTORE_TOOL_NAME}")
set(SYSTEMD_UNIT_NAME "cpuboost-restore.service")
set(KDE_INSTALL_PLASMA_PLASMOIDS_DIR
    "${CMAKE_INSTALL_DATADIR}/plasma/plasmoids"
    CACHE PATH "Install path for Plasma widgets"
)

install(DIRECTORY package/
    DESTINATION "${KDE_INSTALL_PLASMA_PLASMOIDS_DIR}/${PLASMOID_ID}"
    COMPONENT Plasmoid
)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 QUIET COMPONENTS Core DBus Gui)
find_package(KF6Auth QUIET)
find_package(KF6CoreAddons QUIET)

if(Qt6Core_FOUND AND Qt6DBus_FOUND AND Qt6Gui_FOUND AND KF6Auth_FOUND AND KF6CoreAddons_FOUND)
    add_library(cpuboost-common STATIC
        src/cpuboost-sysfs.cpp
    )
    target_include_directories(cpuboost-common
        PUBLIC
            "${CMAKE_CURRENT_SOURCE_DIR}/src"
    )
    target_link_libraries(cpuboost-common
        PUBLIC
            Qt6::Core
    )

    add_executable(${KAUTH_CLIENT_NAME}
        src/kauth-client.cpp
    )
    target_link_libraries(${KAUTH_CLIENT_NAME}
        Qt6::Core
        KF6::AuthCore
        KF6::CoreAddons
        cpuboost-common
    )

    add_executable(${KAUTH_HELPER_NAME}
        src/kauth-helper.cpp
    )
    target_link_libraries(${KAUTH_HELPER_NAME}
        Qt6::DBus
        KF6::AuthCore
        cpuboost-common
    )

    add_executable(${RESTORE_TOOL_NAME}
        src/restore-state.cpp
    )
    target_link_libraries(${RESTORE_TOOL_NAME}
        Qt6::Core
        cpuboost-common
    )

    configure_file(
        "${CMAKE_CURRENT_SOURCE_DIR}/kauth/${KAUTH_HELPER_ID}.service.in"
        "${CMAKE_CURRENT_BINARY_DIR}/${KAUTH_HELPER_ID}.service"
        @ONLY
    )
    configure_file(
        "${CMAKE_CURRENT_SOURCE_DIR}/kauth/${KAUTH_HELPER_ID}.conf.in"
        "${CMAKE_CURRENT_BINARY_DIR}/${KAUTH_HELPER_ID}.conf"
        @ONLY
    )
    configure_file(
        "${CMAKE_CURRENT_SOURCE_DIR}/systemd/${SYSTEMD_UNIT_NAME}.in"
        "${CMAKE_CURRENT_BINARY_DIR}/${SYSTEMD_UNIT_NAME}"
        @ONLY
    )

    install(TARGETS ${KAUTH_CLIENT_NAME}
        DESTINATION "${KDE_INSTALL_PLASMA_PLASMOIDS_DIR}/${PLASMOID_ID}/contents/bin"
        COMPONENT Plasmoid
    )
    install(TARGETS ${KAUTH_HELPER_NAME}
        DESTINATION "${KAUTH_HELPER_INSTALL_DIR}"
        COMPONENT KAuthSystem
    )
    install(TARGETS ${RESTORE_TOOL_NAME}
        DESTINATION "${CMAKE_INSTALL_LIBEXECDIR}/${PROJECT_NAME}"
        COMPONENT KAuthSystem
    )
    install(FILES
        "${CMAKE_CURRENT_BINARY_DIR}/${KAUTH_HELPER_ID}.service"
        DESTINATION "${CMAKE_INSTALL_DATAROOTDIR}/dbus-1/system-services"
        COMPONENT KAuthSystem
    )
    install(FILES
        "${CMAKE_CURRENT_BINARY_DIR}/${KAUTH_HELPER_ID}.conf"
        DESTINATION "${CMAKE_INSTALL_DATAROOTDIR}/dbus-1/system.d"
        COMPONENT KAuthSystem
    )
    install(FILES
        "kauth/${KAUTH_HELPER_ID}.policy"
        DESTINATION "${CMAKE_INSTALL_DATAROOTDIR}/polkit-1/actions"
        COMPONENT KAuthSystem
    )
    install(FILES
        "${CMAKE_CURRENT_BINARY_DIR}/${SYSTEMD_UNIT_NAME}"
        DESTINATION "lib/systemd/system"
        COMPONENT KAuthSystem
    )
else()
    message(WARNING "Qt6/KF6 development files for KAuth were not found. Building the plasmoid without the KAuth client/helper integration.")
endif()
