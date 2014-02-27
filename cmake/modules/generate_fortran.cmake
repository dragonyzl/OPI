set(OUTPUT_FILE ${OUTPUT_PATH}/opi_fortran_bindings.f90)

include(ParseArguments)

file(WRITE ${OUTPUT_FILE}  "!******************************************************************\n")
file(APPEND ${OUTPUT_FILE} "!* BINDINGS GENERATED BY BUILDSYS\n")
file(APPEND ${OUTPUT_FILE} "!* DO NOT EDIT MANUALLY\n")
file(APPEND ${OUTPUT_FILE} "!*****************************************************************/\n")
file(APPEND ${OUTPUT_FILE} "!< This module contains all c-interoperable types\n")

set(TYPEDEF)

macro(WRITE_TYPE TEXT)
  set(TYPEDEF "${TYPEDEF}${TEXT}\n")
endmacro()

macro(WRITE_INTERFACE TEXT)
  set(INTERFACE "${INTERFACE}${TEXT}\n")
endmacro()

macro(WRITE_CONTAINS TEXT)
  set(CONTAINS "${CONTAINS}${TEXT}\n")
endmacro()

macro(BEGIN_STRUCTURE TYPENAME)
  WRITE_TYPE("  type, bind(C) :: OPI_${TYPENAME}")
endmacro()

macro(STRUCTURE_VARIABLE TYPE NAME)
  string(TOLOWER ${TYPE} TYPE_LOWER)
  if("${TYPE_LOWER}" STREQUAL "float")
    set(FORTRAN_TYPE "    real(kind=c_float)")
  elseif("${TYPE_LOWER}" STREQUAL "int")
    set(FORTRAN_TYPE "    integer(kind=c_int)")
  else()
    message(FATAL_ERROR "Unknown fortran type: ${TYPE}")
  endif()
  WRITE_TYPE("${FORTRAN_TYPE} :: ${NAME}")
endmacro()

macro(END_STRUCTURE TYPENAME)
  WRITE_TYPE(" end type")
endmacro()

macro(COMMENT COMMENT_TO_WRITE)
  WRITE_TYPE(" !> ${COMMENT_TO_WRITE}")
endmacro()

macro(BEGIN_ENUM TYPENAME)
  WRITE_TYPE(" ! BEGIN ENUM ${TYPENAME}")
endmacro()
macro(BEGIN_ENUM_AS_INT TYPENAME)
  WRITE_TYPE(" ! BEGIN ENUM ${TYPENAME}")
endmacro()
macro(ENUM_VALUE NAME VALUE)
  WRITE_TYPE(" INTEGER(C_INT), PARAMETER :: OPI_${NAME} = ${VALUE}")
endmacro()

macro(END_ENUM TYPENAME)
  WRITE_TYPE(" ! END ENUM ${TYPENAME}")
endmacro()


macro(PARSE_TYPE TYPE)
  set(REFCAST)
  set(VALUE_DEF ", VALUE")
  if("${TYPE}" STREQUAL "FUNCTION_RETURN")
    set(VALUE_DEF "")
  endif()
  unset(OPI_STRUCT_TYPE)
  unset(OPI_STRING_VAL)
  if(${${TYPE}} STREQUAL "void*")
    set(${TYPE} "TYPE(C_PTR)")
  elseif(${${TYPE}} STREQUAL "int")
    set(${TYPE} "INTEGER(C_INT)${VALUE_DEF}")
  elseif(${${TYPE}} STREQUAL "int*")
    set(${TYPE} "INTEGER(C_INT)")
  elseif(${${TYPE}} STREQUAL "float")
    set(${TYPE} "REAL(C_FLOAT)${VALUE_DEF}")
  elseif(${${TYPE}} STREQUAL "float*")
    set(${TYPE} "REAL(C_FLOAT)")
  elseif(${${TYPE}} STREQUAL "double")
    set(${TYPE} "REAL(C_DOUBLE)${VALUE_DEF}")
  elseif(${${TYPE}} STREQUAL "double*")
    set(${TYPE} "REAL(C_DOUBLE)")
  elseif(${${TYPE}} STREQUAL "ErrorCode")
    set(${TYPE} "INTEGER(C_INT)")
  elseif(${${TYPE}} STREQUAL "std::string")
    set(OPI_STRING_VAL 1)
    set(${TYPE} "TYPE(C_PTR)${VALUE_DEF}")
  else()
    if(${${TYPE}} MATCHES "(.*)\\*")
      set(OPI_STRUCT_TYPE OPI_${CMAKE_MATCH_1})
    endif()
    if(${${TYPE}} MATCHES "(.*)&")
      #string(REGEX MATCH "(.*)&" RESULT ${${TYPE}})
      set(REFCAST "${CMAKE_MATCH_1}")
      set(${TYPE} "TYPE(C_PTR)${VALUE_DEF}")
    else()
    set(${TYPE} "TYPE(C_PTR)${VALUE_DEF}")
    endif()
  endif()
endmacro()

macro(PARSE_FUNCTION_ARGS ARGS)
    list(LENGTH ${ARGS} ARG_LEN)
    set(MAKE_STRINGWRAP)
    math(EXPR ARG_LEN "${ARG_LEN} - 1")
    if(${ARG_LEN} GREATER 0)
      foreach(INDEX RANGE 0 ${ARG_LEN} 2)
        list(GET ${ARGS} ${INDEX} TYPE)
        math(EXPR INDEX_2 "${INDEX} + 1")
        list(GET ${ARGS} ${INDEX_2} NAME)
        if(${TYPE} STREQUAL "std::string")
          set(MAKE_STRINGWRAP 1)
          list(APPEND ARG_FUNCTION_PARAM "${NAME}")
          list(APPEND ARG_FUNCTION_PARAM_DEF "CHARACTER(len=*), intent(in) :: ${NAME}")
          list(APPEND ARG_FUNCTION_PARAM_CALL "${NAME}")
          list(APPEND ARG_FUNCTION_PARAM_CALL "len(${NAME})")
          list(APPEND ARG_FUNCTION_WRAP_PARAM "${NAME}")
          list(APPEND ARG_FUNCTION_WRAP_PARAM "${NAME}_len")
          list(APPEND ARG_FUNCTION_WRAP_PARAM_DEF "CHARACTER(C_CHAR) :: ${NAME}(*)")
          list(APPEND ARG_FUNCTION_WRAP_PARAM_DEF "INTEGER(C_INT), VALUE :: ${NAME}_len")
        else()
          PARSE_TYPE(TYPE)
          list(APPEND ARG_FUNCTION_PARAM "${NAME}")
          list(APPEND ARG_FUNCTION_PARAM_DEF "${TYPE} :: ${NAME}")
          list(APPEND ARG_FUNCTION_PARAM_CALL "${NAME}")
          list(APPEND ARG_FUNCTION_WRAP_PARAM "${NAME}")
          list(APPEND ARG_FUNCTION_WRAP_PARAM_DEF "${TYPE} :: ${NAME}")
        endif()
      endforeach()
    endif()
    STRING(REPLACE ";" "," ARG_FUNCTION_PARAM "${ARG_FUNCTION_PARAM}")
    STRING(REPLACE ";" "\n    " ARG_FUNCTION_PARAM_DEF "${ARG_FUNCTION_PARAM_DEF}")
    STRING(REPLACE ";" "," ARG_FUNCTION_PARAM_CALL "${ARG_FUNCTION_PARAM_CALL}")
    STRING(REPLACE ";" "," ARG_FUNCTION_WRAP_PARAM "${ARG_FUNCTION_WRAP_PARAM}")
    STRING(REPLACE ";" "\n    " ARG_FUNCTION_WRAP_PARAM_DEF "${ARG_FUNCTION_WRAP_PARAM_DEF}")
endmacro()

macro(PARSE_FUNCTION)
    list(GET COMMAND_ARGS 0 FUNCTION_NAME)
    PARSE_ARGUMENTS(FUNCTION "OVERLOAD_ALIAS;RETURN;RETURN_PREFIX;ARGS" "" ${COMMAND_ARGS})
    unset(MAKE_STRUCTWRAP)
    unset(MAKE_STRINGWRAP_RETURN)
    if(FUNCTION_RETURN)
      PARSE_TYPE( FUNCTION_RETURN RETURN)
      if(OPI_STRUCT_TYPE)
        set(MAKE_STRUCTWRAP ${OPI_STRUCT_TYPE})
      elseif(OPI_STRING_VAL)
        set(MAKE_STRINGWRAP_RETURN 1)
      endif()
      set(FUNCTION_RESULT "RESULT(result_value)")
      set(FUNCTION_RETURN "\n    ${FUNCTION_RETURN} :: result_value")
      set(FUNCTION_TYPE "FUNCTION")
      set(FUNCTION_CALL_RESULT "result_value = ")
    else()
      set(FUNCTION_RESULT "")
      set(FUNCTION_RETURN "")
      set(FUNCTION_TYPE "SUBROUTINE")
      set(FUNCTION_CALL_RESULT "call ")
    endif()
    if(FUNCTION_OVERLOAD_ALIAS)
      if(NOT FUNCTION_${FUNCTION_PREFIX}${FUNCTION_NAME}_OVERLOADED)
        set(FUNCTION_${FUNCTION_PREFIX}${FUNCTION_NAME}_OVERLOADED 1)
        list(APPEND OVERLOADED_FUNCTIONS ${FUNCTION_PREFIX}${FUNCTION_NAME})
      endif()
      list(APPEND OVERLOADED_FUNCTION_${FUNCTION_PREFIX}${FUNCTION_NAME} ${FUNCTION_PREFIX}${FUNCTION_OVERLOAD_ALIAS})
      set(FUNCTION_NAME ${FUNCTION_OVERLOAD_ALIAS})
    endif()
    # parse function args
    set(ARG_FUNCTION_PARAM "object")
    set(ARG_FUNCTION_PARAM_DEF "TYPE(C_PTR), VALUE :: object")
    set(ARG_FUNCTION_PARAM_CALL "object")
    set(ARG_FUNCTION_WRAP_PARAM "object")
    set(ARG_FUNCTION_WRAP_PARAM_DEF "TYPE(C_PTR), VALUE :: object")
    PARSE_FUNCTION_ARGS(FUNCTION_ARGS)
    if(MAKE_STRINGWRAP)
      WRITE_INTERFACE("  ${FUNCTION_TYPE} ${FUNCTION_PREFIX}${FUNCTION_NAME}StrLen(${ARG_FUNCTION_WRAP_PARAM}) ${FUNCTION_RESULT} &")
      WRITE_INTERFACE("    BIND(C,NAME=\"${FUNCTION_PREFIX}${FUNCTION_NAME}StrLen\")")
      WRITE_INTERFACE("    USE ISO_C_BINDING")
      WRITE_INTERFACE("    ${ARG_FUNCTION_WRAP_PARAM_DEF}${FUNCTION_RETURN}")
      WRITE_INTERFACE("  END ${FUNCTION_TYPE}")
      WRITE_CONTAINS("  ${FUNCTION_TYPE} ${FUNCTION_PREFIX}${FUNCTION_NAME}(${ARG_FUNCTION_PARAM}) ${FUNCTION_RESULT}")
      WRITE_CONTAINS("    USE ISO_C_BINDING")
      if(MAKE_STRINGWRAP_RETURN)
        WRITE_CONTAINS("    ${ARG_FUNCTION_PARAM_DEF}")
        WRITE_CONTAINS("    CHARACTER(KIND=C_CHAR), DIMENSION(:), POINTER :: result_value")
        WRITE_CONTAINS("    result_value => C_F_STRING(${FUNCTION_PREFIX}${FUNCTION_NAME}StrLen(${ARG_FUNCTION_PARAM_CALL}))")
      else()
        WRITE_CONTAINS("    ${ARG_FUNCTION_PARAM_DEF}${FUNCTION_RETURN}")
        WRITE_CONTAINS("    ${FUNCTION_CALL_RESULT}${FUNCTION_PREFIX}${FUNCTION_NAME}StrLen(${ARG_FUNCTION_PARAM_CALL})")
      endif()
      WRITE_CONTAINS("  END ${FUNCTION_TYPE}")
    elseif(MAKE_STRINGWRAP_RETURN)
      WRITE_INTERFACE("  ${FUNCTION_TYPE} ${FUNCTION_PREFIX}${FUNCTION_NAME}_C(${ARG_FUNCTION_PARAM}) ${FUNCTION_RESULT} &")
      WRITE_INTERFACE("     BIND(C,NAME=\"${FUNCTION_PREFIX}${FUNCTION_NAME}\")")
      WRITE_INTERFACE("    USE ISO_C_BINDING")
      WRITE_INTERFACE("    ${ARG_FUNCTION_PARAM_DEF}${FUNCTION_RETURN}")
      WRITE_INTERFACE("  END ${FUNCTION_TYPE}")
      WRITE_CONTAINS("  ${FUNCTION_TYPE} ${FUNCTION_PREFIX}${FUNCTION_NAME}(${ARG_FUNCTION_PARAM}) ${FUNCTION_RESULT}")
      WRITE_CONTAINS("    USE ISO_C_BINDING")
      WRITE_CONTAINS("    ${ARG_FUNCTION_PARAM_DEF}")
      WRITE_CONTAINS("    CHARACTER(KIND=C_CHAR), DIMENSION(:), POINTER :: result_value")
      WRITE_CONTAINS("    result_value => C_F_STRING(${FUNCTION_PREFIX}${FUNCTION_NAME}_C(${ARG_FUNCTION_PARAM}))")
      WRITE_CONTAINS("  END ${FUNCTION_TYPE}")
    elseif(MAKE_STRUCTWRAP)
      WRITE_INTERFACE("  ${FUNCTION_TYPE} ${FUNCTION_PREFIX}${FUNCTION_NAME}_C(${ARG_FUNCTION_PARAM}) ${FUNCTION_RESULT} &")
      WRITE_INTERFACE("     BIND(C,NAME=\"${FUNCTION_PREFIX}${FUNCTION_NAME}\")")
      WRITE_INTERFACE("    USE ISO_C_BINDING")
      WRITE_INTERFACE("    ${ARG_FUNCTION_PARAM_DEF}${FUNCTION_RETURN}")
      WRITE_INTERFACE("  END ${FUNCTION_TYPE}")
      WRITE_CONTAINS("  ${FUNCTION_TYPE} ${FUNCTION_PREFIX}${FUNCTION_NAME}(${ARG_FUNCTION_PARAM}) ${FUNCTION_RESULT}")
      WRITE_CONTAINS("    USE ISO_C_BINDING")
      WRITE_CONTAINS("    USE OPI_TYPES")
      WRITE_CONTAINS("    ${ARG_FUNCTION_PARAM_DEF}")
      WRITE_CONTAINS("    TYPE(C_PTR) :: result_value_c")
      WRITE_CONTAINS("    TYPE(${MAKE_STRUCTWRAP}), POINTER :: result_value(:)")
      WRITE_CONTAINS("    result_value_c = ${FUNCTION_PREFIX}${FUNCTION_NAME}_C(${ARG_FUNCTION_PARAM})")
      WRITE_CONTAINS("    call c_f_pointer( result_value_c, result_value, (/${FUNCTION_PREFIX}getSize(object)/))")
      WRITE_CONTAINS("  END ${FUNCTION_TYPE}")
    elseif(FUNCTION_OVERLOAD_ALIAS)
      WRITE_INTERFACE("  ${FUNCTION_TYPE} ${FUNCTION_PREFIX}${FUNCTION_NAME}_C(${ARG_FUNCTION_PARAM}) ${FUNCTION_RESULT} &")
      WRITE_INTERFACE("     BIND(C,NAME=\"${FUNCTION_PREFIX}${FUNCTION_NAME}\")")
      WRITE_INTERFACE("    USE ISO_C_BINDING")
      WRITE_INTERFACE("    ${ARG_FUNCTION_PARAM_DEF}${FUNCTION_RETURN}")
      WRITE_INTERFACE("  END ${FUNCTION_TYPE}")
      WRITE_CONTAINS("  ${FUNCTION_TYPE} ${FUNCTION_PREFIX}${FUNCTION_NAME}(${ARG_FUNCTION_PARAM}) ${FUNCTION_RESULT}")
      WRITE_CONTAINS("    USE ISO_C_BINDING")
      WRITE_CONTAINS("    ${ARG_FUNCTION_PARAM_DEF}${FUNCTION_RETURN}")
      WRITE_CONTAINS("    ${FUNCTION_CALL_RESULT}${FUNCTION_PREFIX}${FUNCTION_NAME}_C(${ARG_FUNCTION_PARAM})")
      WRITE_CONTAINS("  END ${FUNCTION_TYPE}")
    else()
      WRITE_INTERFACE("  ${FUNCTION_TYPE} ${FUNCTION_PREFIX}${FUNCTION_NAME}(${ARG_FUNCTION_PARAM}) ${FUNCTION_RESULT} &")
      WRITE_INTERFACE("     BIND(C,NAME=\"${FUNCTION_PREFIX}${FUNCTION_NAME}\")")
      WRITE_INTERFACE("    USE ISO_C_BINDING")
      WRITE_INTERFACE("    ${ARG_FUNCTION_PARAM_DEF}${FUNCTION_RETURN}")
      WRITE_INTERFACE("  END ${FUNCTION_TYPE}")
    endif()
endmacro()

macro(CHANGE_COMMAND NEW_COMMAND)
  if("${COMMAND}" STREQUAL "CONSTRUCTOR")
    PARSE_ARGUMENTS(CONSTRUCTOR "NAME;ARGS" "" ${COMMAND_ARGS})
    if(NOT CONSTRUCTOR_NAME)
      set(CONSTRUCTOR_NAME "${FUNCTION_PREFIX}create${CLASS_NAME}")
    else()
      set(CONSTRUCTOR_NAME "OPI_${CONSTRUCTOR_NAME}")
    endif()
    set(ARG_FUNCTION_PARAM)
    set(ARG_FUNCTION_PARAM_DEF)
    PARSE_FUNCTION_ARGS(CONSTRUCTOR_ARGS)
    WRITE_INTERFACE("  FUNCTION ${CONSTRUCTOR_NAME}(${ARG_FUNCTION_PARAM}) RESULT(object) BIND(C,NAME=\"${CONSTRUCTOR_NAME}\")")
    WRITE_INTERFACE("    USE ISO_C_BINDING")
    WRITE_INTERFACE("    TYPE(C_PTR) :: object")
    WRITE_INTERFACE("    ${ARG_FUNCTION_PARAM_DEF}")
    WRITE_INTERFACE("  END FUNCTION\n")
  elseif("${COMMAND}" STREQUAL "DESTRUCTOR")
    PARSE_ARGUMENTS(DESTRUCTOR "NAME;ARGS" "" ${COMMAND_ARGS})
    if(NOT DESTRUCTOR_NAME)
      set(DESTRUCTOR_NAME "${FUNCTION_PREFIX}destroy${CLASS_NAME}")
    else()
      set(DESTRUCTOR_NAME "OPI_${DESTRUCTOR_NAME}")
    endif()
    WRITE_INTERFACE("  FUNCTION ${DESTRUCTOR_NAME}(object) RESULT(errorcode) BIND(C,NAME=\"${DESTRUCTOR_NAME}\")")
    WRITE_INTERFACE("    USE ISO_C_BINDING")
    WRITE_INTERFACE("    TYPE(C_PTR), VALUE :: object")
    WRITE_INTERFACE("    INTEGER(C_INT) :: errorcode")
    WRITE_INTERFACE("  END FUNCTION\n")
  elseif("${COMMAND}" STREQUAL "PREFIX")
    set(FUNCTION_PREFIX ${COMMAND_ARGS})
  elseif("${COMMAND}" STREQUAL "FUNCTION")
    PARSE_FUNCTION(${COMMAND_ARGS})
  endif()

  set(COMMAND ${NEW_COMMAND})
  set(COMMAND_ARGS)
endmacro()

macro(DECLARE_CLASS CLASS_NAME)
  if(NOT CLASS_${CLASS_NAME}_DECLARED)
    set(${BINDINGS} "${BINDINGS}  TYPE(C_PTR), VALUE :: ${CLASS_NAME};\n")
    set(CLASS_${CLASS_NAME}_DECLARED 1)
  endif()
endmacro()

macro(BIND_CLASS CLASS_NAME)
  WRITE_INTERFACE("  ! ${CLASS_NAME} bindings")
  DECLARE_CLASS(${CLASS_NAME})
  set(CLASS_NAME ${CLASS_NAME})
  set(FUNCTION_PREFIX "OPI_${CLASS_NAME}_")
  set(COMMAND )
  set(COMMAND_ARGS)
  foreach(ARG ${ARGN})
    if(${ARG} STREQUAL "CONSTRUCTOR")
      CHANGE_COMMAND("CONSTRUCTOR")
    elseif(${ARG} STREQUAL "DESTRUCTOR")
      CHANGE_COMMAND("DESTRUCTOR")
    elseif(${ARG} STREQUAL "FUNCTION")
      CHANGE_COMMAND("FUNCTION")
    elseif(${ARG} STREQUAL "PREFIX")
      CHANGE_COMMAND("PREFIX")
    else()
      LIST(APPEND COMMAND_ARGS ${ARG})
    endif()
  endforeach()
  CHANGE_COMMAND("")
endmacro()

string(REPLACE " " ";" FILES "${PROCESS_FILES}")
foreach(PROCESS_FILE ${FILES})
  WRITE_TYPE("! Source File: ${PROCESS_FILE}")
  WRITE_INTERFACE("! Source File: ${PROCESS_FILE}")
  include(${PROCESS_FILE})
  WRITE_INTERFACE("")
  WRITE_TYPE("")
endforeach()

set(OVERLOAD_INTERFACES)
macro(WRITE_OVERLOAD TEXT)
  set(OVERLOAD_INTERFACES "${OVERLOAD_INTERFACES}${TEXT}\n")
endmacro()
foreach(OVERLOAD ${OVERLOADED_FUNCTIONS})
  WRITE_OVERLOAD("  INTERFACE ${OVERLOAD}")
  unset(OVERLOADED_FUNCTION_ALIASES)
  foreach(ALIAS ${OVERLOADED_FUNCTION_${OVERLOAD}})
    list(APPEND OVERLOADED_FUNCTION_ALIASES "${ALIAS}")
  endforeach()
  STRING(REPLACE ";" ", &\n" OVERLOADED_FUNCTION_ALIASES "${OVERLOADED_FUNCTION_ALIASES}")
  WRITE_OVERLOAD("    module procedure ${OVERLOADED_FUNCTION_ALIASES}")
  WRITE_OVERLOAD("  END INTERFACE")
endforeach()

file(APPEND ${OUTPUT_FILE} "module OPI_Types
  use ISO_C_BINDING
  INTEGER, PARAMETER :: OPI_API_VERSION_MAJOR = 0
  INTEGER, PARAMETER :: OPI_API_VERSION_MINOR = 1
  INTEGER, PARAMETER :: OPI_UNKNOWN_PLUGIN = 0
  INTEGER, PARAMETER :: OPI_PROPAGATOR_PLUGIN = 1
  INTEGER, PARAMETER :: OPI_PROPAGATOR_MODULE_PLUGIN = 2
  INTEGER, PARAMETER :: OPI_PROPAGATOR_INTEGRATOR_PLUGIN = 3
  INTEGER, PARAMETER :: OPI_DISTANCE_QUERY_PLUGIN = 10
  INTEGER, PARAMETER :: OPI_COLLISION_DETECTION_PLUGIN = 20
  INTEGER, PARAMETER :: OPI_COLLISION_HANDLING_PLUGIN = 30

${TYPEDEF}
end module
module OPI
  use ISO_C_BINDING
  use OPI_Types
  CHARACTER(C_CHAR), DIMENSION(1), SAVE, TARGET, PRIVATE :: dummy_string=\"?\"
  interface
${INTERFACE}
    SUBROUTINE OPI_PluginInfo_init(info, api_major, api_minor, &
      plugin_major, plugin_minor, plugin_patch, &
      plugin_type) &
    BIND(C,NAME=\"OPI_PluginInfo_init\")
      USE ISO_C_BINDING
      TYPE(C_PTR), value :: info
      integer(kind=c_int), value :: api_major
      integer(kind=c_int), value :: api_minor
      integer(kind=c_int), value :: plugin_major
      integer(kind=c_int), value :: plugin_minor
      integer(kind=c_int), value :: plugin_patch
      integer(kind=c_int), value :: plugin_type
    END SUBROUTINE
    FUNCTION OPI_ErrorMessage_C(error) RESULT(message) BIND(C, NAME=\"OPI_ErrorMessage\")
      USE ISO_C_BINDING
      type(c_ptr) :: message
      integer(c_int), value :: error
    END FUNCTION
    SUBROUTINE OPI_PluginInfo_setName_C(info, name, len) BIND(C,NAME=\"OPI_PluginInfo_setName\")
      USE ISO_C_BINDING
      TYPE(C_PTR), value :: info
      CHARACTER(kind=c_char) :: name(*)
      integer(c_int), value :: len
    END SUBROUTINE
    SUBROUTINE OPI_PluginInfo_setAuthor_C(info, name, len) BIND(C,NAME=\"OPI_PluginInfo_setAuthor\")
      USE ISO_C_BINDING
      TYPE(C_PTR), value :: info
      CHARACTER(kind=c_char) :: name(*)
      integer(c_int), value :: len
    END SUBROUTINE
    !> @brief Binding to C API OPI_PluginInfo_setDescription
    SUBROUTINE OPI_PluginInfo_setDescription_C(info, name, len) BIND(C,NAME=\"OPI_PluginInfo_setDescription\")
      USE ISO_C_BINDING
      TYPE(C_PTR), value :: info
      CHARACTER(kind=c_char) :: name(*)
      integer(c_int), value :: len
    END SUBROUTINE
  end interface
${OVERLOAD_INTERFACES}
  contains
    ! Helper function to convert a null-terminated C string into a Fortran character array pointer
    ! Placed here because it is only needed here so far
    ! Could be placed into a different module later, when more functions need it
    FUNCTION C_F_STRING(CPTR) RESULT(FPTR)
      TYPE(C_PTR), INTENT(IN) :: CPTR ! The C address
      CHARACTER(KIND=C_CHAR), DIMENSION(:), POINTER :: FPTR
      INTERFACE ! strlen is a standard C function from <string.h>
         ! int strlen(char *string)
         FUNCTION strlen(string) RESULT(len) BIND(C,NAME=\"strlen\")
            USE ISO_C_BINDING
            TYPE(C_PTR), VALUE :: string ! A C pointer
            INTEGER(C_INT) :: len
         END FUNCTION
      END INTERFACE

      IF(C_ASSOCIATED(CPTR)) THEN
         CALL C_F_POINTER(FPTR=FPTR, CPTR=CPTR, SHAPE=[strlen(CPTR)])
      ELSE
         ! To avoid segfaults, associate FPTR with a dummy target:
         FPTR=>dummy_string
      END IF
    END FUNCTION
    SUBROUTINE OPI_PluginInfo_setName(info, name)
      USE ISO_C_BINDING
      TYPE(C_PTR), value :: info
      CHARACTER(len=*), intent(in) :: name
      call OPI_PluginInfo_setName_C(info, name, len(name))
    END SUBROUTINE
    SUBROUTINE OPI_PluginInfo_setAuthor(info, name)
      USE ISO_C_BINDING
      TYPE(C_PTR), value :: info
      CHARACTER(len=*), intent(in) :: name
      call OPI_PluginInfo_setAuthor_C(info, name, len(name))
    END SUBROUTINE
    SUBROUTINE OPI_PluginInfo_setDescription(info, name)
      USE ISO_C_BINDING
      TYPE(C_PTR), value :: info
      CHARACTER(len=*), intent(in) :: name
      call OPI_PluginInfo_setDescription_C(info, name, len(name))
    END SUBROUTINE
    FUNCTION OPI_ErrorMessage(error) RESULT(message)
      USE ISO_C_BINDING
      CHARACTER(KIND=C_CHAR), DIMENSION(:), POINTER :: message
      integer(c_int), value :: error
      message => C_F_STRING(OPI_ErrorMessage_C(error))
    END FUNCTION
${CONTAINS}
end module")


