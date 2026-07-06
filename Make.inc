SHELL        = /bin/sh
CD           = cd
CP           = cp
LN_S         = ln -s
MKDIR        = mkdir
RM           = /bin/rm -f
TOUCH        = touch

ARCH         = x86_64
TOPdir       = /home/ayman/github/hpl-2.3

INCdir       = $(TOPdir)/include
BINdir       = $(TOPdir)/bin/$(ARCH)
LIBdir       = $(TOPdir)/lib/$(ARCH)

HPLlib       = $(LIBdir)/libhpl.a 

# MPI Configuration
MPdir        = /usr
MPinc        = 
MPlib        = -lmpi

# BLAS/LAPACK Configuration  
LAdir        = /usr
LAinc        = 
LAlib        = -lblas -llapack

# Fortran 77 interface to BLAS
F2CDEFS      = -DAdd_ -DF77_INTEGER=int -DStringSunStyle

# HPL definitions
HPL_OPTS     = -DHPL_CALL_CBLAS
HPL_INCLUDES = -I$(INCdir) -I$(INCdir)/$(ARCH) $(LAinc) $(MPinc)
HPL_LIBS     = $(HPLlib) $(LAlib) $(MPlib)
HPL_DEFS     = $(F2CDEFS) $(HPL_OPTS) $(HPL_INCLUDES)

# Compilers and flags
CC           = mpicc
CCNOOPT      = $(HPL_DEFS)
CCFLAGS      = $(HPL_DEFS) -fomit-frame-pointer -O3 -funroll-loops -W -Wall

# Linker
LINKER       = mpicc
LINKFLAGS    = $(CCFLAGS)

# Archiver
ARCHIVER     = ar
ARFLAGS      = r
RANLIB       = echo
