#---------------------------------------------------------------------
# Makefile for vanitysearch
#
# Author : Jean-Luc PONS
# Modified: Added CUDA version auto-detection and GPU arch compatibility

SRC = Base58.cpp IntGroup.cpp main.cpp Random.cpp \
      Timer.cpp Int.cpp IntMod.cpp Point.cpp SECP256K1.cpp \
      Vanity.cpp GPU/GPUGenerate.cpp hash/ripemd160.cpp \
      hash/sha256.cpp hash/sha512.cpp hash/ripemd160_sse.cpp \
      hash/sha256_sse.cpp Bech32.cpp Wildcard.cpp

OBJDIR = obj

OBJET = $(addprefix $(OBJDIR)/, \
        Base58.o IntGroup.o main.o Random.o Timer.o Int.o \
        IntMod.o Point.o SECP256K1.o Vanity.o GPU/GPUGenerate.o \
        hash/ripemd160.o hash/sha256.o hash/sha512.o \
        hash/ripemd160_sse.o hash/sha256_sse.o \
        GPU/GPUEngine.o Bech32.o Wildcard.o)

# Auto-detect available compilers
# Try to find g++ with version 11, 10, 9, or default g++
GPP_DEFAULT := $(shell which g++ 2>/dev/null)
GPP_11 := $(shell which g++-11 2>/dev/null)
GPP_10 := $(shell which g++-10 2>/dev/null)
GPP_9 := $(shell which g++-9 2>/dev/null)

# Select compiler (prefer newer versions)
ifneq ($(GPP_11),)
    CXX        = g++-11
    CXXCUDA    = /usr/bin/g++-11
else ifneq ($(GPP_10),)
    CXX        = g++-10
    CXXCUDA    = /usr/bin/g++-10
else ifneq ($(GPP_9),)
    CXX        = g++-9
    CXXCUDA    = /usr/bin/g++-9
else ifneq ($(GPP_DEFAULT),)
    CXX        = g++
    CXXCUDA    = /usr/bin/g++
else
    $(error No suitable g++ compiler found. Please install g++)
endif

CUDA       = /usr/local/cuda
NVCC       = $(CUDA)/bin/nvcc

# Auto-detect CUDA version
CUDA_VERSION := $(shell $(NVCC) --version | grep -o "release [0-9]*\.[0-9]*" | cut -d' ' -f2 2>/dev/null || echo "0.0")
CUDA_MAJOR := $(shell echo $(CUDA_VERSION) | cut -d. -f1)
CUDA_MINOR := $(shell echo $(CUDA_VERSION) | cut -d. -f2)

# Debug info
$(info Detected CUDA version: $(CUDA_VERSION))
$(info Using C++ compiler: $(CXX))
$(info Using CUDA host compiler: $(CXXCUDA))

# Base GENCODE flags common to most CUDA versions
GENCODE_BASE := -gencode=arch=compute_60,code=sm_60 \
                -gencode=arch=compute_61,code=sm_61 \
                -gencode=arch=compute_75,code=sm_75

# Conditional GENCODE flags based on CUDA version
# Calculate CUDA version as integer (major * 100 + minor)
CUDA_VERSION_INT := $(shell expr $(CUDA_MAJOR) \* 100 + $(CUDA_MINOR))

ifeq ($(shell expr $(CUDA_VERSION_INT) \>= 1200), 1)
    # CUDA 12.x - full support
    $(info CUDA 12.x detected - full GPU architecture support)
    GENCODE_EXTRA := -gencode=arch=compute_80,code=sm_80 \
                     -gencode=arch=compute_86,code=sm_86 \
                     -gencode=arch=compute_89,code=sm_89 \
                     -gencode=arch=compute_90,code=sm_90 \
                     -gencode=arch=compute_90,code=compute_90
else ifeq ($(shell expr $(CUDA_VERSION_INT) \>= 1180), 1)
    # CUDA 11.8+ - support up to compute_89
    $(info CUDA 11.8+ detected - including Ada Lovelace (sm_89) support)
    GENCODE_EXTRA := -gencode=arch=compute_80,code=sm_80 \
                     -gencode=arch=compute_86,code=sm_86 \
                     -gencode=arch=compute_89,code=sm_89 \
                     -gencode=arch=compute_89,code=compute_89
else ifeq ($(shell expr $(CUDA_VERSION_INT) \>= 1110), 1)
    # CUDA 11.1-11.7 - support up to compute_86
    $(info CUDA 11.1-11.7 detected - including Ampere (sm_86) support)
    GENCODE_EXTRA := -gencode=arch=compute_80,code=sm_80 \
                     -gencode=arch=compute_86,code=sm_86
else ifeq ($(shell expr $(CUDA_VERSION_INT) \>= 1100), 1)
    # CUDA 11.0 - support up to compute_80 ONLY
    $(warning CUDA 11.0 detected - limited to architectures up to Volta (sm_80))
    GENCODE_EXTRA := -gencode=arch=compute_80,code=sm_80
else
    # CUDA 10.x or older
    $(warning CUDA $(CUDA_VERSION) detected - only basic GPU architectures enabled)
    GENCODE_EXTRA :=
endif

# Combined GENCODE flags
GENCODE_FLAGS := $(GENCODE_BASE) $(GENCODE_EXTRA)

# Verify CXXCUDA exists
ifeq ($(wildcard $(CXXCUDA)),)
    $(warning Host compiler $(CXXCUDA) not found, trying to find alternative...)
    # Try to find alternative
    ifneq ($(GPP_DEFAULT),)
        CXXCUDA := $(GPP_DEFAULT)
    else
        $(error Cannot find host compiler for CUDA. Please install g++ or g++-11)
    endif
endif

# Simplified GPU detection
GPU_DETECT := $(shell nvidia-smi -L 2>/dev/null | head -n1 || echo "Unknown GPU")
$(info GPU detected: $(GPU_DETECT))

ifdef debug
CXXFLAGS   = -mssse3 -Wno-write-strings -g -I. -I$(CUDA)/include
NVCC_DEBUG = -G -g
else
CXXFLAGS   = -mssse3 -Wno-write-strings -O2 -I. -I$(CUDA)/include
NVCC_DEBUG = -O2
endif

LFLAGS     = -lpthread -L$(CUDA)/lib64 -lcudart

#--------------------------------------------------------------------

# Unified GPU compilation rule with auto-detected GENCODE flags
$(OBJDIR)/GPU/GPUEngine.o: GPU/GPUEngine.cu
	@echo "Compiling GPU code with CUDA $(CUDA_VERSION)..."
	@echo "Using host compiler: $(CXXCUDA)"
	@echo "Using GPU architectures:"
	@echo "  $(GENCODE_FLAGS)"
	$(NVCC) -maxrregcount=0 --ptxas-options=-v --compile \
	        --compiler-options -fPIC -ccbin $(CXXCUDA) -m64 \
	        $(NVCC_DEBUG) -I$(CUDA)/include \
	        $(GENCODE_FLAGS) \
	        -o $(OBJDIR)/GPU/GPUEngine.o -c GPU/GPUEngine.cu

$(OBJDIR)/%.o : %.cpp
	$(CXX) $(CXXFLAGS) -o $@ -c $<

all: VanitySearch

VanitySearch: $(OBJET)
	@echo "Linking VanitySearch..."
	$(CXX) $(OBJET) $(LFLAGS) -o vanitysearch
	@echo "Build complete with CUDA $(CUDA_VERSION) and compiler $(CXX)"

$(OBJET): | $(OBJDIR) $(OBJDIR)/GPU $(OBJDIR)/hash

$(OBJDIR):
	mkdir -p $(OBJDIR)

$(OBJDIR)/GPU: $(OBJDIR)
	cd $(OBJDIR) && mkdir -p GPU

$(OBJDIR)/hash: $(OBJDIR)
	cd $(OBJDIR) && mkdir -p hash

clean:
	@echo "Cleaning build files..."
	@rm -f obj/*.o
	@rm -f obj/GPU/*.o
	@rm -f obj/hash/*.o

# Utility targets
info:
	@echo "=== Build Information ==="
	@echo "CUDA Version: $(CUDA_VERSION) (Version code: $(CUDA_VERSION_INT))"
	@echo "GPU Info: $(GPU_DETECT)"
	@echo "C++ Compiler: $(CXX) ($(shell $(CXX) --version | head -n1))"
	@echo "CUDA Host Compiler: $(CXXCUDA)"
	@echo "NVCC Compiler: $(NVCC)"
	@echo "GENCODE Flags:"
	@for flag in $(GENCODE_FLAGS); do \
		echo "  $$flag"; \
	done

# Help target
help:
	@echo "=== VanitySearch Makefile Help ==="
	@echo "Available targets:"
	@echo "  make all           - Build VanitySearch (default)"
	@echo "  make debug         - Build with debug symbols"
	@echo "  make clean         - Clean build files"
	@echo "  make info          - Show build configuration"
	@echo "  make help          - Show this help"
	@echo ""
	@echo "Environment variables:"
	@echo "  debug=1            - Enable debug build"
	@echo ""
	@echo "Example:"
	@echo "  make debug=1       # Build with debugging enabled"
	@echo "  make clean all     # Clean and rebuild"

.PHONY: all clean info help
