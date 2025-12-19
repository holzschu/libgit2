# The main libgit2 source tree: this CMakeLists.txt identifies platform
# support and includes the subprojects that make up core libgit2 support.

#
# Optional build configuration settings
#

if(DEPRECATE_HARD)
        add_definitions(-DGIT_DEPRECATE_HARD)
endif()

if(DEBUG_LEAK_CHECKER STREQUAL "valgrind")
	add_definitions(-DVALGRIND)
endif()

#
# Optional debugging functionality
#

if(DEBUG_POOL)
	set(GIT_DEBUG_POOL 1)
endif()
add_feature_info("Debug pool" GIT_DEBUG_POOL "debug-mode struct pool allocators")

if(DEBUG_STRICT_ALLOC)
	set(GIT_DEBUG_STRICT_ALLOC 1)
endif()
add_feature_info("Debug alloc" GIT_DEBUG_STRICT_ALLOC "debug-mode strict allocators")

if(DEBUG_STRICT_OPEN)
	set(GIT_DEBUG_STRICT_OPEN 1)
endif()
add_feature_info("Debug open" GIT_DEBUG_STRICT_OPEN "strict path validation in open")

#
# Optional feature enablement
#

include(SelectThreads)
include(SelectNsec)
include(SelectHTTPSBackend)
include(SelectHashes)
include(SelectHTTPParser)
include(SelectRegex)
include(SelectXdiff)
include(SelectSSH)
include(SelectCompression)
include(SelectI18n)
include(SelectAuthNTLM)
include(SelectAuthNegotiate)

#
# Platform support
#

# futimes/futimens

if(HAVE_FUTIMENS)
	set(GIT_FUTIMENS 1)
endif()

# qsort

# old-style FreeBSD qsort_r() has the 'context' parameter as the first argument
# of the comparison function:
check_prototype_definition_safe(qsort_r
	"void (qsort_r)(void *base, size_t nmemb, size_t size, void *context, int (*compar)(void *, const void *, const void *))"
	"" "stdlib.h" GIT_QSORT_BSD)

# GNU or POSIX qsort_r() has the 'context' parameter as the last argument of the
# comparison function:
check_prototype_definition_safe(qsort_r
	"void (qsort_r)(void *base, size_t nmemb, size_t size, int (*compar)(const void *, const void *, void *), void *context)"
	"" "stdlib.h" GIT_QSORT_GNU)

# C11 qsort_s() has the 'context' parameter as the last argument of the
# comparison function, and returns an error status:
check_prototype_definition_safe(qsort_s
	"errno_t (qsort_s)(void *base, rsize_t nmemb, rsize_t size, int (*compar)(const void *, const void *, void *), void *context)"
	"0" "stdlib.h" GIT_QSORT_C11)

# MSC qsort_s() has the 'context' parameter as the first argument of the
# comparison function, and as the last argument of qsort_s():
check_prototype_definition_safe(qsort_s
	"void (qsort_s)(void *base, size_t num, size_t width, int (*compare )(void *, const void *, const void *), void *context)"
	"" "stdlib.h" GIT_QSORT_MSC)

# random / entropy data

check_symbol_exists(getentropy unistd.h GIT_RAND_GETENTROPY)
check_symbol_exists(getloadavg stdlib.h GIT_RAND_GETLOADAVG)

# poll

# Optional external dependency: zlib
SanitizeBool(USE_BUNDLED_ZLIB)
IF(USE_BUNDLED_ZLIB STREQUAL ON)
	SET(USE_BUNDLED_ZLIB "Bundled")
ENDIF()

IF(USE_BUNDLED_ZLIB STREQUAL "OFF")
	FIND_PACKAGE(ZLIB)
	IF(ZLIB_FOUND)
		LIST(APPEND LIBGIT2_SYSTEM_INCLUDES ${ZLIB_INCLUDE_DIRS})
		LIST(APPEND LIBGIT2_LIBS ${ZLIB_LIBRARIES})
		IF(APPLE OR CMAKE_SYSTEM_NAME MATCHES "FreeBSD")
			LIST(APPEND LIBGIT2_PC_LIBS "-lz")
		ELSE()
			LIST(APPEND LIBGIT2_PC_REQUIRES "zlib")
		ENDIF()
		ADD_FEATURE_INFO(zlib ON "using system zlib")
	ELSE()
		MESSAGE(STATUS "zlib was not found; using bundled 3rd-party sources." )
	ENDIF()
ENDIF()
IF(USE_BUNDLED_ZLIB STREQUAL "Chromium")
	ADD_SUBDIRECTORY("${libgit2_SOURCE_DIR}/deps/chromium-zlib" "${libgit2_BINARY_DIR}/deps/chromium-zlib")
	LIST(APPEND LIBGIT2_INCLUDES "${libgit2_SOURCE_DIR}/deps/chromium-zlib")
	LIST(APPEND LIBGIT2_OBJECTS $<TARGET_OBJECTS:chromium_zlib>)
	ADD_FEATURE_INFO(zlib ON "using (Chromium) bundled zlib")
ELSEIF(USE_BUNDLED_ZLIB OR NOT ZLIB_FOUND)
	ADD_SUBDIRECTORY("${libgit2_SOURCE_DIR}/deps/zlib" "${libgit2_BINARY_DIR}/deps/zlib")
	LIST(APPEND LIBGIT2_INCLUDES "${libgit2_SOURCE_DIR}/deps/zlib")
	LIST(APPEND LIBGIT2_OBJECTS $<TARGET_OBJECTS:zlib>)
	ADD_FEATURE_INFO(zlib ON "using bundled zlib")
ENDIF()

# Optional external dependency: libssh2
IF (USE_SSH)
	FIND_PKGLIBRARIES(LIBSSH2 libssh2)
	# MacOSX / iOS / simulator:
	if (NOT LIBSSH2_FOUND)
	    SET(LIBSSH2_FOUND 1)
	    SET(LIBSSH2_LIBRARIES "-framework libssh2 -framework openssl")
	ENDIF()
ENDIF()
IF (LIBSSH2_FOUND)
	SET(GIT_SSH 1)
	LIST(APPEND LIBGIT2_SYSTEM_INCLUDES ${LIBSSH2_INCLUDE_DIRS})
	LIST(APPEND LIBGIT2_LIBS ${LIBSSH2_LIBRARIES})
	LIST(APPEND LIBGIT2_PC_LIBS ${LIBSSH2_LDFLAGS})

	CHECK_LIBRARY_EXISTS("${LIBSSH2_LIBRARIES}" libssh2_userauth_publickey_frommemory "${LIBSSH2_LIBRARY_DIRS}" HAVE_LIBSSH2_MEMORY_CREDENTIALS)
	IF (HAVE_LIBSSH2_MEMORY_CREDENTIALS)
		SET(GIT_SSH_MEMORY_CREDENTIALS 1)
	ENDIF()
ELSE()
	MESSAGE(STATUS "LIBSSH2 not found. Set CMAKE_PREFIX_PATH if it is installed outside of the default search path.")
ENDIF()
ADD_FEATURE_INFO(SSH GIT_SSH "SSH transport support")

# Optional external dependency: ntlmclient
IF (USE_NTLMCLIENT)
	SET(GIT_NTLM 1)
	ADD_SUBDIRECTORY("${libgit2_SOURCE_DIR}/deps/ntlmclient" "${libgit2_BINARY_DIR}/deps/ntlmclient")
	LIST(APPEND LIBGIT2_INCLUDES "${libgit2_SOURCE_DIR}/deps/ntlmclient")
	LIST(APPEND LIBGIT2_OBJECTS "$<TARGET_OBJECTS:ntlmclient>")
ENDIF()
ADD_FEATURE_INFO(ntlmclient GIT_NTLM "NTLM authentication support for Unix")

# Optional external dependency: GSSAPI

INCLUDE(SelectGSSAPI)

# Optional external dependency: iconv
IF (USE_ICONV)
	FIND_PACKAGE(Iconv)
ENDIF()
IF (ICONV_FOUND)
	SET(GIT_USE_ICONV 1)
	LIST(APPEND LIBGIT2_SYSTEM_INCLUDES ${ICONV_INCLUDE_DIR})
	LIST(APPEND LIBGIT2_LIBS ${ICONV_LIBRARIES})
	LIST(APPEND LIBGIT2_PC_LIBS ${ICONV_LIBRARIES})
ENDIF()
ADD_FEATURE_INFO(iconv GIT_USE_ICONV "iconv encoding conversion support")


IF (THREADSAFE)
	IF (NOT WIN32)
		FIND_PACKAGE(Threads REQUIRED)
	ENDIF()

	SET(GIT_THREADS 1)
ENDIF()

IF (USE_NSEC)
	SET(GIT_USE_NSEC 1)
ENDIF()

IF (HAVE_STRUCT_STAT_ST_MTIM)
	SET(GIT_USE_STAT_MTIM 1)
ELSEIF (HAVE_STRUCT_STAT_ST_MTIMESPEC)
	SET(GIT_USE_STAT_MTIMESPEC 1)
ELSEIF (HAVE_STRUCT_STAT_ST_MTIME_NSEC)
	SET(GIT_USE_STAT_MTIME_NSEC 1)
ENDIF()

target_compile_definitions(git2internal PRIVATE _FILE_OFFSET_BITS=64)

# Collect sourcefiles
file(GLOB SRC_H
	"${libgit2_SOURCE_DIR}/include/git2.h"
	"${libgit2_SOURCE_DIR}/include/git2/*.h"
	"${libgit2_SOURCE_DIR}/include/git2/sys/*.h")
list(SORT SRC_H)
target_sources(git2internal PRIVATE ${SRC_H})

# On Windows use specific platform sources
if(WIN32 AND NOT CYGWIN)
	SET(WIN_RC "win32/git2.rc")

	file(GLOB SRC_OS win32/*.c win32/*.h)
	list(SORT SRC_OS)
	target_sources(git2internal PRIVATE ${SRC_OS})
elseif(AMIGA)
	target_compile_definitions(git2internal PRIVATE NO_ADDRINFO NO_READDIR_R NO_MMAP)
else()
	check_symbol_exists(poll poll.h GIT_IO_POLL)
	check_symbol_exists(select sys/select.h GIT_IO_SELECT)
endif()

# determine architecture of the machine

if(CMAKE_SIZEOF_VOID_P EQUAL 8)
	set(GIT_ARCH_64 1)
elseif(CMAKE_SIZEOF_VOID_P EQUAL 4)
	set(GIT_ARCH_32 1)
elseif(CMAKE_SIZEOF_VOID_P)
	message(FATAL_ERROR "Unsupported architecture (pointer size is ${CMAKE_SIZEOF_VOID_P} bytes)")
else()
	message(FATAL_ERROR "Unsupported architecture (CMAKE_SIZEOF_VOID_P is unset)")
endif()

# realtime support

check_library_exists(rt clock_gettime "time.h" NEED_LIBRT)

if(NEED_LIBRT AND NOT CMAKE_SYSTEM_NAME MATCHES "iOS")
	list(APPEND LIBGIT2_SYSTEM_LIBS rt)
	list(APPEND LIBGIT2_PC_LIBS "-lrt")
endif()

# platform libraries

if(WIN32)
	list(APPEND LIBGIT2_SYSTEM_LIBS "ws2_32" "secur32")
	list(APPEND LIBGIT2_PC_LIBS "-lws2_32" "-lsecur32")
endif()

if(CMAKE_SYSTEM_NAME MATCHES "(Solaris|SunOS)")
	list(APPEND LIBGIT2_SYSTEM_LIBS socket nsl)
	list(APPEND LIBGIT2_PC_LIBS "-lsocket" "-lnsl")
endif()

if(CMAKE_SYSTEM_NAME MATCHES "Haiku")
	list(APPEND LIBGIT2_SYSTEM_LIBS gnu network)
	list(APPEND LIBGIT2_PC_LIBS "-lgnu -lnetwork")
endif()

if(AMIGA)
	add_definitions(-DNO_ADDRINFO -DNO_READDIR_R -DNO_MMAP)
endif()

#
# Set build time information
#

set(GIT_BUILD_CPU "${CMAKE_SYSTEM_PROCESSOR}")
execute_process(COMMAND git rev-parse HEAD
	OUTPUT_VARIABLE GIT_BUILD_COMMIT OUTPUT_STRIP_TRAILING_WHITESPACE)

#
# Include child projects
#

add_subdirectory(libgit2)
add_subdirectory(util)

if(BUILD_CLI AND NOT CMAKE_SYSTEM_NAME MATCHES "iOS")
	add_subdirectory(cli)
endif()

# re-export these to the root so that peer projects (tests, fuzzers,
# examples) can use them
set(LIBGIT2_INCLUDES ${LIBGIT2_INCLUDES} PARENT_SCOPE)
set(LIBGIT2_OBJECTS ${LIBGIT2_OBJECTS} PARENT_SCOPE)
set(LIBGIT2_DEPENDENCY_INCLUDES ${LIBGIT2_DEPENDENCY_INCLUDES} PARENT_SCOPE)
set(LIBGIT2_DEPENDENCY_OBJECTS ${LIBGIT2_DEPENDENCY_OBJECTS} PARENT_SCOPE)
set(LIBGIT2_SYSTEM_INCLUDES ${LIBGIT2_SYSTEM_INCLUDES} PARENT_SCOPE)
set(LIBGIT2_SYSTEM_LIBS ${LIBGIT2_SYSTEM_LIBS} PARENT_SCOPE)
