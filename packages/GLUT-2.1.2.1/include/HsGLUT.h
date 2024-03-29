/* include/HsGLUT.h.  Generated from HsGLUT.h.in by configure.  */
/* -----------------------------------------------------------------------------
 *
 * Module      :  C support for Graphics.UI.GLUT.Fonts
 * Copyright   :  (c) Sven Panne 2002-2005
 * License     :  BSD-style (see the file libraries/GLUT/LICENSE)
 *
 * Maintainer  :  sven.panne@aedion.de
 * Stability   :  provisional
 * Portability :  portable
 *
 * -------------------------------------------------------------------------- */

#ifndef HSGLUT_H
#define HSGLUT_H

/* Define to 1 if you have the <GL/glut.h> header file. */
#define HAVE_GL_GLUT_H 1

/* Define to 1 if you have the <windows.h> header file. */
/* #undef HAVE_WINDOWS_H */

/* Define to 1 if native OpenGL should be used on Mac OS X */
/* #undef USE_QUARTZ_OPENGL */

#ifdef USE_QUARTZ_OPENGL /* Mac OS X only */
#include <GLUT/glut.h>
#else
#if HAVE_WINDOWS_H
#include <windows.h>
#endif
#if HAVE_GL_GLUT_H
#include <GL/glut.h>
#else
#include "glut_local.h"
#endif
#endif

#if FREEGLUT
#include <GL/freeglut_ext.h>
#endif

extern void* hs_GLUT_marshalBitmapFont(int fontID);
extern void* hs_GLUT_marshalStrokeFont(int fontID);
extern void* hs_GLUT_getProcAddress(char *procName);

#endif
