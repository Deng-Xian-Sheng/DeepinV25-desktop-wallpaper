#!/usr/bin/env python3

# SPDX-License-Identifier: GPL-3.0-only
#
# This program prints the user's "idle time" to standard output. "Idle time" refers to the number of milliseconds that have passed since the last input signal was received from any input device.
# If execution fails, the program prints a message to standard error and terminates with a non-zero exit code.
#
# Copyright (c) 2005, 2008 Magnus Henoch <henoch@dtek.chalmers.se>
# Copyright (c) 2006, 2007 Danny Kukawka <dkukawka@suse.de>, <danny.kukawka@web.de>
# Copyright (c) 2008 Eivind Magnus Hvidevold <hvidevold@gmail.com>
# Copyright (c) 2014-2022 Richard Leitner <dev@g0hl1n.net>
# Copyright (c) 2025 CanQi Jin <x17615848429@sina.com>
#
# This file is part of the fuck-xprintidle project, which was inspired by the xprintidle project.
#
# fuck-xprintidle is free software; you can redistribute it and/or modify it under the terms of version 3 of the GNU General Public License as published by the Free Software Foundation.
#
# fuck-xprintidle is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. For more details, please refer to the GNU General Public License.
#
# You should have received a copy of the GNU General Public License along with fuck-xprintidle. If not, see <https://www.gnu.org/licenses/>.
#
# The function workaroundCreepyXServer was adapted from kpowersave-0.7.3 developed by Eivind Magnus Hvidevold <hvidevold@gmail.com>. kpowersave is licensed solely under version 2 of the GNU GPL.
#
# fuck-xprintidle was rewritten in Python by CanQi Jin in 2025 with reference to xprintidle, which was implemented in C.

import ctypes
import ctypes.util
import sys
from ctypes import c_int, c_ulong, c_void_p, POINTER, Structure

# 加载必要的库
libX11 = ctypes.CDLL(ctypes.util.find_library('X11'))
libXss = ctypes.CDLL(ctypes.util.find_library('Xss'))

# 定义必要的类型和结构体
class XScreenSaverInfo(Structure):
    _fields_ = [
        ("window", c_ulong),      # screen saver window
        ("state", c_int),         # off, on, disabled
        ("kind", c_int),          # blanked, internal, external
        ("since", c_ulong),       # milliseconds
        ("idle", c_ulong),        # milliseconds
        ("event_mask", c_ulong),  # events
    ]

# 解析命令行参数
def parse_args():
    human_readable = False
    if len(sys.argv) > 1:
        if sys.argv[1] in ('-h', '--help'):
            print_usage()
            sys.exit(1)
        elif sys.argv[1] in ('-v', '--version'):
            print_version()
            sys.exit(0)
        elif sys.argv[1] in ('-H', '--human-readable'):
            human_readable = True
    return human_readable

def print_usage():
    print(f"usage: {sys.argv[0]} [OPTION]")
    print("Query the X server for the user's idle time")
    print("\nOptions:")
    print("  -h, --help              Show this text")
    print("  -H, --human-readable    Output the time in a human readable format")
    print("  -v, --version           Print the program version")
    print("\nReport bugs at: https://github.com/g0hl1n/xprintidle/issues")

def print_version():
    print("xprintidle n/a")

def get_x_idletime():
    # 初始化X11函数
    XOpenDisplay = libX11.XOpenDisplay
    XOpenDisplay.argtypes = [ctypes.c_char_p]
    XOpenDisplay.restype = c_void_p

    XCloseDisplay = libX11.XCloseDisplay
    XCloseDisplay.argtypes = [c_void_p]
    XCloseDisplay.restype = c_int

    DefaultRootWindow = libX11.XDefaultRootWindow
    DefaultRootWindow.argtypes = [c_void_p]
    DefaultRootWindow.restype = c_ulong

    # 初始化Xss函数
    XScreenSaverAllocInfo = libXss.XScreenSaverAllocInfo
    XScreenSaverAllocInfo.restype = POINTER(XScreenSaverInfo)

    XScreenSaverQueryInfo = libXss.XScreenSaverQueryInfo
    XScreenSaverQueryInfo.argtypes = [c_void_p, c_ulong, POINTER(XScreenSaverInfo)]
    XScreenSaverQueryInfo.restype = c_int

    XFree = libX11.XFree
    XFree.argtypes = [c_void_p]
    XFree.restype = c_int
    
    # 打开显示
    dpy = XOpenDisplay(None)
    if not dpy:
        print("couldn't open display", file=sys.stderr)
        return -1
    
    # 分配屏幕保护信息
    ssi = XScreenSaverAllocInfo()
    if not ssi:
        print("couldn't allocate screen saver info", file=sys.stderr)
        XCloseDisplay(dpy)
        return -1
    
    # 查询空闲时间
    root_window = DefaultRootWindow(dpy)
    if not XScreenSaverQueryInfo(dpy, root_window, ssi):
        print("couldn't query screen saver info", file=sys.stderr)
        XFree(ssi)
        XCloseDisplay(dpy)
        return -1

    idle_time = ssi.contents.idle

    # 清理资源
    XFree(ssi)
    XCloseDisplay(dpy)

    return idle_time

def print_human_time(time_ms):
    conv_facs = [24 * 60 * 60 * 1000, 60 * 60 * 1000, 60 * 1000, 1000, 1]
    names = ["day", "hour", "minute", "second", "millisecond"]
    
    first_print = True
    for i in range(len(conv_facs)):
        unit_mag = time_ms // conv_facs[i]
        time_ms %= conv_facs[i]

        if not unit_mag:
            continue

        if not first_print:
            print(", ", end="")
        print(f"{unit_mag} {names[i]}", end="")
        if unit_mag != 1:
            print("s", end="")

        first_print = False

    if first_print:
        print(f"0 {names[-1]}s", end="")
    
    print()

def main():
    human_readable = parse_args()
    
    idle_time = get_x_idletime()
    if idle_time == -1:
        sys.exit(1)

    if human_readable:
        print_human_time(idle_time)
    else:
        print(idle_time)

if __name__ == '__main__':
    main()
