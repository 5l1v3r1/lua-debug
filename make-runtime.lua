local lm = require "luamake"
local platform = require "bee.platform"

lm.gcc = 'clang'
lm.gxx = 'clang++'

lm.arch = ARGUMENTS.arch or 'x64'

lm.bindir = ("build/%s/bin/%s"):format(lm.plat, lm.arch)
lm.objdir = ("build/%s/obj/%s"):format(lm.plat, lm.arch)

local BUILD_BIN = platform.OS ~= "Windows" or lm.arch == "x86"

local install_deps = {
    BUILD_BIN and "bee",
    BUILD_BIN and "lua",
    BUILD_BIN and "bootstrap",
    BUILD_BIN and "inject",
    BUILD_BIN and platform.OS == "Windows" and "lua54",
    platform.OS == "Windows" and "launcher",
}

if BUILD_BIN then
    lm:import '3rd/bee.lua/make.lua'

    if platform.OS == "Windows" then
        lm:shared_library 'inject' {
            deps = {
                "bee",
                "lua54"
            },
            includes = {
                "3rd/bee.lua",
                lm.arch == "x86" and "3rd/wow64ext/src",
            },
            sources = {
                "src/process_inject/injectdll.cpp",
                "src/process_inject/query_process.cpp",
                "src/process_inject/inject.cpp",
                lm.arch == "x86" and "3rd/wow64ext/src/wow64ext.cpp",
            },
            links = {
                "advapi32",
            }
        }
    else
        lm:shared_library 'inject' {
            deps = {
                "bee",
            },
            includes = {
                "3rd/bee.lua/3rd/lua/src",
            },
            sources = {
                "src/process_inject/inject_osx.cpp",
            }
        }
    end
end

if platform.OS == "Windows" then
    lm:source_set 'detours' {
        rootdir = "3rd/detours/src",
        permissive = true,
        sources = {
            "*.cpp",
            "!uimports.cpp"
        }
    }

    lm:lua_library 'launcher' {
        export_luaopen = false,
        deps = {
            "detours",
        },
        includes = {
            "3rd/bee.lua",
            "3rd/bee.lua/3rd/lua/src",
        },
        sources = {
            "3rd/bee.lua/bee/error.cpp",
            "3rd/bee.lua/bee/utility/unicode_win.cpp",
            "3rd/bee.lua/bee/utility/path_helper.cpp",
            "3rd/bee.lua/bee/utility/file_helper.cpp",
            "src/remotedebug/rdebug_delayload.cpp",
            "src/launcher/*.cpp",
        },
        defines = {
            "BEE_INLINE",
            "_CRT_SECURE_NO_WARNINGS",
        },
        links = {
            "ws2_32",
            "user32",
            "delayimp",
        },
        ldflags = '/DELAYLOAD:lua54.dll',
    }
end

lm:source_set 'runtime/onelua' {
    includes = {
        "3rd/bee.lua/3rd/lua/src",
    },
    sources = {
        "src/remotedebug/onelua.c",
    },
    flags = {
        platform.OS == "Linux" and "-fPIC",
        platform.OS ~= "Windows" and "-fvisibility=hidden",
    }
}

for _, luaver in ipairs {"lua51","lua52","lua53","lua54"} do
    install_deps[#install_deps+1] = "runtime/"..luaver.."/lua"
    install_deps[#install_deps+1] = "runtime/"..luaver.."/remotedebug"
    if platform.OS == "Windows" then
        install_deps[#install_deps+1] = "runtime/"..luaver.."/"..luaver
    end

    lm.rootdir = '3rd/'..luaver

    if platform.OS == "Windows" then
        lm:shared_library ('runtime/'..luaver..'/'..luaver) {
            sources = {
                "*.c",
                "!lua.c",
                "!luac.c",
            },
            defines = {
                "LUA_BUILD_AS_DLL",
                luaver == "lua51" and "_CRT_SECURE_NO_WARNINGS",
                luaver == "lua52" and "_CRT_SECURE_NO_WARNINGS",
            }
        }
        lm:executable ('runtime/'..luaver..'/lua') {
            output = "lua",
            deps = ('runtime/'..luaver..'/'..luaver),
            sources = {
                "lua.c",
            },
            defines = {
                luaver == "lua51" and "_CRT_SECURE_NO_WARNINGS",
                luaver == "lua52" and "_CRT_SECURE_NO_WARNINGS",
            }
        }
    else
        lm:executable ('runtime/'..luaver..'/lua') {
            sources = {
                "*.c",
                "!luac.c",
            },
            defines = {
                luaver == "lua51" and "_XOPEN_SOURCE=600",
                luaver == "lua52" and "_XOPEN_SOURCE=600",
                (luaver == "lua51" and platform.OS == "macOS") and "LUA_USE_DLOPEN",
                platform.OS == "macOS" and "LUA_USE_MACOSX",
                platform.OS == "Linux" and "LUA_USE_LINUX",
            },
            ldflags = {
                platform.OS == "Linux" and "-Wl,-E"
            },
            visibility = "default",
            links = {
                "m",
                "dl",
                "readline",
            }
        }
    end

    lm.rootdir = ''

    local lua_version_num = 100 * math.tointeger(luaver:sub(4,4)) + math.tointeger(luaver:sub(5,5))

    lm:shared_library ('runtime/'..luaver..'/remotedebug') {
        deps = {
            platform.OS == "Windows" and ('runtime/'..luaver..'/'..luaver),
            "runtime/onelua",
        },
        defines = {
            "BEE_STATIC",
            "BEE_INLINE",
            ("DBG_LUA_VERSION=%d"):format(lua_version_num),
            platform.OS == "Windows" and "_CRT_SECURE_NO_WARNINGS",
            platform.OS == "Windows" and "_WIN32_WINNT=0x0601",
        },
        includes = {
            "3rd/bee.lua/",
            "3rd/bee.lua/3rd/lua-seri",
            platform.OS ~= "Windows" and "3rd/"..luaver,
        },
        sources = {
            "src/remotedebug/*.cpp",
            "3rd/bee.lua/bee/error.cpp",
            "3rd/bee.lua/bee/net/*.cpp",
            platform.OS == "Windows" and "3rd/bee.lua/bee/platform/version_win.cpp",
            platform.OS == "Windows" and "3rd/bee.lua/bee/utility/module_version_win.cpp",
            platform.OS == "Windows" and "3rd/bee.lua/bee/utility/unicode_win.cpp",
        },
        links = {
            platform.OS == "Windows" and "version",
            platform.OS == "Windows" and "ws2_32",
            platform.OS == "Windows" and "user32",
            platform.OS == "Windows" and "delayimp",
            platform.OS == "Linux" and "stdc++",
            platform.OS == "Linux" and "pthread",
        },
        ldflags = {
            platform.OS == "Windows" and ("/DELAYLOAD:%s.dll"):format(luaver),
        },
        flags = {
            platform.OS ~= "Windows" and "-fvisibility=hidden"
        }
    }

end

lm:build 'install' {
    '$luamake', 'lua', 'make/install-runtime.lua', lm.plat, lm.arch,
    deps = install_deps
}

lm:default {
    "install",
}
