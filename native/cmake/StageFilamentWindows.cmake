set(
  STAGE_FILAMENT_ROOT
  ""
  CACHE PATH
  "Path to an installed Filament Windows SDK containing include/ and lib/x86_64/."
)

if(NOT STAGE_FILAMENT_ROOT AND DEFINED ENV{STAGE_FILAMENT_ROOT})
  set(
    STAGE_FILAMENT_ROOT
    "$ENV{STAGE_FILAMENT_ROOT}"
    CACHE PATH
    "Path to an installed Filament Windows SDK."
    FORCE
  )
endif()

function(stage_enable_filament_windows target)
  if(NOT STAGE_FILAMENT_ROOT)
    message(
      STATUS
      "Stage 3D Windows Filament backend disabled: set STAGE_FILAMENT_ROOT."
    )
    return()
  endif()

  set(filament_include "${STAGE_FILAMENT_ROOT}/include")
  if(NOT EXISTS "${filament_include}/filament/Engine.h")
    message(FATAL_ERROR "Invalid STAGE_FILAMENT_ROOT: Filament headers not found.")
  endif()

  set(filament_lib_root "${STAGE_FILAMENT_ROOT}/lib/x86_64")
  set(filament_release_dir "")
  set(filament_debug_dir "")
  foreach(candidate md mt "")
    if(candidate)
      set(candidate_dir "${filament_lib_root}/${candidate}")
    else()
      set(candidate_dir "${filament_lib_root}")
    endif()
    if(EXISTS "${candidate_dir}/filament.lib")
      set(filament_release_dir "${candidate_dir}")
      break()
    endif()
  endforeach()
  foreach(candidate mdd mtd md mt "")
    if(candidate)
      set(candidate_dir "${filament_lib_root}/${candidate}")
    else()
      set(candidate_dir "${filament_lib_root}")
    endif()
    if(EXISTS "${candidate_dir}/filament.lib")
      set(filament_debug_dir "${candidate_dir}")
      break()
    endif()
  endforeach()

  if(NOT filament_release_dir OR NOT filament_debug_dir)
    message(FATAL_ERROR "Invalid STAGE_FILAMENT_ROOT: filament.lib not found.")
  endif()

  file(GLOB filament_release_libraries "${filament_release_dir}/*.lib")
  file(GLOB filament_debug_libraries "${filament_debug_dir}/*.lib")

  foreach(filament_library ${filament_release_libraries})
    target_link_libraries(${target} PRIVATE optimized "${filament_library}")
  endforeach()
  foreach(filament_library ${filament_debug_libraries})
    target_link_libraries(${target} PRIVATE debug "${filament_library}")
  endforeach()

  target_include_directories(${target} PRIVATE "${filament_include}")
  target_link_libraries(${target} PRIVATE opengl32.lib shlwapi.lib)
  target_compile_definitions(${target} PRIVATE STAGE_HAS_FILAMENT=1)
  target_compile_features(${target} PRIVATE cxx_std_20)
  if(MSVC)
    target_compile_options(${target} PRIVATE /wd4201 /wd4245 /wd4267 /wd4310)
  endif()

  set(stage_material_source_dir "${CMAKE_SOURCE_DIR}/../assets/material_sources")
  set(stage_material_output_dir "${CMAKE_SOURCE_DIR}/../assets/materials")
  set(stage_matc_executable "${STAGE_FILAMENT_ROOT}/bin/matc.exe")
  if(EXISTS "${stage_matc_executable}" AND EXISTS "${stage_material_source_dir}")
    file(MAKE_DIRECTORY "${stage_material_output_dir}")
    file(
      GLOB stage_material_sources
      "${stage_material_source_dir}/*.mat"
      "${stage_material_source_dir}/*.shader"
    )
    set(stage_compiled_materials "")
    set(stage_material_names "")
    foreach(stage_material_source ${stage_material_sources})
      get_filename_component(stage_material_name "${stage_material_source}" NAME_WE)
      if(stage_material_name IN_LIST stage_material_names)
        continue()
      endif()
      list(APPEND stage_material_names "${stage_material_name}")
      set(stage_preferred_source "${stage_material_source_dir}/${stage_material_name}.mat")
      if(EXISTS "${stage_preferred_source}")
        set(stage_material_source "${stage_preferred_source}")
      endif()
      set(stage_material_output "${stage_material_output_dir}/${stage_material_name}.filamat")
      add_custom_command(
        OUTPUT "${stage_material_output}"
        COMMAND "${stage_matc_executable}"
          -p desktop
          -a opengl
          -o "${stage_material_output}"
          "${stage_material_source}"
        DEPENDS "${stage_material_source}"
        VERBATIM
      )
      list(APPEND stage_compiled_materials "${stage_material_output}")
    endforeach()
    if(stage_compiled_materials)
      add_custom_target(stage_compile_filament_materials DEPENDS ${stage_compiled_materials})
      add_dependencies(${target} stage_compile_filament_materials)
    endif()
  endif()

  message(
    STATUS
    "Stage 3D Windows Filament backend enabled from ${STAGE_FILAMENT_ROOT}."
  )
endfunction()
