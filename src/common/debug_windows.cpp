/*
===========================================================================

  Copyright (c) 2024 LandSandBoat Dev Teams

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see http://www.gnu.org/licenses/

===========================================================================
*/

#ifdef _WIN32
#include "debug.h"

#ifndef __MINGW32__
#include "WheatyExceptionReport.h"
#endif

#ifdef __MINGW32__
#include <shlobj.h>
#else
#include <shlobj_core.h>
#endif
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "user32.lib")

#ifndef __MINGW32__
WheatyExceptionReport g_WheatyExceptionReport;
#endif

void debug::init()
{
#ifndef __MINGW32__
    g_WheatyExceptionReport = WheatyExceptionReport();
#endif
}

bool debug::isRunningUnderDebugger()
{
    return IsDebuggerPresent();
}

bool debug::isUserRoot()
{
    // There is no root user on Windows, so we check for admin instead
    return IsUserAnAdmin();
}

#endif // _WIN32
